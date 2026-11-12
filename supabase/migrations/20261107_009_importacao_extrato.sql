-- V1.14 — Importação de extrato bancário (OFX) pelo app.
-- O navegador lê o arquivo, o síndico revisa e classifica cada movimento, e a função importar_extrato grava tudo
-- em UMA transação: lançamentos, vínculo com o extrato e conferência do saldo. Se algo não bater, nada é gravado.
-- Pré-requisito: migrações 001–008.

-- ---------------------------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------------------------
create table if not exists public.extratos_importados (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  arquivo_nome text not null check (char_length(arquivo_nome) between 1 and 200),
  arquivo_sha256 text not null check (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  periodo_ini date not null,
  periodo_fim date not null check (periodo_fim >= periodo_ini),
  saldo_final_centavos bigint,
  saldo_data date,
  diferenca_saldo_centavos bigint,
  qtd_movimentos int not null check (qtd_movimentos > 0),
  qtd_lancadas int not null default 0,
  qtd_conciliadas int not null default 0,
  qtd_ignoradas int not null default 0,
  qtd_ja_importadas int not null default 0,
  importado_por uuid not null references public.perfis(user_id) on delete restrict,
  importado_em timestamptz not null default now(),
  unique (condominio_id, arquivo_sha256)
);

create table if not exists public.extrato_linhas (
  id uuid primary key default gen_random_uuid(),
  extrato_id uuid not null references public.extratos_importados(id) on delete restrict deferrable initially deferred,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  ordem int not null,
  data_mov date not null,
  valor_centavos bigint not null check (valor_centavos <> 0),        -- positivo = crédito, negativo = débito
  memo text not null check (char_length(memo) between 1 and 200),
  fitid text check (char_length(fitid) <= 60),
  chave text not null,                                              -- data|valor|memo normalizado (evita importar o mesmo movimento duas vezes)
  status text not null check (status in ('lancada', 'conciliada', 'ignorada')),
  lancamento_id uuid references public.lancamentos(id) on delete restrict,
  motivo_ignorar text check (motivo_ignorar is null or char_length(motivo_ignorar) between 5 and 200),
  check ((status = 'ignorada') = (lancamento_id is null)),
  check ((status = 'ignorada') = (motivo_ignorar is not null))
);
create unique index if not exists extrato_linhas_lancamento_uk on public.extrato_linhas (lancamento_id) where lancamento_id is not null;
create index if not exists extrato_linhas_chave_idx on public.extrato_linhas (condominio_id, chave);
create index if not exists extrato_linhas_extrato_idx on public.extrato_linhas (extrato_id, ordem);

create table if not exists public.regras_extrato (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  memo_padrao text not null check (char_length(memo_padrao) between 1 and 200),
  sinal smallint not null check (sinal in (-1, 1)),
  valor_centavos bigint check (valor_centavos is null or valor_centavos > 0),
  categoria text not null check (char_length(categoria) between 1 and 60),
  descricao text not null check (char_length(descricao) between 1 and 120),
  fornecedor text check (char_length(fornecedor) <= 120),
  criada_por uuid not null references public.perfis(user_id) on delete restrict,
  atualizada_em timestamptz not null default now()
);
create unique index if not exists regras_extrato_uk on public.regras_extrato (condominio_id, memo_padrao, sinal, coalesce(valor_centavos, 0));

alter table public.extratos_importados enable row level security;
alter table public.extrato_linhas enable row level security;
alter table public.regras_extrato enable row level security;

drop policy if exists extratos_select on public.extratos_importados;
create policy extratos_select on public.extratos_importados for select
  using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
drop policy if exists extrato_linhas_select on public.extrato_linhas;
create policy extrato_linhas_select on public.extrato_linhas for select
  using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
drop policy if exists regras_extrato_select on public.regras_extrato;
create policy regras_extrato_select on public.regras_extrato for select
  using (condominio_id = public.meu_condominio_id() and public.equipe_admin());

-- só leitura pelo app; toda escrita passa pela função importar_extrato
revoke all on public.extratos_importados, public.extrato_linhas, public.regras_extrato from anon, authenticated;
grant select on public.extratos_importados, public.extrato_linhas, public.regras_extrato to authenticated;

-- extratos e suas linhas, uma vez gravados, não mudam nem somem (são a evidência da importação)
create or replace function public.bloquear_alteracao_extrato() returns trigger
language plpgsql as $$
begin raise exception 'Extratos importados não podem ser alterados nem apagados'; end $$;
drop trigger if exists trg_bloquear_extratos on public.extratos_importados;
create trigger trg_bloquear_extratos before update or delete on public.extratos_importados for each row execute function public.bloquear_alteracao_extrato();
drop trigger if exists trg_bloquear_extrato_linhas on public.extrato_linhas;
create trigger trg_bloquear_extrato_linhas before update or delete on public.extrato_linhas for each row execute function public.bloquear_alteracao_extrato();

-- ---------------------------------------------------------------------------------------
-- 2. Saldo do livro-caixa em uma data (abertura + entradas − saídas até a data, inclusive)
-- ---------------------------------------------------------------------------------------
create or replace function public.saldo_livro_em(p_data date) returns bigint
language plpgsql stable security definer set search_path = public
as $$
declare v_cond uuid; v_ab bigint; v_ab_data date; v_mov bigint;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_conselho_ou_sindico() then raise exception 'Restrito ao síndico e ao conselho'; end if;
  if p_data is null then raise exception 'Informe a data'; end if;
  v_cond := public.meu_condominio_id();
  select saldo_inicial_centavos, saldo_inicial_data into v_ab, v_ab_data from public.condominios where id = v_cond;
  if v_ab_data is not null and p_data < v_ab_data then return 0; end if;
  select coalesce(sum(
           case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos
                when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then -l.valor_centavos else 0 end), 0)
    into v_mov
    from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
   where l.condominio_id = v_cond and l.data_lancamento <= p_data and (v_ab_data is null or l.data_lancamento >= v_ab_data);
  return (case when v_ab_data is null then 0 else v_ab end) + v_mov;
end $$;
revoke all on function public.saldo_livro_em(date) from public, anon;
grant execute on function public.saldo_livro_em(date) to authenticated;

-- ---------------------------------------------------------------------------------------
-- 3. Importação (uma transação)
--    p_linhas: [{ data, valor_centavos (com sinal), memo, fitid, acao: lancar|conciliar|ignorar,
--                 categoria, descricao, fornecedor, lancamento_id, motivo, lembrar: memo|memo_valor }]
-- ---------------------------------------------------------------------------------------
create or replace function public.importar_extrato(
  p_arquivo_nome text, p_sha256 text, p_periodo_ini date, p_periodo_fim date,
  p_saldo_final_centavos bigint, p_saldo_data date, p_linhas jsonb, p_exigir_saldo boolean default true
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_cond uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_ext uuid := gen_random_uuid();
  r record; v_n int; v_chave text; v_ja int; v_dentro int; v_acao text; v_valor bigint; v_tipo text; v_sinal int;
  v_cat text; v_desc text; v_forn text; v_motivo text; v_lid uuid; v_lanc public.lancamentos%rowtype; v_memo text; v_data date;
  v_lanc_n int := 0; v_conc_n int := 0; v_ign_n int := 0; v_ja_n int := 0; v_total int := 0;
  v_ab bigint; v_ab_data date; v_livro bigint; v_dif bigint; v_cont jsonb := '{}'::jsonb; v_seq int;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode importar extratos'; end if;
  v_cond := public.meu_condominio_id();
  if p_arquivo_nome is null or char_length(trim(p_arquivo_nome)) not between 1 and 200 then raise exception 'Nome do arquivo inválido'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Impressão digital do arquivo inválida'; end if;
  if p_periodo_ini is null or p_periodo_fim is null or p_periodo_fim < p_periodo_ini then raise exception 'Período do extrato inválido'; end if;
  if p_periodo_fim > v_hoje then raise exception 'O extrato não pode terminar no futuro'; end if;
  if p_saldo_final_centavos is not null and (p_saldo_data is null or p_saldo_data < p_periodo_ini or p_saldo_data > p_periodo_fim) then
    raise exception 'A data do saldo deve estar dentro do período do extrato'; end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) not between 1 and 2000 then raise exception 'O extrato deve ter de 1 a 2000 movimentos'; end if;
  if exists (select 1 from public.extratos_importados where condominio_id = v_cond and arquivo_sha256 = p_sha256) then
    raise exception 'Este arquivo já foi importado em %', (select to_char(importado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') from public.extratos_importados where condominio_id = v_cond and arquivo_sha256 = p_sha256);
  end if;
  select saldo_inicial_centavos, saldo_inicial_data into v_ab, v_ab_data from public.condominios where id = v_cond;

  for r in select e.value as j, e.ordinality::int as ord from jsonb_array_elements(p_linhas) with ordinality as e(value, ordinality) order by e.ordinality loop
    begin
      v_total := v_total + 1;
      v_memo := regexp_replace(btrim(coalesce(r.j->>'memo', '')), '\s+', ' ', 'g');
      if char_length(v_memo) not between 1 and 200 then raise exception 'Descrição do extrato inválida'; end if;
      v_data := (r.j->>'data')::date; v_valor := (r.j->>'valor_centavos')::bigint;
      if v_data is null or v_data < date '2000-01-01' or v_data > v_hoje then raise exception 'Data inválida'; end if;
      if v_valor is null or v_valor = 0 or abs(v_valor) > 1000000000 then raise exception 'Valor inválido'; end if;
      v_sinal := case when v_valor > 0 then 1 else -1 end; v_tipo := case when v_valor > 0 then 'receita' else 'despesa' end;
      v_chave := v_data::text || '|' || v_valor::text || '|' || upper(v_memo);
      -- movimentos idênticos podem se repetir (ex.: duas tarifas iguais no mesmo dia). A n-ésima ocorrência no arquivo só é
      -- "já importada" se o banco já tinha n; assim, reenviar um período que se sobrepõe a outro não duplica nada.
      v_seq := coalesce((v_cont->>v_chave)::int, 0) + 1; v_cont := jsonb_set(v_cont, array[v_chave], to_jsonb(v_seq));
      select count(*) into v_ja from public.extrato_linhas where condominio_id = v_cond and chave = v_chave;
      if v_seq <= v_ja then v_ja_n := v_ja_n + 1; continue; end if;

      v_acao := coalesce(r.j->>'acao', '');
      if v_acao = 'lancar' then
        v_cat := btrim(coalesce(r.j->>'categoria', '')); v_desc := btrim(coalesce(r.j->>'descricao', '')); v_forn := nullif(btrim(coalesce(r.j->>'fornecedor', '')), '');
        if char_length(v_cat) not between 1 and 60 then raise exception 'Categoria deve ter de 1 a 60 caracteres'; end if;
        if char_length(v_desc) not between 1 and 120 then raise exception 'Descrição deve ter de 1 a 120 caracteres'; end if;
        if char_length(coalesce(v_forn, '')) > 120 then raise exception 'Fornecedor deve ter até 120 caracteres'; end if;
        insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, observacao, criado_por)
        values (v_cond, v_tipo::public.tipo_lancamento, v_data, date_trunc('month', v_data)::date, abs(v_valor), v_cat, v_desc, v_forn, left('Extrato: ' || v_memo, 300), auth.uid())
        returning id into v_lid;
        insert into public.extrato_linhas (id, extrato_id, condominio_id, ordem, data_mov, valor_centavos, memo, fitid, chave, status, lancamento_id)
        values (gen_random_uuid(), v_ext, v_cond, r.ord, v_data, v_valor, v_memo, left(nullif(btrim(coalesce(r.j->>'fitid', '')), ''), 60), v_chave, 'lancada', v_lid);
        v_lanc_n := v_lanc_n + 1;
        if (r.j->>'lembrar') in ('memo', 'memo_valor') then
          insert into public.regras_extrato (condominio_id, memo_padrao, sinal, valor_centavos, categoria, descricao, fornecedor, criada_por)
          values (v_cond, upper(v_memo), v_sinal, case when r.j->>'lembrar' = 'memo_valor' then abs(v_valor) end, v_cat, v_desc, v_forn, auth.uid())
          on conflict (condominio_id, memo_padrao, sinal, coalesce(valor_centavos, 0))
          do update set categoria = excluded.categoria, descricao = excluded.descricao, fornecedor = excluded.fornecedor, atualizada_em = now();
        end if;
      elsif v_acao = 'conciliar' then
        if nullif(btrim(coalesce(r.j->>'lancamento_id', '')), '') is null then raise exception 'Escolha o lançamento a conciliar'; end if;
        begin v_lid := (r.j->>'lancamento_id')::uuid; exception when others then raise exception 'Lançamento a conciliar inválido'; end;
        select * into v_lanc from public.lancamentos where id = v_lid and condominio_id = v_cond;
        if not found then raise exception 'Lançamento a conciliar não encontrado'; end if;
        if v_lanc.tipo::text <> v_tipo then raise exception 'O lançamento escolhido não é uma %', v_tipo; end if;
        if v_lanc.valor_centavos <> abs(v_valor) then raise exception 'O valor do lançamento escolhido é diferente do valor do extrato'; end if;
        if v_lanc.estornado_em is not null then raise exception 'O lançamento escolhido foi estornado'; end if;
        if abs(v_lanc.data_lancamento - v_data) > 31 then raise exception 'A data do lançamento escolhido está a mais de 31 dias da data do extrato'; end if;
        if exists (select 1 from public.extrato_linhas where lancamento_id = v_lid) then raise exception 'O lançamento escolhido já está conciliado com outro movimento do extrato'; end if;
        insert into public.extrato_linhas (id, extrato_id, condominio_id, ordem, data_mov, valor_centavos, memo, fitid, chave, status, lancamento_id)
        values (gen_random_uuid(), v_ext, v_cond, r.ord, v_data, v_valor, v_memo, left(nullif(btrim(coalesce(r.j->>'fitid', '')), ''), 60), v_chave, 'conciliada', v_lid);
        v_conc_n := v_conc_n + 1;
      elsif v_acao = 'ignorar' then
        v_motivo := btrim(coalesce(r.j->>'motivo', ''));
        if char_length(v_motivo) not between 5 and 200 then raise exception 'Informe o motivo para ignorar (5 a 200 caracteres)'; end if;
        insert into public.extrato_linhas (id, extrato_id, condominio_id, ordem, data_mov, valor_centavos, memo, fitid, chave, status, motivo_ignorar)
        values (gen_random_uuid(), v_ext, v_cond, r.ord, v_data, v_valor, v_memo, left(nullif(btrim(coalesce(r.j->>'fitid', '')), ''), 60), v_chave, 'ignorada', v_motivo);
        v_ign_n := v_ign_n + 1;
      else
        raise exception 'Escolha o que fazer com o movimento (lançar, conciliar ou ignorar)';
      end if;
    exception when others then
      raise exception 'Movimento % (% — %): %', r.ord, to_char(coalesce(v_data, date '2000-01-01'), 'DD/MM/YYYY'), left(coalesce(v_memo, ''), 40), sqlerrm;
    end;
  end loop;

  if v_lanc_n + v_conc_n + v_ign_n = 0 then raise exception 'Todos os movimentos deste extrato já foram importados antes'; end if;

  v_livro := null; v_dif := null;
  if p_saldo_final_centavos is not null then
    select coalesce(sum(case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos
                             when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then -l.valor_centavos else 0 end), 0)
      into v_livro from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
     where l.condominio_id = v_cond and l.data_lancamento <= p_saldo_data and (v_ab_data is null or l.data_lancamento >= v_ab_data);
    v_livro := (case when v_ab_data is null or p_saldo_data < v_ab_data then 0 else v_ab end) + v_livro;
    v_dif := p_saldo_final_centavos - v_livro;
    if p_exigir_saldo and v_dif <> 0 then
      raise exception 'Saldo do livro-caixa em % ficaria R$ %, mas o extrato informa R$ % (diferença de R$ %). Nada foi importado.',
        to_char(p_saldo_data, 'DD/MM/YYYY'), replace(to_char(v_livro / 100.0, 'FM999999990.00'), '.', ','), replace(to_char(p_saldo_final_centavos / 100.0, 'FM999999990.00'), '.', ','), replace(to_char(v_dif / 100.0, 'FM999999990.00'), '.', ',');
    end if;
  end if;

  insert into public.extratos_importados (id, condominio_id, arquivo_nome, arquivo_sha256, periodo_ini, periodo_fim, saldo_final_centavos, saldo_data, diferenca_saldo_centavos,
                                          qtd_movimentos, qtd_lancadas, qtd_conciliadas, qtd_ignoradas, qtd_ja_importadas, importado_por)
  values (v_ext, v_cond, btrim(p_arquivo_nome), p_sha256, p_periodo_ini, p_periodo_fim, p_saldo_final_centavos, p_saldo_data, v_dif,
          v_total, v_lanc_n, v_conc_n, v_ign_n, v_ja_n, auth.uid());

  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'importar_extrato', 'extratos_importados', v_ext,
          jsonb_build_object('movimentos', v_total, 'lancadas', v_lanc_n, 'conciliadas', v_conc_n, 'ignoradas', v_ign_n, 'ja_importadas', v_ja_n, 'diferenca_saldo_centavos', v_dif));
  return jsonb_build_object('extrato_id', v_ext, 'lancadas', v_lanc_n, 'conciliadas', v_conc_n, 'ignoradas', v_ign_n, 'ja_importadas', v_ja_n,
                            'saldo_livro_centavos', v_livro, 'diferenca_saldo_centavos', v_dif);
end $$;
revoke all on function public.importar_extrato(text, text, date, date, bigint, date, jsonb, boolean) from public, anon;
grant execute on function public.importar_extrato(text, text, date, date, bigint, date, jsonb, boolean) to authenticated;
