-- EWGEST | Transferência entre estoques de obras da mesma empresa.
-- Não cria estoque físico; registra saída e entrada vinculadas na mesma transação.
-- Compatível com a função existente de transferência ENTRE GALPÕES da mesma obra.
CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras(
 p_empresa_id uuid,
 p_origem_obra_id uuid,
 p_destino_obra_id uuid,
 p_variacao_id uuid,
 p_comprimento_mm integer,
 p_unidade text,
 p_quantidade numeric,
 p_origem_local text,
 p_destino_local text,
 p_observacao text,
 p_operacao_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $ewg$
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
 PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
  NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
    WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_usuario
     AND u.perfil IN ('administrador','gerenciador'))
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
 RETURN jsonb_build_object('repetida',false,'quantidade',p_quantidade,
  'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id,
  'saldo_origem',v_saldo-p_quantidade,'comprimento_mm',p_comprimento_mm);
END;
$ewg$;

REVOKE ALL ON FUNCTION public.ew_transferir_estoque_entre_obras(
 uuid,uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_transferir_estoque_entre_obras(
 uuid,uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid)
 TO authenticated;
NOTIFY pgrst, 'reload schema';
