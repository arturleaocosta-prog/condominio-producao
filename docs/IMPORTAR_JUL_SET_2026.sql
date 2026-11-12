-- Importação ÚNICA dos lançamentos de jul–set/2026 (conta corrente), a partir da planilha de Conciliação Bancária.
-- Gerado por tools/gerar_importacao_conciliacao.py. CONTÉM DADOS REAIS: não publicar nem versionar em repositório público.
-- Rodar no SQL Editor do Supabase (como administrador do projeto), depois das migrações 001 a 007.
-- Tudo acontece em uma única transação: se qualquer conferência falhar, nada é gravado.
do $imp$
declare
  v_cond uuid; v_user uuid; v_n int; v_abertura constant bigint := 937002;
  v_ini date; v_e bigint; v_s bigint; v_exp record;
begin
  select id into v_cond from public.condominios where nome = 'Edifício Valença';
  if v_cond is null then raise exception 'Condomínio "Edifício Valença" não encontrado'; end if;
  select user_id into v_user from public.perfis where condominio_id = v_cond and papel = 'sindico' and ativo order by created_at limit 1;
  if v_user is null then raise exception 'Perfil de síndico ativo não encontrado'; end if;
  if exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_conciliacao_2026_07_09') then
    raise exception 'Esta importação já foi executada; não rode de novo';
  end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond and data_lancamento < '2026-10-01') then
    raise exception 'Já existem lançamentos antes de 01/10/2026; confira antes de importar';
  end if;

  update public.condominios set saldo_inicial_centavos = v_abertura, saldo_inicial_data = date '2026-07-01' where id = v_cond;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, observacao, criado_por)
  select v_cond, l.tipo::public.tipo_lancamento, l.data_l, date_trunc('month', l.data_l)::date, l.valor, l.categoria, l.descricao, l.fornecedor, l.observacao, v_user
    from (values
    ('2026-07-03'::date, 'despesa', 4815, 'Taxas e impostos', 'DARF - Conservadora IDEAL', null, 'Competência 06/2026 - não foi pago na gestão da Multservis'),
    ('2026-07-03'::date, 'despesa', 372666, 'Obras', '2M CONSTRUTORA LTDA', '2M CONSTRUTORA LTDA', 'Competência 06/2026 - 08 parcela, não foi pago na gestão da Multservis'),
    ('2026-07-06'::date, 'despesa', 4200, 'Obras', 'Reembolso Paulo - OBRA Interna', null, null),
    ('2026-07-06'::date, 'despesa', 37, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-07-06'::date, 'despesa', 11900, 'Obras', 'Reembolso Bruno - OBRA Interna', null, null),
    ('2026-07-06'::date, 'despesa', 105, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-07-06'::date, 'despesa', 79459, 'Obras', 'Reembolso Lilian - Obra Interna 1ª parcela (Tintas/elétrica e espelho)', null, null),
    ('2026-07-06'::date, 'despesa', 707, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-07-06'::date, 'despesa', 40000, 'Outras despesas', 'Reembolso Chopp - Confraternização moradores - obra interna', null, null),
    ('2026-07-06'::date, 'despesa', 356, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-07-07'::date, 'despesa', 20000, 'Manutenção e reparos', 'NEWTON CARLOS LINTZ', 'NEWTON CARLOS LINTZ', 'Pix Eletricista'),
    ('2026-07-07'::date, 'despesa', 178, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-07-10'::date, 'despesa', 109452, 'Limpeza', 'IDEAL ASSESSORIA LTDA', 'IDEAL ASSESSORIA LTDA', null),
    ('2026-07-15'::date, 'despesa', 159701, 'Água e esgoto', 'Copasa', 'Copasa', null),
    ('2026-07-16'::date, 'receita', 130856, 'Taxa condominial', 'Cota condominial — Apto 302', null, null),
    ('2026-07-16'::date, 'despesa', 630, 'Outras despesas', 'COBRANÇA COMPENSAÇÃO BOLETO', null, null),
    ('2026-07-16'::date, 'receita', 122686, 'Taxa condominial', 'Cota condominial — Apto 02', null, null),
    ('2026-07-16'::date, 'receita', 120871, 'Taxa condominial', 'Cota condominial — Apto 101', null, null),
    ('2026-07-16'::date, 'receita', 114194, 'Taxa condominial', 'Cota condominial — Apto 102', null, null),
    ('2026-07-16'::date, 'receita', 120983, 'Taxa condominial', 'Cota condominial — Apto 201', null, null),
    ('2026-07-17'::date, 'receita', 122495, 'Taxa condominial', 'Cota condominial — Apto 202', null, null),
    ('2026-07-17'::date, 'receita', 125132, 'Taxa condominial', 'Cota condominial — Apto 301', null, null),
    ('2026-07-17'::date, 'despesa', 3780, 'Outras despesas', 'COBRANÇA COMPENSAÇÃO BOLETO', null, null),
    ('2026-07-17'::date, 'despesa', 12228, 'Energia das áreas comuns', 'CEMIG DISTRIBUIÇÃO S A', 'CEMIG DISTRIBUIÇÃO S A', null),
    ('2026-07-17'::date, 'despesa', 24902, 'Seguro', 'ALLIANZ SEGUROS S A', 'ALLIANZ SEGUROS S A', 'Parcela 4/6'),
    ('2026-07-17'::date, 'despesa', 372666, 'Obras', '2M CONSTRUTORA LTDA', '2M CONSTRUTORA LTDA', 'Parcela 9/12'),
    ('2026-07-17'::date, 'despesa', 89000, 'Gás', 'CAICARA GAS LTDA - ME', 'CAICARA GAS LTDA - ME', 'Compra 2 botijões de gás'),
    ('2026-07-17'::date, 'despesa', 98122, 'Honorários', 'SP MULT LTDA', 'SP MULT LTDA', 'Multservis'),
    ('2026-07-27'::date, 'despesa', 7300, 'Outras despesas', 'TARIFA MANUTENCAO CONTA A', null, null),
    ('2026-07-28'::date, 'despesa', 4710, 'Taxas e impostos', 'DARF - Conservadora IDEAL', null, null),
    ('2026-07-30'::date, 'receita', 120754, 'Taxa condominial', 'Cota condominial — Apto 01', null, null),
    ('2026-07-30'::date, 'receita', 2935, 'Outras receitas', 'Juros/multa recebido — Apto 01', null, null),
    ('2026-07-30'::date, 'despesa', 630, 'Outras despesas', 'COBRANÇA COMPENSAÇÃO BOLETO', null, null),
    ('2026-07-30'::date, 'despesa', 52000, 'Fundo de reserva', 'Transferência Aplicação', null, null),
    ('2026-08-04'::date, 'despesa', 800, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-04'::date, 'despesa', 900, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-07'::date, 'receita', 116089, 'Taxa condominial', 'Cota condominial — Apto 201', null, null),
    ('2026-08-07'::date, 'receita', 117573, 'Taxa condominial', 'Cota condominial — Apto 02', null, null),
    ('2026-08-07'::date, 'despesa', 1260, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-07'::date, 'despesa', 110702, 'Limpeza', 'IDEAL ASSESSORIA LTDA', 'IDEAL ASSESSORIA LTDA', null),
    ('2026-08-10'::date, 'despesa', 114334, 'Obras', 'Reembolso Lilian - Obra Interna 2ª parcela (Tintas/elétrica, espelho e painel)', null, null),
    ('2026-08-10'::date, 'despesa', 850, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-08-11'::date, 'receita', 119511, 'Taxa condominial', 'Cota condominial — Apto 301', null, null),
    ('2026-08-11'::date, 'despesa', 630, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-13'::date, 'receita', 125964, 'Taxa condominial', 'Cota condominial — Apto 302', null, null),
    ('2026-08-13'::date, 'despesa', 630, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-14'::date, 'despesa', 24769, 'Seguro', 'ALLIANZ SEGUROS S A', 'ALLIANZ SEGUROS S A', 'Parcela 5/6'),
    ('2026-08-14'::date, 'despesa', 30000, 'Honorários', 'WRAMOS GERENCIAMENTO CONTABIL LTDA', 'WRAMOS GERENCIAMENTO CONTABIL LTDA', null),
    ('2026-08-14'::date, 'despesa', 372666, 'Obras', '2M CONSTRUTORA LTDA', '2M CONSTRUTORA LTDA', 'Parcela 10/12'),
    ('2026-08-17'::date, 'despesa', 12594, 'Energia das áreas comuns', 'CEMIG DISTRIBUIÇÃO S A', 'CEMIG DISTRIBUIÇÃO S A', null),
    ('2026-08-17'::date, 'despesa', 157087, 'Água e esgoto', 'Copasa', 'Copasa', null),
    ('2026-08-17'::date, 'receita', 108926, 'Taxa condominial', 'Cota condominial — Apto 102', null, null),
    ('2026-08-17'::date, 'receita', 114362, 'Taxa condominial', 'Cota condominial — Apto 101', null, null),
    ('2026-08-17'::date, 'despesa', 1260, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-19'::date, 'despesa', 89000, 'Gás', 'CAICARA GAS LTDA', 'CAICARA GAS LTDA', null),
    ('2026-08-19'::date, 'despesa', 16599, 'Outras despesas', 'Reembolso Lilian - Cartório (Registro Ata)', null, null),
    ('2026-08-19'::date, 'despesa', 147, 'Outras despesas', 'Tarifa PIX', null, null),
    ('2026-08-20'::date, 'receita', 115880, 'Taxa condominial', 'Cota condominial — Apto 202', null, null),
    ('2026-08-20'::date, 'receita', 122128, 'Taxa condominial', 'Cota condominial — Apto 01', null, null),
    ('2026-08-20'::date, 'receita', 4917, 'Outras receitas', 'Juros/multa recebido', null, null),
    ('2026-08-20'::date, 'despesa', 1260, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-21'::date, 'receita', 114362, 'Taxa condominial', 'Cota condominial — Apto 101', null, null),
    ('2026-08-21'::date, 'receita', 2363, 'Outras receitas', 'Juros/multa recebido', null, null),
    ('2026-08-21'::date, 'despesa', 630, 'Outras despesas', 'Taxa Cobrança', null, null),
    ('2026-08-25'::date, 'despesa', 7300, 'Outras despesas', 'TARIFA MANUTENCAO CONTA A', null, null),
    ('2026-08-27'::date, 'despesa', 4695, 'Taxas e impostos', 'DARF - Conservadora IDEAL', null, null),
    ('2026-09-01'::date, 'despesa', 52000, 'Fundo de reserva', 'Transferência Aplicação', null, 'Aplicação mês 08/2026'),
    ('2026-09-08'::date, 'despesa', 3900, 'Outras despesas', 'Tarifa', null, null),
    ('2026-09-08'::date, 'despesa', 109452, 'Limpeza', 'IDEAL ASSESSORIA LTDA', 'IDEAL ASSESSORIA LTDA', null),
    ('2026-09-08'::date, 'despesa', 129774, 'Obras', 'Reembolso Lilian - Obra Interna 3ª parcela (Tintas/elétrica, espelho e painel)', null, null),
    ('2026-09-08'::date, 'despesa', 850, 'Outras despesas', 'Tarifa Pix', null, null),
    ('2026-09-09'::date, 'despesa', 800, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-11'::date, 'receita', 118268, 'Taxa condominial', 'Cota condominial — Apto 201', null, null),
    ('2026-09-11'::date, 'despesa', 630, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-14'::date, 'receita', 129019, 'Taxa condominial', 'Cota condominial — Apto 302', null, null),
    ('2026-09-14'::date, 'despesa', 630, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-14'::date, 'despesa', 372666, 'Obras', '2M CONSTRUTORA LTDA', '2M CONSTRUTORA LTDA', 'Parcela 11/12'),
    ('2026-09-14'::date, 'despesa', 24776, 'Seguro', 'ALLIANZ SEGUROS S A', 'ALLIANZ SEGUROS S A', 'Parcela 6/6'),
    ('2026-09-14'::date, 'despesa', 30000, 'Honorários', 'WRAMOS GERENCIAMENTO CONTABIL LTDA', 'WRAMOS GERENCIAMENTO CONTABIL LTDA', null),
    ('2026-09-15'::date, 'receita', 116030, 'Taxa condominial', 'Cota condominial — Apto 02', null, null),
    ('2026-09-15'::date, 'despesa', 630, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-15'::date, 'despesa', 150593, 'Água e esgoto', 'Copasa', 'Copasa', null),
    ('2026-09-17'::date, 'receita', 111548, 'Taxa condominial', 'Cota condominial — Apto 102', null, null),
    ('2026-09-17'::date, 'receita', 119740, 'Taxa condominial', 'Cota condominial — Apto 301', null, null),
    ('2026-09-17'::date, 'despesa', 1260, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-17'::date, 'despesa', 10495, 'Energia das áreas comuns', 'CEMIG DISTRIBUIÇÃO S A', 'CEMIG DISTRIBUIÇÃO S A', null),
    ('2026-09-18'::date, 'despesa', 4589, 'Taxas e impostos', 'DARF - Conservadora IDEAL', null, null),
    ('2026-09-23'::date, 'receita', 118201, 'Taxa condominial', 'Cota condominial — Apto 202', null, null),
    ('2026-09-23'::date, 'receita', 2600, 'Outras receitas', 'Juros/multa recebido', null, null),
    ('2026-09-23'::date, 'despesa', 630, 'Outras despesas', 'Tarifa Cobrança', null, null),
    ('2026-09-25'::date, 'despesa', 7300, 'Outras despesas', 'TARIFA MANUTENCAO CONTA', null, null),
    ('2026-09-30'::date, 'despesa', 52000, 'Fundo de reserva', 'Transferência Aplicação', null, null)
    ) as l(data_l, tipo, valor, categoria, descricao, fornecedor, observacao);
  get diagnostics v_n = row_count;
  if v_n <> 92 then raise exception 'Esperava 92 lançamentos, gravou %', v_n; end if;

  -- conferência mês a mês contra os totais da planilha
  for v_exp in select * from (values
    ('2026-07-01'::date, 980906, 1469544),
    ('2026-08-01'::date, 1062075, 948113),
    ('2026-09-01'::date, 715406, 952975)
  ) as t(mes, entradas, saidas) loop
    select e, s into v_e, v_s from (
      select coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0)::bigint as e,
             coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0)::bigint as s
        from public.lancamentos where condominio_id = v_cond and data_lancamento >= v_exp.mes and data_lancamento < (v_exp.mes + interval '1 month')::date) x;
    if v_e <> v_exp.entradas or v_s <> v_exp.saidas then
      raise exception 'Conferência falhou em %: entradas % (esperado %), saídas % (esperado %)', v_exp.mes, v_e, v_exp.entradas, v_s, v_exp.saidas;
    end if;
  end loop;
  select v_abertura + coalesce(sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end), 0) into v_e
    from public.lancamentos where condominio_id = v_cond;
  if v_e <> 324757 then raise exception 'Saldo final em 30/09/2026 = % (esperado 324757)', v_e; end if;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
  values (v_cond, v_user, 'importar_conciliacao_2026_07_09', 'lancamentos', jsonb_build_object('lancamentos', v_n, 'saldo_abertura_centavos', v_abertura, 'saldo_final_set_centavos', v_e));
end $imp$;

-- Conferência visual (deve mostrar 3 meses e o saldo final de 30/09/2026 = R$ 3,247.57):
select to_char(date_trunc('month', data_lancamento), 'MM/YYYY') as mes, count(*) as lancamentos,
       round(coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0) / 100.0, 2) as entradas,
       round(coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0) / 100.0, 2) as saidas
  from public.lancamentos group by 1 order by 1;
