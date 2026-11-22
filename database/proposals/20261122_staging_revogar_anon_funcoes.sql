-- EWGEST v46.9 — revogar EXECUTE anon em rotinas legado do Supabase TESTE.
-- Somente ewgest-restauracao-teste; NÃO executar na produção.
-- Verifica 44 funções públicas, 15 com anon EXECUTE, mantendo uso authenticated.
BEGIN;
DO $guard$
DECLARE num_funcs integer; num_anon integer; num_sem_auth integer;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE has_function_privilege('anon',p.oid,'EXECUTE')),
 count(*) FILTER(WHERE has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))
 INTO num_funcs,num_anon,num_sem_auth
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public';
 IF num_funcs<>44 OR num_anon<>15 OR num_sem_auth<>0 THEN
   RAISE EXCEPTION 'Staging de funções divergiu: total %, anon %, falta auth %. Reavaliar.',num_funcs,num_anon,num_sem_auth;
 END IF;
END $guard$;
DO $revoke_anon$
DECLARE func record;
BEGIN
 FOR func IN
   SELECT p.proname,pg_catalog.oidvectortypes(p.proargtypes) arguments
   FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
   ORDER BY p.proname
 LOOP
  EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon',
   func.proname,func.arguments);
 END LOOP;
END $revoke_anon$;
DO $verify$
DECLARE funcs integer; anon integer; auth_less integer;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE has_function_privilege('anon',p.oid,'EXECUTE')),
 count(*) FILTER(WHERE NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))
 INTO funcs,anon,auth_less
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public';
 IF funcs<>44 OR anon<>0 OR auth_less<>0 THEN
  RAISE EXCEPTION 'Permissões finais inválidas: total %, anon %, sem auth %',funcs,anon,auth_less;
 END IF;
END $verify$;
COMMIT;
-- Este script deve falhar em uma segunda execução (guards detectam anon=0).
-- Funções trigger/event_trigger não precisam de permissões anon para disparar.
-- Sem modificação de código, dados ou funções no projeto de produção.
