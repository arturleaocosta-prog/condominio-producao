-- V1.15 — Cobrança por unidade: quem pagou e quem deve.
-- Registra os pagamentos de cada cobrança (baixa), opcionalmente ligados a um crédito do extrato bancário importado.
-- O pagamento NÃO cria lançamento: a receita já entrou no livro-caixa pela importação do extrato (ou por lançamento manual).
-- Pré-requisito: migrações 001–009.

-- ---------------------------------------------------------------------------------------
-- 1. Pagamentos
-- ---------------------------------------------------------------------------------------
create table if not exists public.cobranca_pagamentos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  cobranca_id uuid not null references public.cobrancas(id) on delete restrict,
  data_pagamento date not null,
  valor_centavos bigint not null check (valor_centavos > 0),
  forma text not null check (forma in ('boleto', 'pix', 'transferencia', 'dinheiro', 'outro')),
  extrato_linha_id uuid references public.extrato_linhas(id) on delete restrict,
  observacao text check (observacao is null or char_length(observacao) <= 300),
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now(),
  removido_em timestamptz,
  removido_por uuid references public.perfis(user_id) on delete restrict,
  motivo_remocao text check (motivo_remocao is null or char_length(motivo_remocao) between 5 and 200),
  check ((removido_em is null) = (motivo_remocao is null))
);
create index if not exists cobranca_pagamentos_cobranca_idx on public.cobranca_pagamentos (cobranca_id) where removido_em is null;
create index if not exists cobranca_pagamentos_linha_idx on public.cobranca_pagamentos (extrato_linha_id) where extrato_linha_id is not null and removido_em is null;

alter table public.cobranca_pagamentos enable row level security;
drop policy if exists cobranca_pagamentos_select on public.cobranca_pagamentos;
create policy cobranca_pagamentos_select on public.cobranca_pagamentos for select
  using (condominio_id = public.meu_condominio_id() and (
    public.equipe_conselho_ou_sindico() or exists (
      select 1 from public.cobrancas c join public.vinculos_unidades vu on vu.unidade_id = c.unidade_id and vu.user_id = auth.uid() and vu.ativo
       where c.id = cobranca_pagamentos.cobranca_id)));
revoke all on public.cobranca_pagamentos from anon, authenticated;
grant select on public.cobranca_pagamentos to authenticated;

-- Pagamento registrado não muda nem some: só pode ser "removido" (com motivo) pela função, que preserva o histórico.
create or replace function public.proteger_cobranca_pagamento() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Pagamentos não podem ser apagados; remova com motivo'; end if;
  if current_setting('app.removendo_pagamento', true) = '1' and old.removido_em is null and new.removido_em is not null
     and to_jsonb(new) - 'removido_em' - 'removido_por' - 'motivo_remocao' = to_jsonb(old) - 'removido_em' - 'removido_por' - 'motivo_remocao' then
    return new;
  end if;
  raise exception 'Pagamentos não podem ser alterados; remova com motivo e registre de novo';
end $$;
drop trigger if exists trg_proteger_cobranca_pagamento on public.cobranca_pagamentos;
create trigger trg_proteger_cobranca_pagamento before update or delete on public.cobranca_pagamentos
  for each row execute function public.proteger_cobranca_pagamento();

-- A situação de pagamento da cobrança só muda pelas funções de pagamento (nunca por UPDATE direto).
create or replace function public.proteger_cobranca_situacao_pagamento() returns trigger
language plpgsql as $$
begin
  if ((new.status = 'paga') is distinct from (old.status = 'paga') or new.pago_em is distinct from old.pago_em
      or new.valor_pago_centavos is distinct from old.valor_pago_centavos)
     and coalesce(current_setting('app.pagando', true), '') <> '1' then
    raise exception 'A situação de pagamento só pode ser alterada pelo registro de pagamento (registrar_pagamento_cobranca)';
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_cobranca_pagamento_situacao on public.cobrancas;
create trigger trg_proteger_cobranca_pagamento_situacao before update on public.cobrancas
  for each row execute function public.proteger_cobranca_situacao_pagamento();

-- ---------------------------------------------------------------------------------------
-- 2. Recalcula a situação da cobrança a partir dos pagamentos não removidos
-- ---------------------------------------------------------------------------------------
create or replace function public.recalcular_cobranca_pagamento(p_cobranca_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c public.cobrancas%rowtype; v_soma bigint; v_ultima date;
begin
  select * into c from public.cobrancas where id = p_cobranca_id for update;
  select coalesce(sum(valor_centavos), 0), max(data_pagamento) into v_soma, v_ultima
    from public.cobranca_pagamentos where cobranca_id = p_cobranca_id and removido_em is null;
  perform set_config('app.pagando', '1', true);
  if v_soma >= c.valor_total_centavos then
    update public.cobrancas set status = 'paga', pago_em = (v_ultima::text || ' 12:00:00-03')::timestamptz,
           valor_pago_centavos = v_soma, atualizado_em = now() where id = c.id;
  else
    update public.cobrancas set
           status = case when c.status = 'paga'
                         then (case when c.identificador_externo is not null or c.nosso_numero is not null then 'registrada' else 'pronta_para_emissao' end)::public.status_cobranca
                         else c.status end,
           pago_em = null, valor_pago_centavos = nullif(v_soma, 0), atualizado_em = now() where id = c.id;
  end if;
  perform set_config('app.pagando', '', true);
end $$;
revoke all on function public.recalcular_cobranca_pagamento(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- 3. Registrar e remover pagamento
-- ---------------------------------------------------------------------------------------
create or replace function public.registrar_pagamento_cobranca(
  p_cobranca_id uuid, p_data date, p_valor_centavos bigint, p_forma text,
  p_extrato_linha_id uuid default null, p_observacao text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cond uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; c public.cobrancas%rowtype; l public.extrato_linhas%rowtype;
  v_pago bigint; v_na_linha bigint; v_id uuid; v_novo bigint;
  brl text;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode registrar pagamentos'; end if;
  v_cond := public.meu_condominio_id();
  select * into c from public.cobrancas where id = p_cobranca_id and condominio_id = v_cond for update;
  if not found then raise exception 'Cobrança não encontrada'; end if;
  if c.status::text in ('rascunho', 'cancelada', 'cancelamento_solicitado', 'erro') then
    raise exception 'A cobrança ainda não foi liberada (ou está cancelada); libere o mês antes de registrar pagamentos'; end if;
  if p_data is null or p_data < date '2020-01-01' or p_data > v_hoje then raise exception 'A data do pagamento deve estar entre 2020 e hoje'; end if;
  if p_valor_centavos is null or p_valor_centavos <= 0 then raise exception 'O valor do pagamento deve ser maior que zero'; end if;
  if p_forma is null or p_forma not in ('boleto', 'pix', 'transferencia', 'dinheiro', 'outro') then raise exception 'Forma de pagamento inválida'; end if;
  if char_length(coalesce(p_observacao, '')) > 300 then raise exception 'Observação com até 300 caracteres'; end if;
  select coalesce(sum(valor_centavos), 0) into v_pago from public.cobranca_pagamentos where cobranca_id = c.id and removido_em is null;
  v_novo := v_pago + p_valor_centavos;
  if v_novo > c.valor_total_centavos + c.valor_total_centavos / 2 then
    raise exception 'O total pago (R$ %) passa de 150%% do valor da cobrança (R$ %): confira o valor',
      replace(to_char(v_novo / 100.0, 'FM999999990.00'), '.', ','), replace(to_char(c.valor_total_centavos / 100.0, 'FM999999990.00'), '.', ',');
  end if;
  if p_extrato_linha_id is not null then
    select * into l from public.extrato_linhas where id = p_extrato_linha_id and condominio_id = v_cond for update;
    if not found then raise exception 'Movimento do extrato não encontrado'; end if;
    if l.valor_centavos <= 0 then raise exception 'O movimento do extrato escolhido não é um crédito'; end if;
    if l.status = 'ignorada' then raise exception 'O movimento do extrato escolhido foi ignorado na importação'; end if;
    select coalesce(sum(valor_centavos), 0) into v_na_linha from public.cobranca_pagamentos where extrato_linha_id = l.id and removido_em is null;
    if v_na_linha + p_valor_centavos > l.valor_centavos then
      raise exception 'Este crédito do extrato (R$ %) já tem R$ % baixados; faltam só R$ %',
        replace(to_char(l.valor_centavos / 100.0, 'FM999999990.00'), '.', ','), replace(to_char(v_na_linha / 100.0, 'FM999999990.00'), '.', ','),
        replace(to_char((l.valor_centavos - v_na_linha) / 100.0, 'FM999999990.00'), '.', ',');
    end if;
  end if;
  insert into public.cobranca_pagamentos (condominio_id, cobranca_id, data_pagamento, valor_centavos, forma, extrato_linha_id, observacao, criado_por)
  values (v_cond, c.id, p_data, p_valor_centavos, p_forma, p_extrato_linha_id, nullif(btrim(p_observacao), ''), auth.uid()) returning id into v_id;
  perform public.recalcular_cobranca_pagamento(c.id);
  select * into c from public.cobrancas where id = c.id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'registrar_pagamento_cobranca', 'cobrancas', c.id,
          jsonb_build_object('pagamento_id', v_id, 'valor_centavos', p_valor_centavos, 'forma', p_forma, 'extrato_linha_id', p_extrato_linha_id));
  return jsonb_build_object('pagamento_id', v_id, 'status', c.status, 'pago_centavos', v_novo, 'total_centavos', c.valor_total_centavos,
                            'saldo_centavos', greatest(c.valor_total_centavos - v_novo, 0));
end $$;

create or replace function public.remover_pagamento_cobranca(p_pagamento_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cond uuid; p public.cobranca_pagamentos%rowtype;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode remover pagamentos'; end if;
  v_cond := public.meu_condominio_id();
  if char_length(btrim(coalesce(p_motivo, ''))) not between 5 and 200 then raise exception 'Informe o motivo (5 a 200 caracteres)'; end if;
  select * into p from public.cobranca_pagamentos where id = p_pagamento_id and condominio_id = v_cond and removido_em is null for update;
  if not found then raise exception 'Pagamento não encontrado ou já removido'; end if;
  perform set_config('app.removendo_pagamento', '1', true);
  update public.cobranca_pagamentos set removido_em = now(), removido_por = auth.uid(), motivo_remocao = btrim(p_motivo) where id = p.id;
  perform set_config('app.removendo_pagamento', '', true);
  perform public.recalcular_cobranca_pagamento(p.cobranca_id);
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'remover_pagamento_cobranca', 'cobrancas', p.cobranca_id,
          jsonb_build_object('pagamento_id', p.id, 'valor_centavos', p.valor_centavos, 'motivo', btrim(p_motivo)));
end $$;

-- ---------------------------------------------------------------------------------------
-- 4. Quem deve: cobranças liberadas com saldo em aberto (síndico e conselho)
-- ---------------------------------------------------------------------------------------
create or replace function public.cobrancas_em_aberto() returns table (
  cobranca_id uuid, unidade text, competencia date, vencimento date, total_centavos bigint, pago_centavos bigint, saldo_centavos bigint, dias_atraso integer)
language plpgsql stable security definer set search_path = public as $$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_conselho_ou_sindico() then raise exception 'Restrito ao síndico e ao conselho'; end if;
  return query
    select c.id, u.identificacao::text, c.competencia, c.vencimento, c.valor_total_centavos,
           coalesce(p.pago, 0)::bigint, (c.valor_total_centavos - coalesce(p.pago, 0))::bigint, greatest(v_hoje - c.vencimento, 0)::int
      from public.cobrancas c
      join public.unidades u on u.id = c.unidade_id
      left join lateral (select sum(valor_centavos) as pago from public.cobranca_pagamentos x where x.cobranca_id = c.id and x.removido_em is null) p on true
     where c.condominio_id = public.meu_condominio_id()
       and c.status::text not in ('rascunho', 'cancelada', 'cancelamento_solicitado', 'erro', 'paga')
       and c.valor_total_centavos - coalesce(p.pago, 0) > 0
     order by c.vencimento, u.identificacao;
end $$;

revoke all on function public.registrar_pagamento_cobranca(uuid, date, bigint, text, uuid, text) from public, anon;
revoke all on function public.remover_pagamento_cobranca(uuid, text) from public, anon;
revoke all on function public.cobrancas_em_aberto() from public, anon;
grant execute on function public.registrar_pagamento_cobranca(uuid, date, bigint, text, uuid, text) to authenticated;
grant execute on function public.remover_pagamento_cobranca(uuid, text) to authenticated;
grant execute on function public.cobrancas_em_aberto() to authenticated;

-- ---------------------------------------------------------------------------------------
-- 5. Reabrir o ciclo do mês só sem pagamentos registrados (senão os valores mudariam depois de baixados)
-- ---------------------------------------------------------------------------------------
create or replace function public.reabrir_cobranca_mensal(p_competencia date)
returns void language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_ciclo public.ciclos_cobranca%rowtype;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode reabrir cobranças'; end if;
  v_cond := public.meu_condominio_id();
  select * into v_ciclo from public.ciclos_cobranca where condominio_id = v_cond and competencia = p_competencia for update;
  if not found then raise exception 'Nenhuma cobrança gerada para a competência'; end if;
  if v_ciclo.status <> 'liberado' then raise exception 'Cobranças não estão liberadas'; end if;
  if exists (select 1 from public.cobrancas where ciclo_id = v_ciclo.id and (status <> 'pronta_para_emissao' or identificador_externo is not null or nosso_numero is not null)) then
    raise exception 'Há boleto já enviado ou registrado, ou cobrança já paga: cancele-o no banco antes de reabrir'; end if;
  if exists (select 1 from public.cobranca_pagamentos p join public.cobrancas c on c.id = p.cobranca_id where c.ciclo_id = v_ciclo.id and p.removido_em is null) then
    raise exception 'Há pagamentos registrados nesta competência: remova-os (com motivo) antes de reabrir'; end if;
  update public.cobrancas set status = 'rascunho', atualizado_em = now() where ciclo_id = v_ciclo.id;
  update public.ciclos_cobranca set status = 'gerado', liberado_por = null, liberado_em = null where id = v_ciclo.id;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, 'cobranca_mensal.reabrir', 'ciclos_cobranca', v_ciclo.id, jsonb_build_object('competencia', p_competencia));
end $$;
revoke execute on function public.reabrir_cobranca_mensal(date) from public, anon;
grant execute on function public.reabrir_cobranca_mensal(date) to authenticated;

-- ---------------------------------------------------------------------------------------
-- 6. Morador só enxerga a cobrança da própria unidade DEPOIS de liberada (rascunho, cancelada e erro ficam ocultos)
--    Os itens e os pagamentos herdam essa regra (suas policies consultam cobrancas).
-- ---------------------------------------------------------------------------------------
drop policy if exists cobrancas_leitura_perfil on public.cobrancas;
create policy cobrancas_leitura_perfil on public.cobrancas for select using (
  condominio_id = public.meu_condominio_id() and (
    public.meu_papel() in ('sindico', 'conselho') or (
      status::text not in ('rascunho', 'cancelada', 'cancelamento_solicitado', 'erro')
      and exists (select 1 from public.vinculos_unidades vu where vu.unidade_id = cobrancas.unidade_id and vu.user_id = auth.uid() and vu.ativo))));
