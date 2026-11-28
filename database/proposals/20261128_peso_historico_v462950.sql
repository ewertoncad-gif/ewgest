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
CREATE OR REPLACE FUNCTION public.ew_rateio_industrial_lote(p_empresa_id uuid,p_titulo_id uuid,p_versao int,p_operacao_id uuid,p_criterio text,p_selecao jsonb,p_motivo text,p_confirmar boolean,p_previa jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $
DECLARE t ew_financeiro_interna.titulos%ROWTYPE; c ew_financeiro_interna.classificacao_atual%ROWTYPE;
 lote ew_financeiro_interna.rateios_lotes%ROWTYPE; x record; v_plano jsonb; v_entrada jsonb; v_resultado jsonb;
 v_saldo bigint; v_ids uuid[]; v_count int; v_rows int;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_versao IS NULL OR p_confirmar IS NULL OR p_criterio IS NULL OR p_criterio NOT IN ('QUANTIDADE','AREA','PESO_INFORMADO','PESO_CONSUMO') OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 OR jsonb_typeof(p_selecao) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Parâmetros de rateio inválidos.'; END IF;
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
 IF p_criterio='PESO_CONSUMO' AND p_confirmar THEN
  -- Não espera a produção: se houver escrita concorrente, exige nova tentativa.
  LOCK TABLE public.ew_estoque_obras_movimentos,public.ew_estornos_parcelas IN SHARE MODE NOWAIT;
 END IF;
 -- Trava as fontes para impedir mudanças de liberação/dimensões durante o cálculo.
 PERFORM l.id FROM public.liberacoes_corte l JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=p_empresa_id WHERE l.id=ANY(v_ids) ORDER BY l.id FOR SHARE OF l,e;
 WITH fontes AS (
 SELECT l.id, CASE p_criterio WHEN 'QUANTIDADE' THEN l.quantidade::numeric WHEN 'AREA' THEN round(e.largura_mm::numeric*e.altura_mm::numeric*l.quantidade/1000000,6) WHEN 'PESO_CONSUMO' THEN ew_compras_interna.peso_liberacao(p_empresa_id,l.id,(date_trunc('month',t.competencia::timestamp)+interval '1 month - 1 day')::date) ELSE z.peso_kg END peso
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
 IF v_rows<>v_count THEN RAISE EXCEPTION 'Liberação, fábrica ou medida incompatível com o título; peso de consumo exige histórico individual completo.';END IF;
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
END $;
REVOKE EXECUTE ON FUNCTION public.ew_rateio_industrial_lote(uuid,uuid,int,uuid,text,jsonb,text,boolean,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_rateio_industrial_lote(uuid,uuid,int,uuid,text,jsonb,text,boolean,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.ew_indicadores_industriais(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $
DECLARE resultado jsonb; financeiro jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT public.ew_pode(p_empresa_id,'relatorios.financeiros') OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'Sem permissão para indicadores industriais.';END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 financeiro:=public.ew_rateio_industrial_consultar(p_empresa_id,p_inicio,p_fim);
 WITH docs AS MATERIALIZED (
 SELECT f.* ,round(f.valor_total*100)::bigint cents
 FROM public.ew_obra_faturamentos f WHERE f.empresa_id=p_empresa_id AND f.status='emitido' AND f.cancelado_em IS NULL AND f.data_faturamento BETWEEN p_inicio AND p_fim
), linhas AS MATERIALIZED (
 SELECT d.id doc_id,d.obra_id,d.categoria,d.data_faturamento,d.criado_em,i.esquadria_id,round(i.valor_total*100)::bigint cents,
  e.id item_ok,coalesce(i.area_m2,i.quantidade*e.largura_mm*e.altura_mm/1000000) area
 FROM docs d JOIN public.ew_obra_faturamentos_itens i ON i.empresa_id=d.empresa_id AND i.faturamento_id=d.id
 LEFT JOIN public.esquadrias e ON e.empresa_id=d.empresa_id AND e.obra_id=d.obra_id AND e.id=i.esquadria_id
), docs_ok AS (
 SELECT d.id FROM docs d JOIN linhas l ON l.doc_id=d.id GROUP BY d.id,d.cents
 HAVING sum(l.cents)=d.cents AND bool_and(l.item_ok IS NOT NULL AND l.cents>0 AND coalesce(l.area,0)>0)
), atrib AS (
 SELECT l.obra_id,l.esquadria_id,l.cents,l.area,
  CASE WHEN a.n>0 AND a.n=a.n_nome AND a.n=a.n_area AND a.n_fabricas=1 AND a.area>=h.area AND h.area>0 THEN a.fabrica ELSE NULL END fabrica
 FROM linhas l JOIN docs_ok k ON k.id=l.doc_id
 LEFT JOIN LATERAL (
  SELECT count(*) n,count(nullif(btrim(ri.fabrica),'')) n_nome,count(DISTINCT nullif(btrim(ri.fabrica),'')) n_fabricas,count(*) FILTER(WHERE ri.area_m2>0) n_area,
   min(nullif(btrim(ri.fabrica),'')) fabrica,coalesce(sum(ri.area_m2),0) area
  FROM public.romaneios r JOIN public.romaneios_itens ri ON ri.romaneio_id=r.id AND ri.natureza='esquadria'
  WHERE r.empresa_id=p_empresa_id AND r.obra_id=l.obra_id AND r.status='emitido' AND r.cancelado_em IS NULL
   AND r.data_saida<=l.data_faturamento AND r.criado_em<=l.criado_em AND ri.esquadria_id=l.esquadria_id
 ) a ON true
 LEFT JOIN LATERAL (
  SELECT coalesce(sum(coalesce(i.area_m2,i.quantidade*e.largura_mm*e.altura_mm/1000000)),0) area
  FROM public.ew_obra_faturamentos f JOIN public.ew_obra_faturamentos_itens i ON i.empresa_id=f.empresa_id AND i.faturamento_id=f.id
  JOIN public.esquadrias e ON e.empresa_id=f.empresa_id AND e.obra_id=f.obra_id AND e.id=i.esquadria_id
  WHERE f.empresa_id=p_empresa_id AND f.obra_id=l.obra_id AND f.categoria=l.categoria AND f.status='emitido' AND f.cancelado_em IS NULL
   AND (f.criado_em,f.id)<=(l.criado_em,l.doc_id) AND i.esquadria_id=l.esquadria_id
 ) h ON true
 WHERE l.categoria='fabricacao'

 ), areas AS (
 SELECT fabrica,sum(area) area_m2,sum(cents)::bigint receita FROM atrib GROUP BY fabrica
 ), movimentos AS MATERIALIZED (
 SELECT m.id,m.liberacao_id,m.lote_id,m.unidade,m.comprimento_mm,p.peso_kg_m,s.peso_unitario_kg,s.base,s.movimento_id IS NOT NULL historico,(s.variacao_id IS NOT DISTINCT FROM m.variacao_id AND s.unidade IS NOT DISTINCT FROM m.unidade AND s.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND s.quantidade_original=-m.quantidade_delta) consistente,
 CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL AND l.cancelado_em IS NULL THEN nullif(btrim(l.fabrica),'')
 WHEN m.origem='PLANO_CORTE_LOTE' AND b.id IS NOT NULL AND b.cancelado_em IS NULL THEN nullif(btrim(b.fabrica),'') ELSE NULL END fabrica,
 -m.quantidade_delta-coalesce(z.qtd,0) qtd
 FROM public.ew_estoque_obras_movimentos m
 LEFT JOIN ew_compras_interna.pesos_consumo s ON s.empresa_id=m.empresa_id AND s.movimento_id=m.id
 LEFT JOIN public.ew_materiais_variacoes v ON v.empresa_id=m.empresa_id AND v.id=m.variacao_id
 LEFT JOIN public.ew_perfis p ON p.empresa_id=v.empresa_id AND p.id=v.perfil_id
 LEFT JOIN public.liberacoes_corte l ON l.id=m.liberacao_id
 LEFT JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=m.empresa_id AND e.obra_id=m.obra_id
 LEFT JOIN public.ew_liberacoes_lotes b ON b.id=m.lote_id AND b.empresa_id=m.empresa_id AND b.obra_id=m.obra_id
 LEFT JOIN LATERAL (
 SELECT sum(CASE WHEN ep.qtd IS NOT NULL THEN ep.qtd ELSE x.quantidade_delta END) qtd
 FROM public.ew_estoque_obras_movimentos x
 LEFT JOIN LATERAL(SELECT sum(p.quantidade) qtd FROM public.ew_estornos_parcelas p WHERE p.empresa_id=m.empresa_id AND p.movimento_original_id=m.id AND p.movimento_estorno_id=x.id) ep ON true
 WHERE x.empresa_id=m.empresa_id AND x.obra_id=m.obra_id AND x.origem='ESTORNO' AND x.quantidade_delta>0 AND (x.estorno_de_id=m.id OR ep.qtd IS NOT NULL)
 ) z ON true
 WHERE m.empresa_id=p_empresa_id AND (s.tipo='PERFIL' OR (s.movimento_id IS NULL AND v.tipo='perfil')) AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND m.quantidade_delta<0 AND (m.criado_em AT TIME ZONE 'America/Recife')::date BETWEEN p_inicio AND p_fim
 ), pesos AS (
 SELECT *, CASE WHEN historico THEN CASE WHEN consistente AND qtd>0 THEN qtd*peso_unitario_kg ELSE NULL END WHEN qtd>0 AND unidade='KG' THEN qtd WHEN qtd>0 AND unidade='BARRA' AND comprimento_mm>0 AND peso_kg_m>0 THEN qtd*comprimento_mm*peso_kg_m/1000 WHEN qtd>0 AND unidade IN ('M','MT') AND peso_kg_m>0 THEN qtd*peso_kg_m ELSE NULL END kg
 FROM movimentos WHERE qtd<>0
 ), por_fabrica AS (
 SELECT fabrica,coalesce(sum(kg) FILTER(WHERE unidade='KG'),0) kg_registrado,
 coalesce(sum(kg) FILTER(WHERE unidade<>'KG' AND NOT historico),0) kg_estimado,
 coalesce(sum(kg) FILTER(WHERE unidade<>'KG' AND historico),0) kg_historico,
 count(*) FILTER(WHERE kg IS NULL) peso_pendente,count(*) FILTER(WHERE kg IS NOT NULL) peso_com_base
 FROM pesos GROUP BY fabrica
 ), fin AS (
 SELECT * FROM jsonb_to_recordset(financeiro->'fabrica') x(fabrica text,receita_centavos bigint,material_centavos bigint,rateio_centavos bigint)
 ), chaves AS (SELECT fabrica FROM areas UNION SELECT fabrica FROM por_fabrica UNION SELECT fabrica FROM fin)
 SELECT jsonb_build_object('fabrica',coalesce(jsonb_agg(jsonb_build_object('fabrica',k.fabrica,'receita_centavos',coalesce(f.receita_centavos,0),'material_centavos',coalesce(f.material_centavos,0),'rateio_centavos',coalesce(f.rateio_centavos,0),'area_m2',CASE WHEN k.fabrica IS NOT NULL AND a.receita=f.receita_centavos AND a.area_m2>0 THEN a.area_m2 ELSE NULL END,'kg_registrado',coalesce(p.kg_registrado,0),'kg_estimado',coalesce(p.kg_estimado,0),'kg_historico',coalesce(p.kg_historico,0),'peso_pendente',coalesce(p.peso_pendente,0),'peso_com_base',coalesce(p.peso_com_base,0)) ORDER BY k.fabrica NULLS LAST),'[]'::jsonb),
 'peso_pendente',coalesce(sum(p.peso_pendente),0)) INTO resultado
 FROM chaves k LEFT JOIN fin f ON f.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN areas a ON a.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN por_fabrica p ON p.fabrica IS NOT DISTINCT FROM k.fabrica;
 RETURN resultado;
END $;
REVOKE EXECUTE ON FUNCTION public.ew_indicadores_industriais(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_indicadores_industriais(uuid,date,date) TO authenticated;

COMMIT;
