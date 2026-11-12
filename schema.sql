-- Esquema inicial para Supabase / PostgreSQL.
-- Revise e aplique em ambiente de desenvolvimento antes de usar dados reais.
create extension if not exists pgcrypto;

create type public.perfil_condominio as enum ('sindico','conselho','morador');
create type public.tipo_lancamento as enum ('receita','despesa','estorno');
create type public.status_ocorrencia as enum ('aberta','em_andamento','concluida','cancelada');
create type public.status_reserva as enum ('confirmada','cancelada');
create type public.status_enquete as enum ('rascunho','aberta','encerrada');

create table public.condominios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  endereco text,
  fuso_horario text not null default 'America/Sao_Paulo',
  created_at timestamptz not null default now()
);

create table public.unidades (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  identificacao text not null,
  fracao_ideal numeric(9,6),
  ativa boolean not null default true,
  created_at timestamptz not null default now(),
  unique(condominio_id, identificacao)
);

-- O id corresponde ao auth.users.id. O papel é definido apenas por administrador autorizado.
create table public.perfis (
  user_id uuid primary key references auth.users(id) on delete cascade,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  nome text not null,
  email text not null,
  papel public.perfil_condominio not null default 'morador',
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.vinculos_unidades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfis(user_id) on delete cascade,
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  tipo_vinculo text not null default 'morador' check (tipo_vinculo in ('morador','proprietario','responsavel')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  unique(user_id, unidade_id)
);

create table public.convites (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete cascade,
  unidade_id uuid references public.unidades(id) on delete set null,
  email text not null,
  papel public.perfil_condominio not null default 'morador',
  token_hash text not null unique,
  enviado_por uuid not null references public.perfis(user_id),
  expira_em timestamptz not null,
  aceito_em timestamptz,
  created_at timestamptz not null default now()
);

create table public.lancamentos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  tipo public.tipo_lancamento not null,
  data_lancamento date not null,
  competencia date,
  valor_centavos bigint not null check (valor_centavos > 0),
  categoria text not null,
  descricao text not null check (length(trim(descricao)) between 1 and 120),
  fornecedor text,
  numero_documento text,
  observacao text,
  lancamento_original_id uuid references public.lancamentos(id),
  criado_por uuid not null references public.perfis(user_id),
  criado_em timestamptz not null default now(),
  estornado_em timestamptz,
  estornado_por uuid references public.perfis(user_id),
  motivo_estorno text,
  check ((tipo <> 'estorno') or lancamento_original_id is not null)
);
create index lancamentos_condominio_data_idx on public.lancamentos(condominio_id, data_lancamento desc);

create table public.comprovantes_financeiros (
  id uuid primary key default gen_random_uuid(),
  lancamento_id uuid not null references public.lancamentos(id) on delete restrict,
  caminho_storage text not null,
  nome_arquivo text not null,
  mime_type text,
  enviado_por uuid not null references public.perfis(user_id),
  created_at timestamptz not null default now()
);

create table public.avisos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  titulo text not null,
  conteudo text not null,
  publicado boolean not null default false,
  publicado_em timestamptz,
  criado_por uuid not null references public.perfis(user_id),
  created_at timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create table public.leituras_avisos (
  aviso_id uuid not null references public.avisos(id) on delete cascade,
  user_id uuid not null references public.perfis(user_id) on delete cascade,
  lido_em timestamptz not null default now(),
  primary key(aviso_id,user_id)
);

create table public.documentos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  titulo text not null,
  categoria text not null,
  descricao text,
  caminho_storage text not null,
  nome_arquivo text not null,
  visibilidade text not null default 'moradores' check (visibilidade in ('sindico','conselho','moradores')),
  criado_por uuid not null references public.perfis(user_id),
  created_at timestamptz not null default now(),
  arquivado_em timestamptz
);

create table public.ocorrencias (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  unidade_id uuid references public.unidades(id) on delete set null,
  criado_por uuid not null references public.perfis(user_id),
  titulo text not null,
  descricao text not null,
  status public.status_ocorrencia not null default 'aberta',
  responsavel uuid references public.perfis(user_id),
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  concluida_em timestamptz
);
create table public.historico_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  ocorrencia_id uuid not null references public.ocorrencias(id) on delete cascade,
  autor uuid not null references public.perfis(user_id),
  descricao text not null,
  status_anterior public.status_ocorrencia,
  status_novo public.status_ocorrencia,
  created_at timestamptz not null default now()
);

create table public.areas_comuns (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  nome text not null,
  descricao text,
  duracao_max_minutos integer not null default 240 check (duracao_max_minutos > 0),
  antecedencia_dias integer not null default 60 check (antecedencia_dias >= 0),
  intervalo_minutos integer not null default 0 check (intervalo_minutos >= 0),
  ativa boolean not null default true,
  unique(condominio_id,nome)
);
create table public.reservas (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  area_id uuid not null references public.areas_comuns(id) on delete restrict,
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  solicitante uuid not null references public.perfis(user_id) on delete restrict,
  inicio timestamptz not null,
  fim timestamptz not null,
  status public.status_reserva not null default 'confirmada',
  criada_em timestamptz not null default now(),
  cancelada_em timestamptz,
  check (fim > inicio)
);
create index reservas_area_periodo_idx on public.reservas(area_id,inicio,fim) where status='confirmada';
-- Para produção, evitar sobreposição concorrente com uma exclusion constraint usando tstzrange + btree_gist,
-- ou uma função transacional SECURITY DEFINER que valida disponibilidade e insere atomicamente.

create table public.enquetes (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  pergunta text not null,
  descricao text,
  opcoes jsonb not null check (jsonb_typeof(opcoes)='array' and jsonb_array_length(opcoes)>=2),
  status public.status_enquete not null default 'rascunho',
  inicio_em timestamptz,
  fim_em timestamptz,
  criada_por uuid not null references public.perfis(user_id),
  created_at timestamptz not null default now(),
  check (fim_em is null or inicio_em is null or fim_em > inicio_em)
);
create table public.respostas_enquetes (
  enquete_id uuid not null references public.enquetes(id) on delete cascade,
  user_id uuid not null references public.perfis(user_id) on delete cascade,
  opcao_index integer not null check (opcao_index >= 0),
  respondida_em timestamptz not null default now(),
  primary key(enquete_id,user_id)
);

create table public.auditoria (
  id bigint generated always as identity primary key,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  user_id uuid references public.perfis(user_id) on delete set null,
  acao text not null,
  entidade text not null,
  registro_id uuid,
  detalhes jsonb,
  created_at timestamptz not null default now()
);

-- Helpers de autorização. O cliente não pode definir papel por conta própria.
create or replace function public.meu_condominio_id()
returns uuid language sql stable security definer set search_path=public
as $$ select condominio_id from public.perfis where user_id=auth.uid() and ativo=true limit 1 $$;
create or replace function public.meu_papel()
returns public.perfil_condominio language sql stable security definer set search_path=public
as $$ select papel from public.perfis where user_id=auth.uid() and ativo=true limit 1 $$;
create or replace function public.equipe_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.meu_papel()='sindico',false) $$;
create or replace function public.equipe_conselho_ou_sindico()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.meu_papel() in ('sindico','conselho'),false) $$;

-- RLS ativado em todas as tabelas com dados do condomínio.
alter table public.condominios enable row level security;
alter table public.unidades enable row level security;
alter table public.perfis enable row level security;
alter table public.vinculos_unidades enable row level security;
alter table public.convites enable row level security;
alter table public.lancamentos enable row level security;
alter table public.comprovantes_financeiros enable row level security;
alter table public.avisos enable row level security;
alter table public.leituras_avisos enable row level security;
alter table public.documentos enable row level security;
alter table public.ocorrencias enable row level security;
alter table public.historico_ocorrencias enable row level security;
alter table public.areas_comuns enable row level security;
alter table public.reservas enable row level security;
alter table public.enquetes enable row level security;
alter table public.respostas_enquetes enable row level security;
alter table public.auditoria enable row level security;

-- Condomínio e unidades: usuários ativos do mesmo condomínio podem consultar; apenas síndico administra.
create policy "condominio_select_membros" on public.condominios for select using (id=public.meu_condominio_id());
create policy "condominio_update_sindico" on public.condominios for update using (id=public.meu_condominio_id() and public.equipe_admin()) with check (id=public.meu_condominio_id() and public.equipe_admin());
create policy "unidades_select_membros" on public.unidades for select using (condominio_id=public.meu_condominio_id());
create policy "unidades_admin_all" on public.unidades for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());

-- Perfil: cada pessoa lê o próprio perfil; síndico pode administrar perfis do condomínio.
create policy "perfil_select_proprio_ou_sindico" on public.perfis for select using (user_id=auth.uid() or (condominio_id=public.meu_condominio_id() and public.equipe_admin()));
create policy "perfil_update_proprio_nome" on public.perfis for update using (user_id=auth.uid()) with check (user_id=auth.uid() and papel=public.meu_papel() and condominio_id=public.meu_condominio_id());
create policy "perfil_admin_all" on public.perfis for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
create policy "vinculos_select_proprios_ou_sindico" on public.vinculos_unidades for select using (user_id=auth.uid() or (public.equipe_admin() and unidade_id in (select id from public.unidades where condominio_id=public.meu_condominio_id())));
create policy "vinculos_admin_all" on public.vinculos_unidades for all using (public.equipe_admin() and unidade_id in (select id from public.unidades where condominio_id=public.meu_condominio_id())) with check (public.equipe_admin() and unidade_id in (select id from public.unidades where condominio_id=public.meu_condominio_id()));

-- Livro-caixa: síndico pode gerir; conselho consulta; morador não vê lançamentos individuais.
create policy "lancamentos_select_sindico_conselho" on public.lancamentos for select using (condominio_id=public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
create policy "lancamentos_insert_sindico" on public.lancamentos for insert with check (condominio_id=public.meu_condominio_id() and public.equipe_admin() and criado_por=auth.uid());
create policy "lancamentos_update_sindico" on public.lancamentos for update using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
-- Não conceder DELETE em lançamentos financeiros; usar estorno/ajuste com auditoria.
create policy "comprovantes_select_conselho_sindico" on public.comprovantes_financeiros for select using (exists(select 1 from public.lancamentos l where l.id=lancamento_id and l.condominio_id=public.meu_condominio_id()) and public.equipe_conselho_ou_sindico());
create policy "comprovantes_admin_insert" on public.comprovantes_financeiros for insert with check (public.equipe_admin() and enviado_por=auth.uid() and exists(select 1 from public.lancamentos l where l.id=lancamento_id and l.condominio_id=public.meu_condominio_id()));

create policy "avisos_select_publicados" on public.avisos for select using (condominio_id=public.meu_condominio_id() and (public.equipe_admin() or publicado=true));
create policy "avisos_admin_all" on public.avisos for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
create policy "leituras_avisos_select_own" on public.leituras_avisos for select using (user_id=auth.uid());
create policy "leituras_avisos_insert_own" on public.leituras_avisos for insert with check (user_id=auth.uid() and exists(select 1 from public.avisos a where a.id=aviso_id and a.condominio_id=public.meu_condominio_id() and a.publicado=true));

create policy "documentos_select_by_visibility" on public.documentos for select using (
 condominio_id=public.meu_condominio_id() and arquivado_em is null and
 (public.equipe_admin() or (visibilidade='conselho' and public.equipe_conselho_ou_sindico()) or visibilidade='moradores')
);
create policy "documentos_admin_all" on public.documentos for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());

create policy "ocorrencias_select_sindico_conselho_ou_propria" on public.ocorrencias for select using (condominio_id=public.meu_condominio_id() and (public.equipe_conselho_ou_sindico() or criado_por=auth.uid() or unidade_id in (select vu.unidade_id from public.vinculos_unidades vu where vu.user_id=auth.uid() and vu.ativo=true)));
create policy "ocorrencias_insert_membro" on public.ocorrencias for insert with check (condominio_id=public.meu_condominio_id() and criado_por=auth.uid());
create policy "ocorrencias_update_sindico" on public.ocorrencias for update using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
create policy "historico_ocorrencias_select_allowed" on public.historico_ocorrencias for select using (exists(select 1 from public.ocorrencias o where o.id=ocorrencia_id and o.condominio_id=public.meu_condominio_id() and (public.equipe_conselho_ou_sindico() or o.criado_por=auth.uid() or o.unidade_id in (select vu.unidade_id from public.vinculos_unidades vu where vu.user_id=auth.uid() and vu.ativo=true))));
create policy "historico_ocorrencias_insert_member" on public.historico_ocorrencias for insert with check (autor=auth.uid() and exists(select 1 from public.ocorrencias o where o.id=ocorrencia_id and o.condominio_id=public.meu_condominio_id() and (public.equipe_admin() or o.criado_por=auth.uid() or o.unidade_id in (select vu.unidade_id from public.vinculos_unidades vu where vu.user_id=auth.uid() and vu.ativo=true))));

create policy "areas_select_membros" on public.areas_comuns for select using (condominio_id=public.meu_condominio_id() and ativa=true);
create policy "areas_admin_all" on public.areas_comuns for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
create policy "reservas_select_membros" on public.reservas for select using (condominio_id=public.meu_condominio_id() and (public.equipe_conselho_ou_sindico() or solicitante=auth.uid() or unidade_id in (select vu.unidade_id from public.vinculos_unidades vu where vu.user_id=auth.uid() and vu.ativo=true)));
create policy "reservas_insert_own_unit" on public.reservas for insert with check (condominio_id=public.meu_condominio_id() and solicitante=auth.uid() and unidade_id in (select vu.unidade_id from public.vinculos_unidades vu where vu.user_id=auth.uid() and vu.ativo=true));
create policy "reservas_cancel_own_or_admin" on public.reservas for update using (condominio_id=public.meu_condominio_id() and (public.equipe_admin() or solicitante=auth.uid())) with check (condominio_id=public.meu_condominio_id() and (public.equipe_admin() or solicitante=auth.uid()));

create policy "enquetes_select_membros" on public.enquetes for select using (condominio_id=public.meu_condominio_id() and (public.equipe_admin() or status<>'rascunho'));
create policy "enquetes_admin_all" on public.enquetes for all using (condominio_id=public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id=public.meu_condominio_id() and public.equipe_admin());
create policy "respostas_select_own_or_admin" on public.respostas_enquetes for select using (user_id=auth.uid() or public.equipe_admin());
create policy "respostas_insert_own_open_poll" on public.respostas_enquetes for insert with check (user_id=auth.uid() and exists(select 1 from public.enquetes e where e.id=enquete_id and e.condominio_id=public.meu_condominio_id() and e.status='aberta' and (e.inicio_em is null or e.inicio_em<=now()) and (e.fim_em is null or e.fim_em>now())));

create policy "auditoria_select_sindico_conselho" on public.auditoria for select using (condominio_id=public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
-- Inserções de auditoria devem ser feitas por funções confiáveis/trigger no banco, não pelo cliente.

-- IMPORTANTE: políticas RLS são uma base inicial, não substituem revisão de segurança.
-- Configurar buckets privados para documentos e comprovantes; validar o papel e o condomínio nas policies de storage.
-- Criar convites e confirmação automática de reservas por Edge Function/transação segura; nunca expor service_role no navegador.

-- Resumo agregado para moradores: retorna totais, nunca linhas individuais.
-- A função valida o condomínio do usuário e deve ser chamada pelo cliente autenticado.
create or replace function public.resumo_financeiro(p_ano integer, p_mes integer)
returns table(receitas_centavos bigint, despesas_centavos bigint, saldo_centavos bigint)
language plpgsql stable security definer set search_path=public
as $$
declare v_cond uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  v_cond := public.meu_condominio_id();
  if v_cond is null then raise exception 'Usuário sem vínculo ativo com condomínio'; end if;
  if p_mes < 1 or p_mes > 12 or p_ano < 2000 or p_ano > 2200 then raise exception 'Período inválido'; end if;
  return query
  with base as (
    select l.id,l.tipo,l.valor_centavos,l.data_lancamento,l.estornado_em,l.lancamento_original_id
    from public.lancamentos l
    where l.condominio_id=v_cond
      and l.data_lancamento >= make_date(p_ano,p_mes,1)
      and l.data_lancamento < (make_date(p_ano,p_mes,1) + interval '1 month')::date
  ), totals as (
    select
      coalesce(sum(case
        when b.tipo='receita' and b.estornado_em is null then b.valor_centavos
        when b.tipo='estorno' and orig.tipo='despesa' then b.valor_centavos
        else 0 end),0)::bigint as inc,
      coalesce(sum(case
        when b.tipo='despesa' and b.estornado_em is null then b.valor_centavos
        when b.tipo='estorno' and orig.tipo='receita' then b.valor_centavos
        else 0 end),0)::bigint as out
    from base b left join public.lancamentos orig on orig.id=b.lancamento_original_id
  ) select totals.inc, totals.out, totals.inc-totals.out from totals;
end;
$$;
revoke all on function public.resumo_financeiro(integer,integer) from public;
grant execute on function public.resumo_financeiro(integer,integer) to authenticated;
