#!/usr/bin/env bash
# Cria um banco PostgreSQL descartável, aplica schema + migrações e roda os testes de login/convites/vaga.
# Requer PostgreSQL local (psql). Uso: PGHOST=/tmp PGPORT=5433 PGUSER=postgres bash tools/sql/rodar_testes_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=${DB:-teste_condominio}
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -f tools/sql/mock_supabase.sql
$P -d $DB -f schema.sql 2>&1 | grep -v NOTICE || true
for f in supabase/migrations/*.sql; do echo "aplicando $f"; $P -d $DB -f "$f" 2>&1 | grep -v NOTICE || true; done
for T in teste_login_convites_vaga teste_livro_caixa teste_saldo_abertura teste_importacao_jul_set teste_importacao_ofx_out teste_edicao_anexos teste_importar_extrato teste_cobranca_pagamentos teste_importacao_out_fim_nov teste_dashboard_financeiro; do echo "== $T"; $P -d $DB -f tools/sql/$T.sql 2>&1 | grep -v -E "NOTICE|DETAIL|drop cascades"; done
