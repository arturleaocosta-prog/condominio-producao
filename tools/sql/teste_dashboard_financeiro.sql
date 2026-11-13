drop schema if exists t cascade; create schema t;
create table t.res(n serial, secao text, nome text, ok boolean, info text);
grant usage on schema t to public; grant all on t.res to public; grant all on sequence t.res_n_seq to public;
create function t.eu(p uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub', coalesce(p::text,''), true); execute 'set local role authenticated'; end $$;
create function t.fim() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create function t.ok(sec text, nome text, cond boolean, info text default null) returns void language plpgsql as $$ begin
  insert into t.res(secao,nome,ok,info) values (sec,nome,coalesce(cond,false),info); end $$;
create function t.erro(sec text, nome text, cmd text, trecho text default null) returns void language plpgsql as $$
declare m text; begin
  begin execute cmd; insert into t.res(secao,nome,ok,info) values (sec,nome,false,'não deu erro');
  exception when others then get stacked diagnostics m = message_text;
    insert into t.res(secao,nome,ok,info) values (sec,nome, trecho is null or m ilike '%'||trecho||'%', m);
  end; end $$;

-- Cenário: Edifício Valença com jul–out/2026 importados; dashboard do exercício jul/2026–jun/2027.
truncate public.auditoria, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-00000000000d','Edifício Valença'),('bbbbbbbb-0000-0000-0000-00000000000d','Outro Prédio');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-00000000000d','s@v.com'),('22222222-0000-0000-0000-00000000000d','m@v.com'),('33333333-0000-0000-0000-00000000000d','c@v.com'),('44444444-0000-0000-0000-00000000000d','x@o.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-00000000000d','aaaaaaaa-0000-0000-0000-00000000000d','Síndico','s@v.com','sindico'),
 ('22222222-0000-0000-0000-00000000000d','aaaaaaaa-0000-0000-0000-00000000000d','Morador','m@v.com','morador'),
 ('33333333-0000-0000-0000-00000000000d','aaaaaaaa-0000-0000-0000-00000000000d','Conselho','c@v.com','conselho'),
 ('44444444-0000-0000-0000-00000000000d','bbbbbbbb-0000-0000-0000-00000000000d','Síndico B','x@o.com','sindico');
\echo '>>> esperado: ERROR (livro-caixa ainda sem as importações)'
\set ON_ERROR_STOP off
\i docs/CRIAR_DASHBOARD_2026_2027.sql
\set ON_ERROR_STOP on
\i docs/IMPORTAR_JUL_SET_2026.sql
\i docs/IMPORTAR_OUT_2026_ATE_21.sql
\i docs/IMPORTAR_OUT_2026_22_A_31.sql
\i docs/CRIAR_DASHBOARD_2026_2027.sql
do $$
declare S constant text := 'dashboard financeiro'; r jsonb; m jsonb; v_id uuid; v_id2 uuid; v_n int;
 sind uuid := '11111111-0000-0000-0000-00000000000d'; mor uuid := '22222222-0000-0000-0000-00000000000d';
 cons uuid := '33333333-0000-0000-0000-00000000000d'; outro uuid := '44444444-0000-0000-0000-00000000000d';
begin
 select id into v_id from public.dashboards_financeiros;
 -- valores iguais ao PDF
 perform t.eu(sind); r := public.dashboard_financeiro(v_id);
 perform t.ok(S,'12 meses (jul/2026 a jun/2027)', jsonb_array_length(r->'meses') = 12, r::text);
 m := r->'meses'->0;
 perform t.ok(S,'jul/2026: inicial 9.370,02, entradas 9.809,06, saídas 14.695,44, final 4.483,64, conciliado',
   (m->>'saldo_inicial_centavos')::bigint = 937002 and (m->>'entradas_centavos')::bigint = 980906 and (m->>'saidas_centavos')::bigint = 1469544
   and (m->>'saldo_final_centavos')::bigint = 448364 and m->>'status' = 'conciliado', m::text);
 m := r->'meses'->3;
 perform t.ok(S,'out/2026: entradas 10.639,11, saídas 9.876,98, final 4.009,70, conciliado',
   (m->>'entradas_centavos')::bigint = 1063911 and (m->>'saidas_centavos')::bigint = 987698 and (m->>'saldo_final_centavos')::bigint = 400970 and m->>'status' = 'conciliado', m::text);
 m := r->'meses'->11;
 perform t.ok(S,'jun/2027: sem movimento, saldo 4.009,70, pendente', (m->>'saldo_inicial_centavos')::bigint = 400970 and (m->>'saldo_final_centavos')::bigint = 400970 and m->>'status' = 'pendente' and (m->>'entradas_centavos')::bigint = 0, m::text);
 perform t.ok(S,'totais 38.222,98 / 43.583,30 / resultado −5.360,32 / 4 de 12 conciliados',
   (r->'totais'->>'entradas_centavos')::bigint = 3822298 and (r->'totais'->>'saidas_centavos')::bigint = 4358330
   and (r->'totais'->>'resultado_centavos')::bigint = -536032 and (r->'totais'->>'conciliados')::int = 4 and (r->'totais'->>'meses')::int = 12, (r->'totais')::text);
 -- síndico cria, edita, informa extrato
 v_id2 := public.salvar_dashboard_financeiro(null, 'Teste 2º semestre', '2026-07-15', '2026-12-01', false, null);
 perform t.ok(S,'síndico cria dashboard (mês normalizado para o dia 1)', (select mes_inicio from public.dashboards_financeiros where id = v_id2) = '2026-07-01');
 perform public.salvar_dashboard_financeiro(v_id2, 'Teste editado', '2026-07-01', '2026-09-01', false, 'obs');
 perform t.ok(S,'síndico edita título, período e observação', (select titulo = 'Teste editado' and mes_fim = '2026-09-01' and observacao = 'obs' from public.dashboards_financeiros where id = v_id2));
 perform t.ok(S,'informar extrato diferente do calculado → divergente', (public.registrar_saldo_extrato('2026-10-01', 400000)->>'status') = 'divergente');
 perform t.ok(S,'dashboard mostra out/2026 divergente', (public.dashboard_financeiro(v_id)->'meses'->3->>'status') = 'divergente');
 perform t.ok(S,'corrigir o extrato → conciliado', (public.registrar_saldo_extrato('2026-10-01', 400970)->>'status') = 'conciliado');
 perform t.ok(S,'apagar o extrato → pendente', (public.registrar_saldo_extrato('2026-09-01', null)->>'status') = 'pendente');
 perform t.ok(S,'com set/2026 pendente, 3 de 12 conciliados', (public.dashboard_financeiro(v_id)->'totais'->>'conciliados')::int = 3);
 perform public.registrar_saldo_extrato('2026-09-01', 324757);
 perform t.fim();
 perform t.erro(S,'período maior que 24 meses é recusado', $q$ select t.eu('11111111-0000-0000-0000-00000000000d'); select public.salvar_dashboard_financeiro(null,'x','2026-01-01','2028-01-01',true,null) $q$, '24 meses');
 perform t.erro(S,'mês final antes do inicial é recusado', $q$ select t.eu('11111111-0000-0000-0000-00000000000d'); select public.salvar_dashboard_financeiro(null,'x','2026-05-01','2026-01-01',true,null) $q$, 'posterior');
 perform t.erro(S,'período repetido é recusado', $q$ select t.eu('11111111-0000-0000-0000-00000000000d'); select public.salvar_dashboard_financeiro(null,'x','2026-07-01','2027-06-01',true,null) $q$, 'Já existe');
 perform t.erro(S,'mês futuro não pode ser conciliado', $q$ select t.eu('11111111-0000-0000-0000-00000000000d'); select public.registrar_saldo_extrato('2030-01-01', 1) $q$, 'futuro');
 -- um lançamento novo no mês desfaz a conciliação
 insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, criado_por)
   values ('aaaaaaaa-0000-0000-0000-00000000000d','despesa','2026-10-31','2026-10-01',100,'Outras despesas','Tarifa esquecida',sind);
 perform t.eu(cons);
 perform t.ok(S,'lançamento novo em out/2026 → mês volta a divergente', (public.dashboard_financeiro(v_id)->'meses'->3->>'status') = 'divergente');
 -- conselho: vê tudo, não edita
 perform t.ok(S,'conselho vê os 2 dashboards', (select count(*) from public.dashboards_financeiros) = 2);
 perform t.ok(S,'conselho abre o dashboard oculto aos moradores', public.dashboard_financeiro(v_id2) is not null);
 perform t.fim();
 perform t.erro(S,'conselho não cria', $q$ select t.eu('33333333-0000-0000-0000-00000000000d'); select public.salvar_dashboard_financeiro(null,'x','2025-01-01','2025-02-01',true,null) $q$, 'síndico');
 perform t.erro(S,'conselho não informa extrato', $q$ select t.eu('33333333-0000-0000-0000-00000000000d'); select public.registrar_saldo_extrato('2026-10-01', 1) $q$, 'síndico');
 perform t.eu(cons); update public.dashboards_financeiros set titulo = 'x'; delete from public.dashboards_financeiros; perform t.fim();
 perform t.ok(S,'conselho não altera nem apaga direto na tabela (RLS)', (select count(*) from public.dashboards_financeiros where titulo = 'x') = 0 and (select count(*) from public.dashboards_financeiros) = 2);
 -- morador: só os visíveis, só leitura
 perform t.eu(mor);
 perform t.ok(S,'morador vê só o dashboard visível', (select count(*) from public.dashboards_financeiros) = 1);
 perform t.ok(S,'morador abre o dashboard visível', (public.dashboard_financeiro(v_id)->'totais'->>'meses')::int = 12);
 perform t.fim();
 perform t.erro(S,'morador não abre o oculto', format($q$ select t.eu('22222222-0000-0000-0000-00000000000d'); select public.dashboard_financeiro(%L) $q$, v_id2), 'não encontrado');
 perform t.erro(S,'morador não cria', $q$ select t.eu('22222222-0000-0000-0000-00000000000d'); select public.salvar_dashboard_financeiro(null,'x','2025-01-01','2025-02-01',true,null) $q$, 'síndico');
 perform t.erro(S,'morador não exclui', format($q$ select t.eu('22222222-0000-0000-0000-00000000000d'); select public.excluir_dashboard_financeiro(%L) $q$, v_id), 'síndico');
 perform t.erro(S,'morador não chama a função interna de saldos', $q$ select t.eu('22222222-0000-0000-0000-00000000000d'); select * from public.saldos_mensais_condominio('aaaaaaaa-0000-0000-0000-00000000000d','2026-07-01','2026-07-01') $q$, 'permission');
 perform t.eu(mor); perform t.ok(S,'morador não lê a tabela de conciliações', (select count(*) from public.conciliacoes_bancarias) = 0); perform t.fim();
 -- outro condomínio
 perform t.eu(outro);
 perform t.ok(S,'síndico de outro condomínio não vê nada', (select count(*) from public.dashboards_financeiros) = 0);
 perform t.fim();
 perform t.erro(S,'síndico de outro condomínio não abre', format($q$ select t.eu('44444444-0000-0000-0000-00000000000d'); select public.dashboard_financeiro(%L) $q$, v_id), 'não encontrado');
 perform t.erro(S,'síndico de outro condomínio não exclui', format($q$ select t.eu('44444444-0000-0000-0000-00000000000d'); select public.excluir_dashboard_financeiro(%L) $q$, v_id), 'não encontrado');
 -- exclusão
 perform t.eu(sind); perform public.excluir_dashboard_financeiro(v_id2); perform t.fim();
 perform t.ok(S,'síndico exclui; dashboard principal continua', (select count(*) from public.dashboards_financeiros) = 1);
 perform t.ok(S,'criação, edição, extratos e exclusão auditados',
   (select count(*) from public.auditoria where acao in ('dashboard.criar','dashboard.editar','dashboard.excluir','conciliacao.saldo_extrato')) >= 7);
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
