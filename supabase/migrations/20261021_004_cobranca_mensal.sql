-- V1.7 — Cobrança mensal por unidade (preparação dos boletos).
-- Aplicar depois de schema.sql e das migrações 001, 002 e 003, em ambiente de teste.
-- Esta migração NÃO emite boleto bancário: gera, confere e libera as cobranças (valor, vencimento e itens)
-- que alimentam a emissão pela CAIXA (manual ou, no futuro, pela integração da Edge Function).

-- 1) Novos tipos de item (a lista da migração 001 não tinha fundo de obras, gás, parcelas e compensação).
alter table public.itens_cobranca drop constraint itens_cobranca_tipo_check;
alter table public.itens_cobranca add constraint itens_cobranca_tipo_check check (tipo in (
  'cota_condominial','fundo_obras','agua','gas','parcelada','compensacao','rateio','multa','juros','desconto','outro'));

-- 2) Competência de consumo da água (a fatura costuma ser de mês anterior ao da cobrança).
alter table public.rateios_agua add column competencia_consumo date;

-- 3) Ciclo mensal: um registro por condomínio/competência, com situação e totais.
create table public.ciclos_cobranca (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  vencimento date not null,
  status text not null default 'gerado' check (status in ('gerado','liberado')),
  total_centavos bigint not null default 0 check (total_centavos >= 0),
  gerado_por uuid not null references public.perfis(user_id) on delete restrict,
  gerado_em timestamptz not null default now(),
  liberado_por uuid references public.perfis(user_id) on delete restrict,
  liberado_em timestamptz,
  unique (condominio_id, competencia),
  check ((status = 'liberado') = (liberado_em is not null))
);
alter table public.cobrancas add column ciclo_id uuid references public.ciclos_cobranca(id) on delete restrict;
create index cobrancas_ciclo_idx on public.cobrancas(ciclo_id);

-- 4) Itens previstos informados pelo síndico para a competência (gás, parcelas, compensações...).
--    Cota condominial, fundo de obras e água são calculados pela função a partir da previsão e do rateio.
create table public.itens_cobranca_previstos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  tipo text not null check (tipo in ('gas','parcelada','compensacao','desconto','multa','juros','outro')),
  descricao text not null check (length(trim(descricao)) between 1 and 120),
  valor_centavos bigint not null check (valor_centavos <> 0),
  detalhes jsonb,               -- ex.: leituras do gás {leitura_anterior, leitura_atual, consumo_m3, preco_m3}
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now()
);
create index itens_previstos_comp_idx on public.itens_cobranca_previstos(condominio_id, competencia, unidade_id);

-- 5) RLS: síndico administra; conselho consulta; morador não acessa estas tabelas (vê só suas cobranças).
alter table public.ciclos_cobranca enable row level security;
alter table public.itens_cobranca_previstos enable row level security;
create policy ciclos_leitura_equipe on public.ciclos_cobranca
  for select to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
-- Sem policy de escrita para clientes: o ciclo só é criado/alterado pelas funções abaixo.
create policy itens_previstos_leitura_equipe on public.itens_cobranca_previstos
  for select to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
create policy itens_previstos_admin_escrita on public.itens_cobranca_previstos
  for all to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_admin())
  with check (condominio_id = public.meu_condominio_id() and public.equipe_admin());

-- 6) Conferência: devolve problemas (nivel 'erro' impede a liberação; 'aviso' só informa).
create or replace function public.validar_cobranca_mensal(p_competencia date)
returns table(nivel text, codigo text, mensagem text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_cond uuid; v_ciclo public.ciclos_cobranca%rowtype; v_n_unid int; v_n_cob int; v_soma numeric(12,7);
  v_fatura bigint; v_agua bigint; v_div int; v_rateio uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_conselho_ou_sindico() then raise exception 'Acesso restrito a síndico e conselho'; end if;
  v_cond := public.meu_condominio_id();
  select * into v_ciclo from public.ciclos_cobranca where condominio_id = v_cond and competencia = p_competencia;
  if not found then
    return query select 'erro'::text, 'ciclo_inexistente'::text, 'Nenhuma cobrança gerada para a competência.'::text; return;
  end if;
  select count(*), coalesce(sum(fracao_ideal),0) into v_n_unid, v_soma from public.unidades where condominio_id = v_cond and ativa;
  if v_soma <> 1.0000000 then
    return query select 'erro'::text, 'fracoes'::text, format('As frações ideais ativas somam %s (deve ser 1,0000000).', v_soma); end if;
  select count(*) into v_n_cob from public.cobrancas where ciclo_id = v_ciclo.id;
  if v_n_cob <> v_n_unid then
    return query select 'erro'::text, 'unidades'::text, format('%s cobranças para %s unidades ativas.', v_n_cob, v_n_unid); end if;
  select count(*) into v_div from public.cobrancas c
    where c.ciclo_id = v_ciclo.id and c.valor_total_centavos <> coalesce((select sum(i.valor_centavos) from public.itens_cobranca i where i.cobranca_id = c.id),0);
  if v_div > 0 then
    return query select 'erro'::text, 'total_itens'::text, format('%s cobrança(s) com total diferente da soma dos itens.', v_div); end if;
  select count(*) into v_div from public.cobrancas c where c.ciclo_id = v_ciclo.id and (c.vencimento <> v_ciclo.vencimento);
  if v_div > 0 then
    return query select 'aviso'::text, 'vencimento'::text, format('%s cobrança(s) com vencimento diferente do ciclo.', v_div); end if;
  select r.id, r.valor_fatura_centavos into v_rateio, v_fatura from public.rateios_agua r where r.condominio_id = v_cond and r.competencia = p_competencia;
  if v_rateio is not null then
    select coalesce(sum(i.valor_centavos),0) into v_agua from public.itens_cobranca i join public.cobrancas c on c.id = i.cobranca_id
      where c.ciclo_id = v_ciclo.id and i.tipo = 'agua';
    if v_agua <> v_fatura then
      return query select 'erro'::text, 'agua'::text, format('Água cobrada (%s) difere da fatura (%s) em centavos.', v_agua, v_fatura); end if;
  end if;
  if v_ciclo.vencimento < v_ciclo.competencia then
    return query select 'aviso'::text, 'vencimento_anterior'::text, 'Vencimento anterior ao mês de competência.'::text; end if;
end $$;

-- 7) Geração: calcula e grava as cobranças em rascunho, uma por unidade ativa, com itens discriminados.
create or replace function public.gerar_cobranca_mensal(
  p_competencia date,
  p_vencimento date,
  p_fatura_agua_centavos bigint default null,
  p_competencia_consumo_agua date default null,
  p_substituir_rascunhos boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cond uuid; v_user uuid := auth.uid(); v_prev public.previsoes_mensais%rowtype;
  v_soma numeric(12,7); v_n int; v_rateio uuid; v_fatura bigint; v_ciclo uuid; v_resto bigint; v_cob uuid; r record;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode gerar cobranças'; end if;
  v_cond := public.meu_condominio_id();
  if p_competencia is null or p_competencia <> date_trunc('month', p_competencia)::date then
    raise exception 'Competência deve ser o primeiro dia do mês'; end if;
  if p_vencimento is null then raise exception 'Informe o vencimento'; end if;

  -- trava por condomínio/competência para evitar geração concorrente
  perform pg_advisory_xact_lock(hashtextextended(v_cond::text || p_competencia::text, 0));

  select * into v_prev from public.previsoes_mensais where condominio_id = v_cond and competencia = p_competencia;
  if not found then raise exception 'Cadastre a previsão orçamentária da competência antes de gerar'; end if;
  select count(*), coalesce(sum(fracao_ideal),0) into v_n, v_soma from public.unidades
    where condominio_id = v_cond and ativa;
  if v_n = 0 then raise exception 'Nenhuma unidade ativa'; end if;
  if exists (select 1 from public.unidades where condominio_id = v_cond and ativa and (fracao_ideal is null or fracao_ideal <= 0)) then
    raise exception 'Há unidade ativa sem fração ideal'; end if;
  if v_soma <> 1.0000000 then raise exception 'As frações ideais ativas somam % (deve ser 1,0000000)', v_soma; end if;

  -- cobranças já existentes
  if exists (select 1 from public.cobrancas where condominio_id = v_cond and competencia = p_competencia) then
    if not p_substituir_rascunhos then
      raise exception 'Já existem cobranças para esta competência'; end if;
    if exists (select 1 from public.cobrancas where condominio_id = v_cond and competencia = p_competencia and status <> 'rascunho') then
      raise exception 'Só é possível substituir cobranças em rascunho'; end if;
    delete from public.itens_cobranca where cobranca_id in (select id from public.cobrancas where condominio_id = v_cond and competencia = p_competencia);
    delete from public.cobrancas where condominio_id = v_cond and competencia = p_competencia;
    delete from public.ciclos_cobranca where condominio_id = v_cond and competencia = p_competencia;
  end if;

  -- rateio da água (fração aplicada fica gravada; rateio existente é reutilizado, nunca reescrito)
  select id, valor_fatura_centavos into v_rateio, v_fatura from public.rateios_agua where condominio_id = v_cond and competencia = p_competencia;
  if v_rateio is not null then
    if p_fatura_agua_centavos is not null and p_fatura_agua_centavos <> v_fatura then
      raise exception 'Já existe rateio de água fechado para a competência com outra fatura'; end if;
  else
    if p_fatura_agua_centavos is null or p_fatura_agua_centavos <= 0 then
      raise exception 'Informe a fatura de água da competência'; end if;
    v_fatura := p_fatura_agua_centavos;
    insert into public.rateios_agua (condominio_id, competencia, valor_fatura_centavos, vencimento, competencia_consumo)
      values (v_cond, p_competencia, v_fatura, null, p_competencia_consumo_agua) returning id into v_rateio;
    -- maior resto: piso em centavos + 1 centavo para os maiores restos; empate decidido pela identificação da unidade
    create temp table tmp_agua on commit drop as
      select u.id as unidade_id, u.identificacao, u.fracao_ideal,
             floor(v_fatura * u.fracao_ideal)::bigint as base,
             (v_fatura * u.fracao_ideal) - floor(v_fatura * u.fracao_ideal) as resto
      from public.unidades u where u.condominio_id = v_cond and u.ativa;
    v_resto := v_fatura - (select sum(base) from tmp_agua);
    insert into public.rateios_agua_itens (condominio_id, rateio_id, unidade_id, fracao_aplicada, valor_centavos)
      select v_cond, v_rateio, t.unidade_id, t.fracao_ideal,
             t.base + case when row_number() over (order by t.resto desc, t.identificacao) <= v_resto then 1 else 0 end
      from tmp_agua t;
  end if;

  insert into public.ciclos_cobranca (condominio_id, competencia, vencimento, gerado_por)
    values (v_cond, p_competencia, p_vencimento, v_user) returning id into v_ciclo;

  -- itens por unidade
  create temp table tmp_itens on commit drop as
    select u.id as unidade_id, 'cota_condominial'::text as tipo,
           'Cota condominial ' || to_char(p_competencia, 'MM/YYYY') as descricao,
           v_prev.taxa_por_unidade_centavos as valor, null::uuid as rateio_id, 1 as ordem
    from public.unidades u where u.condominio_id = v_cond and u.ativa and v_prev.taxa_por_unidade_centavos > 0
    union all
    select u.id, 'fundo_obras', 'Fundo de obras ' || to_char(p_competencia, 'MM/YYYY'), v_prev.fundo_obras_por_unidade_centavos, null, 2
    from public.unidades u where u.condominio_id = v_cond and u.ativa and v_prev.fundo_obras_por_unidade_centavos > 0
    union all
    select i.unidade_id, 'agua', 'Água (rateio pela fração ideal ' || to_char(i.fracao_aplicada, 'FM0.0000000') || ')', i.valor_centavos, v_rateio, 3
    from public.rateios_agua_itens i where i.rateio_id = v_rateio and i.valor_centavos <> 0
    union all
    select p.unidade_id, p.tipo, p.descricao, p.valor_centavos, null,
           case p.tipo when 'gas' then 4 when 'parcelada' then 5 when 'compensacao' then 6 else 7 end
    from public.itens_cobranca_previstos p where p.condominio_id = v_cond and p.competencia = p_competencia;

  for r in
    select u.id as unidade_id, u.identificacao, coalesce(sum(t.valor),0)::bigint as total
    from public.unidades u left join tmp_itens t on t.unidade_id = u.id
    where u.condominio_id = v_cond and u.ativa group by u.id, u.identificacao order by u.identificacao
  loop
    if r.total <= 0 then raise exception 'Unidade % com total não positivo (%): revise os itens', r.identificacao, r.total; end if;
    insert into public.cobrancas (condominio_id, unidade_id, competencia, vencimento, valor_total_centavos, criado_por, ciclo_id)
      values (v_cond, r.unidade_id, p_competencia, p_vencimento, r.total, v_user, v_ciclo) returning id into v_cob;
    insert into public.itens_cobranca (cobranca_id, tipo, descricao, valor_centavos, rateio_id)
      select v_cob, t.tipo, t.descricao, t.valor, t.rateio_id from tmp_itens t where t.unidade_id = r.unidade_id order by t.ordem, t.descricao;
  end loop;

  update public.ciclos_cobranca set total_centavos = (select sum(valor_total_centavos) from public.cobrancas where ciclo_id = v_ciclo) where id = v_ciclo;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, 'cobranca_mensal.gerar', 'ciclos_cobranca', v_ciclo,
            jsonb_build_object('competencia', p_competencia, 'vencimento', p_vencimento, 'unidades', v_n, 'substituiu_rascunhos', p_substituir_rascunhos));
  return v_ciclo;
end $$;

-- 8) Liberação: só com a conferência sem erros; muda as cobranças para 'pronta_para_emissao'.
create or replace function public.liberar_cobranca_mensal(p_competencia date)
returns void language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_ciclo public.ciclos_cobranca%rowtype; v_msg text;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode liberar cobranças'; end if;
  v_cond := public.meu_condominio_id();
  select * into v_ciclo from public.ciclos_cobranca where condominio_id = v_cond and competencia = p_competencia for update;
  if not found then raise exception 'Nenhuma cobrança gerada para a competência'; end if;
  if v_ciclo.status = 'liberado' then raise exception 'Cobranças já liberadas'; end if;
  if exists (select 1 from public.cobrancas where ciclo_id = v_ciclo.id and status <> 'rascunho') then
    raise exception 'Há cobrança fora de rascunho'; end if;
  select string_agg(mensagem, ' | ') into v_msg from public.validar_cobranca_mensal(p_competencia) where nivel = 'erro';
  if v_msg is not null then raise exception 'Conferência com erro: %', v_msg; end if;
  update public.cobrancas set status = 'pronta_para_emissao', atualizado_em = now() where ciclo_id = v_ciclo.id;
  update public.ciclos_cobranca set status = 'liberado', liberado_por = v_user, liberado_em = now() where id = v_ciclo.id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, 'cobranca_mensal.liberar', 'ciclos_cobranca', v_ciclo.id, jsonb_build_object('competencia', p_competencia, 'total_centavos', v_ciclo.total_centavos));
end $$;

-- 9) Reabertura: volta para rascunho enquanto nenhum boleto foi enviado/registrado no banco.
create or replace function public.reabrir_cobranca_mensal(p_competencia date)
returns void language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_ciclo public.ciclos_cobranca%rowtype;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode reabrir cobranças'; end if;
  v_cond := public.meu_condominio_id();
  select * into v_ciclo from public.ciclos_cobranca where condominio_id = v_cond and competencia = p_competencia for update;
  if not found then raise exception 'Nenhuma cobrança gerada para a competência'; end if;
  if v_ciclo.status <> 'liberado' then raise exception 'Cobranças não estão liberadas'; end if;
  if exists (select 1 from public.cobrancas where ciclo_id = v_ciclo.id and (status <> 'pronta_para_emissao' or identificador_externo is not null or nosso_numero is not null)) then
    raise exception 'Há boleto já enviado ou registrado: cancele-o no banco antes de reabrir'; end if;
  update public.cobrancas set status = 'rascunho', atualizado_em = now() where ciclo_id = v_ciclo.id;
  update public.ciclos_cobranca set status = 'gerado', liberado_por = null, liberado_em = null where id = v_ciclo.id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, 'cobranca_mensal.reabrir', 'ciclos_cobranca', v_ciclo.id, jsonb_build_object('competencia', p_competencia));
end $$;

-- 10) Visão para a emissão dos boletos (respeita a RLS de quem consulta).
create or replace view public.v_cobrancas_para_emissao with (security_invoker = true) as
select c.id as cobranca_id, c.ciclo_id, c.condominio_id, u.identificacao as unidade, c.competencia, c.vencimento,
       c.valor_total_centavos, c.status,
       (select jsonb_agg(jsonb_build_object('tipo', i.tipo, 'descricao', i.descricao, 'valor_centavos', i.valor_centavos) order by i.criado_em, i.descricao)
          from public.itens_cobranca i where i.cobranca_id = c.id) as itens
from public.cobrancas c join public.unidades u on u.id = c.unidade_id
where c.status = 'pronta_para_emissao';

revoke execute on function public.gerar_cobranca_mensal(date,date,bigint,date,boolean) from public, anon;
revoke execute on function public.liberar_cobranca_mensal(date) from public, anon;
revoke execute on function public.reabrir_cobranca_mensal(date) from public, anon;
revoke execute on function public.validar_cobranca_mensal(date) from public, anon;
grant execute on function public.gerar_cobranca_mensal(date,date,bigint,date,boolean) to authenticated;
grant execute on function public.liberar_cobranca_mensal(date) to authenticated;
grant execute on function public.reabrir_cobranca_mensal(date) to authenticated;
grant execute on function public.validar_cobranca_mensal(date) to authenticated;

comment on table public.ciclos_cobranca is 'Ciclo mensal de cobrança: gerado -> liberado. Liberar não emite boleto; a emissão depende da integração/convênio CAIXA.';
comment on table public.itens_cobranca_previstos is 'Itens informados pelo síndico para a competência (gás, parcelas, compensações); cota, fundo de obras e água vêm da previsão e do rateio.';
