-- BACKUP 3 de 3 (opcional) — lista de moradores e papéis, para reenviar convites se o projeto for recriado.
-- Não contém senhas: o login é refeito pelo próprio morador.
select p.nome, p.email, p.papel, p.ativo, string_agg(u.identificacao, ', ' order by u.identificacao) as unidades
  from public.perfis p
  join public.condominios c on c.id = p.condominio_id and c.nome = 'Edifício Valença'
  left join public.vinculos_unidades vu on vu.user_id = p.user_id and vu.ativo
  left join public.unidades u on u.id = vu.unidade_id
 group by p.nome, p.email, p.papel, p.ativo
 order by p.papel, p.nome;
