-- EWGEST 46.29.47: cálculo e gravação atômica de rateios industriais.
BEGIN;
CREATE TABLE ew_financeiro_interna.rateios_lotes(
 empresa_id uuid NOT NULL,operacao_id uuid NOT NULL,titulo_id uuid NOT NULL,
 entrada jsonb NOT NULL,resultado jsonb NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,operacao_id)
);
ALTER TABLE ew_financeiro_interna.rateios_lotes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.rateios_lotes FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_rateio_industrial_lote(p_empresa_id uuid,p_titulo_id uuid,p_versao int,p_operacao_id uuid,p_criterio text,p_selecao jsonb,p_motivo text,p_confirmar boolean,p_previa jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE; c ew_financeiro_interna.classificacao_atual%ROWTYPE;
 lote ew_financeiro_interna.rateios_lotes%ROWTYPE; x record; v_plano jsonb; v_entrada jsonb; v_resultado jsonb;
 v_saldo bigint; v_ids uuid[]; v_count int; v_rows int; v_peso numeric;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_versao IS NULL OR p_confirmar IS NULL OR p_criterio IS NULL OR p_criterio NOT IN ('QUANTIDADE','AREA','PESO_INFORMADO') OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 OR jsonb_typeof(p_selecao) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Parâmetros de rateio inválidos.'; END IF;
 v_count:=jsonb_array_length(p_selecao);
 IF v_count NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Selecione de 1 a 100 liberações.';END IF;
 SELECT array_agg(id ORDER BY id) INTO v_ids FROM jsonb_to_recordset(p_selecao) AS z(id uuid,peso_kg numeric);
 IF cardinality(v_ids)<>v_count OR array_position(v_ids,NULL) IS NOT NULL OR (SELECT count(DISTINCT id) FROM unnest(v_ids) AS u(id))<>v_count THEN RAISE EXCEPTION 'Liberações repetidas ou inválidas.';END IF;
 IF p_criterio='PESO_INFORMADO' AND EXISTS(SELECT 1 FROM jsonb_to_recordset(p_selecao) AS z(id uuid,peso_kg numeric) WHERE peso_kg IS NULL OR peso_kg<=0 OR peso_kg>1000000 OR peso_kg<>round(peso_kg,3)) THEN RAISE EXCEPTION 'Informe o peso total de cada liberação em kg, até três decimais.';END IF;
 v_entrada:=jsonb_build_object('titulo',p_titulo_id,'versao',p_versao,'criterio',p_criterio,'selecao',(SELECT jsonb_agg(to_jsonb(z) ORDER BY id) FROM jsonb_to_recordset(p_selecao) AS z(id uuid,peso_kg numeric)),'motivo',btrim(p_motivo),'previa',p_previa);
 IF p_confirmar THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|RATEIO_LOTE|'||p_operacao_id::text,0));
  SELECT * INTO lote FROM ew_financeiro_interna.rateios_lotes WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
  IF FOUND THEN
   IF lote.entrada IS DISTINCT FROM v_entrada THEN RAISE EXCEPTION 'Identificador do lote já utilizado com outros dados.';END IF;
   RETURN lote.resultado||jsonb_build_object('repetido',true);
  END IF;
 END IF;
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND OR t.cancelado_em IS NOT NULL OR t.origem_tipo<>'MANUAL' OR t.tipo<>'PAGAR' THEN RAISE EXCEPTION 'Título industrial indisponível.';END IF;
 SELECT * INTO c FROM ew_financeiro_interna.classificacao_atual WHERE empresa_id=p_empresa_id AND titulo_id=t.id;
 IF NOT FOUND OR c.versao<>p_versao OR c.classe NOT IN ('CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS') THEN RAISE EXCEPTION 'Classificação alterada.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.rateios_industriais r WHERE r.empresa_id=p_empresa_id AND r.titulo_id=t.id AND r.estornado_em IS NULL AND r.classe_versao<>c.versao) THEN RAISE EXCEPTION 'Revise e estorne rateios da classificação anterior.';END IF;
 SELECT t.valor_centavos-coalesce(sum(valor_centavos),0)::bigint INTO v_saldo FROM ew_financeiro_interna.rateios_industriais WHERE empresa_id=p_empresa_id AND titulo_id=t.id AND estornado_em IS NULL;
 IF v_saldo<=0 THEN RAISE EXCEPTION 'Sem saldo para ratear.';END IF;
 -- Trava as fontes para impedir mudanças de liberação/dimensões durante o cálculo.
 PERFORM l.id FROM public.liberacoes_corte l JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=p_empresa_id WHERE l.id=ANY(v_ids) ORDER BY l.id FOR SHARE OF l,e;
 WITH fontes AS (
 SELECT l.id, CASE p_criterio WHEN 'QUANTIDADE' THEN l.quantidade::numeric WHEN 'AREA' THEN e.largura_mm::numeric*e.altura_mm::numeric*l.quantidade/1000000 ELSE z.peso_kg END peso
 FROM jsonb_to_recordset(p_selecao) AS z(id uuid,peso_kg numeric)
 JOIN public.liberacoes_corte l ON l.id=z.id JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=p_empresa_id
 WHERE l.cancelado_em IS NULL AND l.tipo_componente='completo' AND l.quantidade>0 AND nullif(btrim(l.fabrica),'') IS NOT NULL
 AND l.data_liberacao<=(date_trunc('month',t.competencia::timestamp)+interval '1 month - 1 day')::date
 AND (t.galpao_id IS NULL OR btrim(t.centro_custo)=btrim(l.fabrica))
 AND (p_criterio<>'AREA' OR (e.largura_mm>0 AND e.altura_mm>0))
 ), validas AS (SELECT * FROM fontes WHERE peso>0 AND peso<='1000000000000'::numeric),
 partes AS (SELECT id,peso,div(v_saldo*peso,sum(peso) OVER()) base,mod(v_saldo*peso,sum(peso) OVER()) resto FROM validas),
 ordenadas AS (SELECT *,row_number() OVER(ORDER BY resto DESC,id) pos,sum(base) OVER() soma FROM partes)
 SELECT count(*)::int,jsonb_agg(jsonb_build_object('id',id,'peso',peso,'centavos',(base+CASE WHEN pos<=v_saldo-soma THEN 1 ELSE 0 END)::bigint) ORDER BY id) INTO v_rows,v_plano FROM ordenadas;
 IF v_rows<>v_count THEN RAISE EXCEPTION 'Liberação, fábrica ou medida incompatível com o título.';END IF;
 v_resultado:=jsonb_build_object('criterio',p_criterio,'saldo_centavos',v_saldo,'linhas',v_plano,'repetido',false);
 IF NOT p_confirmar THEN RETURN v_resultado;END IF;
 IF p_previa IS DISTINCT FROM v_plano THEN RAISE EXCEPTION 'Saldo ou critérios alterados. Recalcule a prévia.';END IF;
 FOR x IN SELECT * FROM jsonb_to_recordset(v_plano) AS z(id uuid,peso numeric,centavos bigint) ORDER BY id LOOP
  IF x.centavos>0 THEN
   PERFORM public.ew_rateio_industrial_criar(p_empresa_id,t.id,x.id,c.versao,gen_random_uuid(),x.centavos,'Lote '||p_operacao_id::text||' / '||p_criterio||' / '||btrim(p_motivo));
  END IF;
 END LOOP;
 INSERT INTO ew_financeiro_interna.rateios_lotes(empresa_id,operacao_id,titulo_id,entrada,resultado,criado_por) VALUES(p_empresa_id,p_operacao_id,t.id,v_entrada,v_resultado,auth.uid());
 RETURN v_resultado;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_rateio_industrial_lote(uuid,uuid,int,uuid,text,jsonb,text,boolean,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_rateio_industrial_lote(uuid,uuid,int,uuid,text,jsonb,text,boolean,jsonb) TO authenticated;
COMMIT;
