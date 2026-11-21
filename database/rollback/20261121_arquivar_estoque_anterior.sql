-- Versão anterior ao bloqueio de arquivamento de transferência entre obras.
CREATE OR REPLACE FUNCTION public.ew_excluir_estoque_local(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_count integer;v_deleted_at timestamptz;v_item uuid;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
   WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_uid AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente o ADM pode excluir um estoque.';END IF;
 SELECT id INTO v_item FROM public.ew_estoques_locais
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND excluido_em IS NULL FOR UPDATE;
 IF v_item IS NULL THEN RAISE EXCEPTION 'Estoque não encontrado ou já excluído.';END IF;
 SELECT count(distinct variacao_id) INTO v_count FROM public.ew_estoque_obras_movimentos
   WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id;
 v_deleted_at:=now();
 UPDATE public.ew_estoques_locais
 SET excluido_em=v_deleted_at,excluido_por=v_uid,
   restauravel_ate=v_deleted_at+interval '48 hours' WHERE id=v_item;
 RETURN jsonb_build_object('materiais_com_movimento',v_count,
   'restauravel_ate',v_deleted_at+interval '48 hours',
   'aviso','O estoque foi arquivado. Obra, materiais e histórico permanecem preservados.');
END;$function$;
