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

-- Cenário do mundo real: condomínio "Edifício Valença" com síndico; roda a importação gerada a partir da planilha e confere o resultado.
truncate public.auditoria, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000009','Edifício Valença');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-000000000009','sindico@v.com'),('22222222-0000-0000-0000-000000000009','morador@v.com'),('33333333-0000-0000-0000-000000000009','conselho@v.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Síndico','sindico@v.com','sindico'),
 ('22222222-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Morador','morador@v.com','morador'),
 ('33333333-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000009','Conselho','conselho@v.com','conselho');
\i docs/IMPORTAR_JUL_SET_2026.sql
do $$
declare S constant text := 'importação jul-set'; r jsonb; v_n int;
 sind uuid := '11111111-0000-0000-0000-000000000009'; mor uuid := '22222222-0000-0000-0000-000000000009'; cons uuid := '33333333-0000-0000-0000-000000000009';
begin
 select count(*) into v_n from public.lancamentos; perform t.ok(S,'92 lançamentos gravados', v_n = 92, v_n::text);
 perform t.eu(sind);
 r := public.relatorio_mensal(2026,7); perform t.ok(S,'jul: saldo anterior = abertura 9.370,02; entradas 9.809,06; saídas 14.695,44; final 4.483,64',
   (r->>'saldo_anterior_centavos')::bigint = 937002 and (r->>'entradas_centavos')::bigint = 980906 and (r->>'saidas_centavos')::bigint = 1469544 and (r->>'saldo_final_centavos')::bigint = 448364, r::text);
 r := public.relatorio_mensal(2026,8); perform t.ok(S,'ago: entradas 10.620,75; saídas 9.481,13; final 5.623,26',
   (r->>'saldo_anterior_centavos')::bigint = 448364 and (r->>'entradas_centavos')::bigint = 1062075 and (r->>'saidas_centavos')::bigint = 948113 and (r->>'saldo_final_centavos')::bigint = 562326, r::text);
 r := public.relatorio_mensal(2026,9); perform t.ok(S,'set: entradas 7.154,06; saídas 9.529,75; final 3.247,57 (igual ao extrato)',
   (r->>'saldo_anterior_centavos')::bigint = 562326 and (r->>'entradas_centavos')::bigint = 715406 and (r->>'saidas_centavos')::bigint = 952975 and (r->>'saldo_final_centavos')::bigint = 324757, r::text);
 r := public.relatorio_mensal(2026,10); perform t.ok(S,'out: sem lançamentos, saldo anterior = 3.247,57', (r->>'saldo_anterior_centavos')::bigint = 324757 and (r->>'quantidade')::int = 0, r::text);
 perform t.fim();
 perform t.ok(S,'toda categoria usada pertence à lista do app', not exists (select 1 from public.lancamentos where categoria not in
   ('Água e esgoto','Energia das áreas comuns','Manutenção e reparos','Limpeza','Gás','Seguro','Taxas e impostos','Honorários','Obras','Taxa condominial','Fundo de reserva','Outras receitas','Outras despesas')));
 perform t.ok(S,'descrições respeitam o limite e nenhuma está vazia', not exists (select 1 from public.lancamentos where length(trim(descricao)) not between 1 and 120));
 perform t.ok(S,'cotas de moradores identificadas por apartamento, sem nome da pessoa', not exists (select 1 from public.lancamentos where categoria = 'Taxa condominial' and descricao !~ '^Cota condominial — Apto (01|02|101|102|201|202|301|302)$'));
 perform t.ok(S,'competência preenchida no 1º dia do mês', not exists (select 1 from public.lancamentos where competencia is null or competencia <> date_trunc('month', competencia)::date));
 perform t.ok(S,'todos criados pelo síndico', not exists (select 1 from public.lancamentos where criado_por <> sind));
 perform t.ok(S,'importação registrada na auditoria', (select count(*) from public.auditoria where acao = 'importar_conciliacao_2026_07_09') = 1);
 perform t.eu(mor);
 perform t.ok(S,'morador vê só o total do mês (jul: entradas 9.809,06)', (select receitas_centavos from public.resumo_financeiro(2026,7)) = 980906);
 perform t.fim();
 perform t.eu(mor); perform t.ok(S,'morador enxerga 0 lançamentos individuais', (select count(*) from public.lancamentos) = 0); perform t.fim();
 perform t.eu(cons); perform t.ok(S,'conselho enxerga os 92 lançamentos', (select count(*) from public.lancamentos) = 92); perform t.fim();
 -- imutabilidade dos lançamentos importados
 perform t.erro(S,'lançamento importado não pode ser alterado', 'update public.lancamentos set valor_centavos = 1', 'não podem ser alterados');
 perform t.erro(S,'lançamento importado não pode ser apagado', 'delete from public.lancamentos', 'não podem ser apagados');
end $$;
-- segunda execução precisa ser recusada (idempotência). O ERRO abaixo é o resultado ESPERADO.
\echo '>>> esperado: ERROR "Esta importação já foi executada" na segunda execução'
\set ON_ERROR_STOP off
\i docs/IMPORTAR_JUL_SET_2026.sql
\set ON_ERROR_STOP on
do $$ begin
  perform t.ok('importação jul-set','segunda execução não duplica nada', (select count(*) from public.lancamentos) = 92 and (select count(*) from public.auditoria where acao = 'importar_conciliacao_2026_07_09') = 1);
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
