-- Alocação de lote apenas se o histórico físico da origem for integralmente reconhecido.
-- PEPS (aquisição mais antiga; desempate pelo ID e intervalo do lote), nunca preço de cadastro.
CREATE VIEW ew_compras_interna.custo_movimentos_fisicos WITH(security_invoker=true) AS
 SELECT empresa_id,id,'OBRA'::text tipo,obra_id local_id,local_estoque galpao,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,quantidade_delta,origem,estorno_de_id
 FROM public.ew_estoque_obras_movimentos
 UNION ALL
 SELECT empresa_id,id,'EMPRESA',local_empresa_id,galpao,'TECNICO',variacao_id,comprimento_mm,unidade,quantidade_delta,origem,estorno_de_id
 FROM public.ew_compras_estoque_empresa
 UNION ALL
 SELECT m.empresa_id,m.id,'OBRA',m.obra_id,m.local_estoque,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.quantidade_delta,m.origem,m.estorno_de_id
 FROM public.ew_insumos_movimentos m JOIN public.ew_insumos_catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id;
CREATE VIEW ew_compras_interna.custo_movimentos_reconhecidos WITH(security_invoker=true) AS
 SELECT l.empresa_id,l.movimento_id id,l.cancelado_em IS NOT NULL estornado FROM ew_compras_interna.custo_lotes l
 UNION
 SELECT t.empresa_id,t.origem_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT t.empresa_id,t.destino_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL);
CREATE FUNCTION ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa uuid,p_mov uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE m record; s numeric; qtd numeric; falta numeric; a record; res jsonb:='[]'::jsonb;
BEGIN
 SELECT * INTO STRICT m FROM ew_compras_interna.custo_movimentos_fisicos WHERE empresa_id=p_empresa AND id=p_mov;
 IF m.quantidade_delta>=0 THEN RAISE EXCEPTION 'Movimento não é saída'; END IF;
 -- O chamador já detém os locks físicos. Não apropriar se existir qualquer
 -- entrada/saída sem vínculo confirmado, mesmo se o saldo líquido coincidir.
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_fisicos z
 WHERE z.empresa_id=p_empresa AND z.tipo=m.tipo AND z.local_id=m.local_id AND z.galpao=m.galpao AND z.tipo_material=m.tipo_material AND z.material_id=m.material_id AND z.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND z.unidade=m.unidade
 AND z.id<>p_mov AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=p_empresa AND r.id=z.id)
 AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=p_empresa AND r.estornado AND (r.id=z.estorno_de_id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=p_empresa AND ep.movimento_original_id=r.id AND ep.movimento_estorno_id=z.id AND ep.quantidade=abs(z.quantidade_delta))))
 ) THEN RETURN NULL; END IF;
 SELECT coalesce(sum(z.quantidade_delta),0)-m.quantidade_delta INTO s FROM ew_compras_interna.custo_movimentos_fisicos z
 WHERE z.empresa_id=p_empresa AND z.tipo=m.tipo AND z.local_id=m.local_id AND z.galpao=m.galpao AND z.tipo_material=m.tipo_material AND z.material_id=m.material_id AND z.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND z.unidade=m.unidade;
 SELECT coalesce(sum(f.quantidade),0) INTO qtd FROM ew_compras_interna.custo_saldos_fragmentos f
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=l.empresa_id AND e.fonte=l.fonte AND e.item_fiscal_id=l.item_fiscal_id AND e.movimento_id=l.movimento_id AND e.quantidade=l.quantidade AND e.custo_centavos=l.custo_centavos AND e.categoria=l.categoria
 WHERE f.empresa_id=p_empresa AND f.tipo=m.tipo AND f.local_id=m.local_id AND f.galpao=m.galpao AND e.tipo_material=m.tipo_material AND e.material_id=m.material_id AND e.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND e.unidade=m.unidade;
 IF qtd<>s OR qtd< -m.quantidade_delta THEN RETURN NULL; END IF;
 falta:=-m.quantidade_delta;
 FOR a IN SELECT f.lote_id,f.fragmento_id,f.quantidade FROM ew_compras_interna.custo_saldos_fragmentos f
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=l.empresa_id AND e.fonte=l.fonte AND e.item_fiscal_id=l.item_fiscal_id AND e.movimento_id=l.movimento_id AND e.quantidade=l.quantidade AND e.custo_centavos=l.custo_centavos AND e.categoria=l.categoria
 WHERE f.empresa_id=p_empresa AND f.tipo=m.tipo AND f.local_id=m.local_id AND f.galpao=m.galpao AND e.tipo_material=m.tipo_material AND e.material_id=m.material_id AND e.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND e.unidade=m.unidade
 ORDER BY e.criado_em,l.lote_id,f.inicio LOOP
  EXIT WHEN falta<=0;
  res:=res||jsonb_build_array(jsonb_build_object('lote_id',a.lote_id,'fragmento_id',a.fragmento_id,'quantidade',least(falta,a.quantidade)));
  falta:=falta-least(falta,a.quantidade);
 END LOOP;
 IF falta<>0 THEN RETURN NULL; END IF;
 RETURN res;
END;$f$;
CREATE OR REPLACE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid,p_fluxo text,p_transferencia uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE t record; x record; ev record; l uuid; f uuid; al jsonb; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT public.ew_pode(p_empresa,'estoque.transferir_obras') THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF t.estado<>'ATIVA' THEN RAISE EXCEPTION 'Transferência física inválida'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
 IF al IS NULL THEN
  -- Legado: somente primeira transferência com origem inequívoca.
  SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
  l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
  al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
  IF al IS NULL THEN RAISE EXCEPTION 'Histórico de custo não conciliado'; END IF;
 END IF;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,al,uid);
 RETURN true;
END;$f$;
REVOKE ALL ON ew_compras_interna.custo_movimentos_fisicos,ew_compras_interna.custo_movimentos_reconhecidos FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_alocar_saldo_comprovado(uuid,uuid),ew_compras_interna.custo_primeira_transferencia(uuid,text,uuid) FROM PUBLIC,anon,authenticated;
