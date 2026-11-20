-- Restaurar função de cancelamento de despesa anterior ao recebimento manual (20/11/2026).
-- Revisar previamente o estado de materiais recebidos; esta definição anterior não estorna estoque.
CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada' THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 UPDATE public.ew_obra_despesas SET status='cancelada',cancelado_por=v_uid,cancelado_em=now(),
  observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status','cancelada');
END;$function$

-- Para remover a nova RPC se necessário após a reversão da interface:
-- DROP FUNCTION public.ew_registrar_recebimento_manual_financeiro(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid);
