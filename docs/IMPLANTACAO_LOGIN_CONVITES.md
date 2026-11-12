# Implantação — login por convite e aviso da vaga de visitante (migração 005)

Estado (V1.15.0):
- **Banco de dados** pronto e testado: 192 testes em PostgreSQL 16 com RLS (login/convites/vaga 63, livro-caixa 72, saldo de abertura 27, importação jul–set 17, importação de outubro 13).
- **Telas** ligadas ao Supabase: login, criar conta com convite, código do convite, recuperar senha, Convites (síndico), Vaga de visitante e **Financeiro (livro-caixa)**: síndico registra e estorna, conselho consulta o detalhe, morador vê só os totais do mês. 130 testes automatizados de fluxo (com Supabase simulado).
- **Ainda em demonstração** (dados fictícios, não salvos): Cobrança mensal, Boletos, Avisos, Documentos, Ocorrências, Manutenções, Enquetes.
- **Pendente:** teste manual no projeto Supabase de teste real (docs/TESTE_MANUAL_PROJETO_TESTE.md).

## 1. Como o acesso funciona
1. O síndico cria o convite (`criar_convite`): e-mail, papel (morador ou conselho) e unidade. Recebe um token **uma única vez**.
2. O morador cria a conta no Supabase Auth com **o mesmo e-mail** do convite e confirma o e-mail.
3. Logado, o app chama `aceitar_convite(token)`. O banco cria o perfil e o vínculo com a unidade.
4. Quem cria conta sem convite fica sem perfil e **não enxerga nada** (testado).
5. Síndico novo só é criado pelo passo 4 abaixo (nunca por convite).

## 2. Passo a passo no Supabase (projeto de PRODUÇÃO, separado do de teste)
1. Criar o projeto. Em **Authentication → Providers → Email**: manter **Confirm email LIGADO** (obrigatório: a função só aceita e-mail confirmado).
2. SQL Editor: rodar `schema.sql` e depois, em ordem, `supabase/migrations/*.sql` (001 a **007**).
3. Criar o condomínio e as unidades:
   `insert into public.condominios(nome) values ('Edifício Valença') returning id;`
   Em `docs/CONFIGURAR_UNIDADES.sql`, trocar o UUID e rodar. Conferir que a soma das frações retorna 1,0000000.
4. Criar o síndico: **Authentication → Users → Add user** (e-mail confirmado), copiar o UUID e rodar:
   `insert into public.perfis(user_id, condominio_id, nome, email, papel) values ('UUID-DO-USUARIO','UUID-DO-CONDOMINIO','Nome do síndico','email@dominio','sindico');`
5. Rodar os testes (item 3) em um banco **descartável**, nunca no de produção.

## 3. Testes
- Banco: `PGHOST=... PGPORT=... PGUSER=... bash tools/sql/rodar_testes_local.sh` (cria banco descartável, aplica tudo e roda 63 verificações).
- Cálculo: `node tools/testar_cobranca.js` e `node tools/testar_boleto.js`.
- Cobertura do banco: criação/aceite/expiração/cancelamento de convite, e-mail errado ou não confirmado, token reutilizado, isolamento entre condomínios, escalada de privilégio no perfil, avisos da vaga (unidade própria, datas, horários, cancelamento, sem DELETE).

## 4. Vaga de visitante = aviso
Decisão do síndico: é **aviso de uso**, não reserva. Dois avisos no mesmo horário são aceitos de propósito. O texto da tela deve continuar dizendo que a vaga não é garantida.

## 5. Publicação (somente após o teste manual passar)
1. `bash tools/preparar_publicacao.sh` monta a pasta `publicar/` **sem** `data/` (dados financeiros reais) e confere que não há chave secreta.
2. Suba o **conteúdo** de `publicar/` em um endereço HTTPS (por exemplo, GitHub Pages).
3. No Supabase (Authentication → URL Configuration): informe esse endereço como **Site URL** e também em **Redirect URLs**. Sem isso, o link de confirmação de e-mail e o de recuperar senha não voltam para o app.
4. `config.js` leva só a URL e a chave **pública**. Nunca a `service_role` nem a senha do banco.

## 6. O que falta antes de liberar para os moradores
- Teste manual completo no projeto de teste (item 5 acima).
- Projeto Supabase de **produção** (plano Pro, para não pausar por inatividade) com o mesmo passo a passo do item 2.
- `data/financeiro.js` tem dados reais e **não pode** ir para repositório público nem para a hospedagem. Hoje só `data/financeiro.json` está no `.gitignore`: acrescente também `data/financeiro.js`.
- Módulos financeiros ainda são demonstração; boletos continuam de teste (convênio e homologação da CAIXA pendentes).

## 7. Livro-caixa (migração 006)
- **Se você já rodou 001–005 no Supabase de teste, rode agora só a `20261026_006_livro_caixa.sql`** (uma vez, em nova query).
- Conferência final (32 tabelas, 7 funções, 65 policies):
```sql
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE') as tabelas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and proname in ('criar_convite','aceitar_convite','cancelar_convite',
      'registrar_lancamento','estornar_lancamento','resumo_financeiro','relatorio_mensal')) as funcoes,
  (select count(*) from pg_policies where schemaname = 'public') as policies;
```
- A migração 006 também **retira privilégios excedentes** de todas as tabelas (acesso anônimo e permissões que o app não usa). O acesso passa a depender só do login e das regras (RLS).
- Lançamentos nunca são editados nem apagados. Correção = estorno (cria um lançamento de estorno na data de hoje e marca o original). O mês do original não muda.
- Convenção dos totais: entradas = receitas + estornos de despesas; saídas = despesas + estornos de receitas.
- **Ainda não existe saldo inicial.** O "saldo acumulado" soma tudo o que foi lançado no app. Para refletir o saldo real da conta da CAIXA, é preciso lançar o saldo de abertura ou criar o campo (decisão sua).
- **Ainda não existe anexo de nota/comprovante** (precisa configurar o Storage do Supabase).

## 8. Saldo de abertura e importação de jul–set/2026 (migração 007)
Ordem no Supabase (projeto de teste e, depois, produção):
1. Rode `supabase/migrations/20261028_007_saldo_abertura.sql` (uma vez). Ela cria o saldo de abertura, a função `definir_saldo_abertura` e passa o "saldo acumulado" a somar a abertura.
2. Rode `docs/IMPORTAR_JUL_SET_2026.sql` (uma vez, como administrador, no SQL Editor). Ele grava **92 lançamentos** da conciliação de jul–set/2026 (conta corrente) e o **saldo de abertura de R$ 9.370,02 em 01/07/2026**.
   - Tudo acontece em uma transação: ele confere mês a mês contra a planilha e o saldo final de 30/09/2026 (R$ 3.247,57). Se algo não bater, nada é gravado.
   - Rodar uma segunda vez é recusado ("Esta importação já foi executada").
   - O arquivo contém dados reais: **não publique nem coloque em repositório**.
3. Conferência: no app (síndico), Financeiro, mês 09/2026: saldo acumulado = **R$ 3.247,57**. Em 10/2026: saldo anterior = R$ 3.247,57.
- Conferência de objetos no Supabase (após a 007): **32 tabelas, 8 funções, 65 policies** (use a mesma query da seção 7, acrescentando `'definir_saldo_abertura'` na lista de funções).
- Como ficou a classificação: cotas por apartamento ("Cota condominial — Apto 301") sem o nome do morador; DARF da conservadora em "Taxas e impostos"; 2M Construtora e obras internas em "Obras"; gás em "Gás"; tarifas bancárias em "Outras despesas".
- **Transferências para a aplicação** (R$ 1.040,00) entram como despesa "Fundo de reserva". O resultado do mês fica menor do que o real. Se quiser, criamos o tipo "transferência entre contas".
- A conta de **aplicação** (saldo R$ 15.317,45 em 30/09) não faz parte deste livro-caixa.
- A previsão orçamentária ainda traz o conjunto antigo de frações nas abas jul, ago e nov–jun. O banco já usa o novo; corrija a planilha.

## 9. Importação de outubro (extrato OFX de 01 a 21/10/2026)
- Ordem: migrações 001–007 → `IMPORTAR_JUL_SET_2026.sql` → **`IMPORTAR_OUT_2026_ATE_21.sql`** (cada um uma única vez).
- O script de outubro só grava se: a importação de jul–set já foi feita; não há lançamentos a partir de 01/10; o saldo atual do livro-caixa é R$ 3.247,57 (igual ao saldo inicial do extrato); e o saldo final fica em **R$ 4.122,32** (igual ao extrato em 21/10). Qualquer divergência cancela tudo.
- **No projeto de teste ele será recusado** se você lançou algo em outubro durante os testes (lançamentos não podem ser apagados). Rode no projeto de **produção**, que começa limpo.
- Classificação confirmada por você: 308,40 contabilidade (Honorários); 445,00 botijão de gás (Gás); 3.726,74 2M Construtora (Obras); 1.082,02 Ideal Assessoria (Limpeza); PIX de 1.310,38 reembolso da 4ª parcela da obra interna (Obras).
- Cotas entram **somadas por dia de liquidação** ("Cotas recebidas por boleto — liquidação de dd/mm"), porque o OFX não identifica o morador.
- Para importar novos períodos: `python3 tools/gerar_importacao_ofx.py extrato.ofx saida.sql` (use `--propor` para ver a classificação antes). Movimento sem classificação confirmada impede a geração.

## 10. Privacidade das telas (V1.12)
- **Início** não mostra mais saldo, receitas nem despesas (para nenhum perfil quando há login). Mostra ocorrências pendentes, avisos e atalhos.
- **Financeiro:** morador e conselho abrem com os valores **ocultos**, e nada financeiro é pedido ao banco até tocarem em "Mostrar valores". Voltam a ocultar ao sair da tela, ao minimizar o app e após 2 minutos sem uso. O síndico vê direto e pode ocultar.
- **Cobrança mensal e Boletos (teste)** aparecem só para o síndico; os demais perfis nem veem o item no menu, e a rota direta volta ao Início.
- Publicação: veja `docs/PUBLICAR_NETLIFY.md` (publicação manual, sem o logo do Netlify, e conferência de que `data/financeiro.js` não está no ar).

## 11. Edição de lançamentos e anexos (migração 008, app 1.13)
**Ordem obrigatória: primeiro a migração 008 no Supabase, depois publicar o app 1.13.** O app novo lê colunas criadas pela 008; sem ela, o Financeiro mostra erro.
1. No SQL Editor, rode `supabase/migrations/20261105_008_edicao_e_anexos.sql` (uma vez). Ela cria o bucket privado `comprovantes` (limite de 10 MB; PDF, JPG, PNG e WEBP), o histórico de edições e as funções `editar_lancamento`, `registrar_comprovante` e `remover_comprovante`.
2. Conferência (esperado: **33 tabelas, 11 funções, 65 policies**; funções contadas: `criar_convite`, `aceitar_convite`, `cancelar_convite`, `registrar_lancamento`, `estornar_lancamento`, `resumo_financeiro`, `relatorio_mensal`, `definir_saldo_abertura`, `editar_lancamento`, `registrar_comprovante`, `remover_comprovante`). E o bucket:
```sql
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'comprovantes';
```
   Esperado: `public = false` e `file_size_limit = 10485760`.
3. Se a 008 falhar na parte do Storage (permissão para criar o bucket ou as policies): crie o bucket `comprovantes` em **Storage → New bucket** (privado, limite 10 MB) e me envie a mensagem de erro.
4. Publique o pacote `condominio_publicar_v1_13_0.zip` e confira o rodapé: **Versão 1.13.0**.

**Como funciona**
- **Novo lançamento** tem os campos Fornecedor e Nota fiscal ou documento (até 8 arquivos, 10 MB cada). Os arquivos são validados antes de gravar o lançamento; se o envio falhar, o lançamento fica salvo e o app avisa para anexar de novo pelo botão 📎 da linha.
- **Editar** (só o síndico): data, valor, categoria, descrição, fornecedor, documento e observação. O tipo não muda. **Todo ajuste exige motivo** e fica no histórico (antes e depois), que o síndico e o conselho consultam em "ver histórico". Estornos e lançamentos já estornados não são editáveis. Editar valor ou data de um mês passado altera o saldo desse mês; relatórios já impressos não mudam.
- **Anexos:** cada arquivo guarda o SHA-256 (impressão digital). Remover um anexo só o tira da lista (o arquivo e o motivo ficam como evidência). Síndico e conselho abrem os arquivos por link temporário de 1 minuto; moradores não têm acesso. O conselho consegue salvar o arquivo que abrir: não há como impedir isso no navegador.
- **Backup:** o backup em CSV traz os lançamentos já editados (valores atuais), com a versão e a data da última edição. **Não traz o histórico de edições nem os arquivos anexos.** Os arquivos precisam de cópia à parte (Storage → bucket → baixar), principalmente no plano gratuito, que não faz backup automático.

## 12. Importação de extrato OFX pelo app (migração 009, app 1.14)
**Ordem obrigatória: primeiro a migração 009 no Supabase, depois publicar o app 1.14.** (As migrações 008 e 009 devem estar aplicadas.)
1. No SQL Editor, rode `supabase/migrations/20261107_009_importacao_extrato.sql` (uma vez). Ela cria `extratos_importados`, `extrato_linhas` e `regras_extrato` e as funções `saldo_livro_em` e `importar_extrato`.
2. Conferência (esperado: **36 tabelas, 13 funções e 68 policies**: as 11 funções da lista anterior mais `saldo_livro_em` e `importar_extrato`, e uma policy de leitura em cada uma das 3 novas tabelas):
```sql
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE') as tabelas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and proname in ('criar_convite','aceitar_convite','cancelar_convite','registrar_lancamento','estornar_lancamento',
      'resumo_financeiro','relatorio_mensal','definir_saldo_abertura','editar_lancamento','registrar_comprovante','remover_comprovante',
      'saldo_livro_em','importar_extrato')) as funcoes,
  (select count(*) from pg_policies where schemaname = 'public') as policies;
```
3. Publique o pacote `condominio_publicar_v1_14_0.zip` (rodapé: **Versão 1.14.0**).

**Como usar (síndico):** Financeiro, **Importar extrato (OFX)**, escolha o arquivo.
- O app lê o arquivo no navegador (acentos do Windows-1252 incluídos) e **não grava nem envia o número da conta**.
- Cada movimento aparece para revisão com uma sugestão: cobrança de boletos, tarifas, água e luz já vêm classificadas; um movimento com o mesmo valor de um lançamento que você já fez vem como **conciliar**; o resto fica **pendente** até você escolher **Lançar** (categoria, descrição, fornecedor), **Conciliar** com um lançamento existente ou **Ignorar** (com motivo). O botão Importar só libera sem pendências.
- "Lembrar para os próximos extratos" salva uma regra (pelo texto do banco, ou pelo texto e valor) para sugerir sozinho no mês seguinte.
- Nada é gravado até o botão Importar. Aí o banco grava tudo **em uma única transação** e confere o saldo: se o saldo do livro-caixa na data do extrato não ficar igual ao saldo final do arquivo, **nada é importado** e o app oferece "importar mesmo com a diferença" (a diferença fica registrada).
- **Sem duplicar:** o mesmo arquivo é recusado pela impressão digital (SHA-256); movimentos de um período que se sobrepõe a outro já importado aparecem como "já importados" e não entram de novo (inclusive tarifas idênticas no mesmo dia).
- O conselho consulta os extratos importados e seus movimentos (botão **Extratos importados**), com o lançamento ligado a cada um. Moradores não têm acesso.
- Os movimentos de cotas dos moradores entram **somados por dia** ("Cotas recebidas por boleto — liquidação de dd/mm"): o OFX não informa quem pagou.
- Linhas do extrato e extratos importados **não podem ser alterados nem apagados** (evidência). Para corrigir um lançamento criado pela importação, use Editar ou Estornar.
- **Backup:** o backup em CSV continua cobrindo os lançamentos. As tabelas de extrato e regras não entram nele.

## 13. Cobrança por unidade (migração 010, app 1.15)
**Ordem: migração 010 no Supabase e depois o app 1.15** (guia em `docs/PUBLICACAO_PASSO_A_PASSO.md`). Conferência: **37 tabelas, 20 funções e 69 policies**.

**Fluxo do síndico (Cobrança mensal)**
1. **Previsão do mês:** taxa condominial por unidade e fundo de obras por unidade (valores iguais para todos, como na planilha de previsão).
2. **Itens por unidade:** gás, parcelas, compensações, descontos, multas e juros avulsos (desconto/crédito entra negativo).
3. **Gerar:** vencimento, fatura de água (COPASA) e mês de consumo. A água é dividida pela **fração ideal**; taxa e fundo, pelo valor por unidade. O resultado fica em **rascunho**, que os moradores **não veem**.
4. **Conferir:** o app mostra os avisos e erros da conferência do banco; com erro, não deixa liberar. "Gerar de novo" substitui o rascunho.
5. **Liberar:** a cobrança de cada unidade passa a existir para o morador e para o conselho.
6. **Pagamentos:** "Registrar pagamento" (data, valor, forma, observação) e, se quiser, o **crédito do extrato** de onde veio o dinheiro (um crédito pode pagar várias unidades, até o seu valor). Pagamento parcial mantém em aberto; quitado vira **Paga**. Erros se corrigem **removendo o pagamento com motivo** (o histórico fica).
7. **Quem está em aberto:** lista com saldo e dias de atraso (síndico e conselho).
8. **Reabrir** só enquanto não houver pagamento registrado.

**Regras importantes**
- O pagamento **não cria lançamento**: a receita já entra no livro-caixa pelo extrato (ou por lançamento manual). Assim não há receita em duplicidade.
- Moradores veem só a cobrança da própria unidade, **depois de liberada**. Conselho consulta tudo, sem alterar. Valores abrem ocultos para morador e conselho.
- O pagamento recusa valor acima de 150% da cobrança (confere o valor) e crédito de extrato acima do que ainda está livre.
- Boletos continuam de teste (convênio da CAIXA pendente): hoje a cobrança é o controle interno; o boleto/PIX é enviado como você já faz.
- **Backup:** o backup em CSV não inclui cobranças e pagamentos. Anote os totais de cada mês liberado ou imprima a tela.
