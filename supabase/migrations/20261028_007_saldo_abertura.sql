-- V1.11 — Saldo de abertura do livro-caixa.
-- Antes: o "saldo acumulado" somava só os lançamentos feitos no app (sem saldo inicial).
-- Agora: saldo acumulado = saldo de abertura (na data de abertura) + entradas − saídas desde essa data.
-- Pré-requisito: migrações 001–006.

alter table public.condominios add column if not exists saldo_inicial_centavos bigint not null default 0;
alter table public.condominios add column if not exists saldo_inicial_data date;
alter table public.condominios drop constraint if exists condominios_saldo_inicial_data_chk;
alter table public.condominios add constraint condominios_saldo_inicial_data_chk
  check (saldo_inicial_data is null or saldo_inicial_data = date_trunc('month', saldo_inicial_data)::date);  -- sempre dia 1º
alter table public.condominios drop constraint if exists condominios_saldo_inicial_limite_chk;
alter table public.condominios add constraint condominios_saldo_inicial_limite_chk
  check (saldo_inicial_centavos between -100000000000 and 100000000000);

-- O saldo de abertura só pode ser alterado pela função definir_saldo_abertura (auditada), nunca por UPDATE direto.
revoke update on public.condominios from authenticated;
grant update (nome, endereco, fuso_horario) on public.condominios to authenticated;

-- ---------------------------------------------------------------------------------------
-- Lançamentos não podem ter data anterior ao saldo de abertura (seriam ignorados no saldo).
-- Vale para qualquer inserção (app ou importação); estornos têm a data de hoje e passam.
-- ---------------------------------------------------------------------------------------
create or replace function public.validar_data_lancamento() returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_data date;
begin
  if new.tipo <> 'estorno' then
    select saldo_inicial_data into v_data from public.condominios where id = new.condominio_id;
    if v_data is not null and new.data_lancamento < v_data then
      raise exception 'A data não pode ser anterior ao saldo de abertura (%)', to_char(v_data, 'DD/MM/YYYY');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_validar_data_lancamento on public.lancamentos;
create trigger trg_validar_data_lancamento before insert on public.lancamentos
  for each row execute function public.validar_data_lancamento();

-- ---------------------------------------------------------------------------------------
-- Definir/alterar o saldo de abertura pelo app (síndico). Auditado.
-- ---------------------------------------------------------------------------------------
create or replace function public.definir_saldo_abertura(p_data date, p_valor_centavos bigint) returns void
language plpgsql security definer set search_path = public
as $$
declare v_cond uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode definir o saldo de abertura'; end if;
  v_cond := public.meu_condominio_id();
  if p_data is null or p_data <> date_trunc('month', p_data)::date then raise exception 'A data do saldo de abertura deve ser o dia 1º de um mês'; end if;
  if p_valor_centavos is null or p_valor_centavos not between -100000000000 and 100000000000 then raise exception 'Valor inválido'; end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond and tipo <> 'estorno' and data_lancamento < p_data) then
    raise exception 'Existem lançamentos anteriores a essa data; escolha uma data igual ou anterior ao primeiro lançamento';
  end if;
  update public.condominios set saldo_inicial_centavos = p_valor_centavos, saldo_inicial_data = p_data where id = v_cond;
  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'definir_saldo_abertura', 'condominios', v_cond,
          jsonb_build_object('data', p_data, 'valor_centavos', p_valor_centavos));
end $$;
revoke all on function public.definir_saldo_abertura(date, bigint) from public, anon;
grant execute on function public.definir_saldo_abertura(date, bigint) to authenticated;

-- ---------------------------------------------------------------------------------------
-- Relatório mensal passa a considerar o saldo de abertura.
--   mês anterior à abertura: saldo anterior = 0; mês da abertura: saldo anterior = saldo de abertura.
-- ---------------------------------------------------------------------------------------
create or replace function public.relatorio_mensal(p_ano integer, p_mes integer) returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v_cond uuid; v_ini date; v_fim date; v_res jsonb; v_ab bigint; v_ab_data date;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_conselho_ou_sindico() then raise exception 'Relatório detalhado restrito ao síndico e ao conselho'; end if;
  v_cond := public.meu_condominio_id();
  if p_ano is null or p_mes is null or p_mes < 1 or p_mes > 12 or p_ano < 2000 or p_ano > 2200 then raise exception 'Período inválido'; end if;
  v_ini := make_date(p_ano, p_mes, 1); v_fim := (v_ini + interval '1 month')::date;
  select saldo_inicial_centavos, saldo_inicial_data into v_ab, v_ab_data from public.condominios where id = v_cond;
  with mov as (
    select l.data_lancamento as data, l.categoria as cat,
           case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos else 0 end as entrada,
           case when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then l.valor_centavos else 0 end as saida
      from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
     where l.condominio_id = v_cond and l.data_lancamento < v_fim
       and (v_ab_data is null or l.data_lancamento >= v_ab_data)
  ), ant as (
    select case when v_ab_data is not null and v_ini < v_ab_data then 0
                else (case when v_ab_data is null then 0 else v_ab end) + coalesce((select sum(entrada - saida) from mov where data < v_ini), 0) end::bigint as v
  ), tot as (
    select coalesce(sum(entrada), 0)::bigint as e, coalesce(sum(saida), 0)::bigint as s, count(*)::int as q from mov where data >= v_ini
  ), cats as (
    select coalesce(jsonb_agg(jsonb_build_object('categoria', c.cat, 'entradas_centavos', c.e, 'saidas_centavos', c.s) order by c.cat), '[]'::jsonb) as j
      from (select cat, sum(entrada)::bigint as e, sum(saida)::bigint as s from mov where data >= v_ini group by cat) c
  )
  select jsonb_build_object('ano', p_ano, 'mes', p_mes, 'saldo_anterior_centavos', ant.v,
           'entradas_centavos', tot.e, 'saidas_centavos', tot.s, 'saldo_mes_centavos', tot.e - tot.s,
           'saldo_final_centavos', ant.v + tot.e - tot.s, 'quantidade', tot.q, 'por_categoria', cats.j,
           'saldo_abertura_centavos', case when v_ab_data is null then null else v_ab end, 'saldo_abertura_data', v_ab_data)
    into v_res from ant, tot, cats;
  return v_res;
end $$;
revoke all on function public.relatorio_mensal(integer, integer) from public, anon;
grant execute on function public.relatorio_mensal(integer, integer) to authenticated;
