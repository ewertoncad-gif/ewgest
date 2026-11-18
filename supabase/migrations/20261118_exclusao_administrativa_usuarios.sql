-- Excluir do cadastro operacional sem apagar o histórico do autor.
-- auth.users é referenciado por saídas, romaneios e auditorias (RESTRICT).
-- A exclusão é lógica, com bloqueio do login e retirada do vínculo.
alter table public.usuarios_login
  add column if not exists excluido_em timestamptz,
  add column if not exists excluido_por uuid references auth.users(id);
create index if not exists usuarios_login_ativos_listagem_idx
  on public.usuarios_login (empresa_id,login_chave)
  where excluido_em is null;
comment on column public.usuarios_login.excluido_em is
  'Exclusão administrativa: conta removida da listagem e sem acesso. Histórico preservado.';
