# Atualizar o app e conferir a versão (GitHub Pages ou Netlify)

## Por que o navegador pode mostrar uma versão antiga
O app é instalável (PWA) e guarda uma cópia local para funcionar sem internet. Até a versão 1.12.0 essa cópia tinha **prioridade** sobre a rede, e o GitHub Pages ainda deixa o navegador reutilizar arquivos por até 10 minutos. Resultado: logo após publicar, podia aparecer a versão anterior.
A partir da **1.12.1** o app busca a versão publicada primeiro (a cópia local só serve quando não há internet) e a instalação ignora o cache HTTP.

## Passo 1 — A versão publicada é a nova? (janela anônima)
1. Abra uma **janela anônima/privada** (ela não usa o cache do app).
2. Entre em `https://SEU-SITE/auth.js` (por exemplo, `https://arturleaocosta-prog.github.io/Sistema-Valenca/auth.js`) e procure por **Versão 1.12** (Ctrl+F).
   - Aparece **Versão 1.12.1** (ou a que você enviou): a publicação está certa; o que está velho é o cache do seu aparelho (Passo 2).
   - Aparece versão antiga ou dá 404: os arquivos publicados não foram trocados. Confira no GitHub se `index.html` e `auth.js` estão na **raiz** do repositório (e não dentro de uma pasta como `publicar/`), se o último *commit* tem os arquivos novos e se **Actions → pages build and deployment** terminou em verde.

## Passo 2 — Atualizar o seu aparelho
**Primeiro tente o jeito simples (não apaga nada):**
1. Abra o app com internet e deixe uns 10 segundos.
2. Feche **por completo** (no celular, tire da lista de apps recentes) e abra de novo.
3. Repita uma vez. A primeira abertura baixa e instala a versão nova; a segunda já a mostra. No rodapé do menu deve aparecer **Versão 1.12.1**.

**Se ainda ficar velho — computador (Chrome/Edge), sem apagar outros sites:**
1. F12 → aba **Application**.
2. **Service Workers** → *Unregister* no do endereço do app.
3. **Cache Storage** → apague os itens `condominio-shell-…`.
4. Recarregue com Ctrl+F5.

**Se ainda ficar velho — celular:**
- App instalado na tela inicial: remova o ícone e instale de novo pelo navegador.
- **Cuidado com "Limpar dados do site":** no GitHub Pages todos os seus sites ficam no mesmo endereço (`SEU-USUARIO.github.io`). Limpar os dados desse endereço apaga também os dados locais de **outros** apps seus hospedados lá. Use só em último caso.

## Para quem publica
- Depois de enviar arquivos novos, aguarde o *pages build and deployment* ficar verde (1 a 2 minutos) antes de testar.
- Sempre aumente o número da versão (rodapé do menu) para saber, de relance, qual está no ar.
