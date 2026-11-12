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
truncate public.auditoria, public.extrato_linhas, public.extratos_importados, public.regras_extrato, public.comprovantes_financeiros, public.lancamentos_historico, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000001','Cond A'),('bbbbbbbb-0000-0000-0000-000000000001','Cond B');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-000000000001','sindico@a.com'),('22222222-0000-0000-0000-000000000101','m101@a.com'),
 ('33333333-0000-0000-0000-000000000001','conselho@a.com'),('44444444-0000-0000-0000-000000000001','sindico@b.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');
create function t.sha(x text) returns text language sql immutable as $$ select encode(sha256(convert_to(x, 'UTF8')), 'hex') $$;
create function t.ln(d date, v bigint, memo text, acao text, extra jsonb default '{}') returns jsonb language sql immutable as
 $$ select jsonb_build_object('data', d, 'valor_centavos', v, 'memo', memo, 'acao', acao) || extra $$;
create function t.lan(d date, v bigint, memo text) returns jsonb language sql immutable as
 $$ select t.ln(d, v, memo, 'lancar', jsonb_build_object('categoria', case when v > 0 then 'Taxa condominial' else 'Outras despesas' end, 'descricao', 'Teste ' || memo)) $$;

do $$
declare S constant text := 'importação de extrato';
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '2 months')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; mor uuid := '22222222-0000-0000-0000-000000000101';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
 r jsonb; v_man uuid; v_man2 uuid; v_n int; v_id uuid; v_est uuid;
begin
 update public.condominios set saldo_inicial_centavos = 100000, saldo_inicial_data = m0 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
 perform t.eu(sind);
 v_man := public.registrar_lancamento('despesa', m0 + 4, 12345, 'Limpeza', 'Pagamento manual');
 -- (1) importação básica: 2 lançadas + 1 conciliada com lançamento manual
 r := public.importar_extrato('extrato1.ofx', t.sha('f1'), m0 + 1, m0 + 10, 187025, m0 + 10, jsonb_build_array(
   t.ln(m0 + 5, 100000, 'COB COMPE', 'lancar', '{"categoria":"Taxa condominial","descricao":"Cotas recebidas por boleto","lembrar":"memo"}'),
   t.lan(m0 + 5, -630, 'COB COMPE'),
   t.ln(m0 + 6, -12345, 'PAGAMENTO DE BOLETO', 'conciliar', jsonb_build_object('lancamento_id', v_man))));
 perform t.ok(S,'importa: 2 lançadas, 1 conciliada, 0 ignoradas e saldo bate', (r->>'lancadas')::int = 2 and (r->>'conciliadas')::int = 1 and (r->>'ignoradas')::int = 0 and (r->>'diferenca_saldo_centavos')::bigint = 0 and (r->>'saldo_livro_centavos')::bigint = 187025, r::text);
 select count(*) into v_n from public.lancamentos where condominio_id = 'aaaaaaaa-0000-0000-0000-000000000001'; perform t.ok(S,'o lançamento manual não é duplicado (3 lançamentos no total)', v_n = 3, v_n::text);
 perform t.ok(S,'crédito vira receita e débito vira despesa, em valor positivo', exists (select 1 from public.lancamentos where tipo = 'receita' and valor_centavos = 100000) and exists (select 1 from public.lancamentos where tipo = 'despesa' and valor_centavos = 630));
 perform t.ok(S,'lançamento criado traz o histórico do banco na observação e competência no 1º dia', exists (select 1 from public.lancamentos where observacao = 'Extrato: COB COMPE' and competencia = date_trunc('month', data_lancamento)::date));
 perform t.ok(S,'linhas do extrato guardam status e vínculo', (select count(*) from public.extrato_linhas where status = 'lancada') = 2 and (select count(*) from public.extrato_linhas where status = 'conciliada' and lancamento_id = v_man) = 1);
 perform t.ok(S,'cabeçalho do extrato registra período, saldo, contagens e quem importou', exists (select 1 from public.extratos_importados where arquivo_nome = 'extrato1.ofx' and qtd_movimentos = 3 and qtd_lancadas = 2 and qtd_conciliadas = 1 and saldo_final_centavos = 187025 and importado_por = sind));
 -- (2) mesmo arquivo de novo
 perform t.erro(S,'o mesmo arquivo (mesma impressão digital) é recusado', format('select public.importar_extrato(%L,%L,%L,%L,187025,%L,%L::jsonb)', 'extrato1.ofx', t.sha('f1'), m0 + 1, m0 + 10, m0 + 10, jsonb_build_array(t.lan(m0 + 5, 100000, 'COB COMPE'))::text), 'já foi importado');
 -- (3) período que se sobrepõe: os 3 movimentos antigos viram "já importados", só o novo é gravado
 r := public.importar_extrato('extrato2.ofx', t.sha('f2'), m0 + 1, m0 + 12, 189025, m0 + 12, jsonb_build_array(
   t.lan(m0 + 5, 100000, 'COB COMPE'), t.lan(m0 + 5, -630, 'COB COMPE'), t.ln(m0 + 6, -12345, 'PAGAMENTO DE BOLETO', 'ignorar', '{"motivo":"já conferido"}'), t.lan(m0 + 11, 2000, 'JUROS')));
 perform t.ok(S,'sobreposição: 3 já importados e só 1 novo lançado (sem duplicar)', (r->>'ja_importadas')::int = 3 and (r->>'lancadas')::int = 1 and (r->>'conciliadas')::int = 0 and (r->>'ignoradas')::int = 0, r::text);
 select count(*) into v_n from public.lancamentos where condominio_id = 'aaaaaaaa-0000-0000-0000-000000000001'; perform t.ok(S,'sobreposição: o livro-caixa ganhou só 1 lançamento', v_n = 4, v_n::text);
 perform t.erro(S,'arquivo em que tudo já foi importado é recusado', format('select public.importar_extrato(%L,%L,%L,%L,189025,%L,%L::jsonb)', 'extrato3.ofx', t.sha('f3'), m0 + 1, m0 + 12, m0 + 12,
   jsonb_build_array(t.lan(m0 + 5, 100000, 'COB COMPE'), t.lan(m0 + 11, 2000, 'JUROS'))::text), 'já foram importados');
 -- (4) saldo não confere
 select count(*) into v_n from public.lancamentos; 
 perform t.erro(S,'saldo diferente do extrato: nada é importado', format('select public.importar_extrato(%L,%L,%L,%L,555555,%L,%L::jsonb)', 'extrato4.ofx', t.sha('f4'), m0 + 1, m0 + 20, m0 + 20,
   jsonb_build_array(t.lan(m0 + 15, 1000, 'DEPOSITO'))::text), 'Nada foi importado');
 perform t.ok(S,'saldo diferente: nenhum lançamento nem extrato foi gravado', (select count(*) from public.lancamentos) = v_n and not exists (select 1 from public.extratos_importados where arquivo_nome = 'extrato4.ofx') and not exists (select 1 from public.extrato_linhas where memo = 'DEPOSITO'));
 r := public.importar_extrato('extrato4.ofx', t.sha('f4'), m0 + 1, m0 + 20, 555555, m0 + 20, jsonb_build_array(t.lan(m0 + 15, 1000, 'DEPOSITO')), false);
 perform t.ok(S,'saldo diferente com "importar mesmo assim": grava e informa a diferença', (r->>'lancadas')::int = 1 and (r->>'diferenca_saldo_centavos')::bigint = 555555 - 190025, r::text);
 -- (5) movimentos idênticos no mesmo dia (n-ésima ocorrência)
 r := public.importar_extrato('extrato5.ofx', t.sha('f5'), m0 + 21, m0 + 30, null, null, jsonb_build_array(t.lan(m0 + 25, -630, 'COB COMPE'), t.lan(m0 + 25, -630, 'COB COMPE')), true);
 perform t.ok(S,'duas tarifas idênticas no mesmo dia entram as duas', (r->>'lancadas')::int = 2 and (r->>'ja_importadas')::int = 0, r::text);
 r := public.importar_extrato('extrato6.ofx', t.sha('f6'), m0 + 21, m0 + 32, null, null, jsonb_build_array(t.lan(m0 + 25, -630, 'COB COMPE'), t.lan(m0 + 25, -630, 'COB COMPE'), t.lan(m0 + 25, -630, 'COB COMPE')), true);
 perform t.ok(S,'reenvio com 3 ocorrências: 2 já importadas e 1 nova', (r->>'ja_importadas')::int = 2 and (r->>'lancadas')::int = 1, r::text);
 perform t.erro(S,'sem saldo no arquivo, a conferência é dispensada mas o período é validado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'x.ofx', t.sha('f7'), m0 + 30, m0 + 21, '[]'), 'Período');
 perform t.fim();
end $$;
-- ---- conciliar: validações ----
do $$
declare S constant text := 'importação de extrato';
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '2 months')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001'; v_a uuid; v_b uuid; v_c uuid; v_e uuid; v_o uuid; v_ja uuid; v_f uuid;
 sh int := 100;
 function_dummy int;
begin
 perform t.eu(sind);
 v_a := public.registrar_lancamento('despesa', m0 + 40, 4242, 'Limpeza', 'Manual A');
 v_b := public.registrar_lancamento('receita', m0 + 40, 5000, 'Taxa condominial', 'Manual B (receita)');
 v_c := public.registrar_lancamento('despesa', m0 + 41, 7777, 'Limpeza', 'Manual C');
 v_f := public.registrar_lancamento('despesa', m0 + 1, 3131, 'Limpeza', 'Manual distante');
 v_e := public.estornar_lancamento(v_c, 'lançado por engano') ; -- estorna C
 v_ja := (select lancamento_id from public.extrato_linhas where status = 'conciliada' limit 1);
 perform t.erro(S,'conciliar com valor diferente é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c1.ofx', t.sha('c1'), m0 + 35, m0 + 45, jsonb_build_array(t.ln(m0 + 40, -4000, 'PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_a)))::text), 'valor do lançamento escolhido é diferente');
 perform t.erro(S,'conciliar crédito com lançamento de despesa é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c2.ofx', t.sha('c2'), m0 + 35, m0 + 45, jsonb_build_array(t.ln(m0 + 40, 4242, 'PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_a)))::text), 'não é uma receita');
 perform t.erro(S,'conciliar com lançamento estornado é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c3.ofx', t.sha('c3'), m0 + 35, m0 + 45, jsonb_build_array(t.ln(m0 + 41, -7777, 'PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_c)))::text), 'estornado');
 perform t.erro(S,'conciliar com lançamento já conciliado é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c4.ofx', t.sha('c4'), m0 + 6, m0 + 9, jsonb_build_array(t.ln(m0 + 7, -12345, 'OUTRO PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_ja)))::text), 'já está conciliado');
 perform t.erro(S,'conciliar com lançamento a mais de 31 dias da data do extrato é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c5.ofx', t.sha('c5'), m0 + 38, m0 + 45, jsonb_build_array(t.ln(m0 + 40, -3131, 'PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_f)))::text), '31 dias');
 perform t.erro(S,'conciliar sem escolher o lançamento é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c6.ofx', t.sha('c6'), m0 + 35, m0 + 45, jsonb_build_array(t.ln(m0 + 40, -4242, 'PAGTO', 'conciliar'))::text), 'Escolha o lançamento');
 perform t.fim(); perform t.eu(sindB);
 perform t.erro(S,'síndico de outro condomínio não concilia com lançamento alheio', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c7.ofx', t.sha('c7'), m0 + 35, m0 + 45, jsonb_build_array(t.ln(m0 + 40, -4242, 'PAGTO', 'conciliar', jsonb_build_object('lancamento_id', v_a)))::text), 'não encontrado');
 perform t.fim(); perform t.eu(sind);
 -- conciliar ok com data próxima e duas conciliações no mesmo extrato não repetem o lançamento
 perform t.erro(S,'duas linhas do mesmo extrato não podem conciliar o mesmo lançamento', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'c8.ofx', t.sha('c8'), m0 + 35, m0 + 45, jsonb_build_array(
   t.ln(m0 + 40, -4242, 'PAGTO UM', 'conciliar', jsonb_build_object('lancamento_id', v_a)), t.ln(m0 + 42, -4242, 'PAGTO DOIS', 'conciliar', jsonb_build_object('lancamento_id', v_a)))::text), 'já está conciliado');
 perform t.ok(S,'após as recusas o lançamento A continua livre para conciliar', not exists (select 1 from public.extrato_linhas where lancamento_id = v_a));
 -- (6) ignorar, ação ausente, linha inválida
 perform t.erro(S,'ignorar sem motivo é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i1.ofx', t.sha('i1'), m0 + 50, m0 + 55, jsonb_build_array(t.ln(m0 + 51, -100, 'TARIFA', 'ignorar'))::text), 'motivo');
 perform t.erro(S,'movimento sem ação é recusado e a mensagem indica a linha', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i2.ofx', t.sha('i2'), m0 + 50, m0 + 55, jsonb_build_array(t.lan(m0 + 51, -100, 'A'), jsonb_build_object('data', m0 + 52, 'valor_centavos', -200, 'memo', 'B'))::text), 'Movimento 2');
 perform t.erro(S,'data anterior ao saldo de abertura é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i3.ofx', t.sha('i3'), m0 - 5, m0 - 1, jsonb_build_array(t.lan(m0 - 3, -100, 'ANTIGO'))::text), 'anterior ao saldo de abertura');
 perform t.erro(S,'data futura é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i4.ofx', t.sha('i4'), m0 + 50, m0 + 55, jsonb_build_array(t.lan(((now() at time zone 'America/Sao_Paulo')::date) + 5, -100, 'FUTURO'))::text), 'Data inválida');
 perform t.erro(S,'valor zero é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i5.ofx', t.sha('i5'), m0 + 50, m0 + 55, jsonb_build_array(t.ln(m0 + 51, 0, 'ZERO', 'ignorar', '{"motivo":"zero zero"}'))::text), 'Valor inválido');
 perform t.erro(S,'categoria vazia é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i6.ofx', t.sha('i6'), m0 + 50, m0 + 55, jsonb_build_array(t.ln(m0 + 51, -100, 'X', 'lancar', '{"descricao":"d"}'))::text), 'Categoria');
 perform t.erro(S,'descrição com mais de 120 caracteres é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i7.ofx', t.sha('i7'), m0 + 50, m0 + 55, jsonb_build_array(t.ln(m0 + 51, -100, 'X', 'lancar', jsonb_build_object('categoria','Limpeza','descricao', repeat('x', 121))))::text), 'Descrição');
 perform t.erro(S,'lista vazia é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i8.ofx', t.sha('i8'), m0 + 50, m0 + 55, '[]'), '1 a 2000');
 perform t.erro(S,'mais de 2000 movimentos é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,(select jsonb_agg(t.ln(%L::date, -(g), ''M'' || g, ''ignorar'', ''{"motivo":"teste teste"}'')) from generate_series(1, 2001) g))', 'i9.ofx', t.sha('i9'), m0 + 50, m0 + 55, m0 + 51), '1 a 2000');
 perform t.erro(S,'JSON que não é lista é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i10.ofx', t.sha('i10'), m0 + 50, m0 + 55, '{"a":1}'), '1 a 2000');
 perform t.erro(S,'impressão digital inválida é recusada', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i11.ofx', 'abc', m0 + 50, m0 + 55, jsonb_build_array(t.lan(m0 + 51, -100, 'A'))::text), 'Impressão digital');
 perform t.erro(S,'extrato que termina no futuro é recusado', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'i12.ofx', t.sha('i12'), m0 + 50, ((now() at time zone 'America/Sao_Paulo')::date) + 3, jsonb_build_array(t.lan(m0 + 51, -100, 'A'))::text), 'futuro');
 perform t.fim();
end $$;
-- ---- permissões, imutabilidade, regras, saldo e auditoria ----
do $$
declare S constant text := 'importação de extrato'; v_n int; r jsonb;
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '2 months')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; mor uuid := '22222222-0000-0000-0000-000000000101'; cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
begin
 perform t.eu(mor);
 perform t.erro(S,'morador NÃO importa extrato', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'p.ofx', t.sha('p1'), m0 + 50, m0 + 55, jsonb_build_array(t.lan(m0 + 51, -100, 'A'))::text), 'Apenas o síndico');
 select count(*) into v_n from public.extratos_importados; perform t.ok(S,'morador NÃO enxerga extratos nem linhas', v_n = 0 and (select count(*) from public.extrato_linhas) = 0);
 perform t.erro(S,'morador NÃO consulta o saldo do livro-caixa', format('select public.saldo_livro_em(%L)', m0 + 5), 'Restrito');
 perform t.fim(); perform t.eu(cons);
 perform t.erro(S,'conselho NÃO importa extrato', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'p.ofx', t.sha('p2'), m0 + 50, m0 + 55, jsonb_build_array(t.lan(m0 + 51, -100, 'A'))::text), 'Apenas o síndico');
 perform t.ok(S,'conselho enxerga os extratos importados e suas linhas', (select count(*) from public.extratos_importados) >= 4 and (select count(*) from public.extrato_linhas) >= 8);
 perform t.ok(S,'conselho NÃO enxerga as regras do síndico', (select count(*) from public.regras_extrato) = 0);
 perform t.ok(S,'conselho consulta o saldo do livro-caixa na data', public.saldo_livro_em(m0 + 10) = 187025 - 3131, public.saldo_livro_em(m0 + 10)::text);
 perform t.fim(); perform t.eu(sindB);
 perform t.ok(S,'outro condomínio NÃO enxerga extratos nem linhas', (select count(*) from public.extratos_importados) = 0 and (select count(*) from public.extrato_linhas) = 0);
 perform t.fim(); perform t.anon();
 perform t.erro(S,'anônimo NÃO executa importar_extrato', format('select public.importar_extrato(%L,%L,%L,%L,null,null,%L::jsonb)', 'p.ofx', t.sha('p3'), m0, m0, '[]'), 'permission denied');
 perform t.fim(); perform t.eu(sind);
 perform t.erro(S,'síndico NÃO escreve direto nas linhas do extrato', 'insert into public.extrato_linhas(extrato_id,condominio_id,ordem,data_mov,valor_centavos,memo,chave,status,motivo_ignorar) values (gen_random_uuid(), gen_random_uuid(), 1, now(), 1, ''x'', ''x'', ''ignorada'', ''motivo teste'')', 'permission denied');
 perform t.erro(S,'síndico NÃO apaga linhas do extrato', 'delete from public.extrato_linhas', 'permission denied');
 perform t.erro(S,'síndico NÃO altera extratos importados', 'update public.extratos_importados set qtd_lancadas = 99', 'permission denied');
 perform t.erro(S,'síndico NÃO escreve direto nas regras', 'insert into public.regras_extrato(condominio_id,memo_padrao,sinal,categoria,descricao,criada_por) values (gen_random_uuid(),''x'',1,''x'',''x'',gen_random_uuid())', 'permission denied');
 perform t.ok(S,'a regra "lembrar" foi criada pela importação (memo, sem valor fixo)', exists (select 1 from public.regras_extrato where memo_padrao = 'COB COMPE' and sinal = 1 and valor_centavos is null and categoria = 'Taxa condominial'));
 perform t.fim();
 -- até o dono do banco é barrado pelo gatilho de imutabilidade
 perform t.erro(S,'nem o dono do banco altera linhas do extrato (gatilho)', 'update public.extrato_linhas set memo = ''x''', 'não podem ser alterados');
 perform t.erro(S,'nem o dono do banco apaga extratos (gatilho)', 'delete from public.extratos_importados', 'não podem ser alterados');
 -- regras: lembrar pelo valor e atualizar sem duplicar
 perform t.eu(sind);
 perform public.importar_extrato('r1.ofx', t.sha('r1'), m0 + 60, m0 + 62, null, null, jsonb_build_array(t.ln(m0 + 61, -372674, 'PAGAMENTO DE BOLETO', 'lancar', '{"categoria":"Obras","descricao":"2M Construtora","fornecedor":"2M Construtora Ltda","lembrar":"memo_valor"}')));
 perform public.importar_extrato('r2.ofx', t.sha('r2'), m0 + 63, m0 + 65, null, null, jsonb_build_array(t.ln(m0 + 64, -372674, 'pagamento  de boleto', 'lancar', '{"categoria":"Obras","descricao":"2M Construtora (parcela)","fornecedor":"2M Construtora Ltda","lembrar":"memo_valor"}')));
 perform t.ok(S,'regra por memo+valor: reenviar atualiza a mesma regra (não duplica) e normaliza o texto', (select count(*) from public.regras_extrato where memo_padrao = 'PAGAMENTO DE BOLETO' and valor_centavos = 372674) = 1 and (select descricao from public.regras_extrato where valor_centavos = 372674) = '2M Construtora (parcela)');
 perform t.ok(S,'o síndico enxerga as próprias regras', (select count(*) from public.regras_extrato) = 2);
 -- saldo do livro por data
 perform t.ok(S,'saldo antes da abertura é 0', public.saldo_livro_em(m0 - 1) = 0);
 perform t.ok(S,'saldo no dia da abertura = abertura (nenhum lançamento nesse dia)', public.saldo_livro_em(m0) = 100000);
 select count(*) into v_n from public.auditoria where acao = 'importar_extrato'; perform t.ok(S,'cada importação fica na auditoria', v_n >= 7, v_n::text);
 perform t.fim();
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
