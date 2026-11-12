drop schema if exists t cascade; create schema t;
create table t.res(n serial, secao text, nome text, ok boolean, info text);
grant usage on schema t to public; grant all on t.res to public; grant all on sequence t.res_n_seq to public;
create function t.eu(p uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub', coalesce(p::text,''), true); execute 'set local role authenticated'; end $$;
create function t.anon() returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub','', true); execute 'set local role anon'; end $$;
create function t.fim() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create function t.ok(sec text, nome text, cond boolean, info text default null) returns void language plpgsql as $$ begin
  insert into t.res(secao,nome,ok,info) values (sec,nome,coalesce(cond,false),info); end $$;
create function t.erro(sec text, nome text, cmd text, trecho text default null) returns void language plpgsql as $$
declare m text; begin
  begin execute cmd; insert into t.res(secao,nome,ok,info) values (sec,nome,false,'não deu erro');
  exception when others then get stacked diagnostics m = message_text;
    insert into t.res(secao,nome,ok,info) values (sec,nome, trecho is null or m ilike '%'||trecho||'%', m);
  end; end $$;

-- Cenário: Edifício Valença; importação de outubro (OFX, 01–21/10/2026) depois da de jul–set.
truncate public.auditoria, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000009','Edifício Valença');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-000000000009','sindico@v.com'),('22222222-0000-0000-0000-000000000009','morador@v.com'),('33333333-0000-0000-0000-000000000009','conselho@v.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Síndico','sindico@v.com','sindico'),
 ('22222222-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Morador','morador@v.com','morador'),
 ('33333333-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Conselho','conselho@v.com','conselho');
-- 1) sem a importação de jul–set, a de outubro precisa ser recusada (resultado ESPERADO: ERROR)
\echo '>>> esperado: ERROR "Rode antes IMPORTAR_JUL_SET_2026.sql"'
\set ON_ERROR_STOP off
\i docs/IMPORTAR_OUT_2026_ATE_21.sql
\set ON_ERROR_STOP on
do $$ begin perform t.ok('importação out/2026','sem a base de jul–set nada é gravado', (select count(*) from public.lancamentos) = 0); end $$;
-- 2) ordem correta
\i docs/IMPORTAR_JUL_SET_2026.sql
\i docs/IMPORTAR_OUT_2026_ATE_21.sql
do $$
declare S constant text := 'importação out/2026'; r jsonb; v_n int;
 sind uuid := '11111111-0000-0000-0000-000000000009'; mor uuid := '22222222-0000-0000-0000-000000000009'; cons uuid := '33333333-0000-0000-0000-000000000009';
begin
 select count(*) into v_n from public.lancamentos where data_lancamento >= '2026-10-01'; perform t.ok(S,'19 lançamentos de outubro gravados', v_n = 19, v_n::text);
 perform t.eu(sind); r := public.relatorio_mensal(2026,10);
 perform t.ok(S,'saldo anterior de outubro = 3.247,57 (fim de setembro)', (r->>'saldo_anterior_centavos')::bigint = 324757, r::text);
 perform t.ok(S,'entradas de outubro = 9.433,28', (r->>'entradas_centavos')::bigint = 943328);
 perform t.ok(S,'saídas de outubro = 8.558,53', (r->>'saidas_centavos')::bigint = 855853);
 perform t.ok(S,'saldo final em 21/10 = 4.122,32 (igual ao extrato)', (r->>'saldo_final_centavos')::bigint = 412232);
 r := public.relatorio_mensal(2026,9); perform t.ok(S,'setembro não foi alterado (saldo final 3.247,57)', (r->>'saldo_final_centavos')::bigint = 324757);
 perform t.fim();
 perform t.ok(S,'categorias de outubro pertencem à lista do app', not exists (select 1 from public.lancamentos where categoria not in
   ('Água e esgoto','Energia das áreas comuns','Manutenção e reparos','Limpeza','Gás','Seguro','Taxas e impostos','Honorários','Obras','Taxa condominial','Fundo de reserva','Outras receitas','Outras despesas')));
 perform t.ok(S,'botijão de gás (R$ 445,00) em Gás e contabilidade (R$ 308,40) em Honorários',
   exists (select 1 from public.lancamentos where valor_centavos = 44500 and categoria = 'Gás') and exists (select 1 from public.lancamentos where valor_centavos = 30840 and categoria = 'Honorários'));
 perform t.ok(S,'importação de outubro registrada na auditoria', (select count(*) from public.auditoria where acao = 'importar_ofx_2026_10') = 1);
 perform t.eu(mor); perform t.ok(S,'morador vê só o total de outubro (entradas 9.433,28)', (select receitas_centavos from public.resumo_financeiro(2026,10)) = 943328 and (select count(*) from public.lancamentos) = 0); perform t.fim();
 perform t.eu(cons); perform t.ok(S,'conselho enxerga os 111 lançamentos (92 + 19)', (select count(*) from public.lancamentos) = 111); perform t.fim();
end $$;
\echo '>>> esperado: ERROR "Esta importação já foi executada" na segunda execução'
\set ON_ERROR_STOP off
\i docs/IMPORTAR_OUT_2026_ATE_21.sql
\set ON_ERROR_STOP on
do $$ begin perform t.ok('importação out/2026','segunda execução não duplica nada', (select count(*) from public.lancamentos) = 111); end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
