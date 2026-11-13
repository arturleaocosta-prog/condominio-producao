-- V1.16 — Dashboard financeiro (conciliação bancária por exercício), no modelo da planilha "Dashboard".
-- Regras:
--   · só o SÍNDICO cria, edita e exclui um dashboard e informa o saldo do extrato de cada mês;
--   · CONSELHO vê todos; MORADOR vê os marcados como visíveis para moradores (só totais mensais, como no resumo do Financeiro);
--   · os números vêm do livro-caixa (lancamentos), com a mesma regra do relatório mensal (saldo de abertura e estornos);
--   · status do mês: "conciliado" quando o saldo do extrato informado é igual ao saldo calculado; "divergente" quando difere;
--     "pendente" sem extrato. É recalculado a cada consulta: um lançamento novo no mês desfaz a conciliação.
-- Aplicar depois das migrações 001 a 010.

create table public.dashboards_financeiros (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references public.condominios(id) on delete restrict,
  titulo text not null check (length(trim(titulo)) between 1 and 120),
  mes_inicio date not null check (mes_inicio = date_trunc('month', mes_inicio)::date),
  mes_fim date not null check (mes_fim = date_trunc('month', mes_fim)::date),
  visivel_moradores boolean not null default true,
  observacao text check (observacao is null or length(observacao) <= 500),
  criado_por uuid not null references public.perfis(user_id) on delete restrict,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (mes_fim >= mes_inicio and mes_fim < (mes_inicio + interval '24 months')::date),
  unique (condominio_id, mes_inicio, mes_fim)
);

alter table public.dashboards_financeiros enable row level security;
-- leitura: equipe vê todos; morador só os visíveis. Escrita: só pelas funções abaixo (sem policy de escrita).
create policy dashboards_leitura on public.dashboards_financeiros for select to authenticated
  using (condominio_id = public.meu_condominio_id() and (public.equipe_conselho_ou_sindico() or visivel_moradores));

-- ---------------------------------------------------------------------------------------
-- Saldos mês a mês de um condomínio (uso interno; não exposto aos clientes).
-- Mesma regra de public.relatorio_mensal: antes da abertura o saldo anterior é 0; estorno inverte o original.
-- ---------------------------------------------------------------------------------------
create or replace function public.saldos_mensais_condominio(p_cond uuid, p_ini date, p_fim date)
returns table(mes date, saldo_inicial_centavos bigint, entradas_centavos bigint, saidas_centavos bigint,
              saldo_final_centavos bigint, quantidade int)
language plpgsql stable security definer set search_path = public as $$
declare v_ab bigint; v_ab_data date;
begin
  select c.saldo_inicial_centavos, c.saldo_inicial_data into v_ab, v_ab_data from public.condominios c where c.id = p_cond;
  return query
  with mov as (
    select l.data_lancamento as data,
           case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos else 0 end as entrada,
           case when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then l.valor_centavos else 0 end as saida
      from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
     where l.condominio_id = p_cond and l.data_lancamento < (p_fim + interval '1 month')::date
       and (v_ab_data is null or l.data_lancamento >= v_ab_data)
  ), meses as (
    select gs::date as m from generate_series(p_ini, p_fim, interval '1 month') gs
  ), calc as (
    select ms.m,
           (case when v_ab_data is not null and ms.m < v_ab_data then 0
                 else (case when v_ab_data is null then 0 else v_ab end)
                      + coalesce((select sum(x.entrada - x.saida) from mov x where x.data < ms.m), 0) end)::bigint as ini,
           coalesce((select sum(x.entrada) from mov x where x.data >= ms.m and x.data < (ms.m + interval '1 month')::date), 0)::bigint as e,
           coalesce((select sum(x.saida) from mov x where x.data >= ms.m and x.data < (ms.m + interval '1 month')::date), 0)::bigint as s,
           (select count(*) from mov x where x.data >= ms.m and x.data < (ms.m + interval '1 month')::date)::int as q
      from meses ms
  )
  select c.m, c.ini, c.e, c.s, c.ini + c.e - c.s, c.q from calc c order by c.m;
end $$;
revoke all on function public.saldos_mensais_condominio(uuid, date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- Consulta do dashboard (síndico, conselho e, se visível, morador).
-- ---------------------------------------------------------------------------------------
create or replace function public.dashboard_financeiro(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cond uuid; d public.dashboards_financeiros%rowtype; v_meses jsonb; v_tot jsonb;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  v_cond := public.meu_condominio_id();
  if v_cond is null then raise exception 'Perfil inativo'; end if;
  select * into d from public.dashboards_financeiros where id = p_id and condominio_id = v_cond;
  if not found or (not public.equipe_conselho_ou_sindico() and not d.visivel_moradores) then
    raise exception 'Dashboard não encontrado'; end if;

  with s as (
    select x.*, cb.saldo_extrato_centavos as extrato
      from public.saldos_mensais_condominio(v_cond, d.mes_inicio, d.mes_fim) x
      left join public.conciliacoes_bancarias cb
        on cb.condominio_id = v_cond and cb.conta = 'corrente' and cb.competencia = x.mes
  ), st as (
    select s.*, case when s.extrato is null then 'pendente' when s.extrato = s.saldo_final_centavos then 'conciliado' else 'divergente' end as status
      from s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'mes', to_char(st.mes, 'YYYY-MM'), 'saldo_inicial_centavos', st.saldo_inicial_centavos,
           'entradas_centavos', st.entradas_centavos, 'saidas_centavos', st.saidas_centavos,
           'saldo_final_centavos', st.saldo_final_centavos, 'quantidade', st.quantidade,
           'saldo_extrato_centavos', st.extrato, 'status', st.status) order by st.mes), '[]'::jsonb),
         jsonb_build_object('entradas_centavos', coalesce(sum(st.entradas_centavos), 0), 'saidas_centavos', coalesce(sum(st.saidas_centavos), 0),
           'resultado_centavos', coalesce(sum(st.entradas_centavos - st.saidas_centavos), 0),
           'conciliados', count(*) filter (where st.status = 'conciliado'), 'meses', count(*))
    into v_meses, v_tot from st;

  return jsonb_build_object('id', d.id, 'titulo', d.titulo, 'mes_inicio', to_char(d.mes_inicio, 'YYYY-MM'), 'mes_fim', to_char(d.mes_fim, 'YYYY-MM'),
    'visivel_moradores', d.visivel_moradores, 'observacao', d.observacao, 'atualizado_em', d.atualizado_em,
    'meses', v_meses, 'totais', v_tot);
end $$;
revoke all on function public.dashboard_financeiro(uuid) from public, anon;
grant execute on function public.dashboard_financeiro(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------
-- Criar / editar (síndico). p_id nulo cria.
-- ---------------------------------------------------------------------------------------
create or replace function public.salvar_dashboard_financeiro(
  p_id uuid, p_titulo text, p_mes_inicio date, p_mes_fim date, p_visivel_moradores boolean default true, p_observacao text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_id uuid; v_ini date; v_fim date; v_tit text := trim(coalesce(p_titulo, ''));
        v_obs text := nullif(trim(coalesce(p_observacao, '')), '');
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Só o síndico pode criar ou editar o dashboard'; end if;
  v_cond := public.meu_condominio_id();
  if v_tit = '' or char_length(v_tit) > 120 then raise exception 'Título deve ter de 1 a 120 caracteres'; end if;
  if p_mes_inicio is null or p_mes_fim is null then raise exception 'Informe o mês inicial e o mês final'; end if;
  v_ini := date_trunc('month', p_mes_inicio)::date; v_fim := date_trunc('month', p_mes_fim)::date;
  if v_fim < v_ini then raise exception 'O mês final deve ser igual ou posterior ao inicial'; end if;
  if v_fim >= (v_ini + interval '24 months')::date then raise exception 'O período pode ter no máximo 24 meses'; end if;
  if v_obs is not null and char_length(v_obs) > 500 then raise exception 'Observação com mais de 500 caracteres'; end if;
  if exists (select 1 from public.dashboards_financeiros where condominio_id = v_cond and mes_inicio = v_ini and mes_fim = v_fim and id is distinct from p_id) then
    raise exception 'Já existe um dashboard para este período'; end if;

  if p_id is null then
    insert into public.dashboards_financeiros (condominio_id, titulo, mes_inicio, mes_fim, visivel_moradores, observacao, criado_por)
      values (v_cond, v_tit, v_ini, v_fim, coalesce(p_visivel_moradores, true), v_obs, v_user) returning id into v_id;
  else
    update public.dashboards_financeiros
       set titulo = v_tit, mes_inicio = v_ini, mes_fim = v_fim, visivel_moradores = coalesce(p_visivel_moradores, true),
           observacao = v_obs, atualizado_em = now()
     where id = p_id and condominio_id = v_cond returning id into v_id;
    if v_id is null then raise exception 'Dashboard não encontrado'; end if;
  end if;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, case when p_id is null then 'dashboard.criar' else 'dashboard.editar' end, 'dashboards_financeiros', v_id,
            jsonb_build_object('titulo', v_tit, 'mes_inicio', v_ini, 'mes_fim', v_fim, 'visivel_moradores', coalesce(p_visivel_moradores, true)));
  return v_id;
end $$;
revoke all on function public.salvar_dashboard_financeiro(uuid, text, date, date, boolean, text) from public, anon;
grant execute on function public.salvar_dashboard_financeiro(uuid, text, date, date, boolean, text) to authenticated;

create or replace function public.excluir_dashboard_financeiro(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_tit text;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Só o síndico pode excluir o dashboard'; end if;
  v_cond := public.meu_condominio_id();
  delete from public.dashboards_financeiros where id = p_id and condominio_id = v_cond returning titulo into v_tit;
  if v_tit is null then raise exception 'Dashboard não encontrado'; end if;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
    values (v_cond, v_user, 'dashboard.excluir', 'dashboards_financeiros', p_id, jsonb_build_object('titulo', v_tit));
end $$;
revoke all on function public.excluir_dashboard_financeiro(uuid) from public, anon;
grant execute on function public.excluir_dashboard_financeiro(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------
-- Saldo do extrato bancário do mês (síndico). Nulo apaga o saldo informado (volta a "pendente").
-- Devolve o status com o saldo calculado do livro-caixa naquele momento.
-- ---------------------------------------------------------------------------------------
create or replace function public.registrar_saldo_extrato(p_competencia date, p_saldo_extrato_centavos bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cond uuid; v_user uuid := auth.uid(); v_m date; r record; v_status text;
begin
  if v_user is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Só o síndico pode informar o saldo do extrato'; end if;
  v_cond := public.meu_condominio_id();
  if p_competencia is null then raise exception 'Informe o mês'; end if;
  v_m := date_trunc('month', p_competencia)::date;
  if v_m > date_trunc('month', (now() at time zone 'America/Sao_Paulo'))::date then raise exception 'Não é possível conciliar um mês futuro'; end if;
  select * into r from public.saldos_mensais_condominio(v_cond, v_m, v_m);
  if p_saldo_extrato_centavos is null then
    update public.conciliacoes_bancarias set saldo_extrato_centavos = null, conciliada_em = null, saldo_inicial_centavos = r.saldo_inicial_centavos
     where condominio_id = v_cond and conta = 'corrente' and competencia = v_m;
    v_status := 'pendente';
  else
    insert into public.conciliacoes_bancarias (condominio_id, competencia, conta, saldo_inicial_centavos, saldo_extrato_centavos, conciliada_em)
      values (v_cond, v_m, 'corrente', r.saldo_inicial_centavos, p_saldo_extrato_centavos,
              case when p_saldo_extrato_centavos = r.saldo_final_centavos then now() end)
    on conflict (condominio_id, competencia, conta) do update
      set saldo_inicial_centavos = excluded.saldo_inicial_centavos, saldo_extrato_centavos = excluded.saldo_extrato_centavos,
          conciliada_em = excluded.conciliada_em;
    v_status := case when p_saldo_extrato_centavos = r.saldo_final_centavos then 'conciliado' else 'divergente' end;
  end if;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
    values (v_cond, v_user, 'conciliacao.saldo_extrato', 'conciliacoes_bancarias',
            jsonb_build_object('competencia', v_m, 'saldo_extrato_centavos', p_saldo_extrato_centavos, 'saldo_calculado_centavos', r.saldo_final_centavos, 'status', v_status));
  return jsonb_build_object('mes', to_char(v_m, 'YYYY-MM'), 'status', v_status, 'saldo_calculado_centavos', r.saldo_final_centavos,
                            'saldo_extrato_centavos', p_saldo_extrato_centavos,
                            'diferenca_centavos', case when p_saldo_extrato_centavos is null then null else r.saldo_final_centavos - p_saldo_extrato_centavos end);
end $$;
revoke all on function public.registrar_saldo_extrato(date, bigint) from public, anon;
grant execute on function public.registrar_saldo_extrato(date, bigint) to authenticated;
