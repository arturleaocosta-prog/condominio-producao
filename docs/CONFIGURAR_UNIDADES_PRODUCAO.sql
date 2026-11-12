-- Cria as 8 unidades do Edifício Valença com as frações ideais VIGENTES (conjunto novo, 7 casas decimais).
-- Não precisa copiar nenhum código: ele procura o condomínio pelo nome. Rode uma única vez, depois de criar o condomínio.
-- As frações somam exatamente 1,0000000 (a consulta final mostra a conferência).
do $chk$ begin
  if not exists (select 1 from public.condominios where nome = 'Edifício Valença') then
    raise exception 'Condomínio "Edifício Valença" não encontrado: crie-o antes (insert into public.condominios ...)';
  end if;
  if (select numeric_scale from information_schema.columns where table_schema = 'public' and table_name = 'unidades' and column_name = 'fracao_ideal') < 7 then
    raise exception 'Rode antes as migrações 001 a 007: a coluna fracao_ideal ainda não comporta 7 casas decimais';
  end if;
end $chk$;

with dados(identificacao, fracao_ideal) as (
  values
    ('01', 0.1221736::numeric(10,7)),
    ('02', 0.1102275::numeric(10,7)),
    ('101',0.1105078::numeric(10,7)),
    ('102',0.1114779::numeric(10,7)),
    ('201',0.1170276::numeric(10,7)),
    ('202',0.1114779::numeric(10,7)),
    ('301',0.1662468::numeric(10,7)),
    ('302',0.1508609::numeric(10,7))
)
insert into public.unidades (condominio_id, identificacao, fracao_ideal)
select c.id, d.identificacao, d.fracao_ideal
  from dados d cross join (select id from public.condominios where nome = 'Edifício Valença') c
on conflict (condominio_id, identificacao) do update set fracao_ideal = excluded.fracao_ideal;

-- Conferência: deve mostrar 8 unidades e soma 1,0000000.
select count(*) as unidades, sum(u.fracao_ideal) as soma
  from public.unidades u join public.condominios c on c.id = u.condominio_id and c.nome = 'Edifício Valença';
