BEGIN;
ALTER TABLE public.ew_compras_locais_empresa ADD COLUMN IF NOT EXISTS excluido_em timestamptz,
 ADD COLUMN IF NOT EXISTS excluido_por uuid REFERENCES auth.users(id),
 ADD COLUMN IF NOT EXISTS exclusao_motivo text;
UPDATE public.ew_permissoes_catalogo SET descricao='Cadastrar e excluir locais de estoque independentes' WHERE chave='estoque.gerenciar_locais';

-- Somente locais manuais gerados pelo fluxo legado, sem elementos de obra.
CREATE OR REPLACE FUNCTION public.ew_local_estoque_motivo(p_empresa uuid,p_tipo text,p_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
DECLARE o public.obras%rowtype;
BEGIN
 IF p_tipo='OBRA' THEN
  SELECT * INTO o FROM public.obras WHERE id=p_id AND empresa_id=p_empresa;
  IF NOT FOUND OR o.arquivada_em IS NOT NULL THEN RETURN 'Local indisponível'; END IF;
  IF o.codigo IS DISTINCT FROM 'MAN-'||upper(left(replace(o.id::text,'-',''),10))
    OR EXISTS(SELECT 1 FROM public.ew_cem_obras_materiais WHERE obra_id=p_id)
    OR EXISTS(SELECT 1 FROM public.esquadrias WHERE obra_id=p_id)
  THEN RETURN 'Vinculado a obra — cadastro permanente'; END IF;
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos WHERE obra_id=p_id GROUP BY variacao_id,comprimento_mm,unidade,local_estoque HAVING sum(quantidade_delta)<>0)
   OR EXISTS(SELECT 1 FROM public.ew_insumos_movimentos WHERE obra_id=p_id GROUP BY insumo_id,local_estoque HAVING sum(quantidade_delta)<>0)
  THEN RETURN 'Possui saldo de material'; END IF;
  IF EXISTS(SELECT 1 FROM public.romaneios WHERE obra_id=p_id AND status<>'cancelado')
   OR EXISTS(SELECT 1 FROM public.ew_obra_despesas WHERE obra_id=p_id AND status<>'cancelada')
   OR EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos WHERE obra_id=p_id AND estornado_em IS NULL)
   OR EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=p_id AND m.origem='TRANSFERENCIA' AND m.transferencia_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos r WHERE r.estorno_de_id=m.id))
  THEN RETURN 'Possui movimentação ou documento ativo'; END IF;
 ELSIF p_tipo='EMPRESA' THEN
  IF NOT EXISTS(SELECT 1 FROM public.ew_compras_locais_empresa WHERE id=p_id AND empresa_id=p_empresa AND ativo) THEN RETURN 'Local indisponível'; END IF;
  IF EXISTS(SELECT 1 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=p_id GROUP BY variacao_id,comprimento_mm,unidade,galpao HAVING sum(quantidade_delta)<>0)
  THEN RETURN 'Possui saldo de material'; END IF;
 ELSE RETURN 'Tipo inválido'; END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_solicitacoes WHERE empresa_id=p_empresa AND status='ABERTA' AND ((p_tipo='OBRA' AND obra_id=p_id) OR (p_tipo='EMPRESA' AND local_empresa_id=p_id)))
 OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos WHERE empresa_id=p_empresa AND status IN ('ABERTO','PARCIAL') AND ((p_tipo='OBRA' AND obra_id=p_id) OR (p_tipo='EMPRESA' AND local_empresa_id=p_id)))
 THEN RETURN 'Possui compra ou recebimento pendente'; END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_transferencias WHERE empresa_id=p_empresa AND estornado_em IS NULL AND ((origem_tipo=p_tipo AND origem_id=p_id) OR (destino_tipo=p_tipo AND destino_id=p_id)))
 THEN RETURN 'Possui transferência ativa'; END IF;
 RETURN NULL;
END;$f$;
REVOKE ALL ON FUNCTION public.ew_local_estoque_motivo(uuid,text,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_listar_cadastro_locais_estoque(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF NOT public.ew_pode(p_empresa_id,'estoque.gerenciar_locais') THEN RAISE EXCEPTION 'Sem permissão para gerenciar locais.'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.nome),'[]'::jsonb) FROM (
 SELECT o.id,o.nome,o.codigo,'OBRA'::text tipo,public.ew_local_estoque_motivo(p_empresa_id,'OBRA',o.id) impedimento
 FROM public.obras o WHERE o.empresa_id=p_empresa_id AND o.arquivada_em IS NULL
 UNION ALL SELECT l.id,l.nome,NULL,'EMPRESA',public.ew_local_estoque_motivo(p_empresa_id,'EMPRESA',l.id)
 FROM public.ew_compras_locais_empresa l WHERE l.empresa_id=p_empresa_id AND l.ativo
 ) x);
END;$f$;

CREATE OR REPLACE FUNCTION public.ew_excluir_cadastro_local_estoque(p_empresa_id uuid,p_tipo text,p_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_uid uuid:=auth.uid(); v_motivo text:=btrim(coalesce(p_motivo,'')); v_imp text; o public.obras%rowtype;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT public.ew_pode(p_empresa_id,'estoque.gerenciar_locais') THEN RAISE EXCEPTION 'Sem permissão para excluir locais.'; END IF;
 IF length(v_motivo) NOT BETWEEN 5 AND 350 THEN RAISE EXCEPTION 'Informe motivo de 5 a 350 caracteres.'; END IF;
 IF p_tipo='OBRA' THEN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,977124));
  SELECT * INTO o FROM public.obras WHERE id=p_id AND empresa_id=p_empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Local não encontrado'; END IF;
 ELSIF p_tipo='EMPRESA' THEN
  PERFORM 1 FROM public.ew_compras_locais_empresa WHERE id=p_id AND empresa_id=p_empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Local não encontrado'; END IF;
 ELSE RAISE EXCEPTION 'Tipo inválido'; END IF;
 v_imp:=public.ew_local_estoque_motivo(p_empresa_id,p_tipo,p_id);
 IF v_imp IS NOT NULL THEN RAISE EXCEPTION '%',v_imp; END IF;
 IF p_tipo='EMPRESA' THEN
  UPDATE public.ew_compras_locais_empresa SET ativo=false,excluido_em=now(),excluido_por=v_uid,exclusao_motivo=v_motivo WHERE id=p_id;
 ELSE
  UPDATE public.ew_estoques_locais SET excluido_em=now(),excluido_por=v_uid,restauravel_ate=now() WHERE obra_id=p_id AND empresa_id=p_empresa_id;
  UPDATE public.obras SET arquivada_em=now(),arquivada_por=v_uid,motivo_arquivamento='Exclusão de local manual: '||v_motivo WHERE id=p_id;
  INSERT INTO public.ew_auditoria_operacoes(empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
   VALUES(p_empresa_id,p_id,o.nome,o.codigo,v_uid,'ARQUIVAR_OBRA',gen_random_uuid(),v_motivo,jsonb_build_object('modo','exclusao_local_manual','historico_preservado',true));
 END IF;
 RETURN jsonb_build_object('excluido',true,'historico_preservado',true);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_listar_cadastro_locais_estoque(uuid),public.ew_excluir_cadastro_local_estoque(uuid,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_listar_cadastro_locais_estoque(uuid),public.ew_excluir_cadastro_local_estoque(uuid,text,uuid,text) TO authenticated;

-- Serializar novas entradas/solicitações com exclusão do local, sem alterar históricos.
CREATE OR REPLACE FUNCTION public.ew_local_estoque_ativo_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE j jsonb:=to_jsonb(NEW); v_id uuid; v_emp uuid:=(j->>'empresa_id')::uuid;
BEGIN
 v_id:=(j->>'local_empresa_id')::uuid;
 IF v_id IS NOT NULL THEN
  PERFORM 1 FROM public.ew_compras_locais_empresa WHERE id=v_id AND empresa_id=v_emp AND ativo FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Local empresarial excluído ou indisponível.'; END IF;
 END IF;
 v_id:=(j->>'obra_id')::uuid;
 IF v_id IS NOT NULL THEN
  -- Para locais legados manuais, impedir novos lançamentos após exclusão.
  PERFORM 1 FROM public.obras WHERE id=v_id AND empresa_id=v_emp
   AND codigo='MAN-'||upper(left(replace(id::text,'-',''),10)) FOR SHARE;
  IF FOUND AND EXISTS(SELECT 1 FROM public.obras WHERE id=v_id AND arquivada_em IS NOT NULL)
  THEN RAISE EXCEPTION 'Local manual excluído.'; END IF;
 END IF;
 RETURN NEW;
END;$f$;
REVOKE ALL ON FUNCTION public.ew_local_estoque_ativo_guard() FROM PUBLIC,anon,authenticated;
DO $g$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['ew_compras_estoque_empresa','ew_compras_solicitacoes','ew_compras_pedidos','ew_estoque_obras_movimentos','ew_insumos_movimentos'] LOOP
  EXECUTE format('CREATE TRIGGER ew_local_estoque_ativo_guard BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.ew_local_estoque_ativo_guard()',t);
 END LOOP;
END;$g$;
COMMIT;
