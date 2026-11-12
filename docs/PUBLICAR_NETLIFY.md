# Publicar no Netlify (teste e produção)

Use **dois sites separados**: um para o projeto Supabase de teste e outro para o de produção. Cada um tem o seu próprio `config.js`.

## Publicar uma versão nova (sem Git, sem logo do Netlify)
1. Descompacte `condominio_publicar_v1_12_0.zip` em uma pasta.
2. Abra o `config.js` da pasta em um editor de texto simples e confirme que a URL e a chave `sb_publishable_...` são do projeto certo (teste ou produção). **Nunca** use a chave secret, a `service_role` nem a senha do banco.
3. No Netlify: **Sites → Add new site → Deploy manually** (primeira vez) ou, em um site existente, aba **Deploys** e a área de arrastar e soltar. Arraste **a pasta** já descompactada.
4. Aguarde o fim da publicação e abra o endereço do site.

**Por que manual:** o logo do Netlify que aparece sobre a barra inferior no celular é o *Netlify Drawer*, uma ferramenta de comentários que só aparece em sites ligados a um repositório Git, em *deploy previews* e *branch deploys*. Publicação manual não cria *preview* e, portanto, não tem o logo.

## Se o site está ligado ao Git e o logo aparece
- Abra o endereço de **produção** do site, não o de *deploy preview* nem o de *branch deploy*.
- Ou desligue: **Project configuration → Build & deploy → Continuous deployment → Collaboration tools → Configure → desativar o Netlify Drawer**.
- Ou use o link permanente (*permalink*) do deploy, que não tem o Drawer.
- Provisório: arraste o logo para outro canto da tela.

## Conferências de segurança depois de publicar (1 minuto)
1. Abra `https://SEU-SITE.netlify.app/data/financeiro.js`. **Tem de dar “página não encontrada” (404).** Se baixar um arquivo, você publicou a pasta errada (o projeto inteiro): apague o deploy e publique só a pasta do pacote de publicação.
2. Abra `https://SEU-SITE.netlify.app/config.js` e confirme que só aparecem a URL e a chave `sb_publishable_`.
3. O rodapé do menu mostra **Versão 1.12.0** depois do login.

## Supabase
Em **Authentication → URL Configuration**, o **Site URL** e os **Redirect URLs** são o endereço do site do Netlify (com `/**` no segundo).
