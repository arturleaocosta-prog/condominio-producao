# Especificação V1.5 — distribuição móvel

## Objetivo
Permitir instalar o protótipo na tela inicial de dispositivos móveis por meio de PWA, sem alterar o estado de protótipo nem sugerir que existe aplicativo nativo publicado.

## Alterações
- Manifest com `display: standalone`, `scope`, `start_url`, orientação retrato e ícones PNG 192×192/512×512.
- Metadados para instalação na tela inicial do iOS e ícone Apple Touch.
- Service worker versionado, cache dos arquivos essenciais e ícones.
- Guia de publicação HTTPS e instalação em Android/iOS.

## Limitações
- A instalação exige origem HTTPS (ou localhost para testes); `file://` não é suficiente.
- PWA não é APK nem IPA.
- O protótipo ainda usa dados fictícios/em memória e não tem autenticação real, persistência, push ou emissão real de boletos CAIXA.
- Não usar em produção antes da implementação e auditoria do backend e testes de segurança.
