> **V1.11.0** — login por convite, Convites, Vaga de visitante, Financeiro (livro-caixa) com saldo de abertura e importação de jul–set/2026. Leia `docs/IMPLANTACAO_LOGIN_CONVITES.md` e `docs/TESTE_MANUAL_PROJETO_TESTE.md` antes de publicar.

# Aplicativo de gestão condominial — V1.8.1 (PWA + financeiro + cobrança mensal + boletos de teste)

Esta entrega prepara o protótipo para instalação na tela inicial de celulares Android e iPhone como **Progressive Web App (PWA)**.

## Arquivos principais
- `index.html`: interface responsiva do protótipo.
- `manifest.webmanifest`: metadados de instalação e ícones.
- `sw.js`: cache básico da interface para acesso posterior.
- `icons/`: ícones 192×192 e 512×512.
- `GUIA_INSTALACAO_CELULAR.md`: publicação HTTPS e instruções para Android/iPhone.
- `livro-caixa-original.html`: referência original preservada.
- `schema.sql` e `supabase/`: base de dados e esqueleto de integração.

## Como instalar no celular
O conteúdo precisa ser publicado em hospedagem HTTPS. Depois, abra o endereço no Chrome (Android) ou Safari (iPhone) e use “Instalar app”/“Adicionar à tela inicial”. Veja o guia completo.

## Estado funcional
Este é um protótipo, não um sistema de produção. A interface não tem login real nem persistência no banco; o seletor de perfil é apenas demonstrativo. A emissão de boletos CAIXA reais, sincronização, notificações push e anexos persistentes não estão ativos. Não inserir dados reais de moradores, pagamentos ou documentos até conectar e testar o backend.

## Base técnica
- `supabase/migrations/20261019_001_cobranca_caixa.sql`: estrutura para cobranças.
- `supabase/migrations/20261019_002_manutencoes_preventivas.sql`: estrutura para manutenções.
- `supabase/functions/caixa-cobranca/index.ts`: base protegida para futura integração bancária.
- `docs/GUIA_INTEGRACAO_CAIXA.md`: roteiro para obter manual e homologar a integração.

## Novidades da V1.6
- **Frações ideais atualizadas** (fonte: planilha Previsão Orçamentária, abas Set/Out-2026): `docs/CONFIGURAR_UNIDADES.sql` e a seção 3.4 da `ESPECIFICACAO_TECNICA_v1.4.md`. Soma = 1,0000000.
- **Financeiro alimentado pelas planilhas**: `tools/importar_planilhas.py` lê *Previsão Orçamentária* e *Conciliação Bancária* e gera `data/financeiro.json`, exibido nas abas "Previsão orçamentária" e "Conciliação bancária" (perfis síndico e conselho).
  `python tools/importar_planilhas.py Previsao.xlsx Conciliacao.xlsx` (requer `openpyxl`; abra e salve as planilhas no Excel antes, para as fórmulas terem valores em cache).
- `supabase/migrations/20261020_003_financeiro_planilhas.sql`: tabelas de previsão, rateio de água (com a fração aplicada em cada rateio), conciliação, movimentos bancários e aplicação, com RLS.
- `sw.js` não guarda `data/` em cache.

**Privacidade:** `data/financeiro.json` contém valores reais (nomes de pessoas físicas são omitidos por padrão). Não publique em hospedagem aberta enquanto o protótipo não tiver login real.

## Novidades da V1.7 — Cobrança mensal
- Tela **Cobrança mensal**: gera a cobrança por unidade (cota, fundo de obras, água pela fração ideal, gás, parcelas, compensações), confere e libera para a emissão dos boletos; CSV e demonstrativo imprimível. **Não emite boleto bancário** (a emissão é da CAIXA).
- `cobranca.js`: cálculo e conferência (mesmas regras do banco). Teste: `node tools/testar_cobranca.js`.
- `supabase/migrations/20261021_004_cobranca_mensal.sql`: ciclos, itens previstos e funções `gerar/validar/liberar/reabrir_cobranca_mensal`.
- Detalhes, regras e pendências: `ESPECIFICACAO_TECNICA_V1.7_COBRANCA_MENSAL.md`.

## Novidades da V1.8 — Aba "Boletos (teste)"
- Gera, a partir das cobranças liberadas, um boleto por unidade com linha digitável e código de barras, marcado como **TESTE — não pagável** e sem registro no banco. Imprime e exporta CSV.
- `boleto.js` e `tools/testar_boleto.js` (`node tools/testar_boleto.js`). Detalhes e passos para sair do teste: `ESPECIFICACAO_TECNICA_V1.8_BOLETOS_TESTE.md`.

## V1.8.1 — Abrir no computador
- Ao abrir `index.html` direto do disco (duplo clique), o navegador bloqueia `fetch()` de arquivos locais e as planilhas não carregavam. Agora os dados também ficam em `data/financeiro.js`, lido por `<script>`, que funciona nesse modo. `tools/importar_planilhas.py` gera os dois arquivos; ao atualizar o `.json` manualmente, gere o `.js` de novo.
- Instalação como app e uso offline (service worker) exigem servidor (`http://localhost` ou HTTPS); o uso normal no computador não.
