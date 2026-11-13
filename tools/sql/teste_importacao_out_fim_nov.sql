drop schema if exists t cascade; create schema t;
create table t.res(n serial, secao text, nome text, ok boolean, info text);
grant usage on schema t to public; grant all on t.res to public; grant all on sequence t.res_n_seq to public;
create function t.eu(p uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub', coalesce(p::text,''), true); execute 'set local role authenticated'; end $$;
create function t.fim() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create function t.ok(sec text, nome text, cond boolean, info text default null) returns void language plpgsql as $$ begin
  insert into t.res(secao,nome,ok,info) values (sec,nome,coalesce(cond,false),info); end $$;

-- Cenário: Edifício Valença com jul–set e 01–21/10 importados; fim de outubro e previsão de novembro.
truncate public.auditoria, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-00000000000b','Edifício Valença');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-00000000000b','sindico@v.com'),('33333333-0000-0000-0000-00000000000b','conselho@v.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-00000000000b','aaaaaaaa-0000-0000-0000-00000000000b','Síndico','sindico@v.com','sindico'),
 ('33333333-0000-0000-0000-00000000000b','aaaaaaaa-0000-0000-0000-00000000000b','Conselho','conselho@v.com','conselho');
\i docs/CONFIGURAR_UNIDADES_PRODUCAO.sql
\echo '>>> esperado: ERROR (setembro importado, outubro vazio: pede IMPORTAR_OUT_2026_ATE_21.sql)'
\i docs/IMPORTAR_JUL_SET_2026.sql
\set ON_ERROR_STOP off
\i docs/IMPORTAR_OUT_2026_22_A_31.sql
\set ON_ERROR_STOP on
do $$ begin perform t.ok('fim de outubro','com outubro vazio nada é gravado', (select count(*) from public.lancamentos where data_lancamento >= '2026-10-01') = 0); end $$;
\i docs/IMPORTAR_OUT_2026_ATE_21.sql
-- 01–21/10 pode ter entrado sem o script (importação de extrato no app): a trava agora é só o saldo em 21/10
delete from public.auditoria where acao = 'importar_ofx_2026_10';
-- o síndico já tinha digitado no app a cota do Apto 202 (com a data do crédito, 28/10): não pode duplicar
insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, criado_por)
 values ('aaaaaaaa-0000-0000-0000-00000000000b','receita','2026-10-28','2026-10-01',118181,'Taxa condominial','Cota 202 digitada no app','11111111-0000-0000-0000-00000000000b');
\i docs/IMPORTAR_OUT_2026_22_A_31.sql
do $$
declare S constant text := 'fim de outubro'; r jsonb; v_n int; sind uuid := '11111111-0000-0000-0000-00000000000b';
begin
 select count(*) into v_n from public.lancamentos where data_lancamento between '2026-10-22' and '2026-10-31'; perform t.ok(S,'8 lançamentos de 22 a 31/10 (7 novos + 1 já digitado)', v_n = 8, v_n::text);
 perform t.ok(S,'cota do Apto 202 não foi duplicada', (select count(*) from public.lancamentos where valor_centavos = 118181) = 1);
 perform t.eu(sind); r := public.relatorio_mensal(2026,10);
 perform t.ok(S,'entradas de outubro = 10.639,11', (r->>'entradas_centavos')::bigint = 1063911, r::text);
 perform t.ok(S,'saídas de outubro = 9.876,98', (r->>'saidas_centavos')::bigint = 987698);
 perform t.ok(S,'saldo final de outubro = 4.009,70 (extrato)', (r->>'saldo_final_centavos')::bigint = 400970);
 r := public.relatorio_mensal(2026,11); perform t.ok(S,'novembro começa com 4.009,70', (r->>'saldo_anterior_centavos')::bigint = 400970, r::text);
 perform t.fim();
 perform t.ok(S,'categorias pertencem à lista do app', not exists (select 1 from public.lancamentos where categoria not in
   ('Água e esgoto','Energia das áreas comuns','Manutenção e reparos','Limpeza','Gás','Seguro','Taxas e impostos','Honorários','Obras','Taxa condominial','Fundo de reserva','Outras receitas','Outras despesas')));
 perform t.ok(S,'registrado na auditoria', (select count(*) from public.auditoria where acao = 'importar_conciliacao_2026_10_fim') = 1);
end $$;
\echo '>>> esperado: ERROR "Esta importação já foi executada"'
\set ON_ERROR_STOP off
\i docs/IMPORTAR_OUT_2026_22_A_31.sql
\set ON_ERROR_STOP on
do $$ begin perform t.ok('fim de outubro','segunda execução não duplica', (select count(*) from public.lancamentos where data_lancamento between '2026-10-22' and '2026-10-31') = 8); end $$;

\i docs/PREVISAO_NOV_2026.sql
do $$
declare S constant text := 'previsão nov/2026'; sind uuid := '11111111-0000-0000-0000-00000000000b'; v_ciclo uuid; v record; v_tot bigint; v_err int;
begin
 perform t.ok(S,'previsão com taxa 633,35 e fundo 65,00', exists (select 1 from public.previsoes_mensais where competencia='2026-11-01' and taxa_por_unidade_centavos=63335 and fundo_obras_por_unidade_centavos=6500));
 perform t.ok(S,'17 itens por unidade (7 de gás + 8 parcelas + 2 arredondamentos)', (select count(*) from public.itens_cobranca_previstos where competencia='2026-11-01') = 17);
 perform t.eu(sind);
 v_ciclo := public.gerar_cobranca_mensal('2026-11-01','2026-11-20',136071,'2026-10-01',false);
 select count(*) into v_err from public.validar_cobranca_mensal('2026-11-01') where nivel = 'erro';
 perform t.ok(S,'conferência sem erros', v_err = 0);
 for v in select * from (values ('01',111587),('02',103742),('101',100096),('102',99165),('201',101191),('202',101696),('301',104500),('302',110393)) x(un, tot) loop
   select c.valor_total_centavos into v_tot from public.cobrancas c join public.unidades u on u.id = c.unidade_id where c.ciclo_id = v_ciclo and u.identificacao = v.un;
   perform t.ok(S,'Apto '||v.un||' = planilha ('||v.tot||')', v_tot = v.tot, v_tot::text);
 end loop;
 perform t.ok(S,'total gerado = 8.323,70', (select total_centavos from public.ciclos_cobranca where id = v_ciclo) = 832370);
 perform t.ok(S,'água cobrada = fatura 1.360,71', (select sum(i.valor_centavos) from public.itens_cobranca i join public.cobrancas c on c.id=i.cobranca_id where c.ciclo_id=v_ciclo and i.tipo='agua') = 136071);
 perform t.fim();
end $$;
\echo '>>> esperado: ERROR "Esta importação já foi executada"'
\set ON_ERROR_STOP off
\i docs/PREVISAO_NOV_2026.sql
\set ON_ERROR_STOP on
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
