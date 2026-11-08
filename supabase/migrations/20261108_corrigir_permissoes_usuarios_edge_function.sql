-- EWGEST v20: corrigir permissão da Edge Function de gestão de contas.
-- O role service_role é exclusivo do servidor e não deve ser exposto ao navegador.
-- O frontend permanece sem permissões de criar, alterar ou apagar contas diretamente.
BEGIN;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.usuarios_login TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.usuarios_empresas TO service_role;
DO $$
BEGIN
 IF NOT has_table_privilege('service_role','public.usuarios_login','SELECT')
    OR NOT has_table_privilege('service_role','public.usuarios_login','UPDATE')
    OR NOT has_table_privilege('service_role','public.usuarios_empresas','SELECT')
    OR NOT has_table_privilege('service_role','public.usuarios_empresas','INSERT')
 THEN
   RAISE EXCEPTION 'A função não recebeu as permissões necessárias.';
 END IF;
 IF has_table_privilege('anon','public.usuarios_login','SELECT')
    OR has_table_privilege('authenticated','public.usuarios_login','UPDATE')
 THEN
   RAISE EXCEPTION 'Permissão inesperada para cliente. Revertendo.';
 END IF;
END $$;
COMMIT;