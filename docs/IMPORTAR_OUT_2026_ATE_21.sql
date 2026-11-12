-- Importação ÚNICA do extrato OFX de 01/10 a 21/10/2026 (conta corrente).
-- Gerado por tools/gerar_importacao_ofx.py. CONTÉM DADOS REAIS: não publicar nem versionar em repositório público.
-- Pré-requisitos: migrações 001 a 007 e IMPORTAR_JUL_SET_2026.sql já executados. Uma única transação: se algo não bater, nada é gravado.
-- Observação: o OFX não identifica o morador; as cotas entram somadas por dia de liquidação.
do $imp$
declare v_cond uuid; v_user uuid; v_n int; v_saldo bigint;
begin
  select id into v_cond from public.condominios where nome = 'Edifício Valença';
  if v_cond is null then raise exception 'Condomínio "Edifício Valença" não encontrado'; end if;
  select user_id into v_user from public.perfis where condominio_id = v_cond and papel = 'sindico' and ativo order by created_at limit 1;
  if v_user is null then raise exception 'Perfil de síndico ativo não encontrado'; end if;
  if not exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_conciliacao_2026_07_09') then
    raise exception 'Rode antes IMPORTAR_JUL_SET_2026.sql'; end if;
  if exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_ofx_2026_10') then
    raise exception 'Esta importação já foi executada; não rode de novo'; end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond and data_lancamento >= date '2026-10-01') then
    raise exception 'Já existem lançamentos a partir de 01/10/2026; confira antes de importar (lançamentos não podem ser apagados)'; end if;
  select saldo_inicial_centavos + coalesce((select sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end) from public.lancamentos where condominio_id = v_cond), 0)
    into v_saldo from public.condominios where id = v_cond;
  if v_saldo <> 324757 then raise exception 'Saldo do livro-caixa antes desta importação = % (o extrato indica 324757)', v_saldo; end if;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, criado_por)
  select v_cond, l.tipo::public.tipo_lancamento, l.data_l, date_trunc('month', l.data_l)::date, l.valor, l.categoria, l.descricao, l.fornecedor, v_user
    from (values
    ('2026-10-01'::date, 'receita', 117918, 'Taxa condominial', 'Cotas recebidas por boleto — liquidação de 01/10', null),
    ('2026-10-01'::date, 'despesa', 630, 'Outras despesas', 'Tarifa de cobrança bancária (1 boleto)', null),
    ('2026-10-08'::date, 'despesa', 131038, 'Obras', 'Reembolso Lilian - Obra Interna 4ª parcela', null),
    ('2026-10-08'::date, 'despesa', 850, 'Outras despesas', 'Tarifa PIX', null),
    ('2026-10-08'::date, 'despesa', 108202, 'Limpeza', 'Ideal Assessoria Ltda', 'Ideal Assessoria Ltda'),
    ('2026-10-15'::date, 'despesa', 145890, 'Água e esgoto', 'Copasa — água e esgoto', 'Copasa'),
    ('2026-10-16'::date, 'receita', 230123, 'Taxa condominial', 'Cotas recebidas por boleto — liquidação de 16/10', null),
    ('2026-10-16'::date, 'despesa', 1260, 'Outras despesas', 'Tarifa de cobrança bancária (2 boletos)', null),
    ('2026-10-19'::date, 'receita', 242363, 'Taxa condominial', 'Cotas recebidas por boleto — liquidação de 19/10', null),
    ('2026-10-19'::date, 'despesa', 1260, 'Outras despesas', 'Tarifa de cobrança bancária (2 boletos)', null),
    ('2026-10-19'::date, 'despesa', 12230, 'Energia das áreas comuns', 'Cemig — energia das áreas comuns', 'Cemig'),
    ('2026-10-19'::date, 'despesa', 30840, 'Honorários', 'Contabilidade (Wramos Gerenciamento Contábil)', 'Wramos Gerenciamento Contábil Ltda'),
    ('2026-10-19'::date, 'despesa', 44500, 'Gás', 'Aquisição de botijão de gás', null),
    ('2026-10-19'::date, 'despesa', 372674, 'Obras', '2M Construtora Ltda', '2M Construtora Ltda'),
    ('2026-10-19'::date, 'despesa', 4589, 'Taxas e impostos', 'DARF — conservadora (Ideal)', null),
    ('2026-10-20'::date, 'receita', 126019, 'Taxa condominial', 'Cotas recebidas por boleto — liquidação de 20/10', null),
    ('2026-10-20'::date, 'despesa', 630, 'Outras despesas', 'Tarifa de cobrança bancária (1 boleto)', null),
    ('2026-10-21'::date, 'receita', 226905, 'Taxa condominial', 'Cotas recebidas por boleto — liquidação de 21/10', null),
    ('2026-10-21'::date, 'despesa', 1260, 'Outras despesas', 'Tarifa de cobrança bancária (2 boletos)', null)
    ) as l(data_l, tipo, valor, categoria, descricao, fornecedor);
  get diagnostics v_n = row_count;
  if v_n <> 19 then raise exception 'Esperava 19 lançamentos, gravou %', v_n; end if;

  select saldo_inicial_centavos + coalesce((select sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end) from public.lancamentos where condominio_id = v_cond), 0)
    into v_saldo from public.condominios where id = v_cond;
  if v_saldo <> 412232 then raise exception 'Saldo após a importação = % (esperado 412232, o saldo do extrato em 21/10)', v_saldo; end if;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
  values (v_cond, v_user, 'importar_ofx_2026_10', 'lancamentos', jsonb_build_object('lancamentos', v_n, 'saldo_final_centavos', v_saldo, 'extrato_ate', '2026-10-21'));
end $imp$;

-- Conferência visual: saldo final = R$ 4,122.32
select count(*) as lancamentos_outubro, round(coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0) / 100.0, 2) as entradas, round(coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0) / 100.0, 2) as saidas
  from public.lancamentos where data_lancamento >= date '2026-10-01';
