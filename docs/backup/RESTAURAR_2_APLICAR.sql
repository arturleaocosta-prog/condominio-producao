-- RESTAURAR 2 de 2 — valida o CSV importado e grava os lançamentos. Uma única transação: se algo não bater, nada é gravado.
-- Rode só depois de importar o CSV na tabela lancamentos_restauracao. Os lançamentos voltam com os mesmos códigos, datas, valores e estornos.
do $rest$
declare
  v_cond uuid; v_user uuid; v_nome text; v_n int; v_linhas int; v_saldo_esp bigint; v_ab bigint; v_ab_data date; v_saldo bigint;
begin
  select count(*) into v_n from public.lancamentos_restauracao;
  if v_n = 0 then raise exception 'A tabela lancamentos_restauracao está vazia: importe o CSV antes'; end if;
  if (select count(distinct condominio_nome) from public.lancamentos_restauracao) <> 1 then raise exception 'O CSV mistura condomínios ou está corrompido'; end if;
  select condominio_nome into v_nome from public.lancamentos_restauracao limit 1;
  select id into v_cond from public.condominios where nome = v_nome;
  if v_cond is null then raise exception 'Condomínio "%" não existe neste projeto; crie-o antes (roteiro de produção)', v_nome; end if;
  select user_id into v_user from public.perfis where condominio_id = v_cond and papel = 'sindico' and ativo order by created_at limit 1;
  if v_user is null then raise exception 'Perfil de síndico ativo não encontrado; crie o usuário síndico antes'; end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond) then raise exception 'Este projeto já tem lançamentos; a restauração só vale para um projeto vazio'; end if;
  if (select count(distinct (saldo_inicial_centavos, saldo_inicial_data, bk_total_linhas, bk_saldo_final_centavos)) from public.lancamentos_restauracao) <> 1 then
    raise exception 'As colunas de controle do CSV não são iguais em todas as linhas (arquivo alterado?)'; end if;
  select bk_total_linhas::int, bk_saldo_final_centavos::bigint, saldo_inicial_centavos::bigint, nullif(saldo_inicial_data, '')::date
    into v_linhas, v_saldo_esp, v_ab, v_ab_data from public.lancamentos_restauracao limit 1;
  if v_n <> v_linhas then raise exception 'O CSV tem % linhas, mas o backup registrou % (arquivo incompleto?)', v_n, v_linhas; end if;

  -- o saldo calculado a partir do CSV precisa ser o saldo registrado no momento do backup
  select v_ab + coalesce(sum(case when s.tipo = 'receita' or (s.tipo = 'estorno' and o.tipo = 'despesa') then s.valor_centavos::bigint
                                  when s.tipo = 'despesa' or (s.tipo = 'estorno' and o.tipo = 'receita') then -s.valor_centavos::bigint else 0 end), 0)
    into v_saldo from public.lancamentos_restauracao s left join public.lancamentos_restauracao o on o.id = s.lancamento_original_id;
  if v_saldo <> v_saldo_esp then raise exception 'Saldo calculado do CSV = % centavos, mas o backup registrou % (arquivo alterado ou importado errado)', v_saldo, v_saldo_esp; end if;

  update public.condominios set saldo_inicial_centavos = v_ab, saldo_inicial_data = v_ab_data where id = v_cond;

  insert into public.lancamentos (id, condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, numero_documento,
                                  observacao, lancamento_original_id, criado_por, criado_em, estornado_em, estornado_por, motivo_estorno, versao, editado_em, editado_por)
  select s.id::uuid, v_cond, s.tipo::public.tipo_lancamento, s.data_lancamento::date, nullif(s.competencia, '')::date, s.valor_centavos::bigint, s.categoria, s.descricao,
         nullif(s.fornecedor, ''), nullif(s.numero_documento, ''), nullif(s.observacao, ''), nullif(s.lancamento_original_id, '')::uuid, v_user, s.criado_em::timestamptz,
         nullif(s.estornado_em, '')::timestamptz, case when nullif(s.estornado_em, '') is not null then v_user end, nullif(s.motivo_estorno, ''),
         coalesce(nullif(s.versao, '')::int, 1), nullif(s.editado_em, '')::timestamptz, case when nullif(s.editado_em, '') is not null then v_user end
    from public.lancamentos_restauracao s;
  get diagnostics v_n = row_count;
  if v_n <> v_linhas then raise exception 'Gravou % lançamentos (esperado %)', v_n, v_linhas; end if;

  select v_ab + coalesce(sum(case when l.tipo = 'receita' or (l.tipo = 'estorno' and o.tipo = 'despesa') then l.valor_centavos
                                  when l.tipo = 'despesa' or (l.tipo = 'estorno' and o.tipo = 'receita') then -l.valor_centavos else 0 end), 0)
    into v_saldo from public.lancamentos l left join public.lancamentos o on o.id = l.lancamento_original_id where l.condominio_id = v_cond;
  if v_saldo <> v_saldo_esp then raise exception 'Saldo após restaurar = % (esperado %)', v_saldo, v_saldo_esp; end if;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
  values (v_cond, v_user, 'restaurar_backup', 'lancamentos', jsonb_build_object('lancamentos', v_n, 'saldo_final_centavos', v_saldo));
  drop table public.lancamentos_restauracao;
end $rest$;

-- Conferência: compare com o arquivo de controle do backup (mesmos meses, quantidades e saldo final).
select to_char(date_trunc('month', data_lancamento), 'MM/YYYY') as mes, count(*) as lancamentos from public.lancamentos group by 1 order by 1;
