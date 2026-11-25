BEGIN;
-- Consolidação de solicitações: o documento novo é a única origem comercial elegível.
-- Os documentos originais, os itens e a trilha ficam preservados.
CREATE SCHEMA ew_compras_interna;
REVOKE ALL ON SCHEMA ew_compras_interna FROM PUBLIC,anon,authenticated;
CREATE TABLE ew_compras_interna.agrupamentos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 obra_id uuid NOT NULL,solicitacao_id uuid NOT NULL UNIQUE REFERENCES public.ew_compras_solicitacoes(id),
 operacao_id uuid NOT NULL UNIQUE,origens uuid[] NOT NULL,origens_itens jsonb NOT NULL,
 criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ew_compras_interna.agrupamentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.agrupamentos FROM PUBLIC,anon,authenticated;
ALTER TABLE public.ew_compras_solicitacoes ADD COLUMN agrupada_em uuid REFERENCES public.ew_compras_solicitacoes(id);
ALTER TABLE public.ew_compras_solicitacoes DROP CONSTRAINT ew_compras_solicitacoes_status_check;
ALTER TABLE public.ew_compras_solicitacoes ADD CONSTRAINT ew_compras_solicitacoes_status_check CHECK(status IN ('ABERTA','PEDIDO_GERADO','CANCELADA','AGRUPADA'));
ALTER TABLE public.ew_compras_solicitacoes ADD CONSTRAINT ew_compras_solic_agrupamento_coerente CHECK ((status='AGRUPADA')=(agrupada_em IS NOT NULL));

INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES
 ('compras.agrupar','Compras','Agrupar solicitações abertas da mesma obra',41),
 ('compras.cotacao_excel','Compras','Exportar e importar cotações de fornecedores por Excel',42),
 ('compras.replicar_cotacao','Compras','Replicar a lista de cotação para outros fornecedores',43),
 ('compras.aprovar_pedido','Compras','Aprovar pedido e comprometer orçamento da obra',44),
 ('compras.historico_precos','Compras','Consultar histórico de preços cotados por fornecedor',45)
ON CONFLICT(chave) DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,c.chave,CASE WHEN n.nivel=1 THEN true WHEN n.nivel=8 THEN false
 WHEN c.chave='compras.aprovar_pedido' THEN n.nivel=2 AND coalesce(p.permitido,false) AND coalesce(v.permitido,false)
 WHEN c.chave='compras.historico_precos' THEN coalesce(v.permitido,false)
 ELSE coalesce(t.permitido,false) AND coalesce(v.permitido,false) END
FROM public.ew_niveis_acesso n
CROSS JOIN (VALUES ('compras.agrupar'),('compras.cotacao_excel'),('compras.replicar_cotacao'),('compras.aprovar_pedido'),('compras.historico_precos')) c(chave)
LEFT JOIN public.ew_niveis_permissoes t ON t.empresa_id=n.empresa_id AND t.nivel=n.nivel AND t.chave='compras.cotar'
LEFT JOIN public.ew_niveis_permissoes p ON p.empresa_id=n.empresa_id AND p.nivel=n.nivel AND p.chave='compras.pedir'
LEFT JOIN public.ew_niveis_permissoes v ON v.empresa_id=n.empresa_id AND v.nivel=n.nivel AND v.chave='compras.consultar_valores'
ON CONFLICT DO NOTHING;
CREATE FUNCTION public.ew_compras_agrupar_solicitacoes(p_empresa_id uuid,p_obra_id uuid,p_solicitacoes uuid[],p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE ids uuid[]; prev ew_compras_interna.agrupamentos%rowtype; n int; novo uuid; itens jsonb; fontes jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.agrupar') OR NOT public.ew_pode(p_empresa_id,'compras.cotar') OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') THEN RAISE EXCEPTION 'Sem permissão para agrupar solicitações.';END IF;
 IF p_operacao_id IS NULL OR p_solicitacoes IS NULL OR cardinality(p_solicitacoes) NOT BETWEEN 2 AND 50 OR array_position(p_solicitacoes,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Marque de 2 a 50 solicitações.';END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_solicitacoes) x;
 IF cardinality(ids)<>cardinality(p_solicitacoes) THEN RAISE EXCEPTION 'Solicitação repetida.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('EW_AGRUPAR_COMPRAS|'||p_operacao_id::text,4628));
 SELECT * INTO prev FROM ew_compras_interna.agrupamentos WHERE operacao_id=p_operacao_id;
 IF FOUND THEN
  IF prev.empresa_id<>p_empresa_id OR prev.obra_id IS DISTINCT FROM p_obra_id OR prev.origens<>ids OR prev.criado_por<>auth.uid() THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
  RETURN jsonb_build_object('id',prev.solicitacao_id,'repetida',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Obra inexistente ou arquivada.';END IF;
 -- Mesmos locks de linha utilizados na aprovação do pedido; ordem determinística.
 PERFORM 1 FROM public.ew_compras_solicitacoes WHERE id=ANY(ids) AND empresa_id=p_empresa_id AND obra_id=p_obra_id AND status='ABERTA' ORDER BY id FOR UPDATE;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>cardinality(ids) THEN RAISE EXCEPTION 'Somente solicitações abertas da mesma obra podem ser agrupadas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_cotacoes WHERE solicitacao_id=ANY(ids) AND status='ABERTA') OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos WHERE solicitacao_id=ANY(ids))
 THEN RAISE EXCEPTION 'Há cotação ativa ou pedido nas solicitações. Cancele as cotações antes de agrupar.';END IF;
 SELECT jsonb_agg(jsonb_build_object('id',id,'itens',s.itens,'observacoes',observacoes) ORDER BY id) INTO fontes FROM public.ew_compras_solicitacoes s WHERE id=ANY(ids);
 SELECT jsonb_agg(jsonb_build_object('chave',ord::text,'variacao_id',variacao_id,'unidade',unidade,'comprimento_mm',comprimento_mm,'quantidade',quantidade) ORDER BY ord) INTO itens
 FROM (SELECT row_number() OVER(ORDER BY variacao_id,unidade,comprimento_mm) ord,* FROM (
 SELECT (x->>'variacao_id')::uuid variacao_id,x->>'unidade' unidade,(x->>'comprimento_mm')::integer comprimento_mm,sum((x->>'quantidade')::numeric) quantidade
 FROM public.ew_compras_solicitacoes s CROSS JOIN LATERAL jsonb_array_elements(s.itens) x WHERE s.id=ANY(ids)
 GROUP BY 1,2,3) g) l;
 IF jsonb_array_length(itens) NOT BETWEEN 1 AND 200 OR EXISTS(SELECT 1 FROM jsonb_array_elements(itens) x WHERE (x->>'quantidade')::numeric NOT BETWEEN 0.001 AND 1000000) THEN RAISE EXCEPTION 'Agrupamento excede os limites de itens ou quantidades.';END IF;
 INSERT INTO public.ew_compras_solicitacoes(empresa_id,obra_id,operacao_id,itens,observacoes,criado_por)
 VALUES(p_empresa_id,p_obra_id,p_operacao_id,itens,'Consolidação de '||cardinality(ids)||' solicitações',auth.uid()) RETURNING id INTO novo;
 UPDATE public.ew_compras_solicitacoes SET status='AGRUPADA',agrupada_em=novo WHERE id=ANY(ids);
 INSERT INTO ew_compras_interna.agrupamentos(empresa_id,obra_id,solicitacao_id,operacao_id,origens,origens_itens,criado_por) VALUES(p_empresa_id,p_obra_id,novo,p_operacao_id,ids,fontes,auth.uid());
 RETURN jsonb_build_object('id',novo,'repetida',false,'origens',cardinality(ids),'itens',jsonb_array_length(itens));
END;$f$;
-- Bloqueia uma cotação que concorra com o agrupamento da mesma solicitação.
CREATE FUNCTION ew_compras_interna.proteger_cotacao() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM 1 FROM public.ew_compras_solicitacoes s WHERE s.id=NEW.solicitacao_id AND s.empresa_id=NEW.empresa_id AND s.status='ABERTA' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação indisponível para cotação.';END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_compras_cotacao_solic_ativa BEFORE INSERT ON public.ew_compras_cotacoes FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_cotacao();
-- Cancelar uma consolidação ainda sem pedido devolve as solicitações originais ao estado aberto;
-- o registro imutável da consolidação anterior permanece.
CREATE FUNCTION ew_compras_interna.restaurar_origens() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF OLD.status='ABERTA' AND NEW.status='CANCELADA' THEN
 UPDATE public.ew_compras_solicitacoes SET status='ABERTA',agrupada_em=NULL WHERE agrupada_em=NEW.id AND empresa_id=NEW.empresa_id AND status='AGRUPADA';
 END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_compras_restaurar_origens AFTER UPDATE OF status ON public.ew_compras_solicitacoes FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.restaurar_origens();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ew_compras_interna FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ew_compras_agrupar_solicitacoes(uuid,uuid,uuid[],uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_agrupar_solicitacoes(uuid,uuid,uuid[],uuid) TO authenticated;
COMMIT;
