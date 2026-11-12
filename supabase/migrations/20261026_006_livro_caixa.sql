-- V1.10 — Livro-caixa: registro e estorno por funções, lançamentos imutáveis, relatório mensal.
-- Pré-requisito: schema.sql e migrações 001–005.
-- Regras (especificação): valor em centavos; correções só por estorno auditável; conselho consulta detalhe;
-- morador vê apenas totais; nada é apagado nem alterado depois de registrado.

-- ---------------------------------------------------------------------------------------
-- 1. Endurecimento geral de permissões (vale para TODAS as tabelas do app)
--    O Supabase concede privilégios amplos por padrão a anon/authenticated; o acesso real deve
--    vir só das policies (RLS) e das funções. Retiramos o que o app nunca usa.
-- ---------------------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
alter default privileges in schema public revoke all on tables from anon;

-- ---------------------------------------------------------------------------------------
-- 2. Lançamentos: o navegador só lê. Escrita somente pelas funções abaixo.
-- ---------------------------------------------------------------------------------------
drop policy if exists "lancamentos_insert_sindico" on public.lancamentos;
drop policy if exists "lancamentos_update_sindico" on public.lancamentos;
revoke insert, update, delete on public.lancamentos from authenticated;

-- Defesa em profundidade: mesmo quem tem acesso direto ao banco não altera nem apaga lançamentos.
-- Única alteração permitida: marcar o lançamento como estornado (uma vez).
create or replace function public.proteger_lancamento() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Lançamentos não podem ser apagados; use o estorno';
  end if;
  if old.estornado_em is not null then
    raise exception 'Lançamento já estornado não pode ser alterado';
  end if;
  if new.estornado_em is null or new.estornado_por is null or new.motivo_estorno is null
     or (to_jsonb(new) - 'estornado_em' - 'estornado_por' - 'motivo_estorno')
        is distinct from (to_jsonb(old) - 'estornado_em' - 'estornado_por' - 'motivo_estorno') then
    raise exception 'Lançamentos não podem ser alterados; use o estorno';
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_lancamento on public.lancamentos;
create trigger trg_proteger_lancamento before update or delete on public.lancamentos
  for each row execute function public.proteger_lancamento();

-- ---------------------------------------------------------------------------------------
-- 3. Registrar lançamento (síndico)
-- ---------------------------------------------------------------------------------------
create or replace function public.registrar_lancamento(
  p_tipo text,
  p_data date,
  p_valor_centavos bigint,
  p_categoria text,
  p_descricao text,
  p_fornecedor text default null,
  p_numero_documento text default null,
  p_observacao text default null,
  p_competencia date default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_cond uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_desc text := trim(coalesce(p_descricao, '')); v_cat text := trim(coalesce(p_categoria, ''));
  v_forn text := nullif(trim(coalesce(p_fornecedor, '')), ''); v_doc text := nullif(trim(coalesce(p_numero_documento, '')), '');
  v_obs text := nullif(trim(coalesce(p_observacao, '')), ''); v_comp date; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode registrar lançamentos'; end if;
  v_cond := public.meu_condominio_id();
  if p_tipo is null or p_tipo not in ('receita', 'despesa') then raise exception 'Tipo deve ser receita ou despesa'; end if;
  if p_valor_centavos is null or p_valor_centavos <= 0 then raise exception 'O valor deve ser maior que zero'; end if;
  if p_valor_centavos > 1000000000 then raise exception 'Valor acima do limite de R$ 10.000.000,00'; end if;
  if p_data is null then raise exception 'Informe a data'; end if;
  if p_data > v_hoje then raise exception 'A data não pode ser futura'; end if;
  if p_data < v_hoje - 1830 then raise exception 'A data não pode ter mais de 5 anos'; end if;
  if v_desc = '' or char_length(v_desc) > 120 then raise exception 'Descrição deve ter de 1 a 120 caracteres'; end if;
  if v_cat = '' or char_length(v_cat) > 60 then raise exception 'Categoria deve ter de 1 a 60 caracteres'; end if;
  if char_length(coalesce(v_forn, '')) > 120 then raise exception 'Fornecedor deve ter até 120 caracteres'; end if;
  if char_length(coalesce(v_doc, '')) > 60 then raise exception 'Número do documento deve ter até 60 caracteres'; end if;
  if char_length(coalesce(v_obs, '')) > 300 then raise exception 'Observação deve ter até 300 caracteres'; end if;
  v_comp := date_trunc('month', coalesce(p_competencia, p_data))::date;

  -- proteção contra toque duplo no celular
  if exists (
    select 1 from public.lancamentos l
     where l.condominio_id = v_cond and l.criado_por = auth.uid() and l.tipo::text = p_tipo
       and l.data_lancamento = p_data and l.valor_centavos = p_valor_centavos and l.descricao = v_desc
       and coalesce(l.numero_documento, '') = coalesce(v_doc, '') and l.criado_em > now() - interval '2 minutes'
  ) then raise exception 'Lançamento idêntico acabou de ser registrado'; end if;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria,
                                  descricao, fornecedor, numero_documento, observacao, criado_por)
  values (v_cond, p_tipo::public.tipo_lancamento, p_data, v_comp, p_valor_centavos, v_cat, v_desc, v_forn, v_doc, v_obs, auth.uid())
  returning id into v_id;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'registrar_lancamento', 'lancamentos', v_id,
          jsonb_build_object('tipo', p_tipo, 'valor_centavos', p_valor_centavos, 'data', p_data, 'categoria', v_cat));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------
-- 4. Estornar lançamento (síndico): cria lançamento de estorno na data de hoje e marca o original.
--    O mês do original NÃO muda; a correção aparece no mês em que foi feita.
-- ---------------------------------------------------------------------------------------
create or replace function public.estornar_lancamento(p_id uuid, p_motivo text) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_cond uuid; o public.lancamentos%rowtype; v_motivo text := trim(coalesce(p_motivo, ''));
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_admin() then raise exception 'Apenas o síndico pode estornar lançamentos'; end if;
  v_cond := public.meu_condominio_id();
  if char_length(v_motivo) < 5 or char_length(v_motivo) > 200 then raise exception 'Informe o motivo do estorno (5 a 200 caracteres)'; end if;
  select * into o from public.lancamentos where id = p_id and condominio_id = v_cond for update;
  if not found then raise exception 'Lançamento não encontrado'; end if;
  if o.tipo = 'estorno' then raise exception 'Um estorno não pode ser estornado'; end if;
  if o.estornado_em is not null then raise exception 'Este lançamento já foi estornado'; end if;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao,
                                  fornecedor, numero_documento, observacao, lancamento_original_id, criado_por)
  values (v_cond, 'estorno', v_hoje, date_trunc('month', v_hoje)::date, o.valor_centavos, o.categoria,
          left('Estorno: ' || o.descricao, 120), o.fornecedor, o.numero_documento, v_motivo, o.id, auth.uid())
  returning id into v_id;

  update public.lancamentos set estornado_em = now(), estornado_por = auth.uid(), motivo_estorno = v_motivo where id = o.id;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, registro_id, detalhes)
  values (v_cond, auth.uid(), 'estornar_lancamento', 'lancamentos', o.id,
          jsonb_build_object('estorno_id', v_id, 'valor_centavos', o.valor_centavos, 'motivo', v_motivo));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------
-- 5. Totais. Convenção de caixa: entradas = receitas + estornos de despesas; saídas = despesas + estornos de receitas.
--    Cada lançamento conta no mês da sua própria data (o estorno não reescreve um mês já fechado).
--    CORRIGE a versão do schema.sql, que excluía o lançamento original estornado E somava o estorno (contava em dobro).
-- ---------------------------------------------------------------------------------------
create or replace function public.resumo_financeiro(p_ano integer, p_mes integer)
returns table(receitas_centavos bigint, despesas_centavos bigint, saldo_centavos bigint)
language plpgsql stable security definer set search_path = public
as $$
declare v_cond uuid; v_ini date;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  v_cond := public.meu_condominio_id();
  if v_cond is null then raise exception 'Usuário sem vínculo ativo com condomínio'; end if;
  if p_ano is null or p_mes is null or p_mes < 1 or p_mes > 12 or p_ano < 2000 or p_ano > 2200 then raise exception 'Período inválido'; end if;
  v_ini := make_date(p_ano, p_mes, 1);
  return query
  select e.inc, e.sai, e.inc - e.sai from (
    select
      coalesce(sum(case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos end), 0)::bigint as inc,
      coalesce(sum(case when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then l.valor_centavos end), 0)::bigint as sai
    from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
    where l.condominio_id = v_cond and l.data_lancamento >= v_ini and l.data_lancamento < (v_ini + interval '1 month')::date
  ) e;
end $$;

-- Relatório mensal detalhado (síndico e conselho): totais, saldo anterior e resultado por categoria.
create or replace function public.relatorio_mensal(p_ano integer, p_mes integer) returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v_cond uuid; v_ini date; v_fim date; v_res jsonb;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
  if not public.equipe_conselho_ou_sindico() then raise exception 'Relatório detalhado restrito ao síndico e ao conselho'; end if;
  v_cond := public.meu_condominio_id();
  if p_ano is null or p_mes is null or p_mes < 1 or p_mes > 12 or p_ano < 2000 or p_ano > 2200 then raise exception 'Período inválido'; end if;
  v_ini := make_date(p_ano, p_mes, 1); v_fim := (v_ini + interval '1 month')::date;
  with mov as (
    select l.data_lancamento as data, l.categoria as cat,
           case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos else 0 end as entrada,
           case when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then l.valor_centavos else 0 end as saida
      from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id
     where l.condominio_id = v_cond and l.data_lancamento < v_fim
  ), ant as (
    select coalesce(sum(entrada - saida), 0)::bigint as v from mov where data < v_ini
  ), tot as (
    select coalesce(sum(entrada), 0)::bigint as e, coalesce(sum(saida), 0)::bigint as s, count(*)::int as q from mov where data >= v_ini
  ), cats as (
    select coalesce(jsonb_agg(jsonb_build_object('categoria', c.cat, 'entradas_centavos', c.e, 'saidas_centavos', c.s) order by c.cat), '[]'::jsonb) as j
      from (select cat, sum(entrada)::bigint as e, sum(saida)::bigint as s from mov where data >= v_ini group by cat) c
  )
  select jsonb_build_object('ano', p_ano, 'mes', p_mes, 'saldo_anterior_centavos', ant.v,
           'entradas_centavos', tot.e, 'saidas_centavos', tot.s, 'saldo_mes_centavos', tot.e - tot.s,
           'saldo_final_centavos', ant.v + tot.e - tot.s, 'quantidade', tot.q, 'por_categoria', cats.j)
    into v_res from ant, tot, cats;
  return v_res;
end $$;

revoke all on function public.registrar_lancamento(text, date, bigint, text, text, text, text, text, date) from public, anon;
revoke all on function public.estornar_lancamento(uuid, text) from public, anon;
revoke all on function public.relatorio_mensal(integer, integer) from public, anon;
revoke all on function public.resumo_financeiro(integer, integer) from public, anon;
grant execute on function public.registrar_lancamento(text, date, bigint, text, text, text, text, text, date) to authenticated;
grant execute on function public.estornar_lancamento(uuid, text) to authenticated;
grant execute on function public.relatorio_mensal(integer, integer) to authenticated;
grant execute on function public.resumo_financeiro(integer, integer) to authenticated;
