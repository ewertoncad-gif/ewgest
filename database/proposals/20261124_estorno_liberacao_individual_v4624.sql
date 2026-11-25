BEGIN;
-- Estorno de um registro de liberação. Sem modificar estoque ou romaneios.
-- Lotes CEM legados não têm vínculo inequívoco por registro: bloquear até estorno do lote.
CREATE OR REPLACE FUNCTION public.ew_motivo_estorno_liberacao(p_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
DECLARE l public.liberacoes_corte%rowtype; e public.esquadrias%rowtype;
BEGIN
 SELECT * INTO l FROM public.liberacoes_corte WHERE id=p_id;
 IF NOT FOUND OR l.cancelado_em IS NOT NULL THEN RETURN 'Liberação inexistente ou já estornada.'; END IF;
 SELECT * INTO e FROM public.esquadrias WHERE id=l.esquadria_id;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=e.obra_id AND arquivada_em IS NULL) THEN RETURN 'Obra arquivada.'; END IF;
 IF EXISTS(SELECT 1 FROM public.romaneios_itens i JOIN public.romaneios r ON r.id=i.romaneio_id WHERE i.esquadria_id=e.id AND r.status<>'cancelado')
 THEN RETURN 'Existe romaneio ativo desta esquadria. Cancele-o antes.'; END IF;
 IF EXISTS(SELECT 1 FROM public.saidas_producao s WHERE s.esquadria_id=e.id AND s.cancelado_em IS NULL) OR coalesce(e.qtd_fabricada,0)>0
 THEN RETURN 'Existe saída ou quantidade fabricada desta esquadria. Concilie antes.'; END IF;
 IF EXISTS(SELECT 1 FROM public.ew_liberacoes_lotes t CROSS JOIN LATERAL jsonb_array_elements(t.itens_confirmados) i WHERE t.obra_id=e.obra_id AND t.cancelado_em IS NULL AND i->>'esquadria_id'=e.id::text)
 THEN RETURN 'Esquadria vinculada a lote CEM ativo. Utilize o cancelamento do lote/obra após conferir suas dependências.'; END IF;
 IF EXISTS(SELECT 1 FROM public.ew_planos_liberados p WHERE p.liberacao_id=l.id AND p.entregue_em IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.liberacao_id=l.id AND m.quantidade_delta<0))
 OR EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.liberacao_id=l.id AND m.quantidade_delta<0 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos x WHERE x.estorno_de_id=m.id))
 THEN RETURN 'Material entregue à produção. Estorne a baixa vinculada antes.'; END IF;
 RETURN NULL;
END;$f$;
REVOKE ALL ON FUNCTION public.ew_motivo_estorno_liberacao(uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.ew_listar_estornos_liberacao(p_esquadria_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE e public.esquadrias%rowtype;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 SELECT * INTO e FROM public.esquadrias WHERE id=p_esquadria_id;
 IF NOT FOUND OR NOT public.ew_pode(e.empresa_id,'liberacoes.cancelar') THEN RAISE EXCEPTION 'Sem permissão para estornar liberações.'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.id,'quantidade',l.quantidade,'data',l.data_liberacao,'fabrica',l.fabrica,'componente',l.tipo_componente,'impedimento',public.ew_motivo_estorno_liberacao(l.id)) ORDER BY l.registrada_em DESC),'[]'::jsonb) FROM public.liberacoes_corte l WHERE l.esquadria_id=e.id AND l.cancelado_em IS NULL);
END;$f$;
CREATE OR REPLACE FUNCTION public.ew_estornar_liberacao_individual(p_liberacao_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE l public.liberacoes_corte%rowtype;e public.esquadrias%rowtype;o public.obras%rowtype;v_uid uuid:=auth.uid();v_motivo text:=btrim(coalesce(p_motivo,''));v_imp text;v_antes int;v_depois int;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 PERFORM public.ew_exigir_permissao('liberacoes.cancelar');
 SELECT * INTO l FROM public.liberacoes_corte WHERE id=p_liberacao_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Liberação não encontrada.'; END IF;
 SELECT * INTO e FROM public.esquadrias WHERE id=l.esquadria_id;
 IF v_uid IS NULL OR NOT public.ew_pode(e.empresa_id,'liberacoes.cancelar') THEN RAISE EXCEPTION 'Sem permissão.'; END IF;
 IF length(v_motivo) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo de 5 a 400 caracteres.'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(e.obra_id::text,977124));
 SELECT * INTO e FROM public.esquadrias WHERE id=l.esquadria_id FOR UPDATE;
 SELECT * INTO l FROM public.liberacoes_corte WHERE id=p_liberacao_id FOR UPDATE;
 SELECT * INTO o FROM public.obras WHERE id=e.obra_id FOR UPDATE;
 -- O almoxarife bloqueia o mesmo plano antes de conferir a liberação.
 PERFORM 1 FROM public.ew_planos_liberados WHERE liberacao_id=l.id ORDER BY id FOR UPDATE;
 v_imp:=public.ew_motivo_estorno_liberacao(l.id);
 IF v_imp IS NOT NULL THEN RAISE EXCEPTION '%',v_imp; END IF;
 SELECT greatest(coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','marco')),0),coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','folhas')),0))::int INTO v_antes FROM public.liberacoes_corte WHERE esquadria_id=e.id AND cancelado_em IS NULL;
 IF v_antes<>e.qtd_liberada THEN RAISE EXCEPTION 'Quantidade liberada inconsistente. Solicite conferência.'; END IF;
 UPDATE public.liberacoes_corte SET cancelado_em=now(),cancelado_por=v_uid,motivo_cancelamento=v_motivo WHERE id=l.id;
 SELECT greatest(coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','marco')),0),coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','folhas')),0))::int INTO v_depois FROM public.liberacoes_corte WHERE esquadria_id=e.id AND cancelado_em IS NULL;
 UPDATE public.esquadrias SET qtd_liberada=v_depois WHERE id=e.id;
 INSERT INTO public.ew_auditoria_operacoes(empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,referencia_id,motivo,detalhes)
 VALUES(e.empresa_id,e.obra_id,o.nome,o.codigo,v_uid,'CANCELAR_LIBERACOES',l.id,v_motivo,jsonb_build_object('modo','individual','esquadria',e.codigo,'liberacao_id',l.id,'quantidade',l.quantidade,'componente',l.tipo_componente,'fabrica',l.fabrica,'data_liberacao',l.data_liberacao,'qtd_liberada_antes',v_antes,'qtd_liberada_depois',v_depois));
 RETURN jsonb_build_object('cancelada',true,'qtd_liberada',v_depois,'historico_preservado',true);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_listar_estornos_liberacao(uuid),public.ew_estornar_liberacao_individual(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_listar_estornos_liberacao(uuid),public.ew_estornar_liberacao_individual(uuid,text) TO authenticated;
COMMIT;
