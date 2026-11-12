-- Teste do livro-caixa (V1.10): registro, estorno, imutabilidade, totais, relatório mensal e permissões.
-- Rodar em banco de TESTE com schema.sql e migrações 001–006. Uso: psql -d teste -v ON_ERROR_STOP=1 -f tools/sql/teste_livro_caixa.sql
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
 ('33333333-0000-0000-0000-000000000001','conselho@a.com'),('44444444-0000-0000-0000-000000000001','sindico@b.com'),
 ('55555555-0000-0000-0000-000000000001','estranho@x.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');
do $$
declare S constant text := 'registro'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_id uuid; v_n int; r record;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001'; estr uuid := '55555555-0000-0000-0000-000000000001';
 fmt text := 'select public.registrar_lancamento(%L,%L,%s,%L,%L)';
begin
 perform t.eu(sind);
 v_id := public.registrar_lancamento('despesa', v_hoje, 42050, 'Manutenção e reparos', '  Manutenção do portão  ', 'Serralheria X', 'OS 024', 'peça trocada');
 perform t.ok(S,'síndico registra despesa e recebe o id', v_id is not null);
 perform t.fim();
 select * into r from public.lancamentos where id=v_id;
 perform t.ok(S,'valor guardado em centavos e descrição sem espaços sobrando', r.valor_centavos=42050 and r.descricao='Manutenção do portão');
 perform t.ok(S,'competência vira o 1º dia do mês da data', r.competencia = date_trunc('month', v_hoje)::date);
 perform t.ok(S,'criado_por é o síndico logado, no condomínio dele', r.criado_por=sind and r.condominio_id='aaaaaaaa-0000-0000-0000-000000000001');
 perform t.ok(S,'fornecedor, documento e observação são guardados', r.fornecedor='Serralheria X' and r.numero_documento='OS 024' and r.observacao='peça trocada');
 perform t.eu(sind);
 v_id := public.registrar_lancamento('receita', v_hoje, 65000, 'Taxa condominial', 'Taxa — unidade 101', null, null, null, (v_hoje - 40));
 perform t.fim(); select competencia into r from public.lancamentos where id=v_id;
 perform t.ok(S,'competência informada é normalizada para o 1º dia do mês', r.competencia = date_trunc('month', v_hoje - 40)::date);
 perform t.erro(S,'toque duplo: lançamento idêntico em 2 minutos é recusado',format('select public.registrar_lancamento(%L,%L,65000,%L,%L)','receita',v_hoje,'Taxa condominial','Taxa — unidade 101'),'idêntico');
 perform t.eu(sind); v_id := public.registrar_lancamento('receita', v_hoje, 65001, 'Taxa condominial', 'Taxa — unidade 101'); perform t.fim();
 perform t.ok(S,'mesma descrição com valor diferente é aceita', v_id is not null);
 -- validações (como síndico)
 perform t.eu(sind);
 perform t.erro(S,'valor zero recusado',format(fmt,'despesa',v_hoje,'0','Limpeza','x'),'maior que zero');
 perform t.erro(S,'valor negativo recusado',format(fmt,'despesa',v_hoje,'-100','Limpeza','x'),'maior que zero');
 perform t.erro(S,'valor acima do limite recusado',format(fmt,'despesa',v_hoje,'1000000001','Limpeza','x'),'limite');
 perform t.erro(S,'tipo estorno não pode ser registrado direto',format(fmt,'estorno',v_hoje,'100','Limpeza','x'),'receita ou despesa');
 perform t.erro(S,'tipo inválido recusado',format(fmt,'doacao',v_hoje,'100','Limpeza','x'),'receita ou despesa');
 perform t.erro(S,'data futura recusada',format(fmt,'despesa',v_hoje+1,'100','Limpeza','x'),'futura');
 perform t.erro(S,'data com mais de 5 anos recusada',format(fmt,'despesa',v_hoje-1900,'100','Limpeza','x'),'5 anos');
 perform t.erro(S,'descrição vazia recusada',format(fmt,'despesa',v_hoje,'100','Limpeza','   '),'Descrição');
 perform t.erro(S,'descrição com mais de 120 caracteres recusada',format(fmt,'despesa',v_hoje,'100','Limpeza',repeat('x',121)),'Descrição');
 perform t.erro(S,'categoria vazia recusada',format(fmt,'despesa',v_hoje,'100','','x'),'Categoria');
 perform t.erro(S,'observação com mais de 300 caracteres recusada',format('select public.registrar_lancamento(%L,%L,100,%L,%L,null,null,%L)','despesa',v_hoje,'Limpeza','x',repeat('o',301)),'Observação');
 perform t.fim();
 -- quem não pode
 perform t.eu(cons); perform t.erro(S,'conselho NÃO registra lançamento',format(fmt,'despesa',v_hoje,'100','Limpeza','x'),'Apenas o síndico'); perform t.fim();
 perform t.eu(m101); perform t.erro(S,'morador NÃO registra lançamento',format(fmt,'despesa',v_hoje,'100','Limpeza','x'),'Apenas o síndico'); perform t.fim();
 perform t.eu(estr); perform t.erro(S,'usuário sem perfil NÃO registra lançamento',format(fmt,'despesa',v_hoje,'100','Limpeza','x'),'Apenas o síndico'); perform t.fim();
 perform t.anon(); perform t.erro(S,'anônimo NÃO executa registrar_lancamento',format(fmt,'despesa',v_hoje,'100','Limpeza','x'),'permission denied'); perform t.fim();
 select count(*) into v_n from public.auditoria where acao='registrar_lancamento'; perform t.ok(S,'cada registro fica na auditoria', v_n=3, v_n::text);
end $$;
do $$
declare S constant text := 'permissões'; v_id uuid; v_n int;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101'; cons uuid := '33333333-0000-0000-0000-000000000001';
 sindB uuid := '44444444-0000-0000-0000-000000000001';
begin
 select id into v_id from public.lancamentos order by criado_em limit 1;
 perform t.eu(sind);
 perform t.erro(S,'síndico NÃO insere lançamento direto na tabela',$q$insert into public.lancamentos(condominio_id,tipo,data_lancamento,valor_centavos,categoria,descricao,criado_por) values ('aaaaaaaa-0000-0000-0000-000000000001','receita',current_date,100,'x','x','11111111-0000-0000-0000-000000000001')$q$,'permission denied');
 perform t.erro(S,'síndico NÃO altera valor direto na tabela',format('update public.lancamentos set valor_centavos=1 where id=%L',v_id),'permission denied');
 perform t.erro(S,'síndico NÃO apaga lançamento direto',format('delete from public.lancamentos where id=%L',v_id),'permission denied');
 perform t.erro(S,'síndico NÃO executa TRUNCATE no livro-caixa','truncate public.lancamentos','permission denied');
 select count(*) into v_n from public.lancamentos; perform t.ok(S,'síndico lê os lançamentos do condomínio', v_n=3, v_n::text);
 perform t.fim(); perform t.eu(cons);
 select count(*) into v_n from public.lancamentos; perform t.ok(S,'conselho lê o detalhe dos lançamentos', v_n=3, v_n::text);
 perform t.fim(); perform t.eu(m101);
 select count(*) into v_n from public.lancamentos; perform t.ok(S,'morador NÃO enxerga lançamentos individuais', v_n=0, v_n::text);
 perform t.fim(); perform t.eu(sindB);
 select count(*) into v_n from public.lancamentos; perform t.ok(S,'síndico de OUTRO condomínio não enxerga nada', v_n=0, v_n::text);
 perform t.fim(); perform t.anon();
 perform t.erro(S,'anônimo NÃO lê lançamentos','select * from public.lancamentos','permission denied');
 perform t.erro(S,'anônimo NÃO lê perfis (endurecimento geral)','select * from public.perfis','permission denied');
 perform t.erro(S,'anônimo NÃO lê convites','select * from public.convites','permission denied');
 perform t.fim();
 -- trigger de imutabilidade (vale até para quem tem acesso direto ao banco)
 perform t.erro(S,'trigger: alterar valor é barrado mesmo como administrador do banco',format('update public.lancamentos set valor_centavos=1 where id=%L',v_id),'não podem ser alterados');
 perform t.erro(S,'trigger: alterar descrição é barrado',format('update public.lancamentos set descricao=%L where id=%L','outra',v_id),'não podem ser alterados');
 perform t.erro(S,'trigger: apagar é barrado',format('delete from public.lancamentos where id=%L',v_id),'não podem ser apagados');
 perform t.erro(S,'trigger: marcar estorno sem motivo é barrado',format('update public.lancamentos set estornado_em=now() where id=%L',v_id),'não podem ser alterados');
end $$;
do $$
declare S constant text := 'estorno'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_orig uuid; v_est uuid; v_n int; o record; e record;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101'; cons uuid := '33333333-0000-0000-0000-000000000001';
 sindB uuid := '44444444-0000-0000-0000-000000000001'; estr uuid := '55555555-0000-0000-0000-000000000001';
begin
 select id into v_orig from public.lancamentos where numero_documento='OS 024';
 perform t.eu(m101); perform t.erro(S,'morador NÃO estorna',format('select public.estornar_lancamento(%L,%L)',v_orig,'motivo válido'),'Apenas o síndico'); perform t.fim();
 perform t.eu(cons); perform t.erro(S,'conselho NÃO estorna',format('select public.estornar_lancamento(%L,%L)',v_orig,'motivo válido'),'Apenas o síndico'); perform t.fim();
 perform t.eu(sindB); perform t.erro(S,'síndico de OUTRO condomínio NÃO estorna lançamento alheio',format('select public.estornar_lancamento(%L,%L)',v_orig,'motivo válido'),'não encontrado'); perform t.fim();
 perform t.eu(sind);
 perform t.erro(S,'motivo curto recusado',format('select public.estornar_lancamento(%L,%L)',v_orig,'abc'),'motivo');
 perform t.erro(S,'lançamento inexistente recusado',format('select public.estornar_lancamento(%L,%L)',gen_random_uuid(),'motivo válido'),'não encontrado');
 begin v_est := public.estornar_lancamento(v_orig, 'Lançado em duplicidade');
 exception when others then perform t.fim(); perform t.ok(S,'síndico consegue estornar (fluxo principal)', false, SQLERRM); return; end;
 perform t.fim();
 select * into o from public.lancamentos where id=v_orig; select * into e from public.lancamentos where id=v_est;
 perform t.ok(S,'estorno cria lançamento tipo estorno com o mesmo valor e ligado ao original', e.tipo='estorno' and e.valor_centavos=o.valor_centavos and e.lancamento_original_id=v_orig);
 perform t.ok(S,'estorno entra na data de HOJE (não reescreve o mês do original)', e.data_lancamento=v_hoje);
 perform t.ok(S,'original fica marcado com data, autor e motivo', o.estornado_em is not null and o.estornado_por=sind and o.motivo_estorno='Lançado em duplicidade');
 perform t.ok(S,'valor e descrição do original continuam intactos', o.valor_centavos=42050 and o.descricao='Manutenção do portão');
 perform t.eu(sind);
 perform t.erro(S,'estornar de novo é recusado',format('select public.estornar_lancamento(%L,%L)',v_orig,'motivo válido'),'já foi estornado');
 perform t.erro(S,'estornar um estorno é recusado',format('select public.estornar_lancamento(%L,%L)',v_est,'motivo válido'),'não pode ser estornado');
 perform t.fim();
 perform t.erro(S,'trigger: original estornado não pode mais ser alterado',format('update public.lancamentos set estornado_em=null where id=%L',v_orig),'já estornado');
 select count(*) into v_n from public.auditoria where acao='estornar_lancamento'; perform t.ok(S,'estorno fica na auditoria', v_n=1);
end $$;
-- ====================== TOTAIS E RELATÓRIO ======================
truncate public.lancamentos cascade;
do $$
declare S constant text := 'totais'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_ini date := date_trunc('month',(now() at time zone 'America/Sao_Paulo'))::date;
 v_prev date := (date_trunc('month',(now() at time zone 'America/Sao_Paulo')) - interval '1 month')::date; v_desp uuid; v_rec uuid; r record; j jsonb;
 a int := extract(year from v_ini); m int := extract(month from v_ini); pa int := extract(year from v_prev); pm int := extract(month from v_prev);
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101'; cons uuid := '33333333-0000-0000-0000-000000000001';
 sindB uuid := '44444444-0000-0000-0000-000000000001'; estr uuid := '55555555-0000-0000-0000-000000000001'; CA constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
begin
 -- mês anterior (dados históricos): receita 2.000,00 + despesa 300,00 (inseridas direto, como importação)
 insert into public.lancamentos(condominio_id,tipo,data_lancamento,competencia,valor_centavos,categoria,descricao,criado_por) values
  (CA,'receita',v_prev+9,v_prev,200000,'Taxa condominial','Taxas do mês anterior',sind),
  (CA,'despesa',v_prev+11,v_prev,30000,'Limpeza','Limpeza do mês anterior',sind);
 select id into v_desp from public.lancamentos where descricao='Limpeza do mês anterior';
 -- mês atual: receita 1.000,00 e despesa 400,00, via funções
 perform t.eu(sind);
 perform public.registrar_lancamento('receita', v_hoje, 100000, 'Taxa condominial', 'Taxas do mês');
 perform public.registrar_lancamento('despesa', v_hoje, 40000, 'Energia das áreas comuns', 'Conta de energia');
 perform t.fim();
 perform t.eu(m101); select * into r from public.resumo_financeiro(a,m);
 perform t.ok(S,'morador vê só totais do mês: entradas 1.000,00, saídas 400,00, saldo 600,00', r.receitas_centavos=100000 and r.despesas_centavos=40000 and r.saldo_centavos=60000, r::text);
 select * into r from public.resumo_financeiro(pa,pm);
 perform t.ok(S,'totais do mês anterior ficam separados do atual', r.receitas_centavos=200000 and r.despesas_centavos=30000 and r.saldo_centavos=170000, r::text);
 perform t.erro(S,'mês 13 é período inválido','select * from public.resumo_financeiro(2026,13)','Período inválido');
 perform t.erro(S,'mês nulo é período inválido','select * from public.resumo_financeiro(2026,null)','Período inválido');
 perform t.fim(); perform t.eu(estr); perform t.erro(S,'usuário sem perfil NÃO vê totais','select * from public.resumo_financeiro(2026,10)','sem vínculo'); perform t.fim();
 perform t.eu(sindB); select * into r from public.resumo_financeiro(a,m); perform t.ok(S,'outro condomínio vê zero (isolamento)', r.receitas_centavos=0 and r.despesas_centavos=0, r::text); perform t.fim();
 -- estorno da despesa do MÊS ANTERIOR, feito hoje
 perform t.eu(sind); perform public.estornar_lancamento(v_desp, 'Fatura paga em duplicidade'); perform t.fim();
 perform t.eu(m101);
 select * into r from public.resumo_financeiro(pa,pm);
 perform t.ok(S,'mês anterior NÃO é reescrito pelo estorno feito hoje', r.receitas_centavos=200000 and r.despesas_centavos=30000, r::text);
 select * into r from public.resumo_financeiro(a,m);
 perform t.ok(S,'estorno de despesa entra como entrada no mês em que foi feito (sem contar em dobro)', r.receitas_centavos=130000 and r.despesas_centavos=40000 and r.saldo_centavos=90000, r::text);
 perform t.fim();
 -- estorno de uma receita do mês atual
 select id into v_rec from public.lancamentos where descricao='Taxas do mês';
 perform t.eu(sind); perform public.estornar_lancamento(v_rec, 'Pagamento devolvido ao morador'); perform t.fim();
 perform t.eu(m101); select * into r from public.resumo_financeiro(a,m);
 perform t.ok(S,'estorno de receita entra como saída: saldo do mês volta a ser o esperado', r.receitas_centavos=130000 and r.despesas_centavos=140000 and r.saldo_centavos=-10000, r::text);
 perform t.fim();
 -- relatório mensal
 perform t.eu(m101); perform t.erro(S,'morador NÃO acessa o relatório detalhado',format('select public.relatorio_mensal(%s,%s)',a,m),'restrito'); perform t.fim();
 perform t.eu(estr); perform t.erro(S,'usuário sem perfil NÃO acessa o relatório',format('select public.relatorio_mensal(%s,%s)',a,m),'restrito'); perform t.fim();
 perform t.anon(); perform t.erro(S,'anônimo NÃO acessa o relatório',format('select public.relatorio_mensal(%s,%s)',a,m),'permission denied'); perform t.fim();
 perform t.eu(cons); j := public.relatorio_mensal(a,m); perform t.fim();
 perform t.ok(S,'relatório: conselho acessa e os totais batem com o resumo', (j->>'entradas_centavos')::bigint=130000 and (j->>'saidas_centavos')::bigint=140000 and (j->>'saldo_mes_centavos')::bigint=-10000, j::text);
 perform t.ok(S,'relatório: saldo anterior = movimento de meses anteriores (170.000 − 30.000 de despesa + 0)', (j->>'saldo_anterior_centavos')::bigint=170000, j->>'saldo_anterior_centavos');
 perform t.ok(S,'relatório: saldo final = anterior + entradas − saídas', (j->>'saldo_final_centavos')::bigint=160000, j->>'saldo_final_centavos');
 perform t.ok(S,'relatório: quantidade de movimentos do mês', (j->>'quantidade')::int=4, j->>'quantidade');
 perform t.ok(S,'relatório: por categoria soma igual ao total', (select coalesce(sum((x->>'entradas_centavos')::bigint),0)=130000 and coalesce(sum((x->>'saidas_centavos')::bigint),0)=140000 from jsonb_array_elements(j->'por_categoria') x), j->>'por_categoria');
 perform t.ok(S,'relatório: categorias aparecem separadas', (select count(*) from jsonb_array_elements(j->'por_categoria'))=3, j->>'por_categoria');
 perform t.eu(sindB); j := public.relatorio_mensal(a,m); perform t.fim();
 perform t.ok(S,'relatório: outro condomínio recebe tudo zerado', (j->>'quantidade')::int=0 and (j->>'saldo_final_centavos')::bigint=0, j::text);
 perform t.eu(sind); perform t.erro(S,'relatório: mês inválido recusado','select public.relatorio_mensal(2026,0)','Período inválido'); perform t.fim();
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
