-- SOMENTE staging ewgest-restauracao-teste. Reconstrói contratos ausentes
-- nesse ambiente antigo para homologar a v46.15; nunca executar em produção.
BEGIN;
CREATE TABLE IF NOT EXISTS public.classificacoes_tipologias_auditoria
 (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),obra_id uuid NOT NULL,esquadria_referencia_id uuid NOT NULL);
CREATE TABLE IF NOT EXISTS public.esquadrias_descricoes_revisoes
 (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),obra_id uuid NOT NULL,esquadria_referencia_id uuid NOT NULL);
CREATE TABLE IF NOT EXISTS public.romaneios
 (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),obra_id uuid NOT NULL,status text NOT NULL DEFAULT 'emitido');
CREATE TABLE IF NOT EXISTS public.saidas_producao
 (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),esquadria_id uuid NOT NULL,cancelado_em timestamptz);
ALTER TABLE public.classificacoes_tipologias_auditoria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.esquadrias_descricoes_revisoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.romaneios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saidas_producao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.classificacoes_tipologias_auditoria,
 public.esquadrias_descricoes_revisoes,public.romaneios,public.saidas_producao
 FROM PUBLIC,anon,authenticated;
-- Versão original da função real de produção, preservada para o teste isolado.
CREATE OR REPLACE FUNCTION public.ew_transferencias_nfe_conciliadas(p_obra_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_notas integer;v_abertos integer;
BEGIN
 IF p_obra_id IS NULL THEN RETURN 0; END IF;
 SELECT count(*) INTO v_notas FROM public.ew_nfe_recebimentos n WHERE n.obra_id=p_obra_id;
 IF v_notas=0 THEN RETURN 0; END IF;
 -- Jamais conciliar recebimento ativo ou cujo estorno físico não foi detalhado.
 IF EXISTS(
   SELECT 1 FROM public.ew_nfe_recebimentos n WHERE n.obra_id=p_obra_id
   AND (n.estornado_em IS NULL OR n.estorno_operacao_id IS NULL
    OR pg_catalog.jsonb_typeof(n.estorno_detalhes) IS DISTINCT FROM 'array'
    OR pg_catalog.jsonb_array_length(n.estorno_detalhes)=0)
 ) THEN RETURN 0; END IF;
 -- O registro de cada NF deve apontar ao movimento de COMPRA correto.
 -- Cada contrapartida informada no estorno deve realmente existir e ter soma exata.
 IF EXISTS(
   SELECT 1 FROM public.ew_nfe_recebimentos n
   WHERE n.obra_id=p_obra_id AND (
     NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos o
       WHERE o.id=n.movimento_id AND o.empresa_id=n.empresa_id
       AND o.obra_id=n.obra_id AND o.origem='COMPRA'
       AND o.variacao_id=n.variacao_id
       AND o.comprimento_mm IS NOT DISTINCT FROM n.comprimento_mm
       AND o.unidade=n.unidade AND o.quantidade_delta=n.quantidade)
     OR (SELECT coalesce(sum((j.item->>'quantidade')::numeric),0)
         FROM pg_catalog.jsonb_array_elements(n.estorno_detalhes) j(item))<>n.quantidade
     OR NOT EXISTS(
         SELECT 1 FROM pg_catalog.jsonb_array_elements(n.estorno_detalhes) j(item)
         JOIN public.ew_estoque_obras_movimentos e ON e.id=(j.item->>'movimento_id')::uuid
         WHERE e.estorno_de_id=n.movimento_id AND e.origem='ESTORNO')
     OR EXISTS(
         SELECT 1 FROM pg_catalog.jsonb_array_elements(n.estorno_detalhes) j(item)
         LEFT JOIN public.ew_estoque_obras_movimentos e ON e.id=(j.item->>'movimento_id')::uuid
         WHERE e.id IS NULL OR e.obra_id<>n.obra_id OR e.empresa_id<>n.empresa_id
          OR e.variacao_id<>n.variacao_id
          OR e.comprimento_mm IS DISTINCT FROM n.comprimento_mm
          OR e.unidade<>n.unidade OR e.origem<>'ESTORNO'
          OR e.quantidade_delta<>-(j.item->>'quantidade')::numeric
          OR e.local_estoque IS DISTINCT FROM j.item->>'galpao'
        )
    )
 ) THEN RETURN 0; END IF;
 -- Nunca reconhecer como conciliado um item com uso de produção, mesmo
 -- se seu saldo total tiver sido compensado por outros lançamentos.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=p_obra_id
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL')) THEN
  RETURN 0;
 END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
    WHERE m.obra_id=p_obra_id
    GROUP BY m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
    HAVING sum(m.quantidade_delta)<>0) THEN RETURN 0; END IF;
 SELECT count(*) INTO v_abertos
 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=p_obra_id
 AND m.estorno_de_id IS NULL AND NOT EXISTS(
  SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id);
 IF v_abertos=0 THEN RETURN 0; END IF;
 -- Somente movimentos abertos de transferências INTERNAS: nada de compras,
 -- baixas, ajustes e jamais transferências de outra obra.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.estorno_de_id IS NULL
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id)
   AND (m.origem<>'TRANSFERENCIA' OR m.transferencia_id IS NULL))
 THEN RETURN 0;END IF;
 -- Exatamente dois movimentos para cada operação, com mesmo material,
 -- medidas, obra e quantidade inversa em dois galpões diferentes.
 IF EXISTS(
  WITH ids AS (
    SELECT DISTINCT m.transferencia_id
    FROM public.ew_estoque_obras_movimentos m
    WHERE m.obra_id=p_obra_id AND m.origem='TRANSFERENCIA'
      AND m.estorno_de_id IS NULL
      AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
        WHERE e.estorno_de_id=m.id)
  )
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  JOIN ids ON ids.transferencia_id=m.transferencia_id
  GROUP BY m.transferencia_id
  HAVING count(*)<>2 OR
    count(*) FILTER(WHERE m.obra_id=p_obra_id AND m.origem='TRANSFERENCIA'
      AND m.estorno_de_id IS NULL AND NOT EXISTS(
        SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id))<>2
    OR count(DISTINCT m.obra_id)<>1
    OR count(DISTINCT (m.variacao_id,m.comprimento_mm,m.unidade))<>1
    OR count(DISTINCT m.local_estoque)<>2
    OR sum(m.quantidade_delta)<>0
 ) THEN RETURN 0; END IF;
 RETURN v_abertos;
END;
$function$
COMMIT;
