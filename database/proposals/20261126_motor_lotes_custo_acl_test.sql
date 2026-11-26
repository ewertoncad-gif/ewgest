-- Executar em ambiente isolado com o motor instalado no pg_temp.
DO $t$
DECLARE r text; p record;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOR p IN SELECT oid FROM pg_proc WHERE pronamespace=pg_my_temp_schema() AND proname IN ('custo_abrir_lote','custo_mover_fragmento','custo_estornar_evento','custo_cancelar_lote') LOOP
   IF has_function_privilege(r,p.oid,'EXECUTE') THEN RAISE EXCEPTION 'Função acessível por %',r; END IF;
  END LOOP;
  FOR p IN SELECT oid,relkind,relrowsecurity FROM pg_class WHERE relnamespace=pg_my_temp_schema() AND relname IN ('custo_lotes','custo_fragmentos','custo_eventos','custo_saldos_fragmentos','custo_ajustes_obra') LOOP
   IF has_table_privilege(r,p.oid,'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Relação acessível por %',r; END IF;
   IF p.relkind='r' AND NOT p.relrowsecurity THEN RAISE EXCEPTION 'RLS desativado'; END IF;
  END LOOP;
 END LOOP;
END;$t$;
