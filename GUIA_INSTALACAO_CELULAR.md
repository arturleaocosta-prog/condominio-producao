# Instalar o aplicativo no celular — V1.5

## Formato entregue
Esta versão é um **PWA (Progressive Web App)**: abre em tela cheia e pode ser adicionada à tela inicial do Android e do iPhone. Não é um APK Android nem um IPA da App Store. A instalação depende de publicar os arquivos em um endereço HTTPS; abrir o HTML diretamente pelo gerenciador de arquivos não habilita a instalação PWA.

## Publicar
1. Extraia o ZIP.
2. Publique o conteúdo desta pasta em um serviço de hospedagem estática com HTTPS (por exemplo, hospedagem web da organização).
3. Confirme que `index.html`, `manifest.webmanifest`, `sw.js` e a pasta `icons/` estão acessíveis no mesmo caminho.
4. Abra o endereço HTTPS no celular. O navegador precisa ter acesso à rede na primeira visita.

## Android (Chrome)
1. Abra o endereço HTTPS no Chrome.
2. Abra o menu `⋮`.
3. Toque em **Instalar app** ou **Adicionar à tela inicial** (o texto varia conforme a versão).
4. Confirme. O ícone “Condomínio” aparecerá na tela inicial.

## iPhone (Safari)
1. Abra o endereço HTTPS no Safari.
2. Toque em **Compartilhar**.
3. Escolha **Adicionar à Tela de Início**.
4. Confirme o nome e toque em **Adicionar**.

## Limitações importantes
- O protótipo continua sendo demonstrativo: perfil selecionável, dados em memória, sem autenticação real e sem banco conectado.
- O cache permite abrir a estrutura básica depois da primeira visita, mas não transforma os dados em sincronizados ou persistentes.
- Boletos CAIXA reais, alertas push e anexos persistentes ainda dependem de backend, credenciais/convênio e homologação.
- Não use dados pessoais ou financeiros reais nesta versão.

## Para gerar APK ou publicar em loja
É necessário empacotar o projeto com uma solução como Capacitor, configurar assinatura Android/iOS, testar em dispositivos e tratar permissões, segurança e atualização. Essa etapa não está incluída neste pacote PWA.
