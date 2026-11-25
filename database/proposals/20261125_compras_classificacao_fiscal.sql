BEGIN;
-- Nota aprovada sem lastro fiscal suficiente não vira desconto definitivo duplicado.
-- A classificação explícita de saldo avulso fica auditada e vinculada ao estado da nota.
CREATE TABLE ew_compras_interna.classificacoes_fiscais(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 despesa_id uuid NOT NULL REFERENCES public.ew_obra_despesas(id) ON DELETE CASCADE,
 assinatura text NOT NULL,motivo text NOT NULL,usuario_id uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(despesa_id,assinatura)
);
ALTER TABLE ew_compras_interna.classificacoes_fiscais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.classificacoes_fiscais FROM PUBLIC,anon,authenticated;
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES
 ('compras.classificar_nota_avulsa','Compras','Confirmar nota ou saldo fiscal não pertencente a pedidos aprovados',46)
ON CONFLICT DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,'compras.classificar_nota_avulsa',CASE WHEN n.nivel=1 THEN true WHEN n.nivel IN(2,5) THEN coalesce(f.permitido,false) AND coalesce(v.permitido,false) ELSE false END
FROM public.ew_niveis_acesso n
LEFT JOIN public.ew_niveis_permissoes f ON f.empresa_id=n.empresa_id AND f.nivel=n.nivel AND f.chave='financeiro.despesas'
LEFT JOIN public.ew_niveis_permissoes v ON v.empresa_id=n.empresa_id AND v.nivel=n.nivel AND v.chave='compras.consultar_valores'
ON CONFLICT DO NOTHING;
CREATE FUNCTION ew_compras_interna.notas_estado(e uuid,o uuid)
RETURNS TABLE(despesa_id uuid,categoria text,valor_centavos bigint,fornecedor text,numero_documento text,assinatura text,pendente boolean)
LANGUAGE sql STABLE SET search_path='' AS $f$
 WITH links AS (
 SELECT c.despesa_id,c.pedido_id,v.despesa_item_id,v.chave,v.id,v.quantidade_nota,v.quantidade_fisica
 FROM public.ew_compras_nfe_conciliacoes c
 JOIN public.ew_compras_nfe_vinculos v ON v.conciliacao_id=c.id AND v.desvinculado_em IS NULL
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 JOIN public.ew_compras_pedidos p ON p.id=c.pedido_id AND p.empresa_id=e AND p.obra_id=o AND p.status<>'CANCELADO'
 WHERE c.empresa_id=e AND c.desvinculado_em IS NULL
 ), itens AS (
 SELECT i.despesa_id,i.id,i.quantidade,i.valor_total,coalesce(sum(l.quantidade_nota),0) vinculada
 FROM public.ew_obra_despesas_itens i
 JOIN public.ew_obra_despesas d ON d.id=i.despesa_id AND d.empresa_id=e AND d.obra_id=o AND d.status='aprovada'
 LEFT JOIN links l ON l.despesa_item_id=i.id AND l.despesa_id=i.despesa_id
 GROUP BY i.despesa_id,i.id,i.quantidade,i.valor_total
 ), pedidos AS (
 SELECT p.id,f.nome,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END categoria,
 (x->>'quantidade')::numeric>coalesce((SELECT sum(l.quantidade_fisica) FROM links l WHERE l.pedido_id=p.id AND l.chave=x->>'chave'),0) aberto
 FROM public.ew_compras_pedidos p JOIN public.ew_fornecedores f ON f.id=p.fornecedor_id AND f.empresa_id=e
 CROSS JOIN LATERAL jsonb_array_elements(p.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=e
 WHERE p.empresa_id=e AND p.obra_id=o AND p.status<>'CANCELADO'
 ), notas AS (
 SELECT d.id,d.categoria,round(d.valor*100)::bigint valor_centavos,d.fornecedor,d.numero_documento,
 md5(jsonb_build_array(d.valor,d.categoria,d.fornecedor,
   (SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id) FROM itens i WHERE i.despesa_id=d.id),
   (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.id) FROM links l WHERE l.despesa_id=d.id))::text) assinatura,
 (NOT EXISTS(SELECT 1 FROM itens i WHERE i.despesa_id=d.id) OR EXISTS(SELECT 1 FROM itens i WHERE i.despesa_id=d.id AND i.vinculada<i.quantidade)) incompleta,
 (EXISTS(SELECT 1 FROM links l WHERE l.despesa_id=d.id) OR EXISTS(SELECT 1 FROM pedidos p WHERE p.categoria=d.categoria AND p.aberto AND (nullif(btrim(d.fornecedor),'') IS NULL OR lower(btrim(p.nome))=lower(btrim(d.fornecedor))))) candidata
 FROM public.ew_obra_despesas d WHERE d.empresa_id=e AND d.obra_id=o AND d.status='aprovada'
 )
 SELECT n.id,n.categoria,n.valor_centavos,n.fornecedor,n.numero_documento,n.assinatura,
 n.incompleta AND n.candidata AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.classificacoes_fiscais c WHERE c.empresa_id=e AND c.despesa_id=n.id AND c.assinatura=n.assinatura)
 FROM notas n
$f$;
CREATE FUNCTION public.ew_compras_classificar_nota_avulsa(p_empresa_id uuid,p_obra_id uuid,p_despesa_id uuid,p_assinatura text,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE n record;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'financeiro.despesas') AND public.ew_pode(p_empresa_id,'financeiro.consultar') AND public.ew_pode(p_empresa_id,'compras.consultar_valores') AND public.ew_pode(p_empresa_id,'compras.classificar_nota_avulsa')) THEN RAISE EXCEPTION 'Sem permissão para classificar nota.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 8 AND 400 THEN RAISE EXCEPTION 'Informe justificativa de 8 a 400 caracteres.';END IF;
 PERFORM 1 FROM public.ew_obra_despesas WHERE id=p_despesa_id AND empresa_id=p_empresa_id AND obra_id=p_obra_id AND status='aprovada' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Nota indisponível.';END IF;
 SELECT * INTO n FROM ew_compras_interna.notas_estado(p_empresa_id,p_obra_id) WHERE despesa_id=p_despesa_id;
 IF NOT FOUND OR n.assinatura IS DISTINCT FROM p_assinatura THEN RAISE EXCEPTION 'A nota mudou. Atualize o financeiro antes de classificar.';END IF;
 IF NOT n.pendente THEN
  IF EXISTS(SELECT 1 FROM ew_compras_interna.classificacoes_fiscais WHERE despesa_id=p_despesa_id AND assinatura=p_assinatura AND empresa_id=p_empresa_id) THEN RETURN jsonb_build_object('repetida',true);END IF;
  RAISE EXCEPTION 'Nota sem pendência de classificação.';
 END IF;
 INSERT INTO ew_compras_interna.classificacoes_fiscais(empresa_id,despesa_id,assinatura,motivo,usuario_id) VALUES(p_empresa_id,p_despesa_id,p_assinatura,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetida',false,'despesa_id',p_despesa_id);
END;$f$;
REVOKE ALL ON FUNCTION ew_compras_interna.notas_estado(uuid,uuid),public.ew_compras_classificar_nota_avulsa(uuid,uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_classificar_nota_avulsa(uuid,uuid,uuid,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.ew_compras_compromissos_obra(p_empresa_id uuid,p_obra_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem acesso financeiro à obra.';END IF;
 RETURN (WITH notas AS MATERIALIZED (SELECT * FROM ew_compras_interna.notas_estado(p_empresa_id,p_obra_id)), linhas AS (
 SELECT p.id pedido_id,x->>'chave' chave,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END categoria,
 (x->>'quantidade')::numeric qtd,(x->>'preco_unitario_centavos')::bigint preco
 FROM public.ew_compras_pedidos p CROSS JOIN LATERAL jsonb_array_elements(p.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=p.empresa_id
 WHERE p.empresa_id=p_empresa_id AND p.obra_id=p_obra_id AND p.status<>'CANCELADO'
 ), conciliado AS (
 SELECT c.pedido_id,v.chave,sum(v.quantidade_fisica) qtd
 FROM public.ew_compras_nfe_conciliacoes c JOIN public.ew_compras_nfe_vinculos v ON v.conciliacao_id=c.id AND v.desvinculado_em IS NULL
 JOIN notas d ON d.despesa_id=c.despesa_id AND NOT d.pendente
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 WHERE c.empresa_id=p_empresa_id AND c.desvinculado_em IS NULL GROUP BY c.pedido_id,v.chave
 ), compromissos AS (
 SELECT l.categoria,sum(round(l.qtd*l.preco)) total_pedido_centavos,
 sum(round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) conciliado_centavos,
 sum(round(l.qtd*l.preco)-round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) pendente_centavos
 FROM linhas l LEFT JOIN conciliado c ON c.pedido_id=l.pedido_id AND c.chave=l.chave GROUP BY l.categoria
 ), despesas AS (
 SELECT categoria,coalesce(sum(valor_centavos) FILTER(WHERE NOT pendente),0) realizado_centavos,
 coalesce(sum(valor_centavos) FILTER(WHERE pendente),0) pendencia_centavos,
 coalesce(jsonb_agg(jsonb_build_object('id',despesa_id,'fornecedor',fornecedor,'numero_documento',numero_documento,'valor_centavos',valor_centavos,'assinatura',assinatura) ORDER BY despesa_id) FILTER(WHERE pendente),'[]'::jsonb) notas_pendentes FROM notas GROUP BY categoria
 ), categorias AS (SELECT categoria FROM compromissos UNION SELECT categoria FROM despesas)
 SELECT coalesce(jsonb_agg(jsonb_build_object('categoria',k.categoria,'pedido_centavos',coalesce(c.total_pedido_centavos,0),'conciliado_centavos',coalesce(c.conciliado_centavos,0),'comprometido_pendente_centavos',coalesce(c.pendente_centavos,0),'realizado_centavos',coalesce(d.realizado_centavos,0),'consumido_centavos',CASE WHEN coalesce(d.pendencia_centavos,0)>0 THEN NULL ELSE coalesce(c.pendente_centavos,0)+coalesce(d.realizado_centavos,0) END,'pendencia_centavos',coalesce(d.pendencia_centavos,0),'notas_pendentes',coalesce(d.notas_pendentes,'[]'::jsonb)) ORDER BY k.categoria),'[]'::jsonb)
 FROM categorias k LEFT JOIN compromissos c USING(categoria) LEFT JOIN despesas d USING(categoria));
END;$f$;

COMMIT;
