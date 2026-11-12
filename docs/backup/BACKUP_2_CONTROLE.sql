-- BACKUP 2 de 3 — controle (conferência do backup). Anote ou tire um print da ÚLTIMA linha e baixe o CSV junto com o backup.
-- A última coluna é o saldo acumulado ao fim de cada mês; a linha de TOTAL traz o saldo final do livro-caixa.
with cond as (select id, saldo_inicial_centavos from public.condominios where nome = 'Edifício Valença'),
mov as (
  select date_trunc('month', l.data_lancamento)::date as mes,
         case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos else 0 end as e,
         case when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then l.valor_centavos else 0 end as s
    from public.lancamentos l join cond on cond.id = l.condominio_id left join public.lancamentos o on o.id = l.lancamento_original_id),
m as (select mes, count(*) as n, sum(e) as e, sum(s) as s from mov group by mes)
select mes_txt as mes, lancamentos, entradas, saidas, saldo_acumulado from (
  select 0 as g, mes as k, to_char(mes, 'MM/YYYY') as mes_txt, n as lancamentos, round(e / 100.0, 2) as entradas, round(s / 100.0, 2) as saidas,
         round(((select saldo_inicial_centavos from cond) + sum(e - s) over (order by mes)) / 100.0, 2) as saldo_acumulado
    from m
  union all
  select 1, null, 'TOTAL', sum(n), round(sum(e) / 100.0, 2), round(sum(s) / 100.0, 2), round(((select saldo_inicial_centavos from cond) + sum(e - s)) / 100.0, 2) from m
) x order by g, k;
