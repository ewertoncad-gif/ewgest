-- EWGEST 46.9 | completar proteção de novas tabelas no Supabase TESTE
-- Ambiente exclusivo: ewgest-restauracao-teste, 35 tabelas públicas.
-- Função existente idêntica à produção; não alterar a função nem projeto de produção.
BEGIN;
DO $guard$
DECLARE t integer; r integer; a integer; n integer; signature text;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE c.relrowsecurity)
 INTO t,r FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
 WHERE s.nspname='public' AND c.relkind IN ('r','p');
 IF t<>35 OR r<>35 THEN RAISE EXCEPTION 'Staging inesperado: % tabelas, % com RLS.',t,r;END IF;
 SELECT count(*) INTO a FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname='public' AND has_function_privilege('anon',p.oid,'EXECUTE');
 IF a<>0 THEN RAISE EXCEPTION 'Anon EXECUTE não protegido (%).',a;END IF;
 SELECT md5(pg_get_functiondef(p.oid)) INTO signature FROM pg_proc p
 JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname='public' AND p.proname='rls_auto_enable';
 IF signature IS DISTINCT FROM '846ec2fbff751d24b890656d63c3a9bf' THEN
  RAISE EXCEPTION 'Função RLS staging não corresponde à definição de produção.';
 END IF;
 SELECT count(*) INTO n FROM pg_event_trigger WHERE evtname='ensure_rls';
 IF n<>0 THEN RAISE EXCEPTION 'Gatilho ensure_rls já existe. Não reaplicar.';END IF;
END $guard$;
CREATE EVENT TRIGGER ensure_rls
 ON ddl_command_end
 WHEN TAG IN ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')
 EXECUTE FUNCTION public.rls_auto_enable();
DO $check$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_event_trigger
 WHERE evtname='ensure_rls' AND evtevent='ddl_command_end' AND evtenabled='O'
 AND evtfoid='public.rls_auto_enable()'::regprocedure
 AND evttags=ARRAY['CREATE TABLE','CREATE TABLE AS','SELECT INTO'];
 IF n<>1 THEN RAISE EXCEPTION 'Gatilho de RLS não foi criado exatamente como na produção.'; END IF;
END $check$;
COMMIT;
-- Para testar: BEGIN; CREATE TABLE public.ew_v469_teste_rls_temporario(id bigint);
-- SELECT relrowsecurity ...; ROLLBACK; (em transação separada).
