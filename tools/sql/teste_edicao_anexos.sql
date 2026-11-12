-- Teste de edição de lançamentos (histórico) e anexos (Storage): permissões, validações, imutabilidade e isolamento (V1.13).
-- Rodar em banco de TESTE com schema.sql e migrações 001–008 (+ mock do Supabase). Uso: psql -d teste -v ON_ERROR_STOP=1 -f tools/sql/teste_edicao_anexos.sql
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

truncate public.auditoria, public.lancamentos_historico, public.comprovantes_financeiros, public.lancamentos, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from storage.objects; delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000001','Cond A'),('bbbbbbbb-0000-0000-0000-000000000001','Cond B');
insert into auth.users(id,email) values ('11111111-0000-0000-0000-000000000001','sindico@a.com'),('22222222-0000-0000-0000-000000000101','m101@a.com'),
 ('33333333-0000-0000-0000-000000000001','conselho@a.com'),('44444444-0000-0000-0000-000000000001','sindico@b.com');
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');
update public.condominios set saldo_inicial_centavos = 100000, saldo_inicial_data = date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '3 months')::date where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ===================================== EDIÇÃO =====================================
do $$
declare S constant text := 'edição'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
 m0 date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date - interval '3 months')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; mor uuid := '22222222-0000-0000-0000-000000000101';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
 l1 uuid; l2 uuid; l3 uuid; r jsonb; v int; n int; h record; m1 date := (m0 + interval '1 month')::date;
 ed text := 'select public.editar_lancamento(%L,%L,%s,%L,%L,%L,%L,%L,%L)';
begin
 perform t.eu(sind);
 l1 := public.registrar_lancamento('despesa', m0 + 10, 50000, 'Limpeza', 'Limpeza do mês', 'Ideal', 'NF 10', 'obs inicial');
 l2 := public.registrar_lancamento('receita', v_hoje - 2, 80000, 'Taxa condominial', 'Cota 101');
 l3 := public.registrar_lancamento('despesa', v_hoje - 3, 30000, 'Gás', 'Botijão');
 -- (1) edição básica
 v := public.editar_lancamento(l1, m0 + 10, 55000, 'Limpeza', 'Limpeza do mês (corrigido)', 'Ideal', 'NF 10', 'obs inicial', 'valor digitado errado');
 perform t.ok(S,'editar devolve a nova versão (2)', v = 2, v::text);
 perform t.ok(S,'valor, descrição, versão, editado_em e editado_por atualizados', (select valor_centavos = 55000 and descricao = 'Limpeza do mês (corrigido)' and versao = 2 and editado_em is not null and editado_por = sind from public.lancamentos where id = l1));
 perform t.ok(S,'competência não muda quando a data não muda', (select competencia = m0 from public.lancamentos where id = l1));
 select * into h from public.lancamentos_historico where lancamento_id = l1 and versao = 2;
 perform t.ok(S,'histórico guarda só os campos alterados (antes/depois)', h.antes = '{"valor_centavos":50000,"descricao":"Limpeza do mês"}'::jsonb and h.depois = '{"valor_centavos":55000,"descricao":"Limpeza do mês (corrigido)"}'::jsonb, h.antes::text || ' | ' || h.depois::text);
 perform t.ok(S,'histórico guarda motivo e autor', h.motivo = 'valor digitado errado' and h.editado_por = sind);
 -- (2) sem alteração / motivo
 perform t.erro(S,'edição sem nenhuma alteração é recusada', format(ed, l1, m0 + 10, 55000, 'Limpeza', 'Limpeza do mês (corrigido)', 'Ideal', 'NF 10', 'obs inicial', 'sem mudança nenhuma'), 'Nada foi alterado');
 perform t.erro(S,'motivo curto é recusado', format(ed, l1, m0 + 10, 56000, 'Limpeza', 'Limpeza do mês (corrigido)', 'Ideal', 'NF 10', 'obs inicial', 'abc'), 'motivo');
 perform t.erro(S,'motivo vazio é recusado', format(ed, l1, m0 + 10, 56000, 'Limpeza', 'Limpeza do mês (corrigido)', 'Ideal', 'NF 10', 'obs inicial', ''), 'motivo');
 -- (3) validações
 perform t.erro(S,'valor zero é recusado', format(ed, l1, m0 + 10, 0, 'Limpeza', 'x', null, null, null, 'motivo válido'), 'maior que zero');
 perform t.erro(S,'valor acima do limite é recusado', format(ed, l1, m0 + 10, 1000000001, 'Limpeza', 'x', null, null, null, 'motivo válido'), 'limite');
 perform t.erro(S,'data futura é recusada', format(ed, l1, v_hoje + 1, 100, 'Limpeza', 'x', null, null, null, 'motivo válido'), 'futura');
 perform t.erro(S,'data anterior ao saldo de abertura é recusada', format(ed, l1, m0 - 1, 100, 'Limpeza', 'x', null, null, null, 'motivo válido'), 'saldo de abertura');
 perform t.erro(S,'descrição vazia é recusada', format(ed, l1, m0 + 10, 100, 'Limpeza', '   ', null, null, null, 'motivo válido'), 'Descrição');
 perform t.erro(S,'descrição com mais de 120 caracteres é recusada', format(ed, l1, m0 + 10, 100, 'Limpeza', repeat('x', 121), null, null, null, 'motivo válido'), 'Descrição');
 perform t.erro(S,'categoria vazia é recusada', format(ed, l1, m0 + 10, 100, '', 'x', null, null, null, 'motivo válido'), 'Categoria');
 perform t.erro(S,'documento com mais de 60 caracteres é recusado', format(ed, l1, m0 + 10, 100, 'Limpeza', 'x', null, repeat('9', 61), null, 'motivo válido'), 'documento');
 perform t.erro(S,'observação com mais de 300 caracteres é recusada', format(ed, l1, m0 + 10, 100, 'Limpeza', 'x', null, null, repeat('o', 301), 'motivo válido'), 'Observação');
 perform t.ok(S,'validações falhas não deixaram rastro (versão continua 2)', (select versao from public.lancamentos where id = l1) = 2 and (select count(*) from public.lancamentos_historico where lancamento_id = l1) = 1);
 -- (4) segunda edição: muda a data de mês; totais acompanham
 r := public.relatorio_mensal(extract(year from m0)::int, extract(month from m0)::int);
 perform t.ok(S,'antes: saídas do mês original = 550,00', (r->>'saidas_centavos')::bigint = 55000, r::text);
 v := public.editar_lancamento(l1, m1 + 4, 55000, 'Limpeza', 'Limpeza do mês (corrigido)', 'Ideal', 'NF 10', 'obs inicial', 'lançado no mês errado');
 perform t.ok(S,'mudar a data de mês atualiza a competência', (select competencia = m1 and versao = 3 from public.lancamentos where id = l1));
 r := public.relatorio_mensal(extract(year from m0)::int, extract(month from m0)::int);
 perform t.ok(S,'mês antigo perde a despesa (saídas 0)', (r->>'saidas_centavos')::bigint = 0, r::text);
 r := public.relatorio_mensal(extract(year from m1)::int, extract(month from m1)::int);
 perform t.ok(S,'mês novo ganha a despesa e o saldo acumulado acompanha', (r->>'saidas_centavos')::bigint = 55000 and (r->>'saldo_anterior_centavos')::bigint = 100000, r::text);
 select count(*) into n from public.lancamentos_historico where lancamento_id = l1; perform t.ok(S,'duas edições = duas linhas de histórico (versões 2 e 3)', n = 2 and exists (select 1 from public.lancamentos_historico where lancamento_id = l1 and versao = 3));
 perform t.ok(S,'edição fica na auditoria', (select count(*) from public.auditoria where acao = 'editar_lancamento') = 2);
 -- (5) estorno x edição
 perform public.estornar_lancamento(l3, 'lançado por engano');
 perform t.erro(S,'lançamento estornado não pode ser editado', format(ed, l3, v_hoje - 3, 31000, 'Gás', 'Botijão', null, null, null, 'tentando editar'), 'estornado');
 perform t.erro(S,'estorno não pode ser editado', format('select public.editar_lancamento(id,%L,100,%L,%L,null,null,null,%L) from public.lancamentos where tipo = %L', v_hoje, 'Gás', 'x', 'tentando editar', 'estorno'), 'Estornos');
 perform t.erro(S,'lançamento inexistente', format(ed, gen_random_uuid(), v_hoje, 100, 'Gás', 'x', null, null, null, 'motivo válido'), 'não encontrado');
 perform t.fim();
 -- (6) permissões
 perform t.eu(mor); perform t.erro(S,'morador NÃO edita', format(ed, l2, v_hoje - 2, 90000, 'Taxa condominial', 'Cota 101', null, null, null, 'tentando editar'), 'Apenas o síndico'); perform t.fim();
 perform t.eu(cons); perform t.erro(S,'conselho NÃO edita', format(ed, l2, v_hoje - 2, 90000, 'Taxa condominial', 'Cota 101', null, null, null, 'tentando editar'), 'Apenas o síndico'); perform t.fim();
 perform t.anon(); perform t.erro(S,'anônimo NÃO executa editar_lancamento', format(ed, l2, v_hoje - 2, 90000, 'Taxa condominial', 'Cota 101', null, null, null, 'tentando editar'), 'permission denied'); perform t.fim();
 perform t.eu(sindB); perform t.erro(S,'síndico de OUTRO condomínio não edita lançamento de A', format(ed, l2, v_hoje - 2, 90000, 'Taxa condominial', 'Cota 101', null, null, null, 'tentando editar'), 'não encontrado'); perform t.fim();
 perform t.ok(S,'tentativas negadas não alteraram o lançamento', (select valor_centavos = 80000 and versao = 1 from public.lancamentos where id = l2));
 -- (7) imutabilidade fora da função
 perform t.eu(sind);
 perform t.erro(S,'síndico NÃO altera por UPDATE direto', format('update public.lancamentos set valor_centavos = 1 where id = %L', l2), 'permission denied');
 perform t.erro(S,'síndico NÃO apaga por DELETE direto', format('delete from public.lancamentos where id = %L', l2), 'permission denied');
 perform t.fim();
 perform t.erro(S,'nem o dono do banco altera sem passar pela função', format('update public.lancamentos set valor_centavos = 1 where id = %L', l2), 'não podem ser alterados');
 perform set_config('app.editando', '1', false);
 perform t.erro(S,'mesmo "fingindo" ser a edição, não dá para trocar o tipo', format('update public.lancamentos set tipo = %L where id = %L', 'despesa', l2), 'Edição inválida');
 perform t.erro(S,'mesmo "fingindo" ser a edição, não dá para trocar o autor', format('update public.lancamentos set criado_por = %L where id = %L', mor, l2), 'Edição inválida');
 perform t.erro(S,'mesmo "fingindo" ser a edição, não dá para trocar o condomínio', format('update public.lancamentos set condominio_id = %L where id = %L', 'bbbbbbbb-0000-0000-0000-000000000001', l2), 'Edição inválida');
 perform set_config('app.editando', '0', false);
 perform t.erro(S,'lançamento continua sem DELETE nem para o dono', format('delete from public.lancamentos where id = %L', l2), 'não podem ser apagados');
 -- (8) histórico: leitura e imutabilidade
 perform t.eu(cons); perform t.ok(S,'conselho lê o histórico (2 versões)', (select count(*) from public.lancamentos_historico where lancamento_id = l1) = 2); perform t.fim();
 perform t.eu(mor); perform t.ok(S,'morador NÃO lê o histórico', (select count(*) from public.lancamentos_historico) = 0); perform t.fim();
 perform t.eu(sindB); perform t.ok(S,'outro condomínio NÃO lê o histórico', (select count(*) from public.lancamentos_historico) = 0); perform t.fim();
 perform t.eu(sind);
 perform t.erro(S,'síndico NÃO escreve no histórico direto', format('insert into public.lancamentos_historico(lancamento_id,condominio_id,versao,motivo,antes,depois,editado_por) values (%L,%L,9,%L,%L,%L,%L)', l1, 'aaaaaaaa-0000-0000-0000-000000000001', 'forjado aqui', '{}', '{}', sind), 'permission denied');
 perform t.fim();
 perform t.erro(S,'histórico não pode ser alterado nem pelo dono', 'update public.lancamentos_historico set motivo = ''alterado por mim''', 'não pode ser alterado');
 perform t.erro(S,'histórico não pode ser apagado nem pelo dono', 'delete from public.lancamentos_historico', 'não pode ser alterado');
end $$;

-- ===================================== ANEXOS =====================================
do $$
declare S constant text := 'anexos'; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; mor uuid := '22222222-0000-0000-0000-000000000101';
 cons uuid := '33333333-0000-0000-0000-000000000001'; sindB uuid := '44444444-0000-0000-0000-000000000001';
 A constant text := 'aaaaaaaa-0000-0000-0000-000000000001'; B constant text := 'bbbbbbbb-0000-0000-0000-000000000001';
 lanc uuid; lancB uuid; est uuid; cid uuid; caminho text; n int;
 sha constant text := repeat('ab', 32);
 reg text := 'select public.registrar_comprovante(%L,%L,%L,%L,%s,%L)';
begin
 select id into lanc from public.lancamentos where descricao = 'Cota 101';
 select id into est from public.lancamentos where tipo = 'estorno' limit 1;
 perform t.eu(sindB); lancB := public.registrar_lancamento('despesa', v_hoje - 1, 1000, 'Limpeza', 'Lançamento do B'); perform t.fim();
 caminho := A || '/' || lanc || '/' || gen_random_uuid() || '.pdf';
 perform t.ok(S,'bucket é privado e limita 10 MB', (select not public and file_size_limit = 10485760 from storage.buckets where id = 'comprovantes'));
 -- (1) storage: quem envia, quem lê
 perform t.eu(sind);
 insert into storage.objects(bucket_id, name, owner) values ('comprovantes', caminho, sind);
 perform t.ok(S,'síndico envia arquivo para a pasta do próprio condomínio', exists (select 1 from storage.objects where name = caminho));
 perform t.erro(S,'síndico NÃO envia para a pasta de outro condomínio', format('insert into storage.objects(bucket_id,name,owner) values (%L,%L,%L)', 'comprovantes', B || '/x/' || gen_random_uuid() || '.pdf', sind), 'row-level security');
 perform t.erro(S,'síndico NÃO envia para outro bucket', format('insert into storage.objects(bucket_id,name,owner) values (%L,%L,%L)', 'publico', A || '/x/y.pdf', sind), 'violates');
 perform t.fim();
 perform t.eu(mor); perform t.erro(S,'morador NÃO envia arquivo', format('insert into storage.objects(bucket_id,name,owner) values (%L,%L,%L)', 'comprovantes', A || '/' || lanc || '/' || gen_random_uuid() || '.pdf', mor), 'row-level security'); perform t.fim();
 perform t.eu(cons); perform t.erro(S,'conselho NÃO envia arquivo', format('insert into storage.objects(bucket_id,name,owner) values (%L,%L,%L)', 'comprovantes', A || '/' || lanc || '/' || gen_random_uuid() || '.pdf', cons), 'row-level security');
 perform t.ok(S,'conselho LÊ os arquivos do condomínio', (select count(*) from storage.objects where bucket_id = 'comprovantes') = 1); perform t.fim();
 perform t.eu(mor); perform t.ok(S,'morador NÃO lê arquivos', (select count(*) from storage.objects) = 0); perform t.fim();
 perform t.eu(sindB); perform t.ok(S,'outro condomínio NÃO lê arquivos', (select count(*) from storage.objects) = 0); perform t.fim();
 perform t.eu(sind);
 update storage.objects set name = A || '/trocado.pdf' where name = caminho; get diagnostics n = row_count; perform t.ok(S,'síndico NÃO renomeia/sobrescreve arquivo (sem policy de UPDATE)', n = 0);
 delete from storage.objects where name = caminho; get diagnostics n = row_count; perform t.ok(S,'síndico NÃO apaga arquivo (sem policy de DELETE)', n = 0 and exists (select 1 from storage.objects where name = caminho));
 -- (2) registrar_comprovante
 cid := public.registrar_comprovante(lanc, caminho, 'nota 123.pdf', 'application/pdf', 20480, sha);
 perform t.ok(S,'registrar anexo grava nome, tipo, tamanho, hash e autor', (select nome_arquivo = 'nota 123.pdf' and mime_type = 'application/pdf' and tamanho_bytes = 20480 and sha256 = sha and enviado_por = sind and removido_em is null from public.comprovantes_financeiros where id = cid));
 perform t.ok(S,'anexo fica na auditoria', (select count(*) from public.auditoria where acao = 'anexar_comprovante') = 1);
 perform t.erro(S,'caminho de outro lançamento é recusado', format(reg, lanc, A || '/' || gen_random_uuid() || '/' || gen_random_uuid() || '.pdf', 'x.pdf', 'application/pdf', 100, sha), 'Caminho');
 perform t.erro(S,'caminho com extensão não permitida é recusado', format(reg, lanc, A || '/' || lanc || '/' || gen_random_uuid() || '.exe', 'x.exe', 'application/pdf', 100, sha), 'Caminho');
 perform t.erro(S,'caminho de outro condomínio é recusado', format(reg, lanc, B || '/' || lanc || '/' || gen_random_uuid() || '.pdf', 'x.pdf', 'application/pdf', 100, sha), 'Caminho');
 perform t.erro(S,'tipo de arquivo não permitido é recusado', format(reg, lanc, caminho, 'x.pdf', 'application/zip', 100, sha), 'não permitido');
 perform t.erro(S,'tamanho zero é recusado', format(reg, lanc, caminho, 'x.pdf', 'application/pdf', 0, sha), '10 MB');
 perform t.erro(S,'tamanho acima de 10 MB é recusado', format(reg, lanc, caminho, 'x.pdf', 'application/pdf', 10485761, sha), '10 MB');
 perform t.erro(S,'hash inválido é recusado', format(reg, lanc, caminho, 'x.pdf', 'application/pdf', 100, 'zzz'), 'SHA-256');
 perform t.erro(S,'nome vazio é recusado', format(reg, lanc, caminho, '   ', 'application/pdf', 100, sha), 'Nome');
 perform t.erro(S,'arquivo que não foi enviado ao Storage é recusado', format(reg, lanc, A || '/' || lanc || '/' || gen_random_uuid() || '.pdf', 'x.pdf', 'application/pdf', 100, sha), 'não encontrado no armazenamento');
 perform t.erro(S,'estorno não recebe anexo', format(reg, est, A || '/' || est || '/' || gen_random_uuid() || '.pdf', 'x.pdf', 'application/pdf', 100, sha), 'original');
 perform t.erro(S,'lançamento de outro condomínio não recebe anexo', format(reg, lancB, caminho, 'x.pdf', 'application/pdf', 100, sha), 'não encontrado');
 perform t.erro(S,'síndico NÃO insere em comprovantes direto', format('insert into public.comprovantes_financeiros(lancamento_id,caminho_storage,nome_arquivo,enviado_por) values (%L,%L,%L,%L)', lanc, caminho, 'x', sind), 'permission denied');
 perform t.erro(S,'síndico NÃO altera comprovantes direto', format('update public.comprovantes_financeiros set nome_arquivo = %L', 'x'), 'permission denied');
 -- limite de 8 anexos por lançamento
 for n in 1..7 loop
   caminho := A || '/' || lanc || '/' || gen_random_uuid() || '.jpg';
   insert into storage.objects(bucket_id, name, owner) values ('comprovantes', caminho, sind);
   perform public.registrar_comprovante(lanc, caminho, 'foto' || n || '.jpg', 'image/jpeg', 1000, sha);
 end loop;
 caminho := A || '/' || lanc || '/' || gen_random_uuid() || '.png'; insert into storage.objects(bucket_id, name, owner) values ('comprovantes', caminho, sind);
 perform t.erro(S,'o 9º anexo do mesmo lançamento é recusado (limite 8)', format(reg, lanc, caminho, 'x.png', 'image/png', 100, sha), 'Limite de 8');
 perform t.fim();
 -- (3) permissões
 perform t.eu(mor); perform t.erro(S,'morador NÃO registra anexo', format(reg, lanc, caminho, 'x.png', 'image/png', 100, sha), 'Apenas o síndico'); perform t.ok(S,'morador NÃO lista anexos', (select count(*) from public.comprovantes_financeiros) = 0); perform t.fim();
 perform t.eu(cons); perform t.erro(S,'conselho NÃO registra anexo', format(reg, lanc, caminho, 'x.png', 'image/png', 100, sha), 'Apenas o síndico'); perform t.ok(S,'conselho lista os anexos', (select count(*) from public.comprovantes_financeiros) = 8); perform t.fim();
 perform t.eu(sindB); perform t.ok(S,'outro condomínio NÃO lista anexos', (select count(*) from public.comprovantes_financeiros) = 0); perform t.fim();
 perform t.anon(); perform t.erro(S,'anônimo NÃO executa registrar_comprovante', format(reg, lanc, caminho, 'x.png', 'image/png', 100, sha), 'permission denied'); perform t.fim();
 -- (4) remover (o arquivo e o registro permanecem)
 perform t.eu(sind);
 perform t.erro(S,'remover exige motivo', format('select public.remover_comprovante(%L,%L)', cid, 'abc'), 'motivo');
 perform public.remover_comprovante(cid, 'arquivo errado');
 perform t.ok(S,'anexo removido sai da lista ativa, mas o registro e o motivo ficam', (select removido_em is not null and removido_por = sind and motivo_remocao = 'arquivo errado' from public.comprovantes_financeiros where id = cid)
   and (select count(*) from public.comprovantes_financeiros where removido_em is null) = 7);
 perform t.ok(S,'o arquivo continua no Storage (evidência)', (select count(*) from storage.objects) = 9);
 perform t.erro(S,'remover de novo é recusado', format('select public.remover_comprovante(%L,%L)', cid, 'arquivo errado'), 'já removido');
 perform t.fim();
 perform t.eu(mor); perform t.erro(S,'morador NÃO remove anexo', format('select public.remover_comprovante(%L,%L)', cid, 'tentando remover'), 'Apenas o síndico'); perform t.fim();
 perform t.eu(sindB); perform t.erro(S,'síndico de outro condomínio NÃO remove anexo de A', format('select public.remover_comprovante((select id from public.comprovantes_financeiros where removido_em is null limit 1),%L)', 'tentando remover'), 'não encontrado'); perform t.fim();
 perform t.ok(S,'remoção fica na auditoria', (select count(*) from public.auditoria where acao = 'remover_comprovante') = 1);
end $$;
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
