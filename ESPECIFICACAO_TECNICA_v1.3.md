# Especificação técnica — Aplicativo de Gestão Condominial

**Versão:** 1.2  
**Escopo:** condomínio residencial com 8 unidades  
**Status:** especificação atualizada e protótipo navegável; integração de produção pendente.

## 1. Objetivo e arquitetura

Aplicativo responsivo/PWA para moradores, síndico e conselho, com banco de dados centralizado. O HTML do livro-caixa fornecido permanece preservado no pacote como referência funcional. A arquitetura proposta utiliza PostgreSQL, autenticação e armazenamento privado (ex.: Supabase), com regras de autorização no servidor e políticas RLS.

## 2. Perfis e permissões

- **Síndico:** administra cadastro de unidades e usuários, envia convites, cadastra frações ideais, gerencia lançamentos e documentos, registra contas de água, prepara cobranças e acompanha boletos.
- **Conselho:** consulta livro-caixa detalhado e comprovantes dentro do aplicativo; não pode exportar nem baixar dados financeiros.
- **Morador:** conclui cadastro por convite, consulta avisos/documentos permitidos, registra ocorrências, reserva a vaga para visitantes e consulta a prestação de contas resumida e suas próprias cobranças/boletos.

## 3. Módulos

### 3.1 Reservas

- O único recurso reservável é a **vaga de garagem destinada a visitantes**. Não haverá reservas de salão, churrasqueira ou outras áreas comuns.
- Reserva com data, hora inicial/final, unidade solicitante e status.
- Confirmação automática se as regras forem atendidas e não houver sobreposição de horários.
- Regras configuráveis pelo síndico: antecedência, duração máxima e cancelamento.
- A confirmação real deve ocorrer em transação no backend para evitar dupla reserva concorrente; a validação somente no navegador não é suficiente.

### 3.2 Financeiro e anexos

- Livro-caixa com receitas, despesas, competência, categoria, descrição, valor em centavos, documento de referência e auditoria.
- Cada lançamento pode ter múltiplos anexos: nota fiscal, orçamento, recibo, fatura e comprovante de pagamento.
- Arquivos em armazenamento privado, com validação de tipo/tamanho, vínculo com lançamento e autorização de acesso. Não usar URLs públicas permanentes.
- Conselho visualiza lançamentos e comprovantes no aplicativo, sem exportação/download. Moradores veem resumo financeiro conforme a política de transparência.
- Correções financeiras devem gerar estorno/ajuste auditável; não apagar silenciosamente registros fechados.

### 3.3 Frações ideais e conta de água

O síndico cadastra manualmente as frações conforme a convenção. Os valores abaixo devem ser preservados com sete casas decimais:

| Unidade | Fração ideal | Participação |
|---|---:|---:|
| 01 | 0,1125080 | 11,25080% |
| 02 | 0,1114412 | 11,14412% |
| 101 | 0,1117246 | 11,17246% |
| 102 | 0,1127054 | 11,27054% |
| 201 | 0,1183161 | 11,83161% |
| 202 | 0,1127054 | 11,27054% |
| 301 | 0,1680773 | 16,80773% |
| 302 | 0,1525220 | 15,25220% |
| **Total** | **1,0000000** | **100,00000%** |

Fluxo da água:
1. Síndico informa valor total, competência e vencimento, anexando a fatura.
2. Sistema valida competência duplicada e soma das frações ativas.
3. Sistema calcula a parcela de cada unidade usando a fração ideal cadastrada para a competência.
4. Arredondamento monetário ocorre em centavos; eventual diferença residual é distribuída por regra determinística e auditável para garantir que a soma seja exatamente igual à fatura.
5. O rateio fica vinculado à despesa original e aos itens das cobranças individuais, sem duplicar receitas/despesas no livro-caixa.
6. Alterações posteriores em frações não reescrevem rateios já fechados; correções geram ajuste com trilha de auditoria.

### 3.4 Cobrança e boletos bancários — Caixa Econômica Federal

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
- `avisos`, `documentos`, `ocorrencias`, `historico_ocorrencias`, `areas_comuns`, `reservas`, `enquetes`, `respostas_enquetes`, `auditoria`.

## 6. Situação da implementação

O pacote inclui protótipo navegável, esquema SQL inicial, README, esta especificação V1.2 e cópia intacta do HTML do livro-caixa de referência. A instituição financeira definida para a integração é a Caixa Econômica Federal. A tela demonstra o fluxo de reserva exclusiva da vaga visitante e cálculo do rateio da água. O formulário aceita selecionar anexos para demonstração, mas ainda não faz upload persistente. O protótipo não tem autenticação real, banco conectado nem emissão bancária real.

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
