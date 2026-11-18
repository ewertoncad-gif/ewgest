-- Permite que a Edge Function ewgest-acesso verifique qual sessao e a atual.
-- A tabela continua sem acesso de leitura ou escrita para anon e authenticated.
-- A chave de service_role nao e exposta ao navegador.
grant select on table public.ew_sessoes_unicas to service_role;
