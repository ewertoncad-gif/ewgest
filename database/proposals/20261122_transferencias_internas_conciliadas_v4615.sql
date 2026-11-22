-- EWGEST v46.15 — transferências internas históricas, não repetíveis.
-- Concilia SOMENTE quando os materiais estão zerados em TODOS os galpões
-- e não restam entradas, consumos ou transferências entre obras ativos.
-- Não cria nem apaga movimento físico de estoque.
BEGIN;
CREATE OR REPLACE FUNCTION public.ew_transferencias_internas_conciliadas(p_obra_id uuid)
 RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $function$
DECLARE v_abertos integer;
BEGIN
 IF p_obra_id IS NULL THEN RETURN 0;END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id
  GROUP BY m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
  HAVING sum(m.quantidade_delta)<>0) THEN RETURN 0;END IF;
 SELECT count(*) INTO v_abertos
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.obra_id=p_obra_id AND m.origem<>'ESTORNO'
 AND m.estorno_de_id IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos x WHERE x.estorno_de_id=m.id);
 IF v_abertos=0 THEN RETURN 0;END IF;
 -- Somente duas pernas da MESMA obra podem estar sem estorno formal.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.origem<>'ESTORNO'
   AND m.estorno_de_id IS NULL AND NOT EXISTS(
     SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id)
   AND (m.origem<>'TRANSFERENCIA' OR m.transferencia_id IS NULL))
 THEN RETURN 0;END IF;
 IF EXISTS(
  WITH operacoes AS (
   SELECT DISTINCT m.transferencia_id
   FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=p_obra_id
     AND m.origem='TRANSFERENCIA' AND m.estorno_de_id IS NULL
     AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id)
  )
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  JOIN operacoes o ON o.transferencia_id=m.transferencia_id
  WHERE m.origem='TRANSFERENCIA'
  GROUP BY m.transferencia_id
  HAVING count(*)<>2
   OR count(*) FILTER(WHERE m.obra_id=p_obra_id AND m.estorno_de_id IS NULL AND
     NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id))<>2
   OR count(DISTINCT m.obra_id)<>1
   OR count(DISTINCT m.empresa_id)<>1
   OR count(DISTINCT (m.variacao_id,m.comprimento_mm,m.unidade))<>1
   OR count(DISTINCT m.local_estoque)<>2
   OR sum(m.quantidade_delta)<>0
 ) THEN RETURN 0;END IF;
 RETURN v_abertos;
END;
$function$;
REVOKE ALL ON FUNCTION public.ew_transferencias_internas_conciliadas(uuid) FROM PUBLIC,anon,authenticated;
COMMIT;
