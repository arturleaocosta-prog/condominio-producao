-- Teste de segurança/regras: login por convite e aviso da vaga de visitante (V1.9).
-- Rodar em um banco de TESTE já com schema.sql e migrações 001–005 (e o mock do Supabase, se for local).
-- Uso: psql -d teste -v ON_ERROR_STOP=1 -f tools/sql/teste_login_convites_vaga.sql
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
-- espera erro (e, opcionalmente, trecho da mensagem)
create function t.erro(sec text, nome text, cmd text, trecho text default null) returns void language plpgsql as $$
declare m text; begin
  begin execute cmd; insert into t.res(secao,nome,ok,info) values (sec,nome,false,'não deu erro');
  exception when others then get stacked diagnostics m = message_text;
    insert into t.res(secao,nome,ok,info) values (sec,nome, trecho is null or m ilike '%'||trecho||'%', m);
  end; end $$;
-- ---------- dados de teste ----------
truncate public.auditoria, public.avisos_vaga_visitante, public.convites, public.vinculos_unidades, public.perfis, public.unidades, public.condominios cascade;
delete from auth.users;
insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-000000000001','Cond A'),('bbbbbbbb-0000-0000-0000-000000000001','Cond B');
insert into public.unidades(id,condominio_id,identificacao) values
 ('a1000000-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','101'),
 ('a1000000-0000-0000-0000-000000000102','aaaaaaaa-0000-0000-0000-000000000001','102'),
 ('b1000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','X1');
insert into auth.users(id,email) values
 ('11111111-0000-0000-0000-000000000001','sindico@a.com'),('22222222-0000-0000-0000-000000000101','m101@a.com'),
 ('22222222-0000-0000-0000-000000000102','m102@a.com'),('33333333-0000-0000-0000-000000000001','conselho@a.com'),
 ('44444444-0000-0000-0000-000000000001','sindico@b.com'),('55555555-0000-0000-0000-000000000001','estranho@x.com'),
 ('66666666-0000-0000-0000-000000000101','novo101@a.com'),('66666666-0000-0000-0000-000000000102','novo102@a.com');
insert into auth.users(id,email,email_confirmed_at) values ('77777777-0000-0000-0000-000000000001','naoconf@a.com',null);
insert into public.perfis(user_id,condominio_id,nome,email,papel) values
 ('11111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Síndico A','sindico@a.com','sindico'),
 ('22222222-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','Morador 101','m101@a.com','morador'),
 ('22222222-0000-0000-0000-000000000102','aaaaaaaa-0000-0000-0000-000000000001','Morador 102','m102@a.com','morador'),
 ('33333333-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Conselho A','conselho@a.com','conselho'),
 ('44444444-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Síndico B','sindico@b.com','sindico');
insert into public.vinculos_unidades(user_id,unidade_id) values
 ('22222222-0000-0000-0000-000000000101','a1000000-0000-0000-0000-000000000101'),
 ('22222222-0000-0000-0000-000000000102','a1000000-0000-0000-0000-000000000102');
-- ========================= CONVITES / LOGIN =========================
do $$
declare S constant text := 'convites'; v_tok text; v_tok2 text; v_n int; v_r jsonb; v_id uuid;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101';
 m102 uuid := '22222222-0000-0000-0000-000000000102'; cons uuid := '33333333-0000-0000-0000-000000000001';
 sindB uuid := '44444444-0000-0000-0000-000000000001'; estr uuid := '55555555-0000-0000-0000-000000000001';
 n101 uuid := '66666666-0000-0000-0000-000000000101'; n102 uuid := '66666666-0000-0000-0000-000000000102';
 u101 uuid := 'a1000000-0000-0000-0000-000000000101'; u102 uuid := 'a1000000-0000-0000-0000-000000000102';
 uX1 uuid := 'b1000000-0000-0000-0000-000000000001';
begin
 perform t.eu(sind);
 v_tok := public.criar_convite('Novo101@a.com','morador',u101,7);
 perform t.ok(S,'síndico cria convite e recebe token de 48 hex', v_tok ~ '^[0-9a-f]{48}$');
 select count(*) into v_n from public.convites where lower(email)='novo101@a.com' and condominio_id='aaaaaaaa-0000-0000-0000-000000000001';
 perform t.ok(S,'e-mail é gravado em minúsculas e convite fica pendente', v_n=1);
 perform t.erro(S,'síndico NÃO lê token_hash (coluna protegida)','select token_hash from public.convites','permission denied');
 perform t.erro(S,'síndico NÃO insere convite direto na tabela',$q$insert into public.convites(condominio_id,email,token_hash,enviado_por,expira_em) values ('aaaaaaaa-0000-0000-0000-000000000001','x@a.com','h','11111111-0000-0000-0000-000000000001',now()+interval '1 day')$q$,'permission denied');
 perform t.erro(S,'convite para papel síndico é recusado',format('select public.criar_convite(%L,%L,%L)','s2@a.com','sindico',u101),'morador ou conselho');
 perform t.erro(S,'morador sem unidade é recusado',format('select public.criar_convite(%L,%L)','s2@a.com','morador'),'unidade');
 perform t.erro(S,'unidade de outro condomínio é recusada',format('select public.criar_convite(%L,%L,%L)','s2@a.com','morador',uX1),'Unidade inválida');
 perform t.erro(S,'validade 0 dia recusada',format('select public.criar_convite(%L,%L,%L,0)','s2@a.com','morador',u101),'Validade');
 perform t.erro(S,'validade 31 dias recusada',format('select public.criar_convite(%L,%L,%L,31)','s2@a.com','morador',u101),'Validade');
 perform t.erro(S,'e-mail inválido recusado',format('select public.criar_convite(%L,%L,%L)','semarroba','morador',u101),'E-mail');
 perform t.fim();
 perform t.eu(m101);
 perform t.erro(S,'morador NÃO cria convite',format('select public.criar_convite(%L,%L,%L)','a@a.com','morador',u101),'Apenas o síndico');
 select count(*) into v_n from public.convites; perform t.ok(S,'morador não enxerga nenhum convite', v_n=0);
 perform t.erro(S,'morador NÃO cancela convite',format('select public.cancelar_convite(%L)',gen_random_uuid()),'Apenas o síndico');
 perform t.fim(); perform t.eu(sindB);
 select count(*) into v_n from public.convites; perform t.ok(S,'síndico de OUTRO condomínio não enxerga convites', v_n=0);
 perform t.fim(); perform t.anon();
 perform t.erro(S,'anônimo (sem login) não executa criar_convite',format('select public.criar_convite(%L,%L,%L)','a@a.com','morador',u101),'permission denied');
 perform t.erro(S,'anônimo não executa aceitar_convite','select public.aceitar_convite(''x'')','permission denied');
 perform t.fim();
 -- e-mail não confirmado
 perform t.eu(sind); v_tok2 := public.criar_convite('naoconf@a.com','morador',u101,7); perform t.fim();
 perform t.eu('77777777-0000-0000-0000-000000000001'); perform t.erro(S,'e-mail NÃO confirmado não aceita convite',format('select public.aceitar_convite(%L)',v_tok2),'Confirme seu e-mail'); perform t.fim();
 -- aceite
 perform t.eu(n102);
 perform t.erro(S,'aceitar com e-mail diferente do convite é recusado',format('select public.aceitar_convite(%L)',v_tok),'inválido ou expirado');
 perform t.erro(S,'token inexistente é recusado',$q$select public.aceitar_convite('00000000')$q$,'inválido ou expirado');
 perform t.erro(S,'token nulo é recusado','select public.aceitar_convite(null)','inválido ou expirado');
 perform t.fim(); perform t.eu(estr);
 perform t.erro(S,'usuário qualquer logado não aceita convite alheio',format('select public.aceitar_convite(%L)',v_tok),'inválido ou expirado');
 perform t.fim(); perform t.eu(n101);
 v_r := public.aceitar_convite(v_tok);
 perform t.ok(S,'aceite com e-mail correto devolve papel morador', v_r->>'papel'='morador');
 select count(*) into v_n from public.perfis where user_id=n101 and papel='morador' and condominio_id='aaaaaaaa-0000-0000-0000-000000000001';
 perform t.ok(S,'perfil criado como morador no condomínio certo', v_n=1);
 select count(*) into v_n from public.vinculos_unidades where user_id=n101 and unidade_id=u101 and ativo;
 perform t.ok(S,'vínculo com a unidade 101 criado', v_n=1);
 perform t.erro(S,'token já usado não pode ser reutilizado',format('select public.aceitar_convite(%L)',v_tok),'inválido ou expirado');
 perform t.fim();
 -- expirado / substituído / cancelado
 perform t.eu(sind); v_tok := public.criar_convite('novo102@a.com','morador',u102,1); perform t.fim();
 update public.convites set expira_em = now() - interval '1 minute' where lower(email)='novo102@a.com';
 perform t.eu(n102); perform t.erro(S,'convite expirado é recusado',format('select public.aceitar_convite(%L)',v_tok),'inválido ou expirado'); perform t.fim();
 perform t.eu(sind); v_tok := public.criar_convite('novo102@a.com','morador',u102,7); v_tok2 := public.criar_convite('novo102@a.com','morador',u102,7); perform t.fim();
 perform t.eu(n102); perform t.erro(S,'novo convite invalida o anterior do mesmo e-mail',format('select public.aceitar_convite(%L)',v_tok),'inválido ou expirado'); perform t.fim();
 perform t.eu(sind); select id into v_id from public.convites where lower(email)='novo102@a.com' and aceito_em is null and expira_em>now(); perform public.cancelar_convite(v_id); perform t.fim();
 perform t.eu(n102); perform t.erro(S,'convite cancelado pelo síndico é recusado',format('select public.aceitar_convite(%L)',v_tok2),'inválido ou expirado'); perform t.fim();
 perform t.eu(sind); perform t.erro(S,'cancelar convite já inexistente/usado dá erro',format('select public.cancelar_convite(%L)',gen_random_uuid()),'não encontrado'); perform t.fim();
 -- outro condomínio
 perform t.eu(sind); v_tok := public.criar_convite('sindico@b.com','conselho',null,7); perform t.fim();
 perform t.eu(sindB); perform t.erro(S,'usuário que já é de outro condomínio não aceita',format('select public.aceitar_convite(%L)',v_tok),'outro condomínio'); perform t.fim();
 -- conselho
 perform t.eu(sind); v_tok := public.criar_convite('novo102@a.com','conselho',null,7); perform t.fim();
 perform t.eu(n102); v_r := public.aceitar_convite(v_tok); perform t.ok(S,'convite de conselho (sem unidade) cria perfil conselho', v_r->>'papel'='conselho'); perform t.fim();
 select count(*) into v_n from public.auditoria where acao in ('criar_convite','aceitar_convite'); perform t.ok(S,'criação e aceite ficam na auditoria', v_n>=4, v_n::text);
end $$;
-- ========================= PERFIL (escalada de privilégio) =========================
do $$
declare S constant text := 'perfil'; v_n int; m101 uuid := '22222222-0000-0000-0000-000000000101'; sind uuid := '11111111-0000-0000-0000-000000000001';
begin
 perform t.eu(m101);
 perform t.erro(S,'morador NÃO vira síndico',format('update public.perfis set papel=%L where user_id=%L','sindico',m101),'Somente o síndico');
 perform t.erro(S,'morador NÃO troca de condomínio',format('update public.perfis set condominio_id=%L where user_id=%L','bbbbbbbb-0000-0000-0000-000000000001',m101));
 perform t.erro(S,'morador NÃO altera o e-mail do perfil',format('update public.perfis set email=%L where user_id=%L','x@x.com',m101),'Somente o síndico');
 perform t.erro(S,'morador NÃO se reativa/desativa por conta própria',format('update public.perfis set ativo=false where user_id=%L',m101),'Somente o síndico');
 begin update public.perfis set nome='Nome Novo' where user_id=m101; get diagnostics v_n = row_count; exception when others then v_n := -1; end;
 perform t.ok(S,'morador altera o próprio nome', v_n=1);
 perform t.erro(S,'morador NÃO cria perfil de síndico por insert',format('insert into public.perfis(user_id,condominio_id,nome,email,papel) values (gen_random_uuid(),%L,%L,%L,%L)','aaaaaaaa-0000-0000-0000-000000000001','x','x@x.com','sindico'));
 select count(*) into v_n from public.perfis; perform t.ok(S,'morador enxerga só o próprio perfil', v_n=1, v_n::text);
 update public.perfis set nome='Hack' where user_id=sind; get diagnostics v_n = row_count; perform t.ok(S,'morador NÃO altera perfil de outra pessoa', v_n=0);
 perform t.fim(); perform t.eu(sind);
 update public.perfis set ativo=false where user_id=m101; get diagnostics v_n = row_count; perform t.ok(S,'síndico consegue desativar um morador', v_n=1);
 select count(*) into v_n from public.perfis; perform t.ok(S,'síndico enxerga os perfis do seu condomínio (não os de outro)', v_n>=4 and v_n<=6, v_n::text);
 perform t.fim();
 update public.perfis set ativo=true where user_id=m101;
end $$;
-- ========================= VAGA DE VISITANTE =========================
do $$
declare S constant text := 'vaga visitante'; v_n int; v_id uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
 sind uuid := '11111111-0000-0000-0000-000000000001'; m101 uuid := '22222222-0000-0000-0000-000000000101';
 m102 uuid := '22222222-0000-0000-0000-000000000102'; sindB uuid := '44444444-0000-0000-0000-000000000001'; estr uuid := '55555555-0000-0000-0000-000000000001';
 A constant text := 'aaaaaaaa-0000-0000-0000-000000000001'; u101 constant text := 'a1000000-0000-0000-0000-000000000101'; u102 constant text := 'a1000000-0000-0000-0000-000000000102';
begin
 perform t.eu(m101);
 insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim,observacao)
  values (A::uuid,u101::uuid,m101,v_hoje,'14:00','18:00','Visita familiar') returning id into v_id;
 perform t.ok(S,'morador publica aviso para a própria unidade', v_id is not null);
 perform t.erro(S,'morador NÃO publica aviso em nome de outra unidade',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u102,m101,v_hoje));
 perform t.erro(S,'criado_por forjado (outra pessoa) é recusado',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u101,m102,v_hoje));
 perform t.erro(S,'data no passado é recusada',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u101,m101,v_hoje-1),'data deve ser');
 perform t.erro(S,'data além de 90 dias é recusada',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u101,m101,v_hoje+91),'data deve ser');
 perform t.erro(S,'hora final igual/anterior à inicial é recusada',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'12:00','12:00')$q$,A,u101,m101,v_hoje));
 perform t.erro(S,'observação com mais de 200 caracteres é recusada',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim,observacao) values (%L,%L,%L,%L,'10:00','11:00',repeat('x',201))$q$,A,u101,m101,v_hoje));
 -- aviso não é reserva: dois avisos no mesmo horário são aceitos
 perform t.fim(); perform t.eu(m102);
 insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (A::uuid,u102::uuid,m102,v_hoje,'15:00','17:00');
 perform t.ok(S,'avisos no mesmo horário coexistem (é aviso, não reserva)', (select count(*) from public.avisos_vaga_visitante where data_uso=v_hoje and status='ativo')=2);
 select count(*) into v_n from public.avisos_vaga_visitante; perform t.ok(S,'todos os moradores veem o mural de avisos', v_n=2, v_n::text);
 update public.avisos_vaga_visitante set status='cancelado' where id=v_id; get diagnostics v_n=row_count;
 perform t.ok(S,'morador NÃO cancela aviso de outra unidade', v_n=0);
 perform t.erro(S,'morador NÃO apaga aviso (sem DELETE)',format('delete from public.avisos_vaga_visitante where id=%L',v_id),'permission denied');
 perform t.fim(); perform t.eu(m101);
 update public.avisos_vaga_visitante set status='cancelado' where id=v_id; get diagnostics v_n=row_count;
 perform t.ok(S,'morador cancela o próprio aviso', v_n=1);
 perform t.ok(S,'cancelado_em é preenchido automaticamente', (select cancelado_em is not null from public.avisos_vaga_visitante where id=v_id));
 perform t.erro(S,'morador NÃO move o próprio aviso para outro condomínio',format('update public.avisos_vaga_visitante set condominio_id=%L where id=%L','bbbbbbbb-0000-0000-0000-000000000001',v_id));
 perform t.erro(S,'morador NÃO move o próprio aviso para a unidade 102',format('update public.avisos_vaga_visitante set unidade_id=%L where id=%L',u102,v_id));
 perform t.fim(); perform t.eu(sind);
 update public.avisos_vaga_visitante set status='cancelado' where unidade_id=u102::uuid; get diagnostics v_n=row_count;
 perform t.ok(S,'síndico cancela aviso de qualquer unidade', v_n=1);
 perform t.fim(); perform t.eu(sindB);
 select count(*) into v_n from public.avisos_vaga_visitante; perform t.ok(S,'outro condomínio NÃO vê os avisos', v_n=0);
 perform t.erro(S,'outro condomínio NÃO publica na unidade de A',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u101,sindB,v_hoje));
 perform t.fim(); perform t.eu(estr);
 select count(*) into v_n from public.avisos_vaga_visitante; perform t.ok(S,'usuário logado SEM perfil não vê nada', v_n=0);
 perform t.erro(S,'usuário SEM perfil não publica aviso',format($q$insert into public.avisos_vaga_visitante(condominio_id,unidade_id,criado_por,data_uso,hora_inicio,hora_fim) values (%L,%L,%L,%L,'10:00','11:00')$q$,A,u101,estr,v_hoje));
 perform t.fim(); perform t.anon();
 perform t.erro(S,'anônimo NÃO lê avisos','select * from public.avisos_vaga_visitante','permission denied');
 perform t.fim();
end $$;
-- ========================= RESULTADO =========================
select secao, count(*) filter (where ok) as passou, count(*) filter (where not ok) as falhou from t.res group by secao order by 1;
select n, secao, nome, info from t.res where not ok order by n;
