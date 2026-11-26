-- Integração piloto (não publicar antes de cobrir todos os caminhos de estoque).
-- Usa a prévia estrita apenas para aquisição inequívoca e primeira transferência.
-- Operações sem evidência continuam com custo pendente, sem preço estimado.
CREATE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid,p_fluxo text,p_transferencia uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE x record; ev record; l uuid; f uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT public.ew_pode(p_empresa,'estoque.transferir_obras') THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias
 WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
 l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
 SELECT fragmento_id INTO STRICT f FROM ew_compras_interna.custo_saldos_fragmentos
 WHERE empresa_id=p_empresa AND lote_id=l AND evento_origem IS NULL AND tipo=ev.local_tipo AND local_id=ev.local_id AND galpao=ev.galpao;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,jsonb_build_array(jsonb_build_object('lote_id',l,'fragmento_id',f,'quantidade',x.quantidade)),uid);
 RETURN true;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_estornar_se_integrada(p_empresa uuid,p_fluxo text,p_transferencia uuid,p_op uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
BEGIN
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'estoque.estornar') THEN RAISE EXCEPTION 'Sem autorização para estornar'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_transferencias_integradas WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia) THEN RETURN false; END IF;
 PERFORM ew_compras_interna.custo_integrar_estorno(p_empresa,p_fluxo,p_transferencia,p_op,auth.uid());
 RETURN true;
END;$f$;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_primeira_transferencia(uuid,text,uuid),ew_compras_interna.custo_estornar_se_integrada(uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_usuario uuid:=auth.uid();
 v_origem_local text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino_local text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;
 v_unidade_acessorio text;
 v_saldo numeric;
 v_quantidade_movimentos integer;
 v_origem_codigo text;
 v_destino_codigo text;
 v_chave_origem text;
 v_chave_destino text;
 v_observacao text;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.transferir_obras');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
  NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
    WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_usuario
     AND public.ew_pode(p_empresa_id,'estoque.transferir_obras'))
 THEN RAISE EXCEPTION 'Somente ADM pode transferir estoque entre obras.'; END IF;

 IF p_origem_obra_id IS NULL OR p_destino_obra_id IS NULL OR
    p_origem_obra_id=p_destino_obra_id
 THEN RAISE EXCEPTION 'Selecione obras de origem e destino diferentes.'; END IF;

 SELECT codigo INTO v_origem_codigo FROM public.obras
 WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 SELECT codigo INTO v_destino_codigo FROM public.obras
 WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 IF NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_origem_obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_destino_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Obra ou estoque inexistente, de outra empresa ou arquivado.'; END IF;

 IF v_origem_local='' OR v_destino_local='' OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_origem_local AND ativo) OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_destino_local AND ativo)
 THEN RAISE EXCEPTION 'Galpão de origem ou destino inválido.'; END IF;

 SELECT v.tipo,upper(btrim(a.unidade_item))
 INTO v_tipo,v_unidade_acessorio
 FROM public.ew_materiais_variacoes v
 LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id AND a.empresa_id=p_empresa_id
 WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id AND v.ativo;
 IF v_tipo IS NULL OR p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
    (v_tipo='perfil' AND
      (p_unidade IS DISTINCT FROM 'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000
       OR p_comprimento_mm IS NULL OR p_quantidade<>trunc(p_quantidade))) OR
    (v_tipo='acessorio' AND
      (p_comprimento_mm IS NOT NULL OR
       p_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') OR
       p_unidade IS DISTINCT FROM v_unidade_acessorio OR
       p_quantidade<>round(p_quantidade,3)))
 THEN RAISE EXCEPTION 'Material, comprimento, unidade ou quantidade inválidos.'; END IF;
 IF char_length(btrim(coalesce(p_observacao,''))) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe um motivo de 5 a 350 caracteres.'; END IF;

 -- Uma mesma operação não pode ser executada em paralelo, nem reutilizada
 -- para mudar origem, destino, material ou quantidade.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'TRANSF_OBRAS|'||p_operacao_id::text,62841));
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
    WHERE m.transferencia_id=p_operacao_id AND m.empresa_id<>p_empresa_id)
 THEN RAISE EXCEPTION 'Identificador de transferência já utilizado.'; END IF;

 SELECT count(*) INTO v_quantidade_movimentos
 FROM public.ew_estoque_obras_movimentos
 WHERE transferencia_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF v_quantidade_movimentos>0 THEN
  IF v_quantidade_movimentos<>2 OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_origem_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_origem_local
      AND quantidade_delta=-p_quantidade AND origem='TRANSFERENCIA') OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_destino_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_destino_local
      AND quantidade_delta=p_quantidade AND origem='TRANSFERENCIA')
  THEN RAISE EXCEPTION 'Identificador já utilizado para outra transferência.'; END IF;
  RETURN jsonb_build_object('repetida',true,'quantidade',p_quantidade,
    'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id);
 END IF;

 -- Mesma chave de lock do estoque normal. Ordenação estável evita deadlock
 -- quando duas obras transferem materiais entre si ao mesmo tempo.
 v_chave_origem:=p_origem_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 v_chave_destino:=p_destino_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   least(v_chave_origem,v_chave_destino),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   greatest(v_chave_origem,v_chave_destino),34777));
 SELECT coalesce(sum(m.quantidade_delta),0) INTO v_saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_origem_obra_id
  AND m.variacao_id=p_variacao_id AND
  m.comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
  AND m.unidade=p_unidade AND m.local_estoque=v_origem_local;
 IF v_saldo<p_quantidade
 THEN RAISE EXCEPTION 'Saldo insuficiente na obra de origem. Disponível: % %.',v_saldo,p_unidade; END IF;

 v_observacao:='Remanejamento entre obras '||coalesce(v_origem_codigo,'—')||
  ' → '||coalesce(v_destino_codigo,'—')||' · '||btrim(p_observacao);
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 VALUES
 (p_empresa_id,p_origem_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  -p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_origem_local,p_operacao_id),
 (p_empresa_id,p_destino_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_destino_local,p_operacao_id);
 PERFORM ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'OBRAS',p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'quantidade',p_quantidade,
  'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id,
  'saldo_origem',v_saldo-p_quantidade,'comprimento_mm',p_comprimento_mm);
END;
$function$;
-- Preserva toda a lógica física e valida a flag da empresa alvo, sem restringir perfil nominal.
CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras(p_empresa_id uuid, p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_debito public.ew_estoque_obras_movimentos%rowtype;
 v_credito public.ew_estoque_obras_movimentos%rowtype;
 v_n integer;
 v_saldo numeric;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_key_a text;
 v_key_b text;
 v_local_disponivel text;
 v_saldo_total numeric;
 v_alocacao record;
 v_falta numeric;
 v_parcela numeric;
 v_estorno_id uuid;
 v_primeiro boolean:=true;
 v_locais jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_empresa_id IS NULL OR p_transferencia_id IS NULL OR p_operacao_id IS NULL
 OR v_uid IS NULL OR NOT public.ew_pode(p_empresa_id,'estoque.estornar')
 THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estorno de transferência entre obras.'; END IF;
 IF char_length(v_motivo) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe motivo de 5 a 350 caracteres.'; END IF;

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'ESTORNO_TRANSF_OBRAS|'||p_operacao_id::text,62841));
 -- Operação repetida só pode corresponder à mesma transferência, empresa
 -- e a TODAS as parcelas: o primeiro estorno está no campo estorno_de_id
 -- (UNIQUE), as demais são ligadas pela tabela interna ew_estornos_parcelas.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE transferencia_id=p_operacao_id AND origem='ESTORNO') THEN
  SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos m
  WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO';
  IF v_n>=2 AND
   (SELECT count(*) FROM public.ew_estornos_parcelas ep
    WHERE ep.operacao_id=p_operacao_id AND ep.empresa_id=p_empresa_id)=v_n
   AND NOT EXISTS(
    SELECT 1 FROM public.ew_estoque_obras_movimentos m
    LEFT JOIN public.ew_estornos_parcelas ep
     ON ep.movimento_estorno_id=m.id AND ep.operacao_id=p_operacao_id
    LEFT JOIN public.ew_estoque_obras_movimentos original
     ON original.id=ep.movimento_original_id
    WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO'
    AND (ep.id IS NULL OR ep.empresa_id<>p_empresa_id
     OR original.transferencia_id IS DISTINCT FROM p_transferencia_id
     OR m.empresa_id<>p_empresa_id
     OR ep.quantidade<>abs(m.quantidade_delta)
     OR ep.local_estoque<>m.local_estoque)
   )
  THEN RETURN jsonb_build_object('repetida',true,'estornados',v_n); END IF;
  RAISE EXCEPTION 'Identificador já utilizado ou estorno parcial inconsistente.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estornos_parcelas
   WHERE operacao_id=p_operacao_id) THEN
   RAISE EXCEPTION 'Identificador de estorno já utilizado.';
 END IF;

 SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id AND origem='TRANSFERENCIA';
 IF v_n<>2 THEN RAISE EXCEPTION 'Transferência entre obras não localizada ou incompleta.';END IF;
 SELECT * INTO v_debito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta<0;
 SELECT * INTO v_credito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta>0;
 IF v_debito.id IS NULL OR v_credito.id IS NULL OR
  v_debito.obra_id=v_credito.obra_id OR
  v_debito.variacao_id IS DISTINCT FROM v_credito.variacao_id OR
  v_debito.comprimento_mm IS DISTINCT FROM v_credito.comprimento_mm OR
  v_debito.unidade IS DISTINCT FROM v_credito.unidade OR
  v_debito.quantidade_delta<>-v_credito.quantidade_delta
 THEN RAISE EXCEPTION 'Movimentos da transferência não formam um par íntegro.'; END IF;

 v_key_a:=v_debito.obra_id::text;
 v_key_b:=v_credito.obra_id::text;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),977124));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),977124));
 IF NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_debito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_credito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_debito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_credito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL)
 THEN RAISE EXCEPTION 'Uma das obras ou estoques está arquivada.'; END IF;

 -- Estorno individual: dependências físicas do material, não pendências gerais da obra.
 -- Mesmo lock do estoque normal; origem e destino em ordem estável.
 v_key_a:=v_debito.obra_id::text||'|'||v_debito.variacao_id::text||'|'||
  coalesce(v_debito.comprimento_mm::text,'-')||'|'||v_debito.unidade;
 v_key_b:=v_credito.obra_id::text||'|'||v_credito.variacao_id::text||'|'||
  coalesce(v_credito.comprimento_mm::text,'-')||'|'||v_credito.unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),34777));

 IF EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos
  WHERE estorno_de_id IN (v_debito.id,v_credito.id))
 THEN RAISE EXCEPTION 'Uma das pernas já foi estornada. Recarregue o histórico.';END IF;
 -- O saldo disponível não prova que o lote transferido não foi utilizado:
 -- sem lote individual, bloquear consumos posteriores ainda não estornados.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0
   AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','SAIDA_OBRA','AJUSTE')
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Estorno bloqueado: material consumido na obra de destino. Cancele o romaneio, reverta a saída e estorne a baixa primeiro.';END IF;
 -- Transferências posteriores para OUTRAS obras devem ser desfeitas em ordem inversa.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
   AND m.transferencia_id IS DISTINCT FROM p_transferencia_id
   AND (EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
    WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
     AND other.obra_id<>m.obra_id) OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t
      WHERE t.empresa_id=p_empresa_id AND t.movimento_origem_obra_id=m.id AND t.estornado_em IS NULL
        AND t.destino_tipo='EMPRESA'))
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
    WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Material enviado posteriormente para outra obra. Devolva-o primeiro à obra de destino antes de estornar esta transferência.'; END IF;
 -- Não cancelar um material enquanto algum galpão da obra apresenta
 -- saldo negativo para a mesma combinação de variação, unidade e medida.
 IF EXISTS(
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<0
 ) THEN RAISE EXCEPTION 'Saldo negativo na obra destino. Concilie antes de devolver.'; END IF;
 SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_saldo_total
 FROM (SELECT sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
    AND m.variacao_id=v_credito.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
    AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque) t;
 IF v_saldo_total<v_credito.quantidade_delta THEN
  RAISE EXCEPTION 'Saldo insuficiente na obra destino: disponível % de % %.',
    v_saldo_total,v_credito.quantidade_delta,v_credito.unidade;
 END IF;
 v_falta:=v_credito.quantidade_delta;
 v_n:=0;
 -- Descontar exatamente a quantidade que está em cada galpão, sem transferir
 -- o material de volta ao galpão histórico antes de cancelar a operação.
 FOR v_alocacao IN
  SELECT m.local_estoque,sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)>0
  ORDER BY (m.local_estoque=v_credito.local_estoque) DESC,m.local_estoque
 LOOP
  EXIT WHEN v_falta<=0;
  v_parcela:=least(v_falta,v_alocacao.saldo);
  INSERT INTO public.ew_estoque_obras_movimentos
  (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
  VALUES (p_empresa_id,v_credito.obra_id,v_credito.variacao_id,
   v_credito.comprimento_mm,v_credito.unidade,-v_parcela,'ESTORNO',
   gen_random_uuid(),left('Estorno transferência entre obras: '||v_motivo,500),
   v_uid,v_alocacao.local_estoque,p_operacao_id,
   CASE WHEN v_primeiro THEN v_credito.id ELSE NULL END)
  RETURNING id INTO v_estorno_id;
  INSERT INTO public.ew_estornos_parcelas
   (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
    local_estoque,quantidade)
  VALUES(p_empresa_id,v_credito.obra_id,p_operacao_id,v_credito.id,v_estorno_id,
   v_alocacao.local_estoque,v_parcela);
  IF v_primeiro THEN v_local_disponivel:=v_alocacao.local_estoque; END IF;
  v_primeiro:=false;
  v_falta:=v_falta-v_parcela;
  v_n:=v_n+1;
  v_locais:=v_locais||jsonb_build_array(jsonb_build_object(
   'obra_id',v_credito.obra_id,'galpao',v_alocacao.local_estoque,
   'quantidade',v_parcela,'movimento_estorno_id',v_estorno_id,
   'movimento_original_id',v_credito.id));
 END LOOP;
 IF v_falta<>0 THEN
  RAISE EXCEPTION 'Alocação física inconsistente: faltam % %. Operação revertida.',v_falta,v_credito.unidade;
 END IF;
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
 VALUES (p_empresa_id,v_debito.obra_id,v_debito.variacao_id,v_debito.comprimento_mm,
  v_debito.unidade,-v_debito.quantidade_delta,'ESTORNO',gen_random_uuid(),
  left('Devolução para obra de origem: '||v_motivo,500),v_uid,
  v_debito.local_estoque,p_operacao_id,v_debito.id)
 RETURNING id INTO v_estorno_id;
 INSERT INTO public.ew_estornos_parcelas
  (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
   local_estoque,quantidade)
 VALUES (p_empresa_id,v_debito.obra_id,p_operacao_id,v_debito.id,v_estorno_id,
  v_debito.local_estoque,-v_debito.quantidade_delta);
 v_n:=v_n+1;
 INSERT INTO public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
   referencia_id,operacao_id,motivo,detalhes)
 VALUES (p_empresa_id,v_debito.obra_id,
  (SELECT nome FROM public.obras WHERE id=v_debito.obra_id),
  (SELECT codigo FROM public.obras WHERE id=v_debito.obra_id),
  v_uid,'ESTORNAR_ESTOQUE',v_debito.id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','transferencia_entre_obras',
   'transferencia_original_id',p_transferencia_id,
   'obra_origem_id',v_debito.obra_id,'obra_destino_id',v_credito.obra_id,
   'galpao_devolucao_origem',v_debito.local_estoque,
   'parcelas_destino',v_locais,'movimentos_estornados',v_n));
 PERFORM ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'OBRAS',p_transferencia_id,p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'estornados',v_n,
  'origem_obra_id',v_debito.obra_id,'destino_obra_id',v_credito.obra_id,
  'galpao_da_retirada',v_local_disponivel,'parcelas',v_locais,
  'historico_preservado',true);
END;
$function$;
