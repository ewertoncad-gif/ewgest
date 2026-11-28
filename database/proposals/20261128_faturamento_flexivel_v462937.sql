-- EWGEST 46.29.37 — proposta; aplicar somente após testes em PostgreSQL descartável.
BEGIN;
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
 v_plano jsonb:='{}'::jsonb; v_saldo bigint; v_nominal bigint; v_abertas int:=0;
 v_restante numeric; v_alvo bigint; v_centavos bigint; v_modo text; v_esperado bigint;
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
 -- Saldo e rateio da categoria inteira, sob o mesmo lock de emissão e cancelamento.
 SELECT coalesce(sum(valor_total),0) INTO v_faturado FROM public.ew_obra_faturamentos
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido';
 IF v_precificacao_revisao_id IS NOT NULL THEN
  v_saldo:=round((v_budget-v_faturado)*100)::bigint;
  WITH hist AS (
   SELECT fi.esquadria_id,round(sum(coalesce(fi.area_m2,fi.quantidade*e.largura_mm*e.altura_mm/1000000)),6) ja
   FROM public.ew_obra_faturamentos_itens fi
   JOIN public.ew_obra_faturamentos fh ON fh.id=fi.faturamento_id AND fh.empresa_id=fi.empresa_id
   JOIN public.esquadrias e ON e.id=fi.esquadria_id AND e.empresa_id=fi.empresa_id AND e.obra_id=fh.obra_id
   WHERE fh.empresa_id=p_empresa_id AND fh.obra_id=p_obra_id AND fh.categoria=p_categoria AND fh.status='emitido'
   GROUP BY fi.esquadria_id
  ), base AS (
   SELECT pi.esquadria_id,round(pi.area_m2,6) area,coalesce(h.ja,0) ja,
    CASE p_categoria WHEN 'fabricacao' THEN pi.fabricacao_centavos ELSE pi.instalacao_centavos END total
   FROM public.ew_precificacao_revisoes_itens pi LEFT JOIN hist h USING(esquadria_id)
   WHERE pi.revisao_id=v_precificacao_revisao_id AND pi.empresa_id=p_empresa_id AND pi.obra_id=p_obra_id
  ), abertas AS (
   SELECT esquadria_id,area-ja restante,total-round(total::numeric*ja/nullif(area,0)) nominal
   FROM base WHERE total>0 AND ja<area AND ja>=0 AND area>0
  ), pesos AS (
   SELECT *,greatest(1,nominal) peso FROM abertas
  ), acumulados AS (
   SELECT *,sum(peso) OVER() soma_peso,sum(peso) OVER(ORDER BY esquadria_id ROWS UNBOUNDED PRECEDING) acum,
    sum(nominal) OVER() soma_nominal,count(*) OVER() n,min(nominal) OVER() menor
   FROM pesos
  ), rateio AS (
   SELECT *,CASE WHEN v_saldo=soma_nominal AND menor>0 THEN nominal
    ELSE 1+round((v_saldo-n)*acum/soma_peso)-round((v_saldo-n)*(acum-peso)/soma_peso) END alvo
   FROM acumulados
  )
  SELECT coalesce(jsonb_object_agg(esquadria_id::text,jsonb_build_object('restante',restante,'alvo',alvo)),'{}'::jsonb),
   count(*)::int,coalesce(sum(nominal),0)::bigint INTO v_plano,v_abertas,v_nominal FROM rateio;
  IF v_saldo<v_abertas OR (v_abertas=0 AND v_saldo<>0) THEN
   RAISE EXCEPTION 'Saldo incompatível com áreas restantes. Confira o histórico.';
  END IF;
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
   v_restante:=(v_plano->(v_esquadria.id::text)->>'restante')::numeric;
   v_alvo:=(v_plano->(v_esquadria.id::text)->>'alvo')::bigint;
   IF v_restante IS NULL OR v_area_m2>v_restante OR v_alvo<=0 THEN RAISE EXCEPTION 'Esquadria sem saldo contratual nesta categoria.';END IF;
   v_modo:=v_item->>'modo_preco';
   IF v_modo IS NULL THEN
    -- Clientes anteriores continuam válidos sem compensação em aberto.
    IF v_saldo<>v_nominal THEN RAISE EXCEPTION 'Há compensação financeira em aberto. Atualize o EWGEST antes de faturar.';END IF;
    v_line:=round(v_item_centavos::numeric*(v_area_faturada+v_area_m2)/v_preco_item.area_m2,0)/100-v_ja_valor;
   ELSE
    IF v_modo NOT IN ('auto','manual') OR jsonb_typeof(v_item->'valor_centavos') IS DISTINCT FROM 'number'
     OR jsonb_typeof(v_item->'saldo_antes_centavos') IS DISTINCT FROM 'number'
     OR (v_item->>'saldo_antes_centavos')::numeric<>v_saldo
     OR (v_item->>'valor_centavos')::numeric<>round((v_item->>'valor_centavos')::numeric)
    THEN RAISE EXCEPTION 'Saldo ou valor do documento mudou. Atualize a obra e confira os preços.';END IF;
    v_esperado:=(v_item->>'valor_centavos')::bigint;
    IF v_modo='auto' THEN
     IF v_area_m2=v_restante THEN v_centavos:=v_alvo;
     ELSIF v_alvo<=1 THEN RAISE EXCEPTION 'Agrupe mais área para faturar o saldo de centavos.';
     ELSE v_centavos:=least(v_alvo-1,greatest(1,round(v_alvo::numeric*v_area_m2/v_restante)))::bigint;END IF;
     IF v_preco_m2<>round((v_centavos::numeric/100)/v_area_m2,4) THEN RAISE EXCEPTION 'Preço sugerido mudou. Atualize a obra.';END IF;
     v_line:=v_centavos::numeric/100;
    ELSE
     v_centavos:=round(v_area_m2*v_preco_m2*100)::bigint;
     v_line:=v_centavos::numeric/100;
    END IF;
    IF v_esperado<>v_centavos THEN RAISE EXCEPTION 'Valor em centavos divergente. Confira a emissão.';END IF;
   END IF;
   IF v_line<=0 THEN RAISE EXCEPTION 'Sem valor positivo disponível nesta área precificada. Agrupe mais área ou revise o histórico.';END IF;
   IF v_modo IS DISTINCT FROM 'manual' THEN
    v_preco_m2:=round(v_line/v_area_m2,4); v_unit:=round(v_line/v_quantidade,4);
   END IF;
   IF v_preco_m2<=0 OR v_unit<=0 THEN RAISE EXCEPTION 'Preço efetivo abaixo da precisão suportada.';END IF;
   IF v_area_m2=v_restante THEN v_abertas:=v_abertas-1;END IF;
  END IF;
  IF v_line<=0 THEN RAISE EXCEPTION 'Valor de faturamento arredondado para zero.';END IF;
  v_linhas:=v_linhas||jsonb_build_array(v_item||jsonb_build_object('valor_total_validado',v_line,'valor_unitario',v_unit)||CASE WHEN v_item ? 'area_m2' THEN jsonb_build_object('preco_m2',v_preco_m2) ELSE '{}'::jsonb END);
  v_total:=v_total+v_line;
  v_count:=v_count+1;
 END LOOP;
 SELECT coalesce(sum(valor_total),0) INTO v_faturado FROM public.ew_obra_faturamentos
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido';
 IF v_precificacao_revisao_id IS NOT NULL THEN
  IF v_abertas=0 AND v_faturado+v_total<>v_budget THEN
   RAISE EXCEPTION 'Último faturamento deve quitar exatamente o saldo contratado.';
  END IF;
  IF v_abertas>0 AND round((v_budget-v_faturado-v_total)*100)<v_abertas THEN
   RAISE EXCEPTION 'Reserve saldo financeiro para as esquadrias ainda não faturadas.';
  END IF;
 END IF;
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

CREATE OR REPLACE FUNCTION public.ew_cancelar_faturamento_financeiro(p_empresa_id uuid, p_faturamento_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;v_obra uuid;v_categoria text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_faturamento');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
  ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_faturamento'))
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar faturamento.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe motivo de cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT obra_id,categoria INTO v_obra,v_categoria FROM public.ew_obra_faturamentos WHERE id=p_faturamento_id AND empresa_id=p_empresa_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Faturamento não encontrado.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text||'|'||v_obra::text||'|'||v_categoria,0));
 SELECT status INTO v_status FROM public.ew_obra_faturamentos
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'emitido' THEN RAISE EXCEPTION 'Faturamento não pode ser cancelado.';END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado',cancelado_por=v_uid,
  cancelado_em=now(),observacoes=observacoes||' | Cancelado: '||btrim(p_motivo)
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_faturamento_id,'status','cancelado');
END;$function$;
REVOKE EXECUTE ON FUNCTION public.ew_registrar_faturamento_financeiro(uuid,uuid,text,date,text,text,jsonb,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_registrar_faturamento_financeiro(uuid,uuid,text,date,text,text,jsonb,uuid,boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.ew_cancelar_faturamento_financeiro(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_cancelar_faturamento_financeiro(uuid,uuid,text) TO authenticated;
COMMIT;
