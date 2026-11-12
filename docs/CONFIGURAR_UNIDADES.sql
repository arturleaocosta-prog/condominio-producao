-- Substitua o UUID abaixo pelo ID real do condomínio criado no banco.
-- Execute apenas uma vez e confira a convenção antes de liberar o sistema.
-- Frações ATUALIZADAS (V1.6), conforme a planilha Previsão Orçamentária (abas Set/Out-2026).
-- Substituem as frações da V1.5 (01 = 0,1125080 ... 302 = 0,1525220). Rateios já fechados com a
-- fração anterior (Jul/Ago-2026) não devem ser recalculados: guarde a fração aplicada em cada rateio.
-- As frações somam exatamente 1,0000000.
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
select 'SUBSTITUA-PELO-UUID-DO-CONDOMINIO'::uuid, identificacao, fracao_ideal
from dados
on conflict (condominio_id, identificacao) do update
set fracao_ideal = excluded.fracao_ideal;

-- Verificação obrigatória: deve retornar 1,0000000.
-- select sum(fracao_ideal) from public.unidades
-- where condominio_id = 'SUBSTITUA-PELO-UUID-DO-CONDOMINIO'::uuid and ativa;
