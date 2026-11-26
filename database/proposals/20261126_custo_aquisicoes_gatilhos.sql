-- Abertura automática por evidência fiscal completa, após concluir a transação de recebimento.
-- Nunca criar lote retroativo se existiu uma saída posterior à aquisição.
CREATE FUNCTION ew_compras_interna.custo_abrir_evidencia(p_empresa uuid,p_fonte text,p_item uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE e record;
BEGIN
 SELECT * INTO e FROM ew_compras_interna.lotes_aquisicao_evidencias
 WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item;
 IF NOT FOUND THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_lotes l WHERE l.empresa_id=p_empresa AND l.fonte=p_fonte AND l.item_fiscal_id=p_item) THEN RETURN false; END IF;
 IF e.quantidade>1000000 OR e.quantidade<>round(e.quantidade,3) THEN RETURN false; END IF;
 IF e.tipo_material='TECNICO' AND e.local_tipo='OBRA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSIF e.tipo_material='TECNICO' AND e.local_tipo='EMPRESA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_compras_estoque_empresa m WHERE m.empresa_id=p_empresa AND m.local_empresa_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSIF e.tipo_material='INSUMO' THEN
  IF EXISTS(SELECT 1 FROM public.ew_insumos_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.insumo_id=e.material_id AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSE RETURN false;
 END IF;
 PERFORM ew_compras_interna.custo_abrir_lote(p_empresa,e.fonte,e.item_fiscal_id,e.movimento_id,e.categoria,e.quantidade,e.custo_centavos,e.local_tipo,e.local_id,e.galpao);
 RETURN true;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_evento_fiscal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE j jsonb:=to_jsonb(NEW); emp uuid:=(j->>'empresa_id')::uuid; item uuid; fonte text; l record; u uuid:=auth.uid();
BEGIN
 IF emp IS NULL THEN RAISE EXCEPTION 'Empresa fiscal ausente'; END IF;
 IF TG_TABLE_NAME='ew_nfe_recebimentos' THEN item:=(j->>'despesa_item_id')::uuid; fonte:='NFE_DIRETA';
 ELSIF TG_TABLE_NAME='ew_insumos_movimentos' THEN
  IF j->>'origem'='RECEBIMENTO' THEN item:=(j->>'despesa_item_id')::uuid; fonte:='INSUMO';
  ELSE RETURN NEW; END IF;
 ELSIF TG_TABLE_NAME='ew_compras_nfe_vinculos' THEN item:=(j->>'despesa_item_id')::uuid; fonte:='PEDIDO_OBRA';
 ELSIF TG_TABLE_NAME='ew_compras_notas_empresa_itens' THEN item:=(j->>'id')::uuid; fonte:='PEDIDO_EMPRESA';
 ELSE RAISE EXCEPTION 'Tabela fiscal não prevista';
 END IF;
 IF TG_OP='UPDATE' THEN
  FOR l IN SELECT c.lote_id FROM ew_compras_interna.custo_lotes c
   WHERE c.empresa_id=emp AND c.fonte=fonte AND c.item_fiscal_id=item AND c.cancelado_em IS NULL
   AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.lotes_aquisicao_evidencias v WHERE v.empresa_id=c.empresa_id AND v.fonte=c.fonte AND v.item_fiscal_id=c.item_fiscal_id AND v.movimento_id=c.movimento_id AND v.quantidade=c.quantidade AND v.custo_centavos=c.custo_centavos AND v.categoria=c.categoria)
   ORDER BY c.lote_id FOR UPDATE
  LOOP
   IF u IS NULL THEN RAISE EXCEPTION 'Estorno fiscal sem usuário'; END IF;
   PERFORM ew_compras_interna.custo_cancelar_lote(emp,l.lote_id,gen_random_uuid(),u);
  END LOOP;
 ELSE
  PERFORM ew_compras_interna.custo_abrir_evidencia(emp,fonte,item);
 END IF;
 RETURN NEW;
END;$f$;
-- Deferir até que todos os itens da nota tenham sido gravados.
CREATE CONSTRAINT TRIGGER ew_custo_nfe_recebimento AFTER INSERT OR UPDATE OF estornado_em ON public.ew_nfe_recebimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_insumo_recebimento AFTER INSERT ON public.ew_insumos_movimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_nfe_vinculo AFTER INSERT OR UPDATE OF desvinculado_em ON public.ew_compras_nfe_vinculos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_nota_empresa_item AFTER INSERT OR UPDATE OF cancelado_em ON public.ew_compras_notas_empresa_itens DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
-- Guardar o cancelamento de cabeçalhos (inclusive insumos) após o estorno físico.
CREATE FUNCTION ew_compras_interna.custo_guardar_despesa()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE l record; u uuid:=auth.uid();
BEGIN
 IF NEW.status<>'cancelada' OR OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
 FOR l IN SELECT c.lote_id FROM ew_compras_interna.custo_lotes c
 JOIN public.ew_obra_despesas_itens i ON i.empresa_id=c.empresa_id AND i.id=c.item_fiscal_id
 WHERE c.empresa_id=NEW.empresa_id AND i.despesa_id=NEW.id AND c.fonte IN ('NFE_DIRETA','PEDIDO_OBRA','INSUMO') AND c.cancelado_em IS NULL
 ORDER BY c.lote_id FOR UPDATE OF c
 LOOP
  IF u IS NULL THEN RAISE EXCEPTION 'Estorno fiscal sem usuário'; END IF;
  PERFORM ew_compras_interna.custo_cancelar_lote(NEW.empresa_id,l.lote_id,gen_random_uuid(),u);
 END LOOP;
 RETURN NEW;
END;$f$;
CREATE CONSTRAINT TRIGGER ew_custo_despesa_cancelada AFTER UPDATE OF status ON public.ew_obra_despesas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_guardar_despesa();
REVOKE ALL ON FUNCTION ew_compras_interna.custo_abrir_evidencia(uuid,text,uuid),ew_compras_interna.custo_evento_fiscal(),ew_compras_interna.custo_guardar_despesa() FROM PUBLIC,anon,authenticated;
