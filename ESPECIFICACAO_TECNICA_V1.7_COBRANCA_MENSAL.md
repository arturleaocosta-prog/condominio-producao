# Especificação — Cobrança mensal (V1.7)

## 1. Objetivo e limite
Gerar, conferir e liberar a cobrança mensal de cada unidade, entregando os dados para a **confecção dos boletos**.
**O sistema não emite boleto bancário.** A emissão continua na CAIXA (Internet Banking/Cobrança) até a integração da Edge Function `caixa-cobranca` ser homologada (ver `docs/GUIA_INTEGRACAO_CAIXA.md`). O demonstrativo impresso diz isso expressamente.

## 2. Fluxo
1. Previsão do mês e rateio da água cadastrados (planilhas importadas ou tabelas `previsoes_mensais`/`itens_cobranca_previstos`).
2. Síndico escolhe a competência, informa o **vencimento do boleto** (as planilhas não trazem essa data) e clica **Gerar cobranças** → rascunho.
3. Confere o painel de **Conferência**; erros impedem a liberação, avisos exigem confirmação.
4. **Liberar para emissão** → cobranças ficam `pronta_para_emissao`; ficam disponíveis o CSV e os demonstrativos.
5. Emissão dos boletos (manual na CAIXA ou, no futuro, pela integração). **Reabrir** só enquanto nenhum boleto tiver sido enviado/registrado.

## 3. Regras de cálculo (valores em centavos inteiros)
| Item | Regra |
|---|---|
| Cota condominial | `taxa_por_unidade` da previsão, igual para todas as unidades |
| Fundo de obras | `fundo_obras_por_unidade` da previsão |
| Água | fatura × fração ideal **cadastrada**; piso em centavos e +1 centavo para os maiores restos (empate pela identificação); soma = fatura exata; a fração aplicada fica gravada em `rateios_agua_itens` |
| Gás, parcelas, compensações | itens informados por unidade para a competência (compensação pode ser negativa) |
| Total | soma dos itens; deve ser > 0 |

Multa, juros e correção por atraso **não** são calculados nesta versão.

## 4. Conferência
Frações somam 1,0000000 · água fecha na fatura · totais positivos · vencimento informado (aviso se anterior à competência) · quantidade de cobranças = unidades ativas · total = soma dos itens · comparação com a planilha (tolerância 2 centavos) · aviso quando o mês é idêntico ao anterior.

## 5. Banco (migração `20261021_004_cobranca_mensal.sql`)
- `ciclos_cobranca` (um por condomínio/competência: `gerado` → `liberado`); `cobrancas.ciclo_id`.
- `itens_cobranca_previstos`: itens informados pelo síndico (gás com leituras em `detalhes`, parcelas, compensações).
- `itens_cobranca.tipo` ampliado: `fundo_obras`, `gas`, `parcelada`, `compensacao`; `rateios_agua.competencia_consumo`.
- Funções (`security definer`, só `authenticated`): `gerar_cobranca_mensal`, `validar_cobranca_mensal`, `liberar_cobranca_mensal`, `reabrir_cobranca_mensal`. Geração com trava por condomínio/competência e registro em `auditoria`.
- Visão `v_cobrancas_para_emissao` (`security_invoker`): cobranças liberadas com itens em JSON.
- RLS: síndico escreve; conselho consulta; morador não acessa ciclos nem itens previstos (vê só as próprias cobranças pela política já existente).
- Rateio de água já fechado é reutilizado, nunca reescrito; rascunhos podem ser substituídos, cobranças liberadas não.

## 6. Interface (`index.html` + `cobranca.js`)
Tela **Cobrança mensal** (síndico: gera/libera/reabre/CSV/imprime; conselho: consulta e demonstrativo; morador: **Minhas cobranças** com as liberadas da unidade). `cobranca.js` espelha as regras do SQL. Na demonstração os ciclos ficam só na sessão do navegador.

## 7. Verificação realizada
- Migração aplicada sobre `schema.sql` e migrações 001–003 em PostgreSQL 16; geração de Nov-2026: total R$ 7.714,02, água exatamente R$ 1.458,90.
- Testado: geração duplicada, competência inválida, previsão ausente, liberar duas vezes, substituir cobrança liberada, reabrir (com e sem boleto registrado), fração fora de 1,0000000, acesso de morador.
- `tools/testar_cobranca.js`: os totais do JavaScript são idênticos aos do PostgreSQL; água fecha na fatura em todos os 12 meses.
- Não testado: Supabase real (políticas de `auth.uid()` simuladas), celular, impressão em papel.

## 8. Pontos que dependem do síndico
1. **Vencimento do boleto**: informar a cada mês (não consta nas planilhas).
2. **Frações da água**: as abas de Nov-2026 em diante usam a fração anterior; o sistema usa a cadastrada e avisa (diferença de até R$ 14,10 por unidade em Nov-2026). Atualize as planilhas ou confirme qual fração vale.
3. **Out-2026** está idêntico a Set-2026 (inclusive gás); confirme se a planilha do mês foi atualizada.
4. **Dados do pagador** (nome e CPF dos proprietários) não estão no sistema; serão necessários para a emissão do boleto.
5. **Próximos passos**: integração CAIXA (remessa/API), baixa por extrato OFX e cálculo de multa/juros.
