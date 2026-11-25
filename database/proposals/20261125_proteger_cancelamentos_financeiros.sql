-- Preserve os fluxos de cancelamento e revisão por RPC; impeça alteração direta do estado.
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_estado_financeiro() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF current_user IN ('authenticated','anon') THEN
  IF TG_OP='UPDATE' THEN
   IF (NEW.status,NEW.cancelado_em,NEW.cancelado_por) IS DISTINCT FROM (OLD.status,OLD.cancelado_em,OLD.cancelado_por)
   THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: altere o estado financeiro pela rotina de cancelamento ou revisão.'; END IF;
   IF OLD.status IN ('cancelada','cancelado') THEN RAISE EXCEPTION 'Documento cancelado: histórico imutável.'; END IF;
  ELSIF NEW.status IN ('cancelada','cancelado') OR NEW.cancelado_em IS NOT NULL OR NEW.cancelado_por IS NOT NULL THEN
   RAISE EXCEPTION 'PERMISSAO_NEGADA: não é possível inserir documento cancelado diretamente.';
  END IF;
 END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_estado_financeiro() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_estado_financeiro_guard BEFORE INSERT OR UPDATE ON public.ew_obra_despesas FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_estado_financeiro();
CREATE TRIGGER ew_estado_financeiro_guard BEFORE INSERT OR UPDATE ON public.ew_obra_faturamentos FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_estado_financeiro();

CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas'))
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada'
 THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r
    JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
    WHERE i.despesa_id=p_despesa_id AND r.empresa_id=p_empresa_id AND r.estornado_em is null)
 THEN RAISE EXCEPTION 'Esta nota possui materiais recebidos. Estorne as entradas de estoque antes de cancelar a despesa.';END IF;
 IF EXISTS(
    select 1 from public.ew_insumos_movimentos m
    join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
    where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id
     and m.origem='RECEBIMENTO'
 ) THEN RAISE EXCEPTION 'Nota com vidros/outros no estoque: use o cancelamento com estorno físico.';END IF;
 UPDATE public.ew_obra_despesas
 SET status='cancelada',cancelado_por=v_uid,cancelado_em=now(),
 observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status','cancelada');
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_cancelar_faturamento_financeiro(p_empresa_id uuid, p_faturamento_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_faturamento');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
  ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_faturamento'))
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar faturamento.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe motivo de cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_faturamentos
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'emitido' THEN RAISE EXCEPTION 'Faturamento não pode ser cancelado.';END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado',cancelado_por=v_uid,
  cancelado_em=now(),observacoes=observacoes||' | Cancelado: '||btrim(p_motivo)
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_faturamento_id,'status','cancelado');
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_revisar_nfe_almox(p_empresa_id uuid, p_despesa_id uuid, p_acao text, p_justificativa text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas'))
 THEN RAISE EXCEPTION 'Somente ADM pode aprovar ou rejeitar notas.';END IF;
 IF p_acao NOT IN ('aprovar','rejeitar') OR length(coalesce(p_justificativa,''))>400
 THEN RAISE EXCEPTION 'Ação ou justificativa inválida.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'pendente' THEN RAISE EXCEPTION 'A nota não está pendente de aprovação.';END IF;
 IF p_acao='rejeitar' AND length(btrim(coalesce(p_justificativa,'')))<5
 THEN RAISE EXCEPTION 'Informe motivo da rejeição com pelo menos 5 caracteres.';END IF;
 UPDATE public.ew_obra_despesas SET
  status=CASE WHEN p_acao='aprovar' THEN 'aprovada' ELSE 'cancelada' END,
  aprovado_por=CASE WHEN p_acao='aprovar' THEN v_uid ELSE NULL END,
  aprovado_em=CASE WHEN p_acao='aprovar' THEN now() ELSE NULL END,
  cancelado_por=CASE WHEN p_acao='rejeitar' THEN v_uid ELSE NULL END,
  cancelado_em=CASE WHEN p_acao='rejeitar' THEN now() ELSE NULL END,
  observacoes=coalesce(observacoes,'')||CASE WHEN p_acao='rejeitar' THEN ' | Rejeição: '||btrim(p_justificativa) ELSE '' END
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status',CASE WHEN p_acao='aprovar' THEN 'aprovada' ELSE 'cancelada' END);
END;$function$;

REVOKE EXECUTE ON FUNCTION public.ew_cancelar_despesa_financeira(uuid,uuid,text), public.ew_cancelar_faturamento_financeiro(uuid,uuid,text), public.ew_revisar_nfe_almox(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_cancelar_despesa_financeira(uuid,uuid,text), public.ew_cancelar_faturamento_financeiro(uuid,uuid,text), public.ew_revisar_nfe_almox(uuid,uuid,text,text) TO authenticated;
