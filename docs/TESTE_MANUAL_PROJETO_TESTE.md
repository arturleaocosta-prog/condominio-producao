# Teste manual no projeto Supabase de teste (com o app no ar)

Use o projeto **condominio-teste**, nunca o de produção. Use e-mails que você consiga abrir (pode usar o truque `seunome+morador1@gmail.com`).

## Preparação
1. Authentication → Users → **Add user**: crie o síndico (marque o e-mail como confirmado). Copie o UUID.
2. SQL Editor: crie o condomínio e as unidades (`docs/CONFIGURAR_UNIDADES.sql`) e o perfil do síndico (item 4 de `docs/IMPLANTACAO_LOGIN_CONVITES.md`).
3. Publique o app em HTTPS (`tools/preparar_publicacao.sh`) e preencha Site URL e Redirect URLs.

## Roteiro (marque ✔ ou ✘ e anote o que apareceu)
| # | Ação | Resultado esperado |
|---|---|---|
| 1 | Abrir o app sem estar logado | Tela "Entrar"; nada do app aparece |
| 2 | Entrar com senha errada | "E-mail ou senha incorretos." |
| 3 | Entrar como síndico | App abre; item **Convites** aparece; o seletor "Visualizar perfil" some |
| 4 | Convites → gerar convite para `+morador1` na unidade 101 | Mensagem com código aparece; botão copiar e WhatsApp funcionam |
| 5 | Sair. Criar conta com `+morador1` | Pede para confirmar o e-mail |
| 6 | Abrir o link do e-mail | Volta ao app (se abrir página de erro, revise Site URL / Redirect URLs) |
| 7 | Entrar com `+morador1` | Tela "Código do convite" |
| 8 | Digitar código errado | "Convite inválido ou expirado" |
| 9 | Digitar o código certo | App abre como morador; **sem** item Convites |
| 10 | Reutilizar o mesmo código em outra conta | Recusado |
| 11 | Morador: Vaga visitante → Avisar uso (data de hoje, 14h–18h) | Aviso aparece na lista |
| 12 | Morador: tentar data no passado | Recusado |
| 13 | Segundo morador (unidade 102) abre a Vaga | Vê o aviso da 101; **não** vê "Cancelar" nele |
| 14 | Morador 101 cancela o próprio aviso | Aparece como Cancelado |
| 15 | Síndico: cancelar um convite pendente e tentar usar o código | Recusado |
| 16 | "Esqueci a senha" | Chega e-mail; link abre a tela Nova senha; login com a nova senha funciona |
| 17 | Síndico: desativar o morador (SQL: `update public.perfis set ativo=false where email='...'`) e recarregar o app dele | "Acesso desativado" |
| 18 | Fechar e reabrir o app no celular | Continua logado |
| 19 | Instalar na tela inicial (PWA) e repetir o 3 | Funciona igual |

Se qualquer linha der ✘, me envie o número, o que apareceu na tela e, se possível, uma captura.

## Roteiro do livro-caixa (Financeiro) — depois da migração 006
| # | Ação | Resultado esperado |
|---|---|---|
| 20 | Síndico: Financeiro, sem lançamentos | Cartões zerados, lista vazia, sem erro |
| 21 | Novo lançamento: despesa de 1.234,56, categoria Manutenção, nº do documento | Aparece na lista como `− R$ 1.234,56`; Saídas do mês = R$ 1.234,56 |
| 22 | Novo lançamento: receita de 650,00 | Entradas do mês = R$ 650,00; saldo do mês = −R$ 584,56 |
| 23 | Tentar valor `0` e valor `abc` | Mensagem de valor inválido, nada é gravado |
| 24 | Tocar duas vezes rápido em "Salvar" com o mesmo lançamento | Só um lançamento é gravado |
| 25 | Estornar a despesa com o motivo "teste" (menos de 5 letras) | Recusado; com "Valor lançado errado": aparece o estorno e o original fica "Estornado" |
| 26 | Conferir o saldo do mês depois do estorno | Entradas = 650,00 + 1.234,56; saídas = 1.234,56 (o saldo do mês não muda) |
| 27 | Trocar o mês no seletor para o anterior e voltar | Dados do mês certo; o mês anterior não foi alterado pelo estorno |
| 28 | Imprimir relatório | Abre a impressão com totais, categorias e lançamentos |
| 29 | Entrar como conselho | Vê o detalhe; **não** vê Novo lançamento, Estornar nem Imprimir |
| 30 | Entrar como morador | Vê só receitas, despesas e saldo do mês; nenhuma lista |
| 31 | No SQL Editor, tentar `update public.lancamentos set valor_centavos = 1` ou `delete from public.lancamentos` | Erro: "Lançamentos não podem ser alterados/apagados" |

## Roteiro do saldo de abertura e da importação (V1.11) — depois das migrações 006 e 007 e do script de importação
| # | Ação | Resultado esperado |
|---|---|---|
| 32 | Síndico: Financeiro, mês 07/2026 | 34 lançamentos; entradas R$ 9.809,06; saídas R$ 14.695,44 |
| 33 | Mês 08/2026 | 32 lançamentos; entradas R$ 10.620,75; saídas R$ 9.481,13 |
| 34 | Mês 09/2026 | 26 lançamentos; entradas R$ 7.154,06; saídas R$ 9.529,75; **saldo acumulado R$ 3.247,57** (igual ao extrato) |
| 35 | Cartão "Saldo acumulado" | Informa "Inclui saldo de abertura de R$ 9.370,02 em 01/07/2026" |
| 36 | Mês 10/2026 | Saldo anterior R$ 3.247,57; sem lançamentos |
| 37 | Cotas dos moradores | Aparecem como "Cota condominial — Apto 301" etc., sem nome de pessoa |
| 38 | Novo lançamento com data de junho/2026 | Recusado: "A data não pode ser anterior ao saldo de abertura (01/07/2026)" |
| 39 | Conselho: mesmos meses | Vê o detalhe; sem botões de escrita |
| 40 | Morador: mês 09/2026 | Só totais do mês; nenhuma lista |

## Roteiro da importação de outubro (somente no projeto de produção, após `IMPORTAR_OUT_2026_ATE_21.sql`)
| # | Ação | Resultado esperado |
|---|---|---|
| 41 | Síndico: Financeiro, mês 10/2026 | 19 lançamentos; entradas R$ 9.433,28; saídas R$ 8.558,53 |
| 42 | Cartão "Saldo acumulado" | **R$ 4.122,32** (igual ao extrato de 21/10) |
| 43 | Saldo anterior no relatório impresso | R$ 3.247,57 |
| 44 | Linha de gás (R$ 445,00) e contabilidade (R$ 308,40) | Nas categorias Gás e Honorários |
| 45 | Morador: mês 10/2026 | Só totais; nenhuma lista |

## Roteiro da privacidade (V1.12)
| # | Ação | Resultado esperado |
|---|---|---|
| 46 | Morador ou conselho: entrar no app | O Início não mostra saldo, receitas nem despesas |
| 47 | Tocar em Financeiro | Tela "valores ocultos" com o botão Mostrar valores; nenhum número |
| 48 | Tocar em Mostrar valores | Aparecem os totais (morador) ou o detalhe (conselho) |
| 49 | Ir para Início e voltar ao Financeiro | Volta oculto |
| 50 | Mostrar valores e trocar de aplicativo no celular, depois voltar | Voltou oculto |
| 51 | Mostrar valores e não tocar na tela por 2 minutos | Fica oculto sozinho |
| 52 | Morador ou conselho: olhar o menu | Sem "Cobrança mensal" e sem "Boletos (teste)" |
| 53 | Síndico: Financeiro | Abre com os valores visíveis; botão "Ocultar valores" funciona |
| 54 | Abrir `/data/financeiro.js` no endereço do site | Página não encontrada (404) |

## Roteiro de edição e anexos (V1.13) — depois da migração 008
| # | Ação | Resultado esperado |
|---|---|---|
| 55 | Storage no painel do Supabase | Existe o bucket `comprovantes`, privado |
| 56 | Síndico: Novo lançamento com fornecedor e um PDF de nota | Salva; a linha mostra 📎 1 |
| 57 | Novo lançamento com uma foto tirada na hora (celular) | A foto é enviada; a linha mostra 📎 1 |
| 58 | Tentar anexar um arquivo `.docx` ou um PDF de mais de 10 MB | Recusado antes de gravar o lançamento |
| 59 | Tocar em 📎 na linha e em Abrir | O arquivo abre em outra aba por link temporário |
| 60 | Remover um anexo com motivo | Some da lista; a contagem diminui |
| 61 | Anexar mais um arquivo pela janela do 📎 | Contagem aumenta |
| 62 | Editar um lançamento: mudar o valor, sem motivo | Recusado; com motivo, salva e a linha mostra "editado (versão 2)" |
| 63 | Mudar o valor e olhar o aviso | "Esta edição altera o saldo de MM/AAAA" |
| 64 | Ver histórico | Versão, motivo, valor antes e depois |
| 65 | Lançamento estornado e linha de estorno | Sem botão Editar |
| 66 | Conselho: abrir anexo e ver histórico | Consegue; não vê Editar, Anexar nem Remover |
| 67 | Morador: Financeiro | Só os totais; nenhum anexo |
| 68 | Com a sessão de um morador, tentar abrir um arquivo do bucket pelo link antigo (já expirado) | Não abre |

## Roteiro da importação de extrato OFX (V1.14) — depois da migração 009
| # | Ação | Resultado esperado |
|---|---|---|
| 69 | Síndico: Financeiro | Aparecem **Importar extrato (OFX)** e **Extratos importados** |
| 70 | Importar um arquivo que não é OFX (por exemplo, uma foto) | "Este arquivo não parece ser um extrato OFX" |
| 71 | Importar o OFX real do mês | Resumo com período, movimentos, entradas e saídas; sugestões nos movimentos conhecidos; pendentes destacados |
| 72 | Tentar importar com pendentes | Botão desativado |
| 73 | Resolver os pendentes (lançar, conciliar ou ignorar) e importar | Resultado com a contagem; o Financeiro mostra os novos lançamentos |
| 74 | Conferir o saldo acumulado do mês | Igual ao saldo final do extrato |
| 75 | Importar de novo o MESMO arquivo | "já foi importado em dd/mm/aaaa" |
| 76 | Importar um OFX de período que se sobrepõe ao anterior | Os movimentos repetidos aparecem como "já importados" e não duplicam |
| 77 | Lançar à mão uma despesa com o mesmo valor de um movimento do extrato e depois importar | O movimento vem como **conciliar** com esse lançamento (sem criar outro) |
| 78 | Importar com saldo diferente (apague um lançamento por estorno antes, por exemplo) | "Nada foi importado" e a opção de importar mesmo com a diferença |
| 79 | "Lembrar para os próximos extratos" em um boleto e importar o mês seguinte | O movimento igual já vem classificado |
| 80 | Conselho: Extratos importados, Ver movimentos | Vê situação, lançamento ligado e motivo; não vê o botão de importar |
| 81 | Morador: Financeiro | Nenhum botão de extrato |

## Roteiro da cobrança por unidade (V1.15) — depois da migração 010
| # | Ação | Resultado esperado |
|---|---|---|
| 82 | Síndico: Cobrança mensal em um mês sem cobrança | Passos 1, 2 e 3 |
| 83 | Gerar sem salvar a previsão | "Salve a previsão do mês" |
| 84 | Salvar previsão (taxa e fundo por unidade) | Valores reaparecem nos campos |
| 85 | Adicionar item de gás para uma unidade e um desconto (marcando "É desconto") | Aparecem na lista; desconto com valor negativo; remover funciona |
| 86 | Gerar (vencimento, fatura de água, mês de consumo) | Situação Rascunho; total por unidade confere com a sua planilha |
| 87 | Entrar como morador de teste | Não vê nada do rascunho |
| 88 | Síndico: Liberar cobrança | Situação "Liberada"; aparecem os botões de pagamento |
| 89 | Morador: Cobrança → Mostrar valores | Só a unidade dele: total, vencimento, itens |
| 90 | Registrar pagamento parcial (PIX) | Fica "Em aberto" com o pago somado |
| 91 | Registrar o restante usando um crédito do extrato | Vira "Paga" e sai de "Quem está em aberto" |
| 92 | Valor absurdo (muito acima da cobrança) | Recusado, com aviso |
| 93 | Remover um pagamento com motivo | A unidade volta a dever |
| 94 | Reabrir com pagamento registrado | Recusado: "remova-os" |
| 95 | Remover todos os pagamentos e reabrir | Volta a Rascunho; gerar de novo substitui |
| 96 | Conselho: Cobrança | Vê tudo e "Quem está em aberto"; sem botões |
| 97 | Confirmar que o livro-caixa não ganhou receita extra ao registrar pagamento | Nenhum lançamento novo |
