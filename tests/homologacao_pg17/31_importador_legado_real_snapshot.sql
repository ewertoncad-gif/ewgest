-- EWGEST v46.9 - snapshot somente de CODIGO (sem registros/segredos).
-- Funcoes capturadas por leitura SQL em 2026-11-22 do esquema de producao.
-- Apenas CI: PostgreSQL descartavel com dados ficticios.
-- NUNCA aplicar automaticamente este snapshot na producao.
\set ON_ERROR_STOP on
-- Funcao legada existente: ew_criar_obra_estoque
CREATE OR REPLACE FUNCTION public.ew_criar_obra_estoque(p_empresa_id uuid, p_nome text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_obra uuid:=gen_random_uuid();v_codigo text;v_nome text;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
   WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode criar obras para o estoque.';END IF;
 v_nome:=btrim(coalesce(p_nome,''));
 v_codigo:=upper(btrim(coalesce(p_codigo,'')));
 IF length(v_nome) NOT BETWEEN 3 AND 180 OR length(v_codigo)>80
 THEN RAISE EXCEPTION 'Nome ou código de obra inválido.';END IF;
 IF v_codigo='' THEN v_codigo:='MAN-'||upper(left(replace(v_obra::text,'-',''),10));END IF;
 IF EXISTS(SELECT 1 FROM public.obras WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND
   (upper(btrim(nome))=upper(v_nome) OR upper(btrim(codigo))=v_codigo))
 THEN RAISE EXCEPTION 'Já existe uma obra com este nome ou código. Selecione-a na lista.';END IF;
 INSERT INTO public.obras(id,empresa_id,codigo,nome,cliente,situacao)
 VALUES(v_obra,p_empresa_id,v_codigo,v_nome,NULL,'Em andamento');
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(p_empresa_id,v_obra,v_uid);
 RETURN jsonb_build_object('id',v_obra,'codigo',v_codigo,'nome',v_nome);
END;$function$;

-- Funcao legada existente: ew_importar_obra_cem_financeiro
CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_financeiro(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb, p_orcamento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_result jsonb;
 v_valor numeric(14,2);
 v_aluminio numeric(14,2):=0;
 v_acessorios numeric(14,2):=0;
 v_vidros numeric(14,2):=0;
 v_outros numeric(14,2):=0;
 v_fabricacao numeric(14,2):=0;
 v_instalacao numeric(14,2):=0;
 v_soma numeric(14,2):=0;
 v_work_id uuid;
 v_nome text;
 v_linha jsonb;
 v_nivel text;
 v_empresa_faturamento text;
 v_base text;
 v_valor_linha numeric(14,2);
 v_faturar boolean;
 v_nivel_id uuid;
 v_faturadora_id uuid;
 v_existente_base text;
 v_indice integer:=0;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR p_empresa_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=auth.uid() AND ue.empresa_id=p_empresa_id
    AND ue.perfil='administrador'
 ) THEN RAISE EXCEPTION 'Somente ADM pode importar obra com orçamento.'; END IF;
 IF jsonb_typeof(p_orcamento) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'Informe o orçamento antes de importar.'; END IF;
 IF jsonb_typeof(p_orcamento->'valor_total') IS DISTINCT FROM 'number' OR
   (p_orcamento->>'valor_total')::numeric<=0 OR
   (p_orcamento->>'valor_total')::numeric>999999999999.99 OR
   (p_orcamento->>'valor_total')::numeric<>round((p_orcamento->>'valor_total')::numeric,2)
 THEN RAISE EXCEPTION 'Valor total do orçamento inválido.'; END IF;
 v_valor:=(p_orcamento->>'valor_total')::numeric;

 IF jsonb_typeof(p_orcamento->'niveis')='array' THEN
  IF jsonb_array_length(p_orcamento->'niveis') NOT BETWEEN 1 AND 100 THEN
   RAISE EXCEPTION 'Cadastre de 1 a 100 níveis para a obra.'; END IF;
  FOR v_linha IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
   v_indice:=v_indice+1;
   v_nivel:=upper(btrim(coalesce(v_linha->>'nivel','')));
   v_empresa_faturamento:=upper(btrim(coalesce(v_linha->>'empresa_faturamento','')));
   v_base:=v_linha->>'categoria_base';
   IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
      char_length(v_nivel) NOT BETWEEN 2 AND 120 OR
      char_length(v_empresa_faturamento) NOT BETWEEN 2 AND 120 OR
      v_base IS NULL OR v_base NOT IN ('aluminio','acessorios','vidros','outros','fabricacao','instalacao') OR
      jsonb_typeof(v_linha->'valor') IS DISTINCT FROM 'number' OR
      jsonb_typeof(v_linha->'faturar') IS DISTINCT FROM 'boolean'
   THEN RAISE EXCEPTION 'Nível ou empresa inválidos na linha %.',v_indice; END IF;
   v_valor_linha:=(v_linha->>'valor')::numeric;
   IF v_valor_linha<0 OR v_valor_linha>999999999999.99 OR
      v_valor_linha<>round(v_valor_linha,2)
   THEN RAISE EXCEPTION 'Valor inválido na linha %.',v_indice; END IF;
   v_faturar:=(v_linha->>'faturar')::boolean;
   v_soma:=v_soma+v_valor_linha;
   CASE v_base
    WHEN 'aluminio' THEN v_aluminio:=v_aluminio+v_valor_linha;
    WHEN 'acessorios' THEN v_acessorios:=v_acessorios+v_valor_linha;
    WHEN 'vidros' THEN v_vidros:=v_vidros+v_valor_linha;
    WHEN 'outros' THEN v_outros:=v_outros+v_valor_linha;
    WHEN 'fabricacao' THEN v_fabricacao:=v_fabricacao+v_valor_linha;
    WHEN 'instalacao' THEN v_instalacao:=v_instalacao+v_valor_linha;
   END CASE;
  END LOOP;
  IF v_soma<>v_valor THEN
   RAISE EXCEPTION 'A soma dos níveis (%) deve corresponder ao valor total da obra.',v_soma;
  END IF;
 ELSE
  -- Compatibilidade com versões anteriores da interface.
  FOREACH v_nome IN ARRAY ARRAY['aluminio','acessorios','vidros','outros','fabricacao','instalacao'] LOOP
   IF jsonb_typeof(p_orcamento->v_nome) IS DISTINCT FROM 'number' OR
      (p_orcamento->>v_nome)::numeric<0 OR
      (p_orcamento->>v_nome)::numeric>999999999999.99 OR
      (p_orcamento->>v_nome)::numeric<>round((p_orcamento->>v_nome)::numeric,2)
   THEN RAISE EXCEPTION 'Orçamento inválido: %.',v_nome; END IF;
  END LOOP;
  v_aluminio:=(p_orcamento->>'aluminio')::numeric;
  v_acessorios:=(p_orcamento->>'acessorios')::numeric;
  v_vidros:=(p_orcamento->>'vidros')::numeric;
  v_outros:=(p_orcamento->>'outros')::numeric;
  v_fabricacao:=(p_orcamento->>'fabricacao')::numeric;
  v_instalacao:=(p_orcamento->>'instalacao')::numeric;
  IF v_valor<>v_aluminio+v_acessorios+v_vidros+v_outros+v_fabricacao+v_instalacao THEN
   RAISE EXCEPTION 'Soma das categorias inválida.'; END IF;
 END IF;

 v_result:=public.ew_importar_obra_cem(
   p_empresa_id,p_codigo_obra,p_nome_obra,p_cliente,p_esquadrias,
   p_perfis,p_acessorios,p_operacao_id,p_decisoes);
 v_work_id:=(v_result->>'obra_id')::uuid;
 IF v_work_id IS NULL OR v_result->>'obra_criada'<>'true' THEN
  RAISE EXCEPTION 'A importação não confirmou obra nova.'; END IF;

 INSERT INTO public.ew_obra_orcamento(
   empresa_id,obra_id,valor_total,aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por)
 VALUES (p_empresa_id,v_work_id,v_valor,v_aluminio,v_acessorios,v_vidros,
   v_outros,v_fabricacao,v_instalacao,auth.uid());

 IF jsonb_typeof(p_orcamento->'niveis')='array' THEN
  v_indice:=0;
  FOR v_linha IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
   v_indice:=v_indice+1;
   v_nivel:=upper(btrim(v_linha->>'nivel'));
   v_empresa_faturamento:=upper(btrim(v_linha->>'empresa_faturamento'));
   v_base:=v_linha->>'categoria_base';
   v_valor_linha:=(v_linha->>'valor')::numeric;
   v_faturar:=(v_linha->>'faturar')::boolean;
   INSERT INTO public.ew_niveis_orcamento_catalogo(empresa_id,nome,categoria_base)
    VALUES(p_empresa_id,v_nivel,v_base)
    ON CONFLICT (empresa_id,nome) DO NOTHING;
   SELECT id,categoria_base INTO v_nivel_id,v_existente_base
    FROM public.ew_niveis_orcamento_catalogo
    WHERE empresa_id=p_empresa_id AND nome=v_nivel;
   IF v_nivel_id IS NULL OR v_existente_base IS DISTINCT FROM v_base THEN
    RAISE EXCEPTION 'O nível % já existe com outro grupo financeiro.',v_nivel;
   END IF;
   INSERT INTO public.ew_empresas_faturamento_catalogo(empresa_id,nome)
    VALUES(p_empresa_id,v_empresa_faturamento)
    ON CONFLICT (empresa_id,nome) DO NOTHING;
   SELECT id INTO v_faturadora_id
    FROM public.ew_empresas_faturamento_catalogo
    WHERE empresa_id=p_empresa_id AND nome=v_empresa_faturamento;
   IF v_faturadora_id IS NULL THEN
    RAISE EXCEPTION 'Empresa de faturamento não encontrada: %.',v_empresa_faturamento;
   END IF;
   INSERT INTO public.ew_obra_orcamento_niveis(
     empresa_id,obra_id,linha,nivel_id,empresa_faturamento_id,
     nivel_nome,empresa_faturamento_nome,categoria_base,valor,percentual,faturar)
    VALUES(p_empresa_id,v_work_id,v_indice,v_nivel_id,v_faturadora_id,
      v_nivel,v_empresa_faturamento,v_base,v_valor_linha,
      round(v_valor_linha/v_valor*100,5),v_faturar);
  END LOOP;
 END IF;
 RETURN v_result||jsonb_build_object(
    'orcamento_gravado',true,'valor_total',v_valor,'niveis_gravados',v_indice);
END;
$function$;
