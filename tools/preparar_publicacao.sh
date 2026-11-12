#!/usr/bin/env bash
# Monta a pasta "publicar/" só com o que o app precisa para funcionar no ar.
# NÃO inclui: data/ (dados financeiros reais), docs, tools, zips antigos, schema/migrações, livro-caixa-original.html.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf publicar && mkdir -p publicar/icons publicar/vendor
cp index.html auth.js caixa.js ofx.js extrato.js cobranca-ui.js config.js cobranca.js boleto.js sw.js manifest.webmanifest publicar/
cp icons/* publicar/icons/
cp vendor/supabase.js vendor/LICENSE-supabase-js.txt publicar/vendor/
# o index.html tenta carregar data/financeiro.js; sem o arquivo o app segue normalmente (onerror)
echo "Arquivos em publicar/:"; (cd publicar && find . -type f | sort)
# verificações de segurança
if [ -e publicar/data ]; then echo "ERRO: pasta data/ na publicação"; exit 1; fi
# chaves secretas do Supabase: formato novo (sb_secret_...) ou JWT (eyJ...) — a chave pública é sb_publishable_
if grep -rIlE --exclude-dir=vendor "sb_secret_|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}" publicar >/dev/null 2>&1; then echo "ERRO: possível chave secreta encontrada em:"; grep -rIlE --exclude-dir=vendor "sb_secret_|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}" publicar; exit 1; fi
grep -q "sb_publishable_" publicar/config.js && echo "OK: config.js usa a chave pública (publishable)."
echo "OK: publicação sem dados financeiros e sem chave secreta. Suba o CONTEÚDO da pasta publicar/ no servidor (HTTPS)."
