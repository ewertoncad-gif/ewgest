-- Backup da definição anterior à alteração por níveis, obtido em 20/11/2026.
-- Reverter somente após revisão. Não apaga níveis cadastrados nem outras tabelas.

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_financeiro(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb, p_orcamento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_result jsonb;
 v_valor numeric(14,2);
 v_aluminio numeric(14,2);
 v_acessorios numeric(14,2);
 v_vidros numeric(14,2);
 v_outros numeric(14,2);
 v_fabricacao numeric(14,2);
 v_instalacao numeric(14,2);
 v_work_id uuid;
 v_nome text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR p_empresa_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.usuario_id=auth.uid() AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente um ADM pode importar obra com orçamento.';END IF;
 IF jsonb_typeof(p_orcamento) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'Informe o orçamento completo antes de importar.';END IF;
 FOREACH v_nome IN ARRAY ARRAY['valor_total','aluminio','acessorios','vidros','outros','fabricacao','instalacao'] LOOP
  IF jsonb_typeof(p_orcamento->v_nome) IS DISTINCT FROM 'number' OR
     (p_orcamento->>v_nome)::numeric<0 OR
     (p_orcamento->>v_nome)::numeric>999999999999.99 OR
     (p_orcamento->>v_nome)::numeric<>round((p_orcamento->>v_nome)::numeric,2)
  THEN RAISE EXCEPTION 'Orçamento inválido: %. Informe valores numéricos em R$ com duas casas decimais.',v_nome; END IF;
 END LOOP;
 v_valor:=(p_orcamento->>'valor_total')::numeric;
 v_aluminio:=(p_orcamento->>'aluminio')::numeric;
 v_acessorios:=(p_orcamento->>'acessorios')::numeric;
 v_vidros:=(p_orcamento->>'vidros')::numeric;
 v_outros:=(p_orcamento->>'outros')::numeric;
 v_fabricacao:=(p_orcamento->>'fabricacao')::numeric;
 v_instalacao:=(p_orcamento->>'instalacao')::numeric;
 IF v_valor<=0 OR v_valor<>v_aluminio+v_acessorios+v_vidros+v_outros+v_fabricacao+v_instalacao THEN
  RAISE EXCEPTION 'O valor total da obra deve ser igual à soma das seis categorias.';END IF;
 -- Todas as alterações ficam na mesma transação PostgreSQL; orçamento inválido reverte obra e esquadrias.
 v_result:=public.ew_importar_obra_cem(
   p_empresa_id,p_codigo_obra,p_nome_obra,p_cliente,p_esquadrias,
   p_perfis,p_acessorios,p_operacao_id,p_decisoes);
 v_work_id:=(v_result->>'obra_id')::uuid;
 IF v_work_id IS NULL OR v_result->>'obra_criada'<>'true' THEN
  RAISE EXCEPTION 'A importação não confirmou uma obra nova.';END IF;
 INSERT INTO public.ew_obra_orcamento (
 empresa_id,obra_id,valor_total,aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por)
 VALUES (p_empresa_id,v_work_id,v_valor,v_aluminio,v_acessorios,v_vidros,v_outros,v_fabricacao,v_instalacao,auth.uid());
 RETURN v_result||jsonb_build_object('orcamento_gravado',true,'valor_total',v_valor);
END;
$function$

