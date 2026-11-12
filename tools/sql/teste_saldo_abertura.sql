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
truncate public.auditoria, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000001','Cond A'),('bbbbbbbb-0000-0000-0000-000000000001','Cond B');
insert into auth.users(id,email) values
 ('11111111-0000-0000-0000-000000000001','sindico@a.com'),('22222222-0000-0000-0000-000000000101','m101@a.com'),
 ('33333333-0000-0000-0000-000000000001','conselho@a.com'),('44444444-0000-0000-0000-000000000001','sindico@b.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');

do $$
declare S constant text := 'saldo de abertura'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '3 months')::date;   -- mês da abertura (3 meses atrás)
 r jsonb; v_id uuid; v_n int;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
begin
 -- (1) sem saldo de abertura o comportamento anterior é preservado
 perform t.eu(sind);
 perform public.registrar_lancamento('receita', m0 + 2, 100000, 'Taxa condominial', 'Cota 101');
 perform public.registrar_lancamento('despesa', m0 + 5, 40000, 'Limpeza', 'Limpeza do mês');
 r := public.relatorio_mensal(extract(year from m0)::int, extract(month from m0)::int);
 perform t.ok(S,'sem abertura: saldo anterior = 0 e saldo final = movimentos do mês', (r->>'saldo_anterior_centavos')::bigint = 0 and (r->>'saldo_final_centavos')::bigint = 60000, r::text);
 perform t.ok(S,'sem abertura: relatório informa abertura nula', r->'saldo_abertura_data' = 'null'::jsonb and r->'saldo_abertura_centavos' = 'null'::jsonb);
 perform t.fim();
 -- (2) permissões e validações do definir_saldo_abertura
 perform t.eu(m101); perform t.erro(S,'morador NÃO define saldo de abertura', format('select public.definir_saldo_abertura(%L, 1000)', m0), 'Apenas o síndico'); perform t.fim();
 perform t.eu(cons); perform t.erro(S,'conselho NÃO define saldo de abertura', format('select public.definir_saldo_abertura(%L, 1000)', m0), 'Apenas o síndico'); perform t.fim();
 perform t.anon(); perform t.erro(S,'anônimo NÃO executa definir_saldo_abertura', format('select public.definir_saldo_abertura(%L, 1000)', m0), 'permission denied'); perform t.fim();
 perform t.eu(sind);
 perform t.erro(S,'data que não é dia 1º é recusada', format('select public.definir_saldo_abertura(%L, 1000)', m0 + 14), 'dia 1');
 perform t.erro(S,'data nula é recusada', 'select public.definir_saldo_abertura(null, 1000)', 'dia 1');
 perform t.erro(S,'valor nulo é recusado', format('select public.definir_saldo_abertura(%L, null)', m0), 'Valor inválido');
 perform t.erro(S,'valor acima do limite é recusado', format('select public.definir_saldo_abertura(%L, 100000000001)', m0), 'Valor inválido');
 perform t.erro(S,'data posterior a lançamentos existentes é recusada', format('select public.definir_saldo_abertura(%L, 1000)', (m0 + interval '1 month')::date), 'lançamentos anteriores');
 -- (3) com saldo de abertura
 perform public.definir_saldo_abertura(m0, 937002);
 r := public.relatorio_mensal(extract(year from m0)::int, extract(month from m0)::int);
 perform t.ok(S,'mês da abertura: saldo anterior = saldo de abertura', (r->>'saldo_anterior_centavos')::bigint = 937002, r::text);
 perform t.ok(S,'mês da abertura: saldo final = abertura + entradas − saídas', (r->>'saldo_final_centavos')::bigint = 937002 + 100000 - 40000);
 perform t.ok(S,'relatório informa data e valor da abertura', (r->>'saldo_abertura_centavos')::bigint = 937002 and (r->>'saldo_abertura_data')::date = m0);
 r := public.relatorio_mensal(extract(year from (m0 + interval '1 month'))::int, extract(month from (m0 + interval '1 month'))::int);
 perform t.ok(S,'mês seguinte: saldo anterior = saldo final do mês anterior', (r->>'saldo_anterior_centavos')::bigint = 997002 and (r->>'saldo_final_centavos')::bigint = 997002, r::text);
 r := public.relatorio_mensal(extract(year from (m0 - interval '1 month'))::int, extract(month from (m0 - interval '1 month'))::int);
 perform t.ok(S,'mês ANTERIOR à abertura: saldo anterior e final = 0', (r->>'saldo_anterior_centavos')::bigint = 0 and (r->>'saldo_final_centavos')::bigint = 0, r::text);
 perform t.erro(S,'lançamento com data anterior à abertura é recusado', format('select public.registrar_lancamento(%L,%L,5000,%L,%L)','despesa', m0 - 1, 'Limpeza', 'Antes da abertura'), 'anterior ao saldo de abertura');
 v_id := public.registrar_lancamento('despesa', m0 + 7, 5000, 'Limpeza', 'No mês da abertura');
 perform t.ok(S,'lançamento dentro do mês da abertura é aceito', v_id is not null);
 -- (4) estorno feito hoje não é barrado e entra no mês de hoje
 perform public.estornar_lancamento(v_id, 'lançado por engano');
 r := public.relatorio_mensal(extract(year from v_hoje)::int, extract(month from v_hoje)::int);
 perform t.ok(S,'estorno de hoje entra no mês corrente e o saldo acumulado reflete', (r->>'saldo_final_centavos')::bigint = 937002 + 100000 - 40000 - 5000 + 5000, r::text);
 -- (5) auditoria
 select count(*) into v_n from public.auditoria where acao = 'definir_saldo_abertura'; perform t.ok(S,'definição do saldo de abertura fica na auditoria', v_n = 1, v_n::text);
 perform t.fim();
 -- (6) conselho vê; morador não vê o relatório; resumo do morador não muda
 perform t.eu(cons); r := public.relatorio_mensal(extract(year from m0)::int, extract(month from m0)::int);
 perform t.ok(S,'conselho enxerga o relatório com o saldo de abertura', (r->>'saldo_anterior_centavos')::bigint = 937002); perform t.fim();
 perform t.eu(m101); perform t.erro(S,'morador continua sem o relatório detalhado', format('select public.relatorio_mensal(%s,%s)', extract(year from m0)::int, extract(month from m0)::int), 'restrito');
 perform t.ok(S,'resumo do morador soma só o mês (sem saldo de abertura)', (select receitas_centavos from public.resumo_financeiro(extract(year from m0)::int, extract(month from m0)::int)) = 100000); perform t.fim();
end $$;
-- (7) isolamento e acesso direto
do $$
declare S constant text := 'saldo de abertura'; v_n int; r jsonb; m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '3 months')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
begin
 perform t.eu(sindB); perform public.definir_saldo_abertura(m0, 777);
 perform t.fim();
 perform t.ok(S,'síndico B define a própria abertura sem afetar o condomínio A',
   (select saldo_inicial_centavos from public.condominios where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 937002 and
   (select saldo_inicial_centavos from public.condominios where id = 'bbbbbbbb-0000-0000-0000-000000000001') = 777);
 perform t.eu(sind);
 perform t.erro(S,'síndico NÃO altera o saldo de abertura por UPDATE direto', format('update public.condominios set saldo_inicial_centavos = 1 where id = %L','aaaaaaaa-0000-0000-0000-000000000001'), 'permission denied');
 perform t.erro(S,'síndico NÃO altera a data de abertura por UPDATE direto', format('update public.condominios set saldo_inicial_data = %L where id = %L', m0, 'aaaaaaaa-0000-0000-0000-000000000001'), 'permission denied');
 perform t.fim();
 perform t.ok(S,'o saldo de abertura do condomínio A segue intacto', (select saldo_inicial_centavos from public.condominios where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 937002);
 perform t.erro(S,'restrição: data de abertura no meio do mês é rejeitada pelo banco', format('update public.condominios set saldo_inicial_data = %L where id = %L', m0 + 9, 'aaaaaaaa-0000-0000-0000-000000000001'), 'condominios_saldo_inicial_data_chk');
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
