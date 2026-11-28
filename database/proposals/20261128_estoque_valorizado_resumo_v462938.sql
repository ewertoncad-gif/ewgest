-- EWGEST 46.29.38 — fotografia atual, somente leitura. Sem custo inventado ou novos movimentos.
BEGIN;
CREATE OR REPLACE FUNCTION public.ew_estoque_valorizado_resumo(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_result jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT public.ew_pode(p_empresa_id,'estoque.consultar')
  OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'relatorios.financeiros') THEN
  RAISE EXCEPTION 'Sem permissão para consultar estoque valorizado.';
 END IF;
 WITH movimentos AS MATERIALIZED (
 SELECT m.*,jsonb_build_array(m.tipo,m.local_id,m.galpao,m.tipo_material,m.material_id,m.comprimento_mm,m.unidade) chave,
  (EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=m.empresa_id AND r.id=m.id)
   OR EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=m.empresa_id AND r.estornado
    AND (r.id=m.estorno_de_id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=m.empresa_id AND ep.movimento_original_id=r.id AND ep.movimento_estorno_id=m.id AND ep.quantidade=abs(m.quantidade_delta))))) reconhecido
 FROM ew_compras_interna.custo_movimentos_fisicos m WHERE m.empresa_id=p_empresa_id
), fisico AS (
 SELECT chave,tipo,local_id,galpao,sum(quantidade_delta) saldo,count(*) FILTER(WHERE NOT reconhecido) movimentos_pendentes
 FROM movimentos GROUP BY chave,tipo,local_id,galpao
), fragmentos AS MATERIALIZED (
 SELECT f.tipo,f.local_id,f.galpao,f.quantidade,f.custo_centavos,e.movimento_id,
  jsonb_build_array(f.tipo,f.local_id,f.galpao,e.tipo_material,e.material_id,e.comprimento_mm,e.unidade) chave
 FROM ew_compras_interna.custo_saldos_fragmentos f
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 LEFT JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=l.empresa_id AND e.fonte=l.fonte AND e.item_fiscal_id=l.item_fiscal_id AND e.movimento_id=l.movimento_id AND e.quantidade=l.quantidade AND e.custo_centavos=l.custo_centavos AND e.categoria=l.categoria
 WHERE f.empresa_id=p_empresa_id AND f.tipo IN ('OBRA','EMPRESA')
), valorizado AS (
 SELECT chave,tipo,local_id,galpao,sum(quantidade) quantidade,sum(custo_centavos) valor
 FROM fragmentos WHERE movimento_id IS NOT NULL GROUP BY chave,tipo,local_id,galpao
), conciliacao AS (
 SELECT coalesce(f.tipo,v.tipo) tipo,coalesce(f.local_id,v.local_id) local_id,coalesce(f.galpao,v.galpao) galpao,
  coalesce(f.saldo,0) saldo,coalesce(v.quantidade,0) qtd_comprovada,coalesce(v.valor,0) valor,
  coalesce(f.movimentos_pendentes,0) movimentos_pendentes
 FROM fisico f FULL JOIN valorizado v USING(chave)
 WHERE coalesce(f.saldo,0)<>0 OR coalesce(v.quantidade,0)<>0
), avaliacao AS (
 SELECT c.*,CASE WHEN c.tipo='OBRA' THEN EXISTS(SELECT 1 FROM public.obras o WHERE o.empresa_id=p_empresa_id AND o.id=c.local_id AND o.arquivada_em IS NULL)
  WHEN c.tipo='EMPRESA' THEN EXISTS(SELECT 1 FROM public.ew_compras_locais_empresa l WHERE l.empresa_id=p_empresa_id AND l.id=c.local_id AND l.excluido_em IS NULL AND l.ativo)
  ELSE false END local_ativo
 FROM conciliacao c
), resumo AS (
 SELECT tipo,coalesce(nullif(btrim(galpao),''),'Sem galpão') galpao,
  count(*) FILTER(WHERE saldo>0) linhas_fisicas,
  count(*) FILTER(WHERE local_ativo AND saldo>0 AND saldo=qtd_comprovada AND movimentos_pendentes=0) linhas_conciliadas,
  count(*) FILTER(WHERE NOT(local_ativo AND saldo>0 AND saldo=qtd_comprovada AND movimentos_pendentes=0)) pendencias,
  coalesce(sum(valor) FILTER(WHERE local_ativo AND saldo>0 AND saldo=qtd_comprovada AND movimentos_pendentes=0),0) valor_centavos,
  0::bigint fragmentos_sem_evidencia
 FROM avaliacao GROUP BY tipo,coalesce(nullif(btrim(galpao),''),'Sem galpão')
 UNION ALL
 SELECT tipo,coalesce(nullif(btrim(galpao),''),'Sem galpão'),0,0,0,0,count(*)
 FROM fragmentos WHERE movimento_id IS NULL GROUP BY tipo,coalesce(nullif(btrim(galpao),''),'Sem galpão')
), galpoes AS (
 SELECT tipo,galpao,sum(linhas_fisicas)::bigint linhas_fisicas,sum(linhas_conciliadas)::bigint linhas_conciliadas,
  sum(pendencias)::bigint pendencias,sum(valor_centavos)::bigint valor_comprovado_centavos,sum(fragmentos_sem_evidencia)::bigint fragmentos_sem_evidencia
 FROM resumo GROUP BY tipo,galpao
)
SELECT jsonb_build_object('linhas_fisicas',coalesce(sum(linhas_fisicas),0),
 'linhas_conciliadas',coalesce(sum(linhas_conciliadas),0),'pendencias',coalesce(sum(pendencias),0),
 'fragmentos_sem_evidencia',coalesce(sum(fragmentos_sem_evidencia),0),
 'valor_comprovado_centavos',coalesce(sum(valor_comprovado_centavos),0),
 'total_centavos',CASE WHEN coalesce(sum(pendencias+fragmentos_sem_evidencia),0)=0 THEN coalesce(sum(valor_comprovado_centavos),0) ELSE NULL END,
 'galpoes',coalesce(jsonb_agg(to_jsonb(galpoes) ORDER BY galpao,tipo),'[]'::jsonb)) INTO v_result FROM galpoes;
 RETURN v_result;
END;$function$;
REVOKE EXECUTE ON FUNCTION public.ew_estoque_valorizado_resumo(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_estoque_valorizado_resumo(uuid) TO authenticated;
COMMIT;
