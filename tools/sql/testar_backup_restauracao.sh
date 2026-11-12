#!/usr/bin/env bash
# Teste ponta a ponta do backup/restauração (docs/backup): exporta de um projeto, restaura em outro projeto vazio e compara.
# Requer PostgreSQL local. Uso: PGHOST=/tmp PGPORT=5433 PGUSER=postgres bash tools/sql/testar_backup_restauracao.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
P="psql -v ON_ERROR_STOP=1 -q -X"; OK=0; BAD=0; W=$(mktemp -d)
check() { if [ "$2" = "1" ]; then OK=$((OK+1)); else BAD=$((BAD+1)); echo "FALHOU: $1"; fi; }
strip() { sed -e 's/[[:space:]]*;[[:space:]]*$//' "$1" | grep -v '^--'; }      # consulta sem comentários nem ';' final (para \copy)
novo_db() {   # $1 nome; cria banco com schema + migrações + condomínio + síndico (UUIDs recebidos em $2 e $3)
  $P -d postgres -c "drop database if exists $1" -c "create database $1" >/dev/null
  $P -d "$1" -f tools/sql/mock_supabase.sql
  $P -d "$1" -f schema.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do $P -d "$1" -f "$f" >/dev/null 2>&1; done
  $P -d "$1" -c "insert into public.condominios(id,nome) values ('aaaaaaaa-0000-0000-0000-0000000000$4','Edifício Valença')" \
     -c "insert into auth.users(id,email) values ('$2','sind$4@v.com')" \
     -c "insert into public.perfis(user_id,condominio_id,nome,email,papel) values ('$2','aaaaaaaa-0000-0000-0000-0000000000$4','Síndico $4','sind$4@v.com','sindico')"
}
SO=11111111-0000-0000-0000-000000000001; SD=99999999-0000-0000-0000-000000000009
# ---------- origem: dados reais importados + uso no app (lançamento com vírgula/aspas/quebra de linha, estorno) ----------
novo_db bk_origem $SO x 01
$P -d bk_origem -f docs/IMPORTAR_JUL_SET_2026.sql >/dev/null && $P -d bk_origem -f docs/IMPORTAR_OUT_2026_ATE_21.sql >/dev/null
$P -d bk_origem <<EOF2 >/dev/null
select set_config('request.jwt.claim.sub','$SO',false); set role authenticated;
select public.registrar_lancamento('despesa', (now() at time zone 'America/Sao_Paulo')::date, 12345, 'Outras despesas', 'Teste, com "aspas" e acentuação ção', null, 'NF 1,2', E'linha 1\nlinha 2, "citada"');
select public.estornar_lancamento((select id from public.lancamentos where valor_centavos = 44500 limit 1), 'lançado por engano, teste');
select public.editar_lancamento((select id from public.lancamentos where valor_centavos = 30840 limit 1), (select data_lancamento from public.lancamentos where valor_centavos = 30840 limit 1), 30000, 'Honorários', 'Contabilidade, corrigido', null, null, null, 'valor digitado errado');
reset role;
EOF2
# ---------- backup ----------
$P -d bk_origem -c "\copy ($(strip docs/backup/BACKUP_1_LANCAMENTOS.sql)) to '$W/lancamentos.csv' csv header"
$P -d bk_origem -c "\copy ($(strip docs/backup/BACKUP_2_CONTROLE.sql)) to '$W/controle_origem.csv' csv header"
$P -d bk_origem -c "\copy ($(strip docs/backup/BACKUP_3_MORADORES.sql)) to '$W/moradores.csv' csv header"
LIN=$(( $(wc -l < "$W/lancamentos.csv") ))
check "CSV do backup foi gerado e não está vazio" $([ "$LIN" -gt 100 ] && echo 1 || echo 0)
check "backup de moradores lista o síndico" $(grep -q "sindico" "$W/moradores.csv" && echo 1 || echo 0)
check "controle termina em TOTAL com saldo" $(tail -1 "$W/controle_origem.csv" | grep -q '^TOTAL' && echo 1 || echo 0)
# ---------- projeto novo e vazio: preparar, importar CSV, aplicar ----------
novo_db bk_base $SD x 09
$P -d postgres -c "drop database if exists bk_destino" -c "create database bk_destino template bk_base" >/dev/null
$P -d bk_destino -f docs/backup/RESTAURAR_1_PREPARAR.sql
$P -d bk_destino -c "\copy public.lancamentos_restauracao from '$W/lancamentos.csv' csv header"
$P -d bk_destino -f docs/backup/RESTAURAR_2_APLICAR.sql >/dev/null
RC=$?; check "restauração aplicada sem erro" $([ $RC -eq 0 ] && echo 1 || echo 0)
$P -d bk_destino -c "\copy ($(strip docs/backup/BACKUP_2_CONTROLE.sql)) to '$W/controle_destino.csv' csv header"
check "controle tem os 4 meses e o TOTAL (não está vazio)" $([ "$(wc -l < "$W/controle_destino.csv")" -ge 6 ] && echo 1 || echo 0)
check "controle (meses, quantidades, entradas, saídas e saldo) é IDÊNTICO origem × destino" $(cmp -s "$W/controle_origem.csv" "$W/controle_destino.csv" && echo 1 || echo 0)
check "saldo final do controle = 4.122,32 − 123,45 (teste) + 445,00 (estorno do gás) + 8,40 (edição da contabilidade) = 4.452,27" $(tail -1 "$W/controle_destino.csv" | grep -q ',4452.27' && echo 1 || echo 0)
HASH="select md5(string_agg(concat_ws('|',id,tipo,data_lancamento,competencia,valor_centavos,categoria,descricao,coalesce(fornecedor,''),coalesce(numero_documento,''),coalesce(observacao,''),coalesce(lancamento_original_id::text,''),(estornado_em is not null),coalesce(motivo_estorno,''),criado_em,versao,(editado_em is not null)), E'\n' order by id)) from public.lancamentos"
HO=$($P -d bk_origem -Atc "$HASH"); HD=$($P -d bk_destino -Atc "$HASH")
check "conteúdo dos lançamentos (hash de todos os campos, com ids) é IDÊNTICO" $([ -n "$HO" ] && [ "$HO" = "$HD" ] && echo 1 || echo 0)
check "criado_por passou a ser o síndico do projeto novo" $([ "$($P -d bk_destino -Atc "select count(*) from public.lancamentos where criado_por <> '$SD'")" = "0" ] && echo 1 || echo 0)
check "tabela temporária foi apagada" $([ "$($P -d bk_destino -Atc "select to_regclass('public.lancamentos_restauracao') is null")" = "t" ] && echo 1 || echo 0)
check "restauração fica na auditoria" $([ "$($P -d bk_destino -Atc "select count(*) from public.auditoria where acao='restaurar_backup'")" = "1" ] && echo 1 || echo 0)
check "lançamento com vírgula, aspas, acento e quebra de linha voltou intacto" $([ "$($P -d bk_destino -Atc "select count(*) from public.lancamentos where descricao = 'Teste, com \"aspas\" e acentuação ção' and observacao = E'linha 1\nlinha 2, \"citada\"'")" = "1" ] && echo 1 || echo 0)
check "lançamento editado voltou com versão 2 e marca de edição" $([ "$($P -d bk_destino -Atc "select count(*) from public.lancamentos where versao = 2 and editado_em is not null and descricao = 'Contabilidade, corrigido' and valor_centavos = 30000")" = "1" ] && echo 1 || echo 0)
check "estorno e marca de estornado restaurados" $([ "$($P -d bk_destino -Atc "select count(*) from public.lancamentos where estornado_em is not null and motivo_estorno like 'lançado por engano%'")" = "1" ] && echo 1 || echo 0)
$P -d bk_destino -c "update public.lancamentos set valor_centavos = 1" >/dev/null 2>&1; check "depois de restaurar, lançamentos continuam imutáveis" $([ $? -ne 0 ] && echo 1 || echo 0)
$P -d bk_destino -f docs/backup/RESTAURAR_2_APLICAR.sql >/dev/null 2>&1; check "rodar a restauração de novo é recusado" $([ $? -ne 0 ] && echo 1 || echo 0)
# ---------- falhas esperadas ----------
tenta() {   # $1 descrição, $2 arquivo CSV, $3 trecho esperado do erro
  $P -d postgres -c "drop database if exists bk_neg" -c "create database bk_neg template bk_base" >/dev/null
  $P -d bk_neg -f docs/backup/RESTAURAR_1_PREPARAR.sql; $P -d bk_neg -c "\copy public.lancamentos_restauracao from '$2' csv header"
  SAIDA=$($P -d bk_neg -f docs/backup/RESTAURAR_2_APLICAR.sql 2>&1); RC=$?
  N=$($P -d bk_neg -Atc "select count(*) from public.lancamentos")
  check "$1: recusado e nada gravado" $([ $RC -ne 0 ] && [ "$N" = "0" ] && echo "$SAIDA" | grep -q "$3" && echo 1 || echo 0)
  [ $RC -eq 0 ] && echo "   (não deu erro) ou mensagem diferente: $SAIDA" | head -3
}
head -n $((LIN-5)) "$W/lancamentos.csv" > "$W/truncado.csv"; tenta "CSV truncado (faltam linhas)" "$W/truncado.csv" "linhas"
python3 - "$W/lancamentos.csv" "$W/adulterado.csv" <<'PY'
import csv, sys
rows = list(csv.reader(open(sys.argv[1], newline='', encoding='utf-8')))
i = next(k for k, r in enumerate(rows) if k > 0 and r[1] == 'despesa'); rows[i][4] = str(int(rows[i][4]) + 100)   # +R$ 1,00 em um valor
csv.writer(open(sys.argv[2], 'w', newline='', encoding='utf-8')).writerows(rows)
PY
tenta "valor adulterado no CSV" "$W/adulterado.csv" "Saldo calculado"
# projeto que já tem lançamentos
$P -d postgres -c "drop database if exists bk_neg" -c "create database bk_neg template bk_base" >/dev/null
$P -d bk_neg -c "update public.condominios set saldo_inicial_centavos=0, saldo_inicial_data='2026-01-01'" -c "insert into public.lancamentos(condominio_id,tipo,data_lancamento,valor_centavos,categoria,descricao,criado_por) select id,'receita','2026-02-01',100,'Taxa condominial','x','$SD' from public.condominios"
$P -d bk_neg -f docs/backup/RESTAURAR_1_PREPARAR.sql; $P -d bk_neg -c "\copy public.lancamentos_restauracao from '$W/lancamentos.csv' csv header"
S=$($P -d bk_neg -f docs/backup/RESTAURAR_2_APLICAR.sql 2>&1); check "projeto que já tem lançamentos: recusado" $(echo "$S" | grep -q "já tem lançamentos" && echo 1 || echo 0)
# tabela vazia
$P -d postgres -c "drop database if exists bk_neg" -c "create database bk_neg template bk_base" >/dev/null
$P -d bk_neg -f docs/backup/RESTAURAR_1_PREPARAR.sql; S=$($P -d bk_neg -f docs/backup/RESTAURAR_2_APLICAR.sql 2>&1); check "sem importar o CSV: recusado" $(echo "$S" | grep -q "está vazia" && echo 1 || echo 0)
for d in bk_origem bk_base bk_destino bk_neg; do $P -d postgres -c "drop database if exists $d" >/dev/null; done
echo "Backup/restauração: $OK passaram, $BAD falharam."; [ $BAD -eq 0 ]
