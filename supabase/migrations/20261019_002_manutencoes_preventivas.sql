-- V1.4 — calendário de manutenção preventiva.
-- Aplicar após schema.sql e migração V1.3, em ambiente de desenvolvimento.

create type public.status_manutencao as enum ('agendada','em_andamento','concluida','cancelada');

create table public.manutencoes (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  titulo text not null check (length(trim(titulo)) between 3 and 160),
  descricao text,
  categoria text not null default 'Manutenção preventiva',
  proximo_vencimento date not null,
  periodicidade_meses integer not null default 0 check (periodicidade_meses between 0 and 120),
  responsavel text,
  prestador text,
  status public.status_manutencao not null default 'agendada',
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  concluida_em timestamptz,
  cancelada_em timestamptz,
  metadata jsonb not null default '{}'::jsonb
);
create index manutencoes_agenda_idx on public.manutencoes(condominio_id, proximo_vencimento) where status <> 'cancelada';

create table public.execucoes_manutencao (
  id uuid primary key default gen_random_uuid(),
  manutencao_id uuid not null references public.manutencoes(id) on delete restrict,
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  data_execucao date not null,
  registrado_por uuid not null references public.perfis(user_id) on delete restrict,
  observacoes text,
  prestador text,
  lancamento_id uuid references public.lancamentos(id) on delete restrict,
  criado_em timestamptz not null default now()
);
create index execucoes_manutencao_idx on public.execucoes_manutencao(manutencao_id, data_execucao desc);

-- Referências aos anexos privados: o armazenamento e a autorização devem ser implementados no backend.
create table public.anexos_manutencao (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  manutencao_id uuid references public.manutencoes(id) on delete restrict,
  execucao_id uuid references public.execucoes_manutencao(id) on delete restrict,
  storage_path text not null,
  nome_arquivo text not null,
  mime_type text,
  tamanho_bytes bigint check (tamanho_bytes is null or tamanho_bytes >= 0),
  enviado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now(),
  check (manutencao_id is not null or execucao_id is not null)
);

alter table public.manutencoes enable row level security;
alter table public.execucoes_manutencao enable row level security;
alter table public.anexos_manutencao enable row level security;

create policy "manutencoes_select_sindico_conselho" on public.manutencoes
  for select using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
create policy "manutencoes_insert_sindico" on public.manutencoes
  for insert with check (condominio_id = public.meu_condominio_id() and public.equipe_admin() and criado_por = auth.uid());
create policy "manutencoes_update_sindico" on public.manutencoes
  for update using (condominio_id = public.meu_condominio_id() and public.equipe_admin())
  with check (condominio_id = public.meu_condominio_id() and public.equipe_admin());

create policy "execucoes_manutencao_select_sindico_conselho" on public.execucoes_manutencao
  for select using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
create policy "execucoes_manutencao_insert_sindico" on public.execucoes_manutencao
  for insert with check (condominio_id = public.meu_condominio_id() and public.equipe_admin() and registrado_por = auth.uid());

create policy "anexos_manutencao_select_sindico_conselho" on public.anexos_manutencao
  for select using (condominio_id = public.meu_condominio_id() and public.equipe_conselho_ou_sindico());
create policy "anexos_manutencao_insert_sindico" on public.anexos_manutencao
  for insert with check (condominio_id = public.meu_condominio_id() and public.equipe_admin() and enviado_por = auth.uid());

comment on table public.manutencoes is 'Calendário de manutenções preventivas; periodicidade deve ser validada conforme equipamento, fabricante e normas aplicáveis.';
comment on column public.manutencoes.periodicidade_meses is '0 = serviço não recorrente; valores positivos = intervalo em meses, sujeito à validação técnica.';
