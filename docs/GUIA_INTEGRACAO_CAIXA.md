# Integração de cobrança bancária CAIXA — próximos passos

## Estado desta entrega

Esta versão adiciona a estrutura de dados para cobranças por unidade, itens discriminados, metadados do convênio e eventos idempotentes, além de uma Edge Function protegida que valida sessão e papel de síndico. A função permite consultar o estado de prontidão, mas bloqueia emissão, consulta e cancelamento até a implementação do protocolo exato do convênio. **Ainda não existe emissão real de boletos.**

A documentação pública da CAIXA descreve WebService SOAP/XML para registro, consulta, alteração e baixa de títulos. A CAIXA também pode exigir validação de amostras de boleto quando a emissão é feita por aplicativo próprio. O contrato do condomínio e a versão de manual entregue pelo banco são a fonte de verdade para habilitação, campos, segurança e homologação.

## 1. Solicitação ao gerente/área de cobrança

Solicitar por escrito:

- confirmação de que o convênio atual permite **registro online via WebService**; contrato de cobrança por si só não comprova que o canal de WebService está habilitado;
- manual técnico vigente e respectivos WSDL/XSD, endpoints por ambiente e processo de homologação;
- modalidade/sistema de cobrança aplicável ao convênio (por exemplo, SIGCB ou outro), código do beneficiário, carteira, espécie, nosso número e regras de numeração;
- método de autenticação, hash/criptografia, certificados, IPs autorizados e rotação de credenciais;
- campos obrigatórios do título, instruções pós-vencimento (protesto/devolução), juros, multa, descontos, beneficiário final e dados do pagador;
- como obter boleto/PDF, linha digitável, código de barras, retorno de registro, consulta e baixa;
- como receber liquidações e estornos: WebService, arquivo retorno CNAB (240/400), canal de entrega e periodicidade;
- ambiente de testes, cenários de homologação, amostras a validar, tarifas e limites operacionais;
- confirmação sobre boleto híbrido com Pix, se desejado (não será presumido nem ativado sem confirmação contratual).

## 2. Segurança e dados

- Não enviar senhas, tokens, certificados privados ou chaves por chat/e-mail comum. Guardar segredos em Supabase Edge Function Secrets ou cofre equivalente.
- Nunca colocar `SUPABASE_SERVICE_ROLE_KEY` ou segredo bancário no HTML, JavaScript do navegador, repositório público ou PWA.
- Usar dados fictícios em homologação. Não testar com cobrança real até a aprovação formal do banco e do condomínio.
- Guardar no banco apenas metadados necessários do convênio. Segredos não devem ser gravados em `configuracao_cobranca_caixa`.
- Redigir logs: não armazenar XML completo com dados pessoais, credenciais, hashes ou conteúdo sensível. Guardar códigos e resumos de retorno.

## 3. Fluxo técnico planejado

1. Síndico fecha competência e revisa itens da cobrança (cota, água, rateios, ajustes).
2. Backend valida unidade, vencimento, total e ausência de outra cobrança para a mesma unidade/competência.
3. Backend cria solicitação idempotente e registra evento de auditoria.
4. Adaptador CAIXA envia registro conforme o manual vigente e trata timeouts sem repetir cegamente a operação.
5. Resposta bancária é validada; nosso número, identificador, linha digitável/código de barras e PDF são salvos de forma segura.
6. Boleto é disponibilizado somente ao morador vinculado à unidade e aos perfis autorizados.
7. Pagamento só é conciliado por retorno bancário confiável; evento repetido não pode duplicar recebimento.
8. Baixa/cancelamento é solicitado no banco e só muda de estado após retorno confirmatório.

## 4. Regras financeiras

- Uma cobrança por unidade e competência; alteração após registro deve seguir fluxo explícito de baixa/substituição, nunca sobrescrever silenciosamente o boleto registrado.
- Valores em centavos inteiros.
- Itens da cobrança são discriminativos; não criam novas entradas no livro-caixa. A despesa da água continua sendo um único lançamento financeiro, relacionado aos rateios das unidades.
- O rateio de água precisa fechar exatamente com o valor da fatura, incluindo ajuste de centavos auditável.
- O estado `paga` requer `pago_em` e evento bancário confirmado. Consulta resumida sem data/valor de liquidação não deve ser tratada como conciliação definitiva.

## 5. Homologação mínima

- registro aceito e retorno de nosso número;
- dados inválidos rejeitados sem marcar boleto como emitido;
- timeout após envio sem duplicar título em repetição;
- consulta de título registrado;
- cancelamento/baixa com confirmação e rejeição;
- retorno de pagamento, pagamento parcial se permitido, tarifa, estorno e arquivo duplicado;
- duas requisições simultâneas para a mesma unidade/competência;
- morador não consegue consultar boleto de outra unidade;
- conselho não consegue emitir/cancelar nem baixar documentos financeiros;
- segredo bancário ausente em resposta, HTML, logs e banco de dados;
- validação de boleto/amostra pela CAIXA, quando exigida.

## 6. Materiais a fornecer à equipe técnica

Preferencialmente por canal seguro da equipe contratada: manual técnico atual, WSDL/XSD, modalidade do convênio, carteira, código do beneficiário e instruções de homologação. Compartilhar apenas os dados necessários. Credenciais e certificados privados devem ser inseridos diretamente no cofre de segredos do ambiente, nunca nesta conversa.

## Referências

- CAIXA — [Cobrança Bancária](https://www.caixa.gov.br/empresa/pagamentos-recebimentos/recebimentos/cobranca-bancaria/Paginas/default.aspx)
- CAIXA — [Leiaute WebService XML — Cobrança Bancária e Cobrança Híbrida Pix (PDF)](https://www.caixa.gov.br/Downloads/cobranca-caixa/WEBSERVICE-XML-COBRANCA-BANCARIA.pdf)
