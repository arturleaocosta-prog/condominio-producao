-- RESTAURAR 1 de 2 — cria a tabela temporária que recebe o CSV do backup.
-- Pré-requisito: projeto novo com schema.sql, migrações 001–007, condomínio "Edifício Valença", unidades e o usuário síndico (roteiro de produção, partes A a C).
-- Depois: Table Editor → tabela lancamentos_restauracao → Insert → Import data from CSV → escolha o arquivo lancamentos_AAAA-MM-DD.csv (sem abrir no Excel).
drop table if exists public.lancamentos_restauracao;
create table public.lancamentos_restauracao (
  id text, tipo text, data_lancamento text, competencia text, valor_centavos text, categoria text, descricao text, fornecedor text,
  numero_documento text, observacao text, lancamento_original_id text, estornado_em text, motivo_estorno text, criado_em text, versao text, editado_em text,
  condominio_nome text, saldo_inicial_centavos text, saldo_inicial_data text, bk_total_linhas text, bk_saldo_final_centavos text, bk_gerado_em text);
alter table public.lancamentos_restauracao enable row level security;   -- sem policy: ninguém acessa pelo app
revoke all on public.lancamentos_restauracao from anon, authenticated;
