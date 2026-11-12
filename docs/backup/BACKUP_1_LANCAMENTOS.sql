-- BACKUP 1 de 3 — todos os lançamentos do livro-caixa (o que não se recupera de outro lugar).
-- Como usar: SQL Editor → cole → Run → botão de download (seta) acima do resultado → salve como lancamentos_AAAA-MM-DD.csv
-- NÃO abra nem salve esse arquivo no Excel (ele muda datas e números); guarde-o como foi baixado.
with cond as (select id, nome, saldo_inicial_centavos, saldo_inicial_data from public.condominios where nome = 'Edifício Valença'),
l as (select x.* from public.lancamentos x join cond on cond.id = x.condominio_id),
tot as (
  select count(*) as linhas,
         coalesce(max((select saldo_inicial_centavos from cond)), 0) + coalesce(sum(
           case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos
                when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then -l.valor_centavos else 0 end), 0) as saldo
    from l left join l o on o.id = l.lancamento_original_id)
select l.id, l.tipo, l.data_lancamento, l.competencia, l.valor_centavos, l.categoria, l.descricao, l.fornecedor, l.numero_documento,
       l.observacao, l.lancamento_original_id, l.estornado_em, l.motivo_estorno, l.criado_em, l.versao, l.editado_em,
       cond.nome as condominio_nome, cond.saldo_inicial_centavos, cond.saldo_inicial_data,
       tot.linhas as bk_total_linhas, tot.saldo as bk_saldo_final_centavos, now() as bk_gerado_em
  from l cross join cond cross join tot
 order by l.data_lancamento, l.criado_em, l.id;
