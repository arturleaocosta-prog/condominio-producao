-- V1.6 — estrutura para receber previsão orçamentária, rateio de água, conciliação bancária e aplicação
-- (origem: planilhas do Edifício Valença; importação via tools/importar_planilhas.py → seed no Supabase).
-- Aplicar depois de schema.sql e das migrações 001 e 002, em ambiente de teste.
-- Cobrança por unidade continua em public.cobrancas / itens_cobranca (migração 001).

create table public.previsoes_mensais (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  competencia date not null,
  taxa_por_unidade_centavos bigint not null check (taxa_por_unidade_centavos >= 0),
  fundo_obras_por_unidade_centavos bigint not null default 0 check (fundo_obras_por_unidade_centavos >= 0),
  despesas jsonb not null default '[]'::jsonb,   -- descrição, vencimento e valor de cada despesa geral
  gas_preco_m3 numeric(10,4),
  criado_em timestamptz not null default now(),
  unique (condominio_id, competencia)
);

create table public.rateios_agua (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  competencia date not null,
  valor_fatura_centavos bigint not null check (valor_fatura_centavos > 0),
  vencimento date,
  criado_em timestamptz not null default now(),
  unique (condominio_id, competencia)
);

-- fracao_aplicada guarda a fração usada naquele rateio: alterar unidades.fracao_ideal não reescreve rateios fechados.
create table public.rateios_agua_itens (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  rateio_id uuid not null references public.rateios_agua(id) on delete cascade,
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  fracao_aplicada numeric(10,7) not null check (fracao_aplicada > 0 and fracao_aplicada < 1),
  valor_centavos bigint not null check (valor_centavos >= 0),
  unique (rateio_id, unidade_id)
);

create table public.conciliacoes_bancarias (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  competencia date not null,
  conta text not null default 'corrente' check (conta in ('corrente','aplicacao')),
  saldo_inicial_centavos bigint not null,
  saldo_extrato_centavos bigint,                 -- null enquanto o extrato não foi informado
  rendimentos_centavos bigint not null default 0, -- usado na conta de aplicação
  conciliada_em timestamptz,
  unique (condominio_id, competencia, conta)
);

create table public.movimentos_bancarios (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  conciliacao_id uuid not null references public.conciliacoes_bancarias(id) on delete cascade,
  data_movimento date not null,
  descricao text not null,
  categoria text not null,
  debito_centavos bigint not null default 0 check (debito_centavos >= 0),
  credito_centavos bigint not null default 0 check (credito_centavos >= 0),
  unidade_id uuid references public.unidades(id) on delete set null,
  lancamento_id uuid references public.lancamentos(id) on delete set null, -- vínculo opcional, sem duplicar o livro-caixa
  observacao text,
  check ((debito_centavos > 0) <> (credito_centavos > 0))
);
create index movimentos_bancarios_conc_idx on public.movimentos_bancarios(conciliacao_id, data_movimento);

-- RLS: síndico administra; conselho consulta; morador não acessa estas tabelas.
do $$
declare t text;
begin
  foreach t in array array['previsoes_mensais','rateios_agua','rateios_agua_itens','conciliacoes_bancarias','movimentos_bancarios'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico())', t || '_leitura_equipe', t);
    execute format('create policy %I on public.%I for all to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_admin()) with check (condominio_id = public.meu_condominio_id() and public.equipe_admin())', t || '_admin_escrita', t);
  end loop;
end $$;

comment on table public.conciliacoes_bancarias is 'Mês só deve ser marcado como conciliado quando saldo calculado = saldo do extrato bancário real.';
