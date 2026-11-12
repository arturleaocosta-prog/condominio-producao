-- V1.13 — Edição de lançamentos (com histórico obrigatório) e anexos (nota fiscal / documento).
-- Pré-requisito: migrações 001–007.
-- Decisão do síndico: lançamentos passam a poder ser EDITADOS. A trilha de auditoria continua:
--   · toda edição exige motivo e grava o histórico (antes/depois) em tabela que ninguém altera nem apaga;
--   · o lançamento mostra "editado" e o conselho consulta o histórico;
--   · tipo (receita/despesa) NÃO muda por edição; estornos e lançamentos estornados não são editáveis;
--   · editar valor ou data de um mês passado altera o saldo desse mês (por isso o app avisa antes).

-- ---------------------------------------------------------------------------------------
-- 1. Colunas de controle no lançamento
-- ---------------------------------------------------------------------------------------
alter table public.lancamentos add column if not exists versao integer not null default 1;
alter table public.lancamentos add column if not exists editado_em timestamptz;
alter table public.lancamentos add column if not exists editado_por uuid references public.perfis(user_id);

-- ---------------------------------------------------------------------------------------
-- 2. Histórico de edições (somente inserção)
-- ---------------------------------------------------------------------------------------
create table if not exists public.lancamentos_historico (
  id uuid primary key default gen_random_uuid(),
  lancamento_id uuid not null references public.lancamentos(id) on delete restrict,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  versao integer not null,
  motivo text not null check (char_length(motivo) between 5 and 200),
  antes jsonb not null,
  depois jsonb not null,
  editado_por uuid not null references public.perfis(user_id),
  editado_em timestamptz not null default now(),
  unique (lancamento_id, versao)
);
alter table public.lancamentos_historico enable row level security;
revoke all on public.lancamentos_historico from anon, authenticated;
grant select on public.lancamentos_historico to authenticated;
drop policy if exists "lanc_historico_select" on public.lancamentos_historico;
create policy "lanc_historico_select" on public.lancamentos_historico for select
  using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());

create or replace function public.proteger_historico() returns trigger
language plpgsql as $$
begin raise exception 'O histórico de edições não pode ser alterado nem apagado'; end $$;
drop trigger if exists trg_proteger_historico on public.lancamentos_historico;
create trigger trg_proteger_historico before update or delete on public.lancamentos_historico
  for each row execute function public.proteger_historico();

-- ---------------------------------------------------------------------------------------
-- 3. Proteção do lançamento: continua imutável, exceto (a) estorno e (b) edição feita pela função
-- ---------------------------------------------------------------------------------------
create or replace function public.proteger_lancamento() returns trigger
language plpgsql as $$
declare v_novo jsonb; v_velho jsonb;
  v_livres constant text[] := array['data_lancamento','competencia','valor_centavos','categoria','descricao','fornecedor','numero_documento','observacao','versao','editado_em','editado_por'];
begin
  if tg_op = 'DELETE' then
    raise exception 'Lançamentos não podem ser apagados; use o estorno';
  end if;
  if old.estornado_em is not null then
    raise exception 'Lançamento já estornado não pode ser alterado';
  end if;
  -- caminho 1: edição feita por public.editar_lancamento (a função sinaliza com uma variável de sessão)
  if current_setting('app.editando', true) = '1' then
    v_novo := to_jsonb(new); v_velho := to_jsonb(old);
    select jsonb_object_agg(k, v_novo -> k) into v_novo from jsonb_object_keys(v_novo) k where k <> all (v_livres);
    select jsonb_object_agg(k, v_velho -> k) into v_velho from jsonb_object_keys(v_velho) k where k <> all (v_livres);
    if old.tipo = 'estorno' or v_novo is distinct from v_velho then
      raise exception 'Edição inválida: só data, valor, categoria, descrição, fornecedor, documento e observação podem mudar';
    end if;
    return new;
  end if;
  -- caminho 2: estorno (marca o original como estornado, uma vez)
  if new.estornado_em is null or new.estornado_por is null or new.motivo_estorno is null
     or (to_jsonb(new) - 'estornado_em' - 'estornado_por' - 'motivo_estorno')
        is distinct from (to_jsonb(old) - 'estornado_em' - 'estornado_por' - 'motivo_estorno') then
    raise exception 'Lançamentos não podem ser alterados; use a edição ou o estorno';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------------------
-- 4. Editar lançamento (síndico)
-- ---------------------------------------------------------------------------------------
create or replace function public.editar_lancamento(
  p_id uuid, p_data date, p_valor_centavos bigint, p_categoria text, p_descricao text,
  p_fornecedor text, p_numero_documento text, p_observacao text, p_motivo text
) returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_cond uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; l public.lancamentos%rowtype;
  v_desc text := trim(coalesce(p_descricao, '')); v_cat text := trim(coalesce(p_categoria, ''));
  v_forn text := nullif(trim(coalesce(p_fornecedor, '')), ''); v_doc text := nullif(trim(coalesce(p_numero_documento, '')), '');
  v_obs text := nullif(trim(coalesce(p_observacao, '')), ''); v_mot text := trim(coalesce(p_motivo, ''));
  v_abertura date; v_antes jsonb := '{}'::jsonb; v_depois jsonb := '{}'::jsonb; v_versao integer;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode editar lançamentos'; end if;
  v_cond := public.meu_condominio_id();
  select * into l from public.lancamentos where id = p_id and condominio_id = v_cond for update;
  if not found then raise exception 'Lançamento não encontrado'; end if;
  if l.tipo = 'estorno' then raise exception 'Estornos não podem ser editados'; end if;
  if l.estornado_em is not null then raise exception 'Lançamento estornado não pode ser editado'; end if;
  if p_valor_centavos is null or p_valor_centavos <= 0 then raise exception 'O valor deve ser maior que zero'; end if;
  if p_valor_centavos > 1000000000 then raise exception 'Valor acima do limite de R$ 10.000.000,00'; end if;
  if p_data is null then raise exception 'Informe a data'; end if;
  if p_data > v_hoje then raise exception 'A data não pode ser futura'; end if;
  if p_data < v_hoje - 1830 then raise exception 'A data não pode ter mais de 5 anos'; end if;
  select saldo_inicial_data into v_abertura from public.condominios where id = v_cond;
  if v_abertura is not null and p_data < v_abertura then
    raise exception 'A data não pode ser anterior ao saldo de abertura (%)', to_char(v_abertura, 'DD/MM/YYYY'); end if;
  if v_desc = '' or char_length(v_desc) > 120 then raise exception 'Descrição deve ter de 1 a 120 caracteres'; end if;
  if v_cat = '' or char_length(v_cat) > 60 then raise exception 'Categoria deve ter de 1 a 60 caracteres'; end if;
  if char_length(coalesce(v_forn, '')) > 120 then raise exception 'Fornecedor deve ter até 120 caracteres'; end if;
  if char_length(coalesce(v_doc, '')) > 60 then raise exception 'Número do documento deve ter até 60 caracteres'; end if;
  if char_length(coalesce(v_obs, '')) > 300 then raise exception 'Observação deve ter até 300 caracteres'; end if;
  if char_length(v_mot) < 5 or char_length(v_mot) > 200 then raise exception 'Informe o motivo da edição (5 a 200 caracteres)'; end if;

  if l.data_lancamento is distinct from p_data then v_antes := v_antes || jsonb_build_object('data_lancamento', l.data_lancamento); v_depois := v_depois || jsonb_build_object('data_lancamento', p_data); end if;
  if l.valor_centavos is distinct from p_valor_centavos then v_antes := v_antes || jsonb_build_object('valor_centavos', l.valor_centavos); v_depois := v_depois || jsonb_build_object('valor_centavos', p_valor_centavos); end if;
  if l.categoria is distinct from v_cat then v_antes := v_antes || jsonb_build_object('categoria', l.categoria); v_depois := v_depois || jsonb_build_object('categoria', v_cat); end if;
  if l.descricao is distinct from v_desc then v_antes := v_antes || jsonb_build_object('descricao', l.descricao); v_depois := v_depois || jsonb_build_object('descricao', v_desc); end if;
  if l.fornecedor is distinct from v_forn then v_antes := v_antes || jsonb_build_object('fornecedor', l.fornecedor); v_depois := v_depois || jsonb_build_object('fornecedor', v_forn); end if;
  if l.numero_documento is distinct from v_doc then v_antes := v_antes || jsonb_build_object('numero_documento', l.numero_documento); v_depois := v_depois || jsonb_build_object('numero_documento', v_doc); end if;
  if l.observacao is distinct from v_obs then v_antes := v_antes || jsonb_build_object('observacao', l.observacao); v_depois := v_depois || jsonb_build_object('observacao', v_obs); end if;
  if v_depois = '{}'::jsonb then raise exception 'Nada foi alterado'; end if;

  v_versao := l.versao + 1;
  perform set_config('app.editando', '1', true);
  update public.lancamentos set data_lancamento = p_data, valor_centavos = p_valor_centavos, categoria = v_cat, descricao = v_desc,
         fornecedor = v_forn, numero_documento = v_doc, observacao = v_obs,
         competencia = case when l.data_lancamento is distinct from p_data then date_trunc('month', p_data)::date else competencia end,
         versao = v_versao, editado_em = now(), editado_por = auth.uid()
   where id = p_id;
  perform set_config('app.editando', '0', true);

  insert into public.lancamentos_historico (lancamento_id, condominio_id, versao, motivo, antes, depois, editado_por)
  values (p_id, v_cond, v_versao, v_mot, v_antes, v_depois, auth.uid());
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'editar_lancamento', 'lancamentos', p_id, jsonb_build_object('versao', v_versao, 'motivo', v_mot, 'antes', v_antes, 'depois', v_depois));
  return v_versao;
end $$;
revoke all on function public.editar_lancamento(uuid, date, bigint, text, text, text, text, text, text) from public, anon;
grant execute on function public.editar_lancamento(uuid, date, bigint, text, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------------------
-- 5. Anexos (nota fiscal, recibo, boleto pago...) — arquivos em bucket PRIVADO do Storage
-- ---------------------------------------------------------------------------------------
alter table public.comprovantes_financeiros add column if not exists tamanho_bytes bigint;
alter table public.comprovantes_financeiros add column if not exists sha256 text;
alter table public.comprovantes_financeiros add column if not exists removido_em timestamptz;
alter table public.comprovantes_financeiros add column if not exists removido_por uuid references public.perfis(user_id);
alter table public.comprovantes_financeiros add column if not exists motivo_remocao text;
drop policy if exists "comprovantes_admin_insert" on public.comprovantes_financeiros;
revoke insert, update, delete on public.comprovantes_financeiros from authenticated;   -- só pelas funções abaixo

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovantes', 'comprovantes', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = 10485760,
  allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];

-- Pasta do arquivo = código do condomínio: síndico envia; síndico e conselho leem; ninguém altera nem apaga pelo app.
drop policy if exists "comprovantes_storage_select" on storage.objects;
create policy "comprovantes_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'comprovantes' and (storage.foldername(name))[1] = public.meu_condominio_id()::text and public.equipe_conselho_ou_sindico());
drop policy if exists "comprovantes_storage_insert" on storage.objects;
create policy "comprovantes_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovantes' and (storage.foldername(name))[1] = public.meu_condominio_id()::text and public.equipe_admin());

create or replace function public.registrar_comprovante(
  p_lancamento_id uuid, p_caminho text, p_nome text, p_mime text, p_tamanho bigint, p_sha256 text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_cond uuid; l public.lancamentos%rowtype; v_nome text := trim(coalesce(p_nome, '')); v_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode anexar documentos'; end if;
  v_cond := public.meu_condominio_id();
  select * into l from public.lancamentos where id = p_lancamento_id and condominio_id = v_cond;
  if not found then raise exception 'Lançamento não encontrado'; end if;
  if l.tipo = 'estorno' then raise exception 'Anexe o documento ao lançamento original, não ao estorno'; end if;
  if p_caminho is null or p_caminho !~ ('^' || v_cond::text || '/' || p_lancamento_id::text || '/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$') then
    raise exception 'Caminho do arquivo inválido'; end if;
  if p_mime is null or p_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp') then raise exception 'Tipo de arquivo não permitido (use PDF, JPG, PNG ou WEBP)'; end if;
  if p_tamanho is null or p_tamanho < 1 or p_tamanho > 10485760 then raise exception 'O arquivo deve ter até 10 MB'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Impressão digital (SHA-256) inválida'; end if;
  if v_nome = '' or char_length(v_nome) > 120 then raise exception 'Nome do arquivo deve ter de 1 a 120 caracteres'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'comprovantes' and o.name = p_caminho) then
    raise exception 'Arquivo não encontrado no armazenamento; envie de novo'; end if;
  if (select count(*) from public.comprovantes_financeiros c where c.lancamento_id = p_lancamento_id and c.removido_em is null) >= 8 then
    raise exception 'Limite de 8 anexos por lançamento'; end if;
  insert into public.comprovantes_financeiros (lancamento_id, caminho_storage, nome_arquivo, mime_type, enviado_por, tamanho_bytes, sha256)
  values (p_lancamento_id, p_caminho, v_nome, p_mime, auth.uid(), p_tamanho, p_sha256) returning id into v_id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'anexar_comprovante', 'comprovantes_financeiros', v_id, jsonb_build_object('lancamento_id', p_lancamento_id, 'nome', v_nome, 'sha256', p_sha256));
  return v_id;
end $$;

create or replace function public.remover_comprovante(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public
as $$
declare v_cond uuid; v_mot text := trim(coalesce(p_motivo, ''));
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode remover anexos'; end if;
  v_cond := public.meu_condominio_id();
  if char_length(v_mot) < 5 or char_length(v_mot) > 200 then raise exception 'Informe o motivo (5 a 200 caracteres)'; end if;
  -- o anexo some da lista, mas o arquivo e o registro permanecem (evidência); o motivo fica gravado
  update public.comprovantes_financeiros c set removido_em = now(), removido_por = auth.uid(), motivo_remocao = v_mot
   where c.id = p_id and c.removido_em is null
     and exists (select 1 from public.lancamentos l where l.id = c.lancamento_id and l.condominio_id = v_cond);
  if not found then raise exception 'Anexo não encontrado ou já removido'; end if;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'remover_comprovante', 'comprovantes_financeiros', p_id, jsonb_build_object('motivo', v_mot));
end $$;

revoke all on function public.registrar_comprovante(uuid, text, text, text, bigint, text) from public, anon;
revoke all on function public.remover_comprovante(uuid, text) from public, anon;
grant execute on function public.registrar_comprovante(uuid, text, text, text, bigint, text) to authenticated;
grant execute on function public.remover_comprovante(uuid, text) to authenticated;
