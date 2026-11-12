# Especificação técnica — Aplicativo de Gestão Condominial

**Versão:** 1.4  
**Escopo:** condomínio residencial com 8 unidades  
**Status:** especificação atualizada e protótipo navegável; integração de produção pendente.

## 1. Objetivo e arquitetura

Aplicativo responsivo/PWA para moradores, síndico e conselho, com banco de dados centralizado. O HTML do livro-caixa fornecido permanece preservado no pacote como referência funcional. A arquitetura proposta utiliza PostgreSQL, autenticação e armazenamento privado (ex.: Supabase), com regras de autorização no servidor e políticas RLS.

## 2. Perfis e permissões

- **Síndico:** administra cadastro de unidades e usuários, envia convites, cadastra frações ideais, gerencia lançamentos e documentos, registra contas de água, prepara cobranças e acompanha boletos.
- **Conselho:** consulta livro-caixa detalhado e comprovantes dentro do aplicativo; não pode exportar nem baixar dados financeiros.
- **Morador:** conclui cadastro por convite, consulta avisos/documentos permitidos, registra ocorrências, publica avisos sobre a intenção de uso da vaga de visitante e consulta a prestação de contas resumida e suas próprias cobranças/boletos.

## 3. Módulos

### 3.1 Vaga de visitante — mural de avisos

- Existe uma única vaga de garagem destinada a visitantes.
- O módulo não é um sistema formal de reservas: funciona como mural de avisos para informar os moradores sobre a intenção de uso.
- O aviso pode incluir data, horário aproximado, unidade responsável, observação e estado (ativo/encerrado).
- O aviso não garante disponibilidade nem cria prioridade ou exclusividade de uso.
- O protótipo permite publicar e encerrar avisos localmente; persistência e autenticação dependem da integração com o backend.


### 3.2 Calendário de manutenções preventivas

- Módulo acessível somente aos perfis síndico e conselho. O conselho consulta; o síndico cria, edita e registra execução.
- Cada tarefa possui título, categoria, descrição, próximo vencimento, periodicidade em meses (0 para tarefa não recorrente), responsável, prestador, situação e histórico de execuções.
- O calendário sinaliza tarefas atrasadas, próximas (janela demonstrativa de 30 dias) e agendadas.
- Ao registrar uma execução, o sistema guarda data e observações; para tarefa recorrente, calcula a próxima ocorrência a partir da data executada. A produção deve usar operação transacional e trilha de auditoria.
- Exemplos iniciais: limpeza da caixa de gordura, limpeza/desinfecção da caixa d’água, inspeção/manutenção dos extintores e revisão preventiva do portão.
- Os intervalos no protótipo são apenas exemplos configuráveis. Não representam orientação normativa universal: o síndico deve validar frequências com o prestador habilitado, fabricante, laudos e exigências locais aplicáveis.
- Execuções devem aceitar anexos privados (ordem de serviço, relatório, certificado, nota fiscal) e vínculo opcional com lançamento do livro-caixa, sem duplicar o registro financeiro.
- A tela apresenta alertas ao consultar o aplicativo; push, e-mail ou notificações externas ainda precisam ser configurados no backend.

### 3.3 Financeiro e anexos

- Livro-caixa com receitas, despesas, competência, categoria, descrição, valor em centavos, documento de referência e auditoria.
- Cada lançamento pode ter múltiplos anexos: nota fiscal, orçamento, recibo, fatura e comprovante de pagamento.
- Arquivos em armazenamento privado, com validação de tipo/tamanho, vínculo com lançamento e autorização de acesso. Não usar URLs públicas permanentes.
- Conselho visualiza lançamentos e comprovantes no aplicativo, sem exportação/download. Moradores veem resumo financeiro conforme a política de transparência.
- Correções financeiras devem gerar estorno/ajuste auditável; não apagar silenciosamente registros fechados.

### 3.4 Frações ideais e conta de água

O síndico cadastra manualmente as frações conforme a convenção. Os valores abaixo (atualizados na V1.6, conforme a planilha de previsão orçamentária) devem ser preservados com sete casas decimais:

| Unidade | Fração ideal | Participação |
|---|---:|---:|
| 01 | 0,1221736 | 12,21736% |
| 02 | 0,1102275 | 11,02275% |
| 101 | 0,1105078 | 11,05078% |
| 102 | 0,1114779 | 11,14779% |
| 201 | 0,1170276 | 11,70276% |
| 202 | 0,1114779 | 11,14779% |
| 301 | 0,1662468 | 16,62468% |
| 302 | 0,1508609 | 15,08609% |
| **Total** | **1,0000000** | **100,00000%** |

Fluxo da água:
1. Síndico informa valor total, competência e vencimento, anexando a fatura.
2. Sistema valida competência duplicada e soma das frações ativas.
3. Sistema calcula a parcela de cada unidade usando a fração ideal cadastrada para a competência.
4. Arredondamento monetário ocorre em centavos; eventual diferença residual é distribuída por regra determinística e auditável para garantir que a soma seja exatamente igual à fatura.
5. O rateio fica vinculado à despesa original e aos itens das cobranças individuais, sem duplicar receitas/despesas no livro-caixa.
6. Alterações posteriores em frações não reescrevem rateios já fechados; correções geram ajuste com trilha de auditoria.

### 3.5 Cobrança e boletos bancários — Caixa Econômica Federal

- **Banco definido:** Caixa Econômica Federal (CAIXA).
- Cada unidade terá uma cobrança individual por competência, com itens discriminados (cota condominial, água e demais rateios aprovados).
- A integração será planejada para a solução de Cobrança Bancária CAIXA, usando o meio técnico autorizado para a conta e o convênio do condomínio. A CAIXA publica documentação de webservice para cobrança bancária e cobrança híbrida; o acesso, leiaute aplicável e condições de uso deverão ser confirmados diretamente com o banco e vinculados ao contrato do beneficiário.
- O fluxo deverá contemplar, conforme o serviço contratado: registro/emissão de boleto, identificador bancário, linha digitável/código de barras, disponibilização segura do boleto, consulta/cancelamento quando suportados e conciliação por retorno bancário ou notificação oficialmente disponível.
- Chamadas bancárias e credenciais ficam exclusivamente no backend/Edge Functions; nunca incluir segredo bancário ou `service_role` no navegador.
- Retornos e notificações deverão ser autenticados quando aplicável, idempotentes e auditados para impedir baixa duplicada ou estado financeiro inconsistente.
- O sistema só marcará uma cobrança como paga após confirmação confiável do banco/retorno bancário; a geração do boleto não equivale a recebimento.
- **Dependências pendentes para ativar a integração:** confirmar se o condomínio já contratou Cobrança Bancária CAIXA; obter do gerente os dados do convênio/beneficiário, documentação técnica vigente aplicável, forma de autenticação, ambiente de homologação, tarifas e processo de liberação. Não inserir credenciais reais no protótipo ou em mensagens de chat.
- Até a conclusão dessas etapas e dos testes de homologação, a integração com a CAIXA é especificada, mas não está ativa no aplicativo.

## 4. Convites, autenticação e segurança

- O síndico envia convite; o morador conclui o cadastro e confirma e-mail.
- Papel do usuário é atribuído por processo administrativo confiável, nunca pelo próprio usuário no navegador.
- RLS deve restringir cada registro ao condomínio e perfil autorizado.
- Documentos financeiros e boletos exigem acesso autenticado e limitado à unidade/perfil.
- Auditoria registra criação, alteração, estorno, rateio, emissão/cancelamento de boleto, retorno bancário e mudança de permissões.
- Configurar backups e testar restauração antes do uso real.

## 5. Modelo de dados previsto

- `condominios`, `unidades`, `perfis`, `vinculos_unidades`, `convites`.
- `lancamentos`, `comprovantes_financeiros`, `contas_agua`, `rateios_agua`.
- `cobrancas_unidades`, `boletos_bancarios`.
- `avisos`, `documentos`, `ocorrencias`, `historico_ocorrencias`, `manutencoes`, `execucoes_manutencao`, `anexos_manutencao`, `enquetes`, `respostas_enquetes`, `auditoria`. A vaga de visitante usa avisos, não reservas formais.

## 6. Situação da implementação

O pacote inclui protótipo navegável, esquema SQL inicial, README, esta especificação V1.4 e cópia intacta do HTML do livro-caixa de referência. A instituição financeira definida para a integração é a Caixa Econômica Federal. A tela demonstra o mural de avisos da vaga de visitante, o calendário preventivo e o cálculo do rateio da água. O formulário aceita selecionar anexos para demonstração, mas ainda não faz upload persistente. O protótipo não tem autenticação real, banco conectado nem emissão bancária real.

## 7. Próximas etapas técnicas

1. Revisar e aplicar o SQL em ambiente de teste.
2. Criar o projeto/backend, usuários iniciais e cadastrar as oito unidades e frações após conferência da convenção.
3. Implementar upload seguro dos anexos e permissões de acesso.
4. Implementar função transacional de rateio e criação de itens de cobrança.
5. Confirmar com a CAIXA a contratação de Cobrança Bancária e o convênio do beneficiário; obter documentação técnica e acesso de homologação. Implementar e testar emissão, cancelamento e conciliação conforme as operações autorizadas pelo banco.
6. Implementar convites, login, RLS e auditoria; executar testes de acesso indevido e concorrência.
7. Realizar testes com os três perfis, conciliar valores, validar backups e só então liberar para uso real.


## Incremento V1.3 — base da cobrança CAIXA

- Criada migração SQL para cobranças por unidade/competência, itens discriminados, configuração não secreta do convênio e eventos bancários idempotentes.
- Precisão de fração ideal ajustada para sete casas decimais.
- Criada Edge Function protegida para validar sessão e papel de síndico e consultar a prontidão da integração. Emissão, consulta e cancelamento bancários permanecem bloqueados até a implementação do protocolo exato e homologação.
- Incluído guia de solicitação de dados técnicos à CAIXA e roteiro de homologação.
- A interface HTML continua sendo protótipo sem persistência/login real; a integração ainda não está conectada ao app.


## Incremento V1.4 — calendário preventivo e mural da vaga

- Protótipo atualizado com módulo de manutenções para síndico e conselho, alertas por vencimento, criação/edição demonstrativa, registro de execução e recorrência em meses.
- Incluídos exemplos de caixa de gordura, caixa d’água, extintores e portão. Frequências são exemplos editáveis e precisam de validação técnica/legal.
- Substituído o módulo de reservas por mural de avisos para a única vaga de visitante, sem confirmação, bloqueio ou garantia de disponibilidade.
- Criada migração `20261019_002_manutencoes_preventivas.sql` com tabelas de manutenções, execuções e referências a anexos privados e políticas RLS para síndico/conselho.
- O protótipo mantém os dados em memória; alertas externos, anexos persistentes, auditoria completa e integração com o banco ainda não estão ativos.
