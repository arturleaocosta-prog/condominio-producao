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
truncate public.auditoria, public.cobranca_pagamentos, public.extrato_linhas, public.extratos_importados, public.regras_extrato, public.itens_cobranca, public.itens_cobranca_previstos, public.cobrancas, public.ciclos_cobranca, public.rateios_agua_itens, public.rateios_agua, public.previsoes_mensais, public.comprovantes_financeiros, public.lancamentos_historico, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000001','Cond A'),('bbbbbbbb-0000-0000-0000-000000000001','Cond B');
insert into public.unidades(id,condominio_id,identificacao,fracao_ideal) values
 ('a1000000-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','101',0.5000000),
 ('a1000000-0000-0000-0000-000000000102','aaaaaaaa-0000-0000-0000-000000000001','102',0.3000000),
 ('a1000000-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000001','201',0.2000000),
 ('b1000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','X1',1.0000000);
insert into auth.users(id,email) values ('11111111-0000-0000-0000-000000000001','sindico@a.com'),('22222222-0000-0000-0000-000000000101','m101@a.com'),('22222222-0000-0000-0000-000000000102','m102@a.com'),
 ('33333333-0000-0000-0000-000000000001','conselho@a.com'),('44444444-0000-0000-0000-000000000001','sindico@b.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('22222222-0000-0000-0000-000000000102','aaaaaaaa-0000-0000-0000-000000000001','Morador 102','m102@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');
insert into public.vinculos_unidades(user_id,unidade_id) values ('22222222-0000-0000-0000-000000000101','a1000000-0000-0000-0000-000000000101'),('22222222-0000-0000-0000-000000000102','a1000000-0000-0000-0000-000000000102');
create function t.sha(x text) returns text language sql immutable as $$ select encode(sha256(convert_to(x, 'UTF8')), 'hex') $$;

do $$
declare S constant text := 'cobrança por unidade';
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '1 month')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101'; m102 uuid := '22222222-0000-0000-0000-000000000102';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
 u101 uuid := 'a1000000-0000-0000-0000-000000000101'; u102 uuid := 'a1000000-0000-0000-0000-000000000102'; u201 uuid := 'a1000000-0000-0000-0000-000000000201';
 v_ciclo uuid; v_n int; r jsonb; v_c101 uuid; v_c102 uuid; v_c201 uuid; v_p1 uuid; v_l1 uuid; v_l2 uuid; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
 perform t.eu(sind);
 insert into public.previsoes_mensais (condominio_id, competencia, taxa_por_unidade_centavos, fundo_obras_por_unidade_centavos) values ('aaaaaaaa-0000-0000-0000-000000000001', m0, 70000, 6500);
 insert into public.itens_cobranca_previstos (condominio_id, competencia, unidade_id, tipo, descricao, valor_centavos, criado_por) values ('aaaaaaaa-0000-0000-0000-000000000001', m0, u102, 'gas', 'Gás 3 m³', 8800, sind);
 v_ciclo := public.gerar_cobranca_mensal(m0, m0 + 9, 100000, m0 - 30, false);
 perform t.ok(S,'gera 1 cobrança por unidade ativa (3) em rascunho', (select count(*) from public.cobrancas where ciclo_id = v_ciclo and status = 'rascunho') = 3);
 perform t.ok(S,'água rateada pela fração ideal: 50.000 + 30.000 + 20.000 centavos', (select string_agg(i.valor_centavos::text, ',' order by u.identificacao) from public.itens_cobranca i join public.cobrancas c on c.id = i.cobranca_id join public.unidades u on u.id = c.unidade_id where c.ciclo_id = v_ciclo and i.tipo = 'agua') = '50000,30000,20000');
 select id into v_c101 from public.cobrancas where ciclo_id = v_ciclo and unidade_id = u101; select id into v_c102 from public.cobrancas where ciclo_id = v_ciclo and unidade_id = u102; select id into v_c201 from public.cobrancas where ciclo_id = v_ciclo and unidade_id = u201;
 perform t.ok(S,'totais: 101 = 70.000+6.500+50.000; 102 inclui o gás; 201 sem gás', (select valor_total_centavos from public.cobrancas where id = v_c101) = 126500 and (select valor_total_centavos from public.cobrancas where id = v_c102) = 70000 + 6500 + 30000 + 8800 and (select valor_total_centavos from public.cobrancas where id = v_c201) = 96500);
 perform t.ok(S,'conferência sem erros', not exists (select 1 from public.validar_cobranca_mensal(m0) where nivel = 'erro'));
 perform t.erro(S,'gerar de novo a mesma competência é recusado', format('select public.gerar_cobranca_mensal(%L,%L,100000)', m0, m0 + 9), 'Já existem cobranças');
 perform t.erro(S,'registrar pagamento antes de liberar é recusado', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c101, hoje, 'pix'), 'ainda não foi liberada');
 perform t.fim(); perform t.eu(m101);
 perform t.ok(S,'morador NÃO enxerga cobrança em rascunho (nem os itens dela)', (select count(*) from public.cobrancas) = 0 and (select count(*) from public.itens_cobranca) = 0);
 perform t.fim(); perform t.eu(sind);
 perform public.liberar_cobranca_mensal(m0);
 perform t.ok(S,'liberar muda as cobranças para pronta_para_emissao e o ciclo para liberado', (select count(*) from public.cobrancas where ciclo_id = v_ciclo and status = 'pronta_para_emissao') = 3 and (select status from public.ciclos_cobranca where id = v_ciclo) = 'liberado');
 perform t.fim();
 perform t.eu(m101);
 perform t.ok(S,'morador vê só a cobrança da própria unidade (e os itens dela)', (select count(*) from public.cobrancas) = 1 and (select count(*) from public.itens_cobranca) = 3 and (select valor_total_centavos from public.cobrancas) = 126500);
 perform t.erro(S,'morador NÃO consulta quem deve', 'select * from public.cobrancas_em_aberto()', 'Restrito');
 perform t.erro(S,'morador NÃO registra pagamento', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c101, hoje, 'pix'), 'Apenas o síndico');
 perform t.fim(); perform t.eu(cons);
 perform t.ok(S,'conselho vê as 3 cobranças e consulta quem deve', (select count(*) from public.cobrancas) = 3 and (select count(*) from public.cobrancas_em_aberto()) = 3);
 perform t.erro(S,'conselho NÃO registra pagamento', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c101, hoje, 'pix'), 'Apenas o síndico');
 perform t.fim(); perform t.eu(sindB);
 perform t.ok(S,'outro condomínio não vê cobranças', (select count(*) from public.cobrancas) = 0);
 perform t.erro(S,'síndico de outro condomínio não registra pagamento em cobrança alheia', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c101, hoje, 'pix'), 'não encontrada');
 perform t.fim(); perform t.anon();
 perform t.erro(S,'anônimo NÃO executa registrar_pagamento_cobranca', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c101, hoje, 'pix'), 'permission denied');
 perform t.fim();
 perform t.eu(sind);
 r := public.registrar_pagamento_cobranca(v_c101, hoje, 50000, 'pix', null, 'primeira parte');
 perform t.ok(S,'pagamento parcial: continua em aberto e informa o saldo', (r->>'status') = 'pronta_para_emissao' and (r->>'saldo_centavos')::bigint = 76500, r::text);
 perform t.ok(S,'quem deve mostra o saldo da 101 reduzido', (select saldo_centavos from public.cobrancas_em_aberto() where unidade = '101') = 76500 and (select pago_centavos from public.cobrancas_em_aberto() where unidade = '101') = 50000);
 r := public.registrar_pagamento_cobranca(v_c101, hoje, 76500, 'boleto');
 perform t.ok(S,'pagamento completo: cobrança vira paga e sai de "quem deve"', (r->>'status') = 'paga' and (r->>'saldo_centavos')::bigint = 0 and not exists (select 1 from public.cobrancas_em_aberto() where unidade = '101') and (select valor_pago_centavos from public.cobrancas where id = v_c101) = 126500);
 perform t.erro(S,'pagamento acima de 150% do valor é recusado (confere o valor)', format('select public.registrar_pagamento_cobranca(%L,%L,200000,%L)', v_c102, hoje, 'pix'), '150');
 perform t.erro(S,'valor zero é recusado', format('select public.registrar_pagamento_cobranca(%L,%L,0,%L)', v_c102, hoje, 'pix'), 'maior que zero');
 perform t.erro(S,'forma inválida é recusada', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c102, hoje, 'cheque'), 'Forma');
 perform t.erro(S,'data futura é recusada', format('select public.registrar_pagamento_cobranca(%L,%L,1000,%L)', v_c102, hoje + 1, 'pix'), 'entre 2020 e hoje');
 select id into v_p1 from public.cobranca_pagamentos where cobranca_id = v_c101 and forma = 'pix';
 perform t.erro(S,'remover pagamento sem motivo é recusado', format('select public.remover_pagamento_cobranca(%L,%L)', v_p1, 'abc'), 'motivo');
 perform public.remover_pagamento_cobranca(v_p1, 'lançado na unidade errada');
 perform t.ok(S,'remover pagamento reabre a cobrança (volta a dever) e guarda o histórico', (select status::text from public.cobrancas where id = v_c101) = 'pronta_para_emissao' and (select pago_centavos from public.cobrancas_em_aberto() where unidade = '101') = 76500 and exists (select 1 from public.cobranca_pagamentos where id = v_p1 and removido_em is not null and motivo_remocao = 'lançado na unidade errada'));
 perform t.erro(S,'remover o mesmo pagamento de novo é recusado', format('select public.remover_pagamento_cobranca(%L,%L)', v_p1, 'de novo teste'), 'já removido');
 perform t.erro(S,'síndico NÃO altera o status da cobrança direto na tabela', format('update public.cobrancas set status = %L, pago_em = now() where id = %L', 'paga', v_c201), 'registro de pagamento');
 perform t.erro(S,'síndico NÃO escreve direto nos pagamentos', format('insert into public.cobranca_pagamentos(condominio_id,cobranca_id,data_pagamento,valor_centavos,forma,criado_por) values (%L,%L,%L,100,%L,%L)', 'aaaaaaaa-0000-0000-0000-000000000001', v_c201, hoje, 'pix', sind), 'permission denied');
 perform t.fim();
 perform t.erro(S,'nem o dono altera a situação de pagamento por UPDATE direto (gatilho)', format('update public.cobrancas set status = %L, pago_em = now() where id = %L', 'paga', v_c201), 'registro de pagamento');
 perform t.erro(S,'pagamentos não são apagados (gatilho)', 'delete from public.cobranca_pagamentos', 'não podem ser apagados');
 perform t.erro(S,'pagamentos não são alterados (gatilho)', 'update public.cobranca_pagamentos set valor_centavos = 1', 'não podem ser alterados');
 -- ligação com o extrato importado
 perform t.eu(sind);
 r := public.importar_extrato('cobr.ofx', t.sha('cobr1'), hoje - 5, hoje - 1, null, null, jsonb_build_array(
   jsonb_build_object('data', hoje - 3, 'valor_centavos', 126500, 'memo', 'COB COMPE', 'acao', 'lancar', 'categoria', 'Taxa condominial', 'descricao', 'Cotas recebidas por boleto'),
   jsonb_build_object('data', hoje - 3, 'valor_centavos', -630, 'memo', 'COB COMPE', 'acao', 'lancar', 'categoria', 'Outras despesas', 'descricao', 'Tarifa')), true);
 select id into v_l1 from public.extrato_linhas where valor_centavos = 126500; select id into v_l2 from public.extrato_linhas where valor_centavos = -630;
 r := public.registrar_pagamento_cobranca(v_c102, hoje - 3, 60000, 'boleto', v_l1, 'parte da 102');
 r := public.registrar_pagamento_cobranca(v_c201, hoje - 3, 66500, 'boleto', v_l1, 'parte da 201');
 perform t.ok(S,'um crédito do extrato pode pagar várias cobranças até o seu valor', (select sum(valor_centavos) from public.cobranca_pagamentos where extrato_linha_id = v_l1 and removido_em is null) = 126500);
 perform t.erro(S,'passar do valor do crédito do extrato é recusado', format('select public.registrar_pagamento_cobranca(%L,%L,100,%L,%L)', v_c102, hoje - 3, 'boleto', v_l1), 'faltam só');
 perform t.erro(S,'débito do extrato não serve como pagamento', format('select public.registrar_pagamento_cobranca(%L,%L,100,%L,%L)', v_c102, hoje - 3, 'boleto', v_l2), 'não é um crédito');
 perform t.fim();
 perform t.ok(S,'pagamento NÃO cria lançamento (a receita já está no livro-caixa pelo extrato)', (select count(*) from public.lancamentos where tipo = 'receita') = 1);
 select count(*) into v_n from public.auditoria where acao in ('registrar_pagamento_cobranca', 'remover_pagamento_cobranca', 'cobranca_mensal.gerar', 'cobranca_mensal.liberar'); perform t.ok(S,'gerar, liberar, pagar e remover ficam na auditoria', v_n >= 7, v_n::text);
end $$;
-- (bloco separado = outra transação: gerar_cobranca_mensal usa tabelas temporárias que só somem no fim da transação)
do $$
declare S constant text := 'cobrança por unidade';
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '1 month')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; v_ciclo uuid;
begin
 perform t.eu(sind);
 perform t.erro(S,'reabrir ciclo com pagamentos registrados é recusado', format('select public.reabrir_cobranca_mensal(%L)', m0), 'pagamentos registrados');
 insert into public.previsoes_mensais (condominio_id, competencia, taxa_por_unidade_centavos, fundo_obras_por_unidade_centavos) values ('aaaaaaaa-0000-0000-0000-000000000001', (m0 - interval '1 month')::date, 50000, 0);
 v_ciclo := public.gerar_cobranca_mensal((m0 - interval '1 month')::date, m0 - 20, 90000, null, false);
 perform public.liberar_cobranca_mensal((m0 - interval '1 month')::date);
 perform public.reabrir_cobranca_mensal((m0 - interval '1 month')::date);
 perform t.ok(S,'reabrir ciclo sem pagamentos volta as cobranças para rascunho', (select count(*) from public.cobrancas where ciclo_id = v_ciclo and status = 'rascunho') = 3 and (select status from public.ciclos_cobranca where id = v_ciclo) = 'gerado');
 perform t.fim();
end $$;
do $$
declare S constant text := 'cobrança por unidade';
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '1 month')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; v_ciclo uuid;
begin
 perform t.eu(sind);
 v_ciclo := public.gerar_cobranca_mensal((m0 - interval '1 month')::date, m0 - 18, 90000, null, true);
 perform t.ok(S,'depois de reaberto, é possível gerar de novo substituindo o rascunho', (select vencimento from public.ciclos_cobranca where id = v_ciclo) = m0 - 18 and (select count(*) from public.cobrancas where ciclo_id = v_ciclo) = 3);
 perform t.fim();
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
