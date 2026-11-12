# Publicar uma versão nova do app — passo a passo (versão 1.14 e 1.15)

Regra de ouro: **primeiro o banco, depois o app**, e sempre **primeiro o projeto de teste, depois a produção**.
Uma versão nova do app lê colunas e tabelas que as migrações criam. Se o app subir antes do banco, a tela mostra erro (nada se perde).

## 0. Antes de mexer em qualquer coisa (2 minutos)
1. Faça o backup do livro-caixa: `docs/backup/BACKUP_1_LANCAMENTOS.sql` e `BACKUP_2_CONTROLE.sql` (SQL Editor, Run, baixar o CSV; não abrir no Excel).
2. Confira o **nome do projeto** no canto superior esquerdo do Supabase (teste ou produção).

## 1. Banco de dados
Abra o **SQL Editor**, uma query nova por arquivo, cole **todo** o conteúdo, **Run**. Esperado: *Success*. Não rode nada duas vezes.

| Versão do app | Migrações a ter rodado (em ordem) |
|---|---|
| 1.13 | …007, **008** `20261105_008_edicao_e_anexos.sql` |
| **1.14** | …008, **009** `20261107_009_importacao_extrato.sql` |
| 1.15 | …009, **010** `20261108_010_cobranca_pagamentos.sql` |

Como saber o que já foi rodado:
```sql
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'lancamentos_historico') as m008,
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'extratos_importados') as m009,
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'cobranca_pagamentos') as m010;
```
`1` significa que a migração já foi rodada; `0`, que falta. Rode só as que faltam, na ordem.

Conferência com a consulta abaixo: depois da 009 (versão 1.14) deve dar **36 tabelas, 17 funções, 68 policies**; depois da 010 (versão 1.15), **37 tabelas, 20 funções, 69 policies**.
```sql
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE') as tabelas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname in (
    'criar_convite','aceitar_convite','cancelar_convite','registrar_lancamento','estornar_lancamento','resumo_financeiro','relatorio_mensal','definir_saldo_abertura',
    'editar_lancamento','registrar_comprovante','remover_comprovante','saldo_livro_em','importar_extrato',
    'gerar_cobranca_mensal','validar_cobranca_mensal','liberar_cobranca_mensal','reabrir_cobranca_mensal','registrar_pagamento_cobranca','remover_pagamento_cobranca','cobrancas_em_aberto')) as funcoes,
  (select count(*) from pg_policies where schemaname = 'public') as policies;
```
Bucket de anexos (da 008): `select id, public, file_size_limit from storage.buckets where id = 'comprovantes';` → `public = false`, `10485760`.

## 2. Publicar o app

**GitHub Pages**
1. Descompacte `condominio_publicar_v1_14_0.zip` (ou `v1_15_0`) em uma pasta.
2. Abra o `config.js` e confira a URL e a chave `sb_publishable_…` do projeto certo (teste ou produção). Nunca use a chave secret, a `service_role` nem a senha do banco.
3. No repositório: **Add file → Upload files**, arraste **o conteúdo** da pasta (não a pasta), mensagem "versão 1.14.0", **Commit changes**.
4. Em **Actions**, espere o item *pages build and deployment* ficar verde (1 a 2 minutos).

**Netlify (publicação manual)**
1. Mesmo passo 1 e 2 acima.
2. Netlify → seu site → aba **Deploys** → arraste a pasta descompactada na área de upload. Nada de Git: assim não aparece o logo do Netlify.

## 3. Conferir (5 minutos)
1. Abra o site em **janela anônima**. Tem de aparecer a tela **Entrar**.
2. Entre como síndico. No rodapé do menu: **Versão 1.14.0** (ou 1.15.0).
3. **Financeiro:** botões *Importar extrato (OFX)* e *Extratos importados* (1.14).
4. **Cobrança mensal:** abre com a previsão do mês e os passos de geração (1.15).
5. Abra `…/data/financeiro.js` no endereço do site: tem de dar "página não encontrada".
6. Entre como morador de teste: Início sem valores; Financeiro e Cobrança só mostram números depois de "Mostrar valores".
Se aparecer versão antiga: feche o app por completo e abra duas vezes; se persistir, limpe os dados do site.

## 4. Se algo der errado
- **O app mostra erro ao abrir uma tela nova:** quase sempre falta rodar a migração correspondente (tabela da seção 1).
- **Voltar uma versão:** suba de novo o pacote da versão anterior. As migrações só acrescentam, então a versão anterior do app continua funcionando com o banco novo.
- **Nunca apague tabelas** para "recomeçar": fale comigo antes.

## 5. Produção
É a mesma sequência (0 → 1 → 2 → 3), no projeto de produção, com o `config.js` de produção e o Site URL / Redirect URLs do Supabase apontando para o endereço de produção.
