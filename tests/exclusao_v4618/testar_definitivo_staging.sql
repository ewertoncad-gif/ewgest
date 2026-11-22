-- Teste de homologação somente no Supabase ISOLADO de staging.
-- Transação inteira revertida: não persiste obras, estoques nem movimentos.
BEGIN;
INSERT INTO public.obras(id,empresa_id,nome,codigo,arquivada_em)
 VALUES('c1111111-1111-4111-8111-111111111111',
 '9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'Obra encerrada fictícia','OBRA-V4618',now());
INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,excluido_em)
 VALUES('9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'c1111111-1111-4111-8111-111111111111',now());
DO $test$
DECLARE erro text;n integer;
BEGIN
 BEGIN
  PERFORM public.ew_restaurar_estoque_local(
   '9ea7617c-6603-4bc1-91e1-c5e274c334d9',
   'c1111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'FALHA: restauração ainda habilitada';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS erro=MESSAGE_TEXT;
  IF erro NOT LIKE 'RESTAURACAO_DESATIVADA%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.ew_excluir_estoque_local(
   '9ea7617c-6603-4bc1-91e1-c5e274c334d9',
   'c1111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'FALHA: arquivamento isolado ainda habilitado';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS erro=MESSAGE_TEXT;
  IF erro NOT LIKE 'ARQUIVAMENTO_ISOLADO_DESATIVADO%' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE public.obras SET arquivada_em=NULL
   WHERE id='c1111111-1111-4111-8111-111111111111';
  RAISE EXCEPTION 'FALHA: reabertura de obra pelo UPDATE';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS erro=MESSAGE_TEXT;
  IF erro NOT LIKE 'OBRA_ENCERRADA_DEFINITIVA%' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE public.ew_estoques_locais SET excluido_em=NULL
   WHERE obra_id='c1111111-1111-4111-8111-111111111111';
  RAISE EXCEPTION 'FALHA: reabertura de estoque pelo UPDATE';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS erro=MESSAGE_TEXT;
  IF erro NOT LIKE 'ESTOQUE_ENCERRADO_DEFINITIVO%' THEN RAISE; END IF;
 END;
 -- Reiniciar corretamente significa criar nova OBRA, com novo ID e mesmo código.
 INSERT INTO public.obras(id,empresa_id,nome,codigo)
 VALUES('c2222222-2222-4222-8222-222222222222',
  '9ea7617c-6603-4bc1-91e1-c5e274c334d9',
  'Obra reimportada fictícia','OBRA-V4618');
 SELECT count(*) INTO n FROM public.obras
 WHERE empresa_id='9ea7617c-6603-4bc1-91e1-c5e274c334d9' AND codigo='OBRA-V4618';
 IF n<>2 THEN RAISE EXCEPTION 'Nova importação não criou ID distinto';END IF;
END;
$test$;
ROLLBACK;
SELECT 'APROVADO: reabertura bloqueada, RPCs desativadas, nova obra com ID distinto e rollback da fixture' AS resultado;