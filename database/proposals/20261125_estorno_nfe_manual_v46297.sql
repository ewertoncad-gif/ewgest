BEGIN;
-- Cancelamento interno integral de notas XML ou manuais com recebimento físico, não cancelamento fiscal na SEFAZ.
-- Sem apagar histórico, sem cancelar nota com recebimento consumido, transferido ou conciliado.
CREATE OR REPLACE FUNCTION public.ew_estornar_nfe_com_recebimentos(p_empresa_id uuid,p_recebimento_id uuid,p_motivo text,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_uid uuid:=auth.uid();v_despesa uuid;v_obra uuid;v_doc public.ew_obra_despesas%rowtype;
 v_item uuid;v_rec record;v_count int:=0;v_motivo text:=btrim(coalesce(p_motivo,''));
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_operacao_id IS NULL OR NOT public.ew_pode(p_empresa_id,'estoque.estornar') OR NOT public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas') THEN
 RAISE EXCEPTION 'O estorno integral exige permissão de estoque e cancelamento financeiro.'; END IF;
 IF length(v_motivo) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo de 5 a 400 caracteres.'; END IF;
 SELECT i.despesa_id,r.obra_id INTO v_despesa,v_obra FROM public.ew_nfe_recebimentos r JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
 WHERE r.id=p_recebimento_id AND r.empresa_id=p_empresa_id AND i.empresa_id=p_empresa_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Recebimento não encontrado.'; END IF;
 -- Mesma ordem de bloqueio da entrada NF-e: item antes do cabeçalho.
 FOR v_item IN SELECT id FROM public.ew_obra_despesas_itens WHERE despesa_id=v_despesa AND empresa_id=p_empresa_id ORDER BY id LOOP
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_item::text,912423));
 END LOOP;
 SELECT * INTO v_doc FROM public.ew_obra_despesas WHERE id=v_despesa AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR (v_doc.origem IS NULL OR v_doc.origem NOT IN ('nfe_xml','manual')) OR v_doc.obra_id IS DISTINCT FROM v_obra OR v_doc.categoria NOT IN ('aluminio','acessorios') THEN RAISE EXCEPTION 'Nota de materiais indisponível.'; END IF;
 IF v_doc.status='cancelada' THEN RETURN jsonb_build_object('ja_estornado',true,'despesa_id',v_doc.id); END IF;
 IF v_doc.status<>'aprovada' THEN RAISE EXCEPTION 'A nota não está aprovada.'; END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_nfe_conciliacoes WHERE despesa_id=v_despesa AND desvinculado_em IS NULL) THEN RAISE EXCEPTION 'Desvincule a conciliação com o pedido antes do estorno.'; END IF;
 -- Travar todos os recebimentos antes da primeira rotina física, que trava a obra.
 FOR v_rec IN SELECT r.id FROM public.ew_nfe_recebimentos r JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
 WHERE i.despesa_id=v_despesa AND r.empresa_id=p_empresa_id AND r.estornado_em IS NULL ORDER BY r.id LOOP
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_rec.id::text,912425));
 END LOOP;
 -- Cada entrada passa pelas mesmas verificações físicas já existentes.
 -- Qualquer erro desfaz TODOS os estornos desta transação.
 FOR v_rec IN SELECT r.id FROM public.ew_nfe_recebimentos r JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
 WHERE i.despesa_id=v_despesa AND r.empresa_id=p_empresa_id AND r.estornado_em IS NULL ORDER BY r.variacao_id,r.comprimento_mm,r.unidade,r.id LOOP
  PERFORM public.ew_estornar_recebimento_nfe(p_empresa_id,v_rec.id,v_motivo,gen_random_uuid());v_count:=v_count+1;
 END LOOP;
 PERFORM public.ew_cancelar_despesa_financeira(p_empresa_id,v_despesa,v_motivo);
 RETURN jsonb_build_object('ja_estornado',false,'despesa_id',v_doc.id,'recebimentos_estornados',v_count,'valor_restaurado',v_doc.valor);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_estornar_nfe_com_recebimentos(uuid,uuid,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_estornar_nfe_com_recebimentos(uuid,uuid,text,uuid) TO authenticated;
COMMIT;