-- A revisão aprovada prevalece sobre o rateio original; centavos acumulados por esquadria.
CREATE OR REPLACE FUNCTION public.ew_registrar_faturamento_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_data_faturamento date, p_numero_documento text, p_observacoes text, p_itens jsonb, p_operacao_id uuid, p_instalacao_confirmada boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_budget numeric;
 v_faturado numeric;
 v_id uuid;
 v_antigo uuid;
 v_item jsonb;
 v_esquadria public.esquadrias%ROWTYPE;
 v_quantidade numeric;
 v_unit numeric;
 v_line numeric;
 v_area_unit numeric; v_area_m2 numeric; v_preco_m2 numeric; v_area_faturada numeric;
 v_total numeric:=0;
 v_total_invoiced numeric;
 v_count int:=0;
 v_shipped numeric;
 v_seen uuid[]:=ARRAY[]::uuid[];
 v_precificacao_revisao_id uuid; v_preco_item public.ew_precificacao_revisoes_itens%ROWTYPE; v_item_centavos bigint; v_ja_valor numeric; v_linhas jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.faturar');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.faturar'))
 THEN RAISE EXCEPTION 'Somente ADM pode registrar faturamentos.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=p_empresa_id AND o.arquivada_em IS NULL FOR SHARE) THEN RAISE EXCEPTION 'Obra não encontrada ou arquivada.';END IF;
 IF p_categoria IS NULL OR p_categoria NOT IN ('fabricacao','instalacao') OR p_operacao_id IS NULL OR p_obra_id IS NULL OR
   p_data_faturamento IS NULL OR length(btrim(coalesce(p_numero_documento,''))) NOT BETWEEN 1 AND 120 OR
   length(coalesce(p_observacoes,''))>1000 OR
   jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 200
 THEN RAISE EXCEPTION 'Informe tipo, data, número do documento e ao menos uma esquadria.';END IF;
 IF p_categoria='instalacao' AND p_instalacao_confirmada IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Confirme a instalação dos itens antes de faturar instalação.';END IF;
 -- Serializa invoices simultâneas da mesma obra/categoria.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria,0));
 SELECT id INTO v_antigo FROM public.ew_obra_faturamentos
  WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF v_antigo IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM public.ew_obra_faturamentos WHERE id=v_antigo AND empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido') THEN RAISE EXCEPTION 'Identificador de faturamento já utilizado ou cancelado.'; END IF;
 RETURN (SELECT jsonb_build_object('id',v_antigo,'ja_registrado',true,'valor_total',valor_total,'categoria',categoria) FROM public.ew_obra_faturamentos WHERE id=v_antigo);END IF;
 -- Sempre bloquear o orçamento contratual original e preservar o registro.
 SELECT CASE p_categoria WHEN 'fabricacao' THEN fabricacao ELSE instalacao END
 INTO v_budget FROM public.ew_obra_orcamento
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento financeiro da obra não encontrado.';END IF;
 -- Nas obras precificadas, usar a DISTRIBUIÇÃO aprovada, não os valores
 -- originais 70/30. Obras antigas continuam usando orçamento legado.
 SELECT id,CASE p_categoria
   WHEN 'fabricacao' THEN fabricacao_distribuida_centavos::numeric/100
   ELSE instalacao_distribuida_centavos::numeric/100 END
 INTO v_precificacao_revisao_id,v_budget
 FROM public.ew_precificacao_revisoes
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND estado='aprovada'
 ORDER BY versao DESC LIMIT 1;
 IF NOT FOUND THEN
  SELECT CASE p_categoria WHEN 'fabricacao' THEN fabricacao ELSE instalacao END
  INTO v_budget FROM public.ew_obra_orcamento
  WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id;
 END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_item->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'valor_unitario') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Esquadria ou valor de faturamento incompleto.';END IF;
  IF (v_item->>'esquadria_id')::uuid=ANY(v_seen) THEN
   RAISE EXCEPTION 'Esquadria repetida no mesmo documento. Agrupe quantidades de cada código.';
  END IF;
  v_seen:=array_append(v_seen,(v_item->>'esquadria_id')::uuid);
  SELECT * INTO v_esquadria FROM public.esquadrias WHERE id=(v_item->>'esquadria_id')::uuid
    AND empresa_id=p_empresa_id AND obra_id=p_obra_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria do faturamento não pertence à obra.';END IF;
  -- Segurança no servidor: em obras precificadas, nenhum documento pode
  -- contornar o cadastro individual aprovado, ainda que o cliente REST seja
  -- invocado diretamente sem passar pela interface.
  IF v_precificacao_revisao_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.ew_precificacao_revisoes_itens pi
   WHERE pi.revisao_id=v_precificacao_revisao_id
    AND pi.empresa_id=p_empresa_id AND pi.obra_id=p_obra_id
    AND pi.esquadria_id=v_esquadria.id
    AND pi.quantidade=v_esquadria.quantidade AND pi.largura_mm=v_esquadria.largura_mm AND pi.altura_mm=v_esquadria.altura_mm
  ) THEN
   RAISE EXCEPTION 'Esquadria sem precificação individual aprovada ou com quantidade divergente: %.',v_esquadria.codigo;
  END IF;
  v_quantidade:=(v_item->>'quantidade')::numeric;
  v_unit:=(v_item->>'valor_unitario')::numeric;
  IF v_quantidade<=0 OR v_quantidade>v_esquadria.quantidade OR v_quantidade<>round(v_quantidade,6) OR
     v_unit<=0 OR v_unit>100000000 OR v_unit<>round(v_unit,4)
  THEN RAISE EXCEPTION 'Quantidade ou preço unitário inválido para %.',v_esquadria.codigo; END IF;
  v_area_unit:=v_esquadria.largura_mm::numeric*v_esquadria.altura_mm::numeric/1000000;
  SELECT coalesce(sum(fi.quantidade),0),coalesce(sum(coalesce(fi.area_m2,fi.quantidade*v_area_unit)),0) INTO v_total_invoiced,v_area_faturada
  FROM public.ew_obra_faturamentos_itens fi
  JOIN public.ew_obra_faturamentos fh ON fh.id=fi.faturamento_id
  WHERE fi.esquadria_id=v_esquadria.id AND fh.empresa_id=p_empresa_id
  AND fh.obra_id=p_obra_id AND fh.categoria=p_categoria AND fh.status='emitido';
  -- Equivalente expedido: completa 100%, marco 50%, folha física 50%/folhas.
  -- Romaneios cancelados não autorizam faturamento.
  IF EXISTS (
   SELECT 1 FROM public.romaneios_itens ri
   JOIN public.romaneios rr ON rr.id=ri.romaneio_id
   LEFT JOIN public.esquadrias_saida_config cfg ON cfg.esquadria_id=ri.esquadria_id
   WHERE ri.esquadria_id=v_esquadria.id AND rr.empresa_id=p_empresa_id
    AND rr.obra_id=p_obra_id AND rr.status='emitido' AND rr.cancelado_em IS NULL
    AND ri.natureza='esquadria' AND ri.tipo_saida='folha' AND ri.composicao_revisao_id IS NULL
    AND (cfg.folhas_por_unidade IS NULL OR cfg.folhas_por_unidade NOT BETWEEN 1 AND 12)
  ) THEN
   RAISE EXCEPTION 'Composição física das folhas não cadastrada para %.',v_esquadria.codigo;
  END IF;
  SELECT coalesce(sum(
    CASE WHEN ri.composicao_revisao_id IS NOT NULL THEN ri.equivalente_expedido ELSE CASE ri.tipo_saida
     WHEN 'completo' THEN ri.quantidade::numeric
     WHEN 'marco' THEN ri.quantidade::numeric/2
     WHEN 'folha' THEN ri.quantidade::numeric/(2*cfg.folhas_por_unidade)
     ELSE 0 END END
  ),0) INTO v_shipped
  FROM public.romaneios_itens ri
  JOIN public.romaneios rr ON rr.id=ri.romaneio_id
  LEFT JOIN public.esquadrias_saida_config cfg ON cfg.esquadria_id=ri.esquadria_id
  WHERE ri.esquadria_id=v_esquadria.id AND rr.empresa_id=p_empresa_id
   AND rr.obra_id=p_obra_id AND rr.status='emitido' AND rr.cancelado_em IS NULL
   AND ri.natureza='esquadria';
  IF NOT (v_item ? 'area_m2' OR v_item ? 'preco_m2') AND
     (v_total_invoiced+v_quantidade>v_esquadria.quantidade OR v_total_invoiced+v_quantidade>v_shipped
      OR round(v_area_faturada+v_quantidade*v_area_unit,6)>round(least(v_shipped,v_esquadria.quantidade)*v_area_unit,6)) THEN
    RAISE EXCEPTION 'Quantidade equivalente não faturável de %: confira saídas ativas e histórico de %.',
      v_esquadria.codigo,p_categoria;
  END IF;
  IF v_item ? 'area_m2' OR v_item ? 'preco_m2' THEN
   IF jsonb_typeof(v_item->'area_m2') IS DISTINCT FROM 'number' OR jsonb_typeof(v_item->'preco_m2') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Informe área e preço por m².'; END IF;
   v_area_m2:=(v_item->>'area_m2')::numeric; v_preco_m2:=(v_item->>'preco_m2')::numeric;
   IF v_area_unit<=0 OR v_area_m2<=0 OR v_area_m2<>round(v_area_m2,6) OR v_preco_m2<=0 OR v_preco_m2>100000000 OR v_preco_m2<>round(v_preco_m2,4)
     OR abs(v_area_m2-v_quantidade*v_area_unit)>greatest(0.000001,v_area_unit*0.0000005)
     OR round(v_area_faturada+v_area_m2,6)>round(least(v_shipped,v_esquadria.quantidade)*v_area_unit,6)
     OR v_unit<>round(v_preco_m2*v_area_unit,4)
   THEN RAISE EXCEPTION 'Área ou preço por m² incompatível com as dimensões e saldo expedido de %.',v_esquadria.codigo; END IF;
   v_line:=round(v_area_m2*v_preco_m2,2);
  ELSE v_line:=round(v_quantidade*v_unit,2); END IF;
  IF v_precificacao_revisao_id IS NOT NULL THEN
   IF NOT (v_item ? 'area_m2' AND v_item ? 'preco_m2') THEN RAISE EXCEPTION 'Faturamento precificado exige área em m².';END IF;
   SELECT * INTO STRICT v_preco_item FROM public.ew_precificacao_revisoes_itens WHERE revisao_id=v_precificacao_revisao_id AND empresa_id=p_empresa_id AND obra_id=p_obra_id AND esquadria_id=v_esquadria.id;
   v_item_centavos:=CASE p_categoria WHEN 'fabricacao' THEN v_preco_item.fabricacao_centavos ELSE v_preco_item.instalacao_centavos END;
   SELECT coalesce(sum(fi.valor_total),0) INTO v_ja_valor FROM public.ew_obra_faturamentos_itens fi JOIN public.ew_obra_faturamentos fh ON fh.id=fi.faturamento_id AND fh.empresa_id=fi.empresa_id WHERE fi.esquadria_id=v_esquadria.id AND fh.empresa_id=p_empresa_id AND fh.obra_id=p_obra_id AND fh.categoria=p_categoria AND fh.status='emitido';
   IF v_area_faturada+v_area_m2>v_preco_item.area_m2 THEN RAISE EXCEPTION 'Área excede a precificação aprovada.';END IF;
   v_line:=round(v_item_centavos::numeric*(v_area_faturada+v_area_m2)/v_preco_item.area_m2,0)/100-v_ja_valor;
   IF v_line<=0 THEN RAISE EXCEPTION 'Sem valor positivo disponível nesta área precificada. Agrupe mais área ou revise o histórico.';END IF;
   -- Valor exato em centavos é calculado pelo servidor; taxa enviada é informativa.
   v_preco_m2:=round(v_line/v_area_m2,4); v_unit:=round(v_line/v_quantidade,4);
   IF v_preco_m2<=0 OR v_unit<=0 THEN RAISE EXCEPTION 'Preço efetivo abaixo da precisão suportada.';END IF;
  END IF;
  IF v_line<=0 THEN RAISE EXCEPTION 'Valor de faturamento arredondado para zero.';END IF;
  v_linhas:=v_linhas||jsonb_build_array(v_item||jsonb_build_object('valor_total_validado',v_line,'valor_unitario',v_unit)||CASE WHEN v_item ? 'area_m2' THEN jsonb_build_object('preco_m2',v_preco_m2) ELSE '{}'::jsonb END);
  v_total:=v_total+v_line;
  v_count:=v_count+1;
 END LOOP;
 SELECT coalesce(sum(valor_total),0) INTO v_faturado FROM public.ew_obra_faturamentos
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido';
 IF v_faturado+v_total>v_budget
 THEN RAISE EXCEPTION 'Faturamento supera o valor contratado para %. Previsto %, já faturado %, novo %.',
 p_categoria,v_budget,v_faturado,v_total;END IF;
 INSERT INTO public.ew_obra_faturamentos(
  empresa_id,obra_id,categoria,data_faturamento,numero_documento,observacoes,valor_total,criado_por,operacao_id)
 VALUES(p_empresa_id,p_obra_id,p_categoria,p_data_faturamento,
 btrim(p_numero_documento),coalesce(p_observacoes,''),v_total,v_uid,p_operacao_id)
 RETURNING id INTO v_id;
 FOR v_item IN SELECT value FROM jsonb_array_elements(v_linhas) LOOP
  v_quantidade:=(v_item->>'quantidade')::numeric;
  v_unit:=(v_item->>'valor_unitario')::numeric;
  INSERT INTO public.ew_obra_faturamentos_itens(
   faturamento_id,empresa_id,esquadria_id,quantidade,valor_unitario,valor_total,area_m2,preco_m2)
  VALUES(v_id,p_empresa_id,(v_item->>'esquadria_id')::uuid,
   v_quantidade,v_unit,(v_item->>'valor_total_validado')::numeric,
   (v_item->>'area_m2')::numeric,(v_item->>'preco_m2')::numeric);
 END LOOP;
 RETURN jsonb_build_object('id',v_id,'categoria',p_categoria,'valor_total',v_total,'itens',v_count,'ja_registrado',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_validar_faturamento_orcamento_niveis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_limite numeric(14,2);
 v_realizado numeric(14,2);
BEGIN
 IF NEW.status IS DISTINCT FROM 'emitido' OR
    NEW.categoria NOT IN ('fabricacao','instalacao') THEN
   RETURN NEW;
 END IF;
 SELECT CASE NEW.categoria WHEN 'fabricacao' THEN fabricacao_distribuida_centavos ELSE instalacao_distribuida_centavos END::numeric/100 INTO v_limite
 FROM public.ew_precificacao_revisoes WHERE empresa_id=NEW.empresa_id AND obra_id=NEW.obra_id AND estado='aprovada' ORDER BY versao DESC LIMIT 1;
 IF FOUND THEN
  SELECT coalesce(sum(valor_total),0) INTO v_realizado FROM public.ew_obra_faturamentos WHERE empresa_id=NEW.empresa_id AND obra_id=NEW.obra_id AND categoria=NEW.categoria AND status='emitido';
  IF v_realizado+NEW.valor_total>v_limite THEN RAISE EXCEPTION 'Faturamento superior à distribuição aprovada: %',NEW.categoria;END IF;
  RETURN NEW;
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM public.ew_obra_orcamento_niveis n
  WHERE n.empresa_id=NEW.empresa_id AND n.obra_id=NEW.obra_id
 ) THEN
  RETURN NEW; -- Orçamentos antigos continuam no fluxo legado.
 END IF;
 SELECT COALESCE(sum(n.valor),0) INTO v_limite
 FROM public.ew_obra_orcamento_niveis n
 WHERE n.empresa_id=NEW.empresa_id AND n.obra_id=NEW.obra_id
   AND n.categoria_base=NEW.categoria AND n.faturar=true;
 SELECT COALESCE(sum(f.valor_total),0) INTO v_realizado
 FROM public.ew_obra_faturamentos f
 WHERE f.empresa_id=NEW.empresa_id AND f.obra_id=NEW.obra_id
   AND f.categoria=NEW.categoria AND f.status='emitido';
 IF v_realizado+NEW.valor_total>v_limite THEN
  RAISE EXCEPTION 'Faturamento superior ao saldo dos níveis autorizados: %',NEW.categoria;
 END IF;
 RETURN NEW;
END;
$function$;

