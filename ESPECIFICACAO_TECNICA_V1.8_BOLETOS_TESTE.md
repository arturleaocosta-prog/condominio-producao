# Especificação — Aba "Boletos (teste)" (V1.8)

## 1. Objetivo e limite
Confeccionar, **somente para teste**, um boleto por unidade a partir das cobranças já liberadas em "Cobrança mensal". Cada boleto sai com faixa e marca d'água "TESTE — SEM VALOR — NÃO PAGAR". **Nenhum boleto é registrado na CAIXA nem pode ser pago.**

## 2. Fluxo
Cobrança mensal liberada → aba Boletos (teste) → conferir dados fictícios do beneficiário e o pagador de cada unidade → **Gerar boletos de teste** → conferir → visualizar, imprimir ou baixar CSV.
Reabrir a cobrança descarta os boletos da competência; alterar beneficiário ou pagador marca os boletos como desatualizados e exige gerar de novo.

## 3. O que o boleto de teste contém
Ficha com banco 104-0, linha digitável (47 dígitos), código de barras ITF-25 (44 dígitos), vencimento, valor, nosso número de teste, beneficiário, pagador e a composição da cobrança da unidade.
- Dígitos verificadores, fator de vencimento (ciclo de 1000 a 9999, reiniciado em 22/02/2025) e linha digitável seguem as regras FEBRABAN; os algoritmos foram conferidos contra um exemplo público.
- **Campo livre (25 dígitos) de teste:** código do beneficiário + nosso número de teste. O layout oficial da CAIXA (SIGCB/convênio) **não** foi aplicado, pois depende do manual e do convênio.
- Nosso número de teste: `99` + AAAAMM + sequência da unidade, completado com zeros (17 dígitos).

## 4. Conferência automática (painel)
Quantidade de boletos = unidades · soma dos boletos = total da cobrança · DV geral, fator de vencimento, valor e correspondência entre linha digitável e código de barras · aviso fixo sobre o campo livre de teste.

## 5. Permissões
Síndico: gera, imprime, baixa CSV e edita beneficiário/pagador. Conselho: consulta. Morador: sem acesso à aba.

## 6. Arquivos
`boleto.js` (cálculo e ficha, sem DOM), tela em `index.html`, testes em `tools/testar_boleto.js` (`node tools/testar_boleto.js`).

## 7. Verificação
- `testar_boleto.js`: algoritmos contra exemplo público, fator nos limites do ciclo, 8 boletos de Nov-2026 conferem e somam o total (R$ 7.714,02), adulteração de valor/linha é detectada, quantidade de barras do ITF.
- Fluxo da tela simulado para síndico, conselho e morador (geração, edição de pagador, impressão, CSV, reabertura).
- Não testado: leitura do código de barras por leitor ou aplicativo de banco, impressão em papel e celular real.

## 8. Para sair do teste
1. Convênio de cobrança com a CAIXA e manual (CNAB/API) do produto contratado.
2. Dados reais do beneficiário (CNPJ, agência, código do beneficiário) e do pagador (nome e CPF/CNPJ).
3. Campo livre e nosso número no layout oficial; registro do boleto; ambiente de homologação da Edge Function `caixa-cobranca`.
