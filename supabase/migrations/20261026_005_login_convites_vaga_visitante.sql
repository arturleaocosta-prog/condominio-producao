-- V1.9 — Login por convite e aviso de uso da vaga de visitante.
-- Pré-requisito: schema.sql e migrações 001–004 aplicados.
-- Modelo: ninguém se cadastra sozinho. O síndico cria o convite; a pessoa cria a conta no
-- Supabase Auth com o MESMO e-mail do convite e chama aceitar_convite(token).

-- ---------------------------------------------------------------------------------------
-- 1. Convites: o cliente não escreve direto na tabela; só pelas funções abaixo.
-- ---------------------------------------------------------------------------------------
revoke all on public.convites from anon, authenticated;
grant select (id, condominio_id, unidade_id, email, papel, enviado_por, expira_em, aceito_em, created_at)
  on public.convites to authenticated;   -- token_hash nunca é exposto ao navegador

drop policy if exists "convites_select_sindico" on public.convites;
create policy "convites_select_sindico" on public.convites for select
  using (condominio_id = public.meu_condominio_id() and public.equipe_admin());

create or replace function public.criar_convite(
  p_email text,
  p_papel public.perfil_condominio,
  p_unidade_id uuid default null,
  p_validade_dias integer default 7
) returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_cond uuid; v_email text; v_token text; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode criar convites'; end if;
  v_cond := public.meu_condominio_id();
  v_email := lower(trim(coalesce(p_email, '')));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido'; end if;
  if p_papel not in ('morador', 'conselho') then
    raise exception 'Convite permitido apenas para morador ou conselho';
  end if;
  if p_validade_dias is null or p_validade_dias < 1 or p_validade_dias > 30 then
    raise exception 'Validade deve ficar entre 1 e 30 dias';
  end if;
  if p_papel = 'morador' and p_unidade_id is null then
    raise exception 'Informe a unidade do morador';
  end if;
  if p_unidade_id is not null and not exists (
    select 1 from public.unidades u where u.id = p_unidade_id and u.condominio_id = v_cond and u.ativa
  ) then raise exception 'Unidade inválida'; end if;

  -- convites pendentes anteriores para o mesmo e-mail deixam de valer
  update public.convites set expira_em = now()
   where condominio_id = v_cond and lower(email) = v_email and aceito_em is null and expira_em > now();

  v_token := encode(gen_random_bytes(24), 'hex');
  insert into public.convites (condominio_id, unidade_id, email, papel, token_hash, enviado_por, expira_em)
  values (v_cond, p_unidade_id, v_email, p_papel, encode(digest(v_token, 'sha256'), 'hex'),
          auth.uid(), now() + make_interval(days => p_validade_dias))
  returning id into v_id;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'criar_convite', 'convites', v_id,
          jsonb_build_object('email', v_email, 'papel', p_papel, 'unidade_id', p_unidade_id));
  return v_token;   -- única vez em que o token existe em texto puro
end $$;

create or replace function public.cancelar_convite(p_convite_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode cancelar convites'; end if;
  update public.convites set expira_em = now()
   where id = p_convite_id and condominio_id = public.meu_condominio_id() and aceito_em is null;
  if not found then raise exception 'Convite não encontrado ou já utilizado'; end if;
end $$;

create or replace function public.aceitar_convite(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid(); v_email text; v_confirmado timestamptz; c public.convites%rowtype; v_perfil public.perfis%rowtype;
begin
  if v_uid is null then raise exception 'Autenticação necessária'; end if;
  select lower(email), email_confirmed_at into v_email, v_confirmado from auth.users where id = v_uid;
  if v_confirmado is null then raise exception 'Confirme seu e-mail antes de aceitar o convite'; end if;
  select * into c from public.convites
   where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') for update;
  -- mesma mensagem para qualquer falha: não revela se o token existe
  if not found or c.aceito_em is not null or c.expira_em <= now() or lower(c.email) <> v_email then
    raise exception 'Convite inválido ou expirado';
  end if;

  select * into v_perfil from public.perfis where user_id = v_uid;
  if found then
    if v_perfil.condominio_id <> c.condominio_id then raise exception 'Usuário já pertence a outro condomínio'; end if;
    if not v_perfil.ativo then raise exception 'Perfil desativado; fale com o síndico'; end if;
  else
    insert into public.perfis (user_id, condominio_id, nome, email, papel)
    values (v_uid, c.condominio_id, split_part(v_email, '@', 1), v_email, c.papel);
  end if;

  if c.unidade_id is not null then
    insert into public.vinculos_unidades (user_id, unidade_id)
    values (v_uid, c.unidade_id) on conflict (user_id, unidade_id) do update set ativo = true;
  end if;

  update public.convites set aceito_em = now() where id = c.id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (c.condominio_id, v_uid, 'aceitar_convite', 'convites', c.id, jsonb_build_object('papel', c.papel));
  return jsonb_build_object('condominio_id', c.condominio_id, 'papel', coalesce(v_perfil.papel, c.papel));
end $$;

revoke all on function public.criar_convite(text, public.perfil_condominio, uuid, integer) from public, anon;
revoke all on function public.cancelar_convite(uuid) from public, anon;
revoke all on function public.aceitar_convite(text) from public, anon;
grant execute on function public.criar_convite(text, public.perfil_condominio, uuid, integer) to authenticated;
grant execute on function public.cancelar_convite(uuid) to authenticated;
grant execute on function public.aceitar_convite(text) to authenticated;

-- ---------------------------------------------------------------------------------------
-- 2. Perfil: morador só altera o próprio nome. Papel, e-mail, condomínio e ativo = síndico.
-- ---------------------------------------------------------------------------------------
create or replace function public.proteger_perfil() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not public.equipe_admin() then
    if new.user_id is distinct from old.user_id or new.condominio_id is distinct from old.condominio_id
       or new.papel is distinct from old.papel or new.email is distinct from old.email
       or new.ativo is distinct from old.ativo then
      raise exception 'Somente o síndico pode alterar papel, e-mail, condomínio ou situação do perfil';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_perfil on public.perfis;
create trigger trg_proteger_perfil before update on public.perfis
  for each row execute function public.proteger_perfil();

-- ---------------------------------------------------------------------------------------
-- 3. Vaga de visitante: AVISO de uso. Não reserva nem garante a vaga (decisão do síndico).
-- ---------------------------------------------------------------------------------------
create table if not exists public.avisos_vaga_visitante (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  data_uso date not null,
  hora_inicio time not null,
  hora_fim time not null,
  observacao text check (observacao is null or char_length(observacao) <= 200),
  status text not null default 'ativo' check (status in ('ativo', 'cancelado')),
  created_at timestamptz not null default now(),
  cancelado_em timestamptz,
  check (hora_fim > hora_inicio)
);
create index if not exists avisos_vaga_data_idx on public.avisos_vaga_visitante (condominio_id, data_uso);
alter table public.avisos_vaga_visitante enable row level security;

create or replace function public.validar_aviso_vaga() returns trigger
language plpgsql as $$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if tg_op = 'INSERT' and (new.data_uso < v_hoje or new.data_uso > v_hoje + 90) then
    raise exception 'A data deve ser de hoje até 90 dias à frente';
  end if;
  if new.status = 'cancelado' and new.cancelado_em is null then new.cancelado_em := now(); end if;
  return new;
end $$;
drop trigger if exists trg_validar_aviso_vaga on public.avisos_vaga_visitante;
create trigger trg_validar_aviso_vaga before insert or update on public.avisos_vaga_visitante
  for each row execute function public.validar_aviso_vaga();

create policy "aviso_vaga_select_membros" on public.avisos_vaga_visitante for select
  using (condominio_id = public.meu_condominio_id());
create policy "aviso_vaga_insert" on public.avisos_vaga_visitante for insert
  with check (
    condominio_id = public.meu_condominio_id() and criado_por = auth.uid() and status = 'ativo'
    and (public.equipe_admin() or unidade_id in (
      select vu.unidade_id from public.vinculos_unidades vu where vu.user_id = auth.uid() and vu.ativo))
    and unidade_id in (select u.id from public.unidades u where u.condominio_id = public.meu_condominio_id())
  );
create policy "aviso_vaga_update_proprio_ou_sindico" on public.avisos_vaga_visitante for update
  using (condominio_id = public.meu_condominio_id() and (public.equipe_admin() or criado_por = auth.uid()))
  with check (
    condominio_id = public.meu_condominio_id()
    and (public.equipe_admin() or (criado_por = auth.uid() and unidade_id in (
      select vu.unidade_id from public.vinculos_unidades vu where vu.user_id = auth.uid() and vu.ativo)))
  );
-- sem policy de DELETE: avisos são cancelados, não apagados (histórico).
-- O Supabase concede ALL por padrão a anon/authenticated em tabelas novas: retiramos o excedente.
revoke all on public.avisos_vaga_visitante from anon, authenticated;
grant select, insert, update on public.avisos_vaga_visitante to authenticated;
