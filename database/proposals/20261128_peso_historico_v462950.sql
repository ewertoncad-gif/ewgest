-- Preserva a referência de peso no instante de cada consumo novo. Não retroage.
BEGIN;
CREATE TABLE ew_compras_interna.pesos_consumo(
 movimento_id uuid PRIMARY KEY,empresa_id uuid NOT NULL,variacao_id uuid,
 tipo text NOT NULL CHECK(tipo IN ('PERFIL','ACESSORIO','INDEFINIDO')),
 unidade text,comprimento_mm integer,quantidade_original numeric NOT NULL CHECK(quantidade_original>0),
 peso_kg_m numeric,peso_unitario_kg numeric CHECK(peso_unitario_kg>0),
 base text NOT NULL CHECK(base IN ('KG_REGISTRADO','CADASTRO_CONGELADO','SEM_BASE','NAO_APLICAVEL')),
 registrado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ew_compras_interna.pesos_consumo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.pesos_consumo FROM PUBLIC,anon,authenticated;
CREATE FUNCTION ew_compras_interna.capturar_peso_consumo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_tipo text;v_linear numeric;v_peso numeric;v_base text:='SEM_BASE';
BEGIN
 SELECT v.tipo,p.peso_kg_m INTO v_tipo,v_linear FROM public.ew_materiais_variacoes v
 LEFT JOIN public.ew_perfis p ON p.empresa_id=v.empresa_id AND p.id=v.perfil_id
 WHERE v.empresa_id=NEW.empresa_id AND v.id=NEW.variacao_id;
 IF v_tipo='perfil' THEN
  IF NEW.unidade='KG' THEN v_peso:=1;v_base:='KG_REGISTRADO';
  ELSIF v_linear>0 AND v_linear<='1000000' AND NEW.unidade='BARRA' AND NEW.comprimento_mm>0 THEN v_peso:=v_linear*NEW.comprimento_mm/1000;v_base:='CADASTRO_CONGELADO';
  ELSIF v_linear>0 AND v_linear<='1000000' AND NEW.unidade IN ('M','MT') THEN v_peso:=v_linear;v_base:='CADASTRO_CONGELADO';END IF;
 ELSIF v_tipo='acessorio' THEN v_base:='NAO_APLICAVEL';END IF;
 INSERT INTO ew_compras_interna.pesos_consumo(movimento_id,empresa_id,variacao_id,tipo,unidade,comprimento_mm,quantidade_original,peso_kg_m,peso_unitario_kg,base)
 VALUES(NEW.id,NEW.empresa_id,NEW.variacao_id,CASE v_tipo WHEN 'perfil' THEN 'PERFIL' WHEN 'acessorio' THEN 'ACESSORIO' ELSE 'INDEFINIDO' END,NEW.unidade,NEW.comprimento_mm,-NEW.quantidade_delta,v_linear,v_peso,v_base);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ew_compras_interna.capturar_peso_consumo() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_peso_consumo_historico AFTER INSERT ON public.ew_estoque_obras_movimentos FOR EACH ROW
WHEN (NEW.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND NEW.quantidade_delta<0)
EXECUTE FUNCTION ew_compras_interna.capturar_peso_consumo();

-- Peso elegível por liberação individual: não distribui lote compartilhado.
CREATE FUNCTION ew_compras_interna.peso_liberacao(p_empresa uuid,p_liberacao uuid,p_ate date)
RETURNS numeric LANGUAGE sql STABLE SET search_path TO '' AS $$
 WITH movimentos AS (
 SELECT m.id,m.quantidade_delta,s.peso_unitario_kg,s.tipo,s.base,
 (s.movimento_id IS NOT NULL AND s.variacao_id IS NOT DISTINCT FROM m.variacao_id AND s.unidade IS NOT DISTINCT FROM m.unidade AND s.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND s.quantidade_original=-m.quantidade_delta) consistente,
 -m.quantidade_delta-coalesce(z.qtd,0) liquido
 FROM public.ew_estoque_obras_movimentos m
 LEFT JOIN ew_compras_interna.pesos_consumo s ON s.empresa_id=m.empresa_id AND s.movimento_id=m.id
 LEFT JOIN LATERAL(
 SELECT sum(coalesce(ep.qtd,x.quantidade_delta)) qtd FROM public.ew_estoque_obras_movimentos x
 LEFT JOIN LATERAL(SELECT sum(p.quantidade) qtd FROM public.ew_estornos_parcelas p WHERE p.empresa_id=m.empresa_id AND p.movimento_original_id=m.id AND p.movimento_estorno_id=x.id) ep ON true
 WHERE x.empresa_id=m.empresa_id AND x.obra_id=m.obra_id AND x.origem='ESTORNO' AND x.quantidade_delta>0 AND (x.estorno_de_id=m.id OR ep.qtd IS NOT NULL)
 ) z ON true
 WHERE m.empresa_id=p_empresa AND m.liberacao_id=p_liberacao AND m.lote_id IS NULL AND m.origem='PLANO_CORTE' AND m.quantidade_delta<0 AND (m.criado_em AT TIME ZONE 'America/Recife')::date<=p_ate
 )
 SELECT CASE WHEN count(*) FILTER(WHERE liquido<>0 AND (NOT consistente OR liquido<0 OR tipo='INDEFINIDO' OR (tipo='PERFIL' AND (peso_unitario_kg IS NULL OR base NOT IN ('KG_REGISTRADO','CADASTRO_CONGELADO')))))=0
 THEN nullif(round(sum(liquido*peso_unitario_kg) FILTER(WHERE tipo='PERFIL' AND liquido>0),6),0) ELSE NULL END
 FROM movimentos
$$;
REVOKE ALL ON FUNCTION ew_compras_interna.peso_liberacao(uuid,uuid,date) FROM PUBLIC,anon,authenticated;
COMMIT;
