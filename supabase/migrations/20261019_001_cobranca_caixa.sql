-- V1.3 — base de dados para cobranças por unidade e integração CAIXA.
-- Aplicar somente depois do schema.sql original, em ambiente de teste.

-- As frações confirmadas possuem sete casas decimais.
alter table public.unidades alter column fracao_ideal type numeric(10,7) using fracao_ideal::numeric(10,7);

create type public.status_cobranca as enum (
  'rascunho', 'pronta_para_emissao', 'enviada', 'registrada',
  'paga', 'vencida', 'cancelamento_solicitado', 'cancelada', 'erro'
);

create table public.cobrancas (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  competencia date not null,
  vencimento date not null,
  valor_total_centavos bigint not null check (valor_total_centavos > 0),
  status public.status_cobranca not null default 'rascunho',
  banco_codigo text not null default '104' check (banco_codigo = '104'),
  provedor text not null default 'caixa',
  identificador_externo text,
  nosso_numero text,
  linha_digitavel text,
  codigo_barras text,
  boleto_storage_path text,
  registrado_em timestamptz,
  pago_em timestamptz,
  valor_pago_centavos bigint check (valor_pago_centavos is null or valor_pago_centavos >= 0),
  cancelamento_solicitado_em timestamptz,
  cancelada_em timestamptz,
  erro_codigo text,
  erro_mensagem text,
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (unidade_id, competencia),
  unique (provedor, identificador_externo),
  check ((status <> 'paga') or pago_em is not null)
);
create index cobrancas_condominio_competencia_idx on public.cobrancas(condominio_id, competencia desc);
create index cobrancas_unidade_vencimento_idx on public.cobrancas(unidade_id, vencimento desc);

create table public.itens_cobranca (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references public.cobrancas(id) on delete restrict,
  tipo text not null check (tipo in ('cota_condominial','agua','rateio','multa','juros','desconto','outro')),
  descricao text not null,
  valor_centavos bigint not null check (valor_centavos <> 0),
  lancamento_id uuid references public.lancamentos(id) on delete restrict,
  rateio_id uuid,
  criado_em timestamptz not null default now(),
  check (lancamento_id is null or rateio_id is null)
);
create index itens_cobranca_cobranca_idx on public.itens_cobranca(cobranca_id);

-- Armazena metadados de integração, nunca senha/chave privada/token bancário.
create table public.configuracao_cobranca_caixa (
  condominio_id uuid primary key references public.condominios(id) on delete restrict,
  habilitada boolean not null default false,
  ambiente text not null default 'homologacao' check (ambiente in ('homologacao','producao')),
  modalidade text,
  codigo_beneficiario text,
  carteira text,
  padrao_remessa text check (padrao_remessa is null or padrao_remessa in ('CNAB240','CNAB400','WEBSERVICE_XML')),
  versao_manual text,
  homologada_em timestamptz,
  atualizada_por uuid references public.perfis(user_id),
  atualizada_em timestamptz not null default now()
);

create table public.eventos_cobranca_bancaria (
  id bigint generated always as identity primary key,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  cobranca_id uuid references public.cobrancas(id) on delete restrict,
  provedor text not null default 'caixa',
  tipo_evento text not null,
  chave_idempotencia text not null,
  codigo_retorno text,
  resumo_retorno text,
  payload_redigido jsonb,
  recebido_em timestamptz not null default now(),
  processado_em timestamptz,
  unique (provedor, chave_idempotencia)
);
create index eventos_cobranca_data_idx on public.eventos_cobranca_bancaria(condominio_id, recebido_em desc);

-- RLS: síndico administra; conselho consulta; morador vê somente cobranças da(s) própria(s) unidade(s).
alter table public.cobrancas enable row level security;
alter table public.itens_cobranca enable row level security;
alter table public.configuracao_cobranca_caixa enable row level security;
alter table public.eventos_cobranca_bancaria enable row level security;

create policy cobrancas_leitura_perfil on public.cobrancas
for select to authenticated using (
  condominio_id = public.meu_condominio_id() and (
    public.meu_papel() in ('sindico','conselho') or
    exists (select 1 from public.vinculos_unidades vu where vu.unidade_id = cobrancas.unidade_id and vu.user_id = auth.uid() and vu.ativo)
  )
);
create policy cobrancas_admin_insert on public.cobrancas
for insert to authenticated with check (
  condominio_id = public.meu_condominio_id() and public.equipe_admin()
);
create policy cobrancas_admin_update on public.cobrancas
for update to authenticated using (
  condominio_id = public.meu_condominio_id() and public.equipe_admin()
) with check (
  condominio_id = public.meu_condominio_id() and public.equipe_admin()
);

create policy itens_cobranca_leitura_perfil on public.itens_cobranca
for select to authenticated using (
  exists (select 1 from public.cobrancas c where c.id = itens_cobranca.cobranca_id and c.condominio_id = public.meu_condominio_id() and (
    public.meu_papel() in ('sindico','conselho') or
    exists (select 1 from public.vinculos_unidades vu where vu.unidade_id = c.unidade_id and vu.user_id = auth.uid() and vu.ativo)
  ))
);
create policy itens_cobranca_admin_write on public.itens_cobranca
for all to authenticated using (
  public.equipe_admin() and exists (select 1 from public.cobrancas c where c.id = itens_cobranca.cobranca_id and c.condominio_id = public.meu_condominio_id())
) with check (
  public.equipe_admin() and exists (select 1 from public.cobrancas c where c.id = itens_cobranca.cobranca_id and c.condominio_id = public.meu_condominio_id())
);

create policy config_caixa_sindico_select on public.configuracao_cobranca_caixa
for select to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_admin());
create policy config_caixa_sindico_write on public.configuracao_cobranca_caixa
for all to authenticated using (condominio_id = public.meu_condominio_id() and public.equipe_admin())
with check (condominio_id = public.meu_condominio_id() and public.equipe_admin());

create policy eventos_caixa_consulta_equipe on public.eventos_cobranca_bancaria
for select to authenticated using (condominio_id = public.meu_condominio_id() and public.meu_papel() in ('sindico','conselho'));
-- Inserção de eventos fica reservada ao backend usando credencial de servidor; não criar policy para cliente.

comment on table public.cobrancas is 'Um boleto por unidade e competência; não marcar pago sem confirmação bancária confiável.';
comment on table public.eventos_cobranca_bancaria is 'Log idempotente e auditável de comunicação com a CAIXA; payload deve ser redigido para não armazenar segredos ou dados excessivos.';
