-- Executar após as seis propostas v46.21, em transação com ROLLBACK.
DO $test$
DECLARE t record; f record; n int:=0;
BEGIN
 FOR t IN SELECT c.oid,c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
 WHERE s.nspname='public' AND c.relname LIKE 'ew\_compras\_%' ESCAPE '\' AND c.relkind='r'
 LOOP
  n:=n+1;
  IF NOT t.relrowsecurity OR has_table_privilege('anon',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR
    has_table_privilege('authenticated',t.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR
    NOT has_table_privilege('authenticated',t.oid,'SELECT') THEN
   RAISE EXCEPTION 'Privilégios inadequados em %',t.relname;
  END IF;
 END LOOP;
 IF n<12 THEN RAISE EXCEPTION 'Tabelas de compras ausentes: %',n; END IF;
 FOR f IN SELECT p.oid,p.proname,p.prorettype FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
 WHERE s.nspname='public' AND p.proname LIKE 'ew\_compras\_%' ESCAPE '\'
 LOOP
  IF has_function_privilege('anon',f.oid,'EXECUTE') OR
    (f.prorettype='trigger'::regtype AND has_function_privilege('authenticated',f.oid,'EXECUTE')) THEN
   RAISE EXCEPTION 'Execução indevida de %',f.proname;
  END IF;
 END LOOP;
 RAISE NOTICE 'PASS: ACL de tabelas e funções de compras, incluindo TRUNCATE.';
END;
$test$;
