-- EWGEST v46.9 — endurecimento adicional SOMENTE do staging Supabase Free
-- PR #64, projeto alvo: ewgest-restauracao-teste (35 tabelas public).
-- 13 tabelas já tinham RLS e apenas políticas 'authenticated',
-- mas conservavam privilégios desnecessários do papel anon.
-- Guardas abortam se o ambiente ou políticas mudarem.
BEGIN;
DO $checks$
DECLARE
 t text;
 expected_tables text[] := ARRAY['empresas','esquadrias','ew_cem_obras_materiais','ew_empresas_faturamento_catalogo','ew_estoque_movimentacoes','ew_fornecedores','ew_materiais_alias','ew_niveis_orcamento_catalogo','ew_obra_orcamento_niveis','fabricantes','obras','tipologias','usuarios_empresas'];
 n integer;
 policy_anon integer;
BEGIN
 SELECT count(*) INTO n FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relkind IN ('r','p');
 IF n<>35 THEN RAISE EXCEPTION 'Staging esperado com 35 tabelas, encontradas %; aborto.',n; END IF;
 FOREACH t IN ARRAY expected_tables LOOP
  PERFORM 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='public' AND c.relname=t AND c.relkind IN ('r','p')
   AND c.relrowsecurity
   AND pg_catalog.has_table_privilege('anon',c.oid,'SELECT')
   AND pg_catalog.has_table_privilege('anon',c.oid,'INSERT');
  IF NOT FOUND THEN RAISE EXCEPTION 'Estado inesperado da tabela %. Reavaliar.',t;END IF;
  SELECT count(*) INTO policy_anon FROM pg_catalog.pg_policies p
   WHERE p.schemaname='public' AND p.tablename=t
   AND (('public'=ANY(p.roles)) OR ('anon'=ANY(p.roles)));
  IF policy_anon<>0 THEN RAISE EXCEPTION 'Tabela % possui política anônima; exigir revisão.',t;END IF;
 END LOOP;
END $checks$;
REVOKE ALL ON TABLE public.empresas FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.esquadrias FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_cem_obras_materiais FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_empresas_faturamento_catalogo FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_estoque_movimentacoes FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_fornecedores FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_materiais_alias FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_niveis_orcamento_catalogo FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ew_obra_orcamento_niveis FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.fabricantes FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.obras FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.tipologias FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.usuarios_empresas FROM PUBLIC, anon;
DO $checks_final$
DECLARE
 n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relkind IN ('r','p')
  AND (pg_catalog.has_table_privilege('anon',c.oid,'SELECT') OR pg_catalog.has_table_privilege('anon',c.oid,'INSERT'));
 IF n<>0 THEN RAISE EXCEPTION 'Ainda existem % tabelas com SELECT/INSERT anon.',n;END IF;
END $checks_final$;
COMMIT;
-- Não cria nem apaga dados, mantém GRANT explícito de authenticated.
-- Não aplicar em produção. Reexecutar apenas após nova revisão de políticas.
