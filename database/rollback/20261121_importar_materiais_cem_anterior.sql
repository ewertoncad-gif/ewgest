-- Snapshot da função ANTES da migração do plano de barras do CEM.
-- Reversão não destrutiva: restaura a função anterior, mantendo os dados
-- e a coluna adicional (que poderá ser ignorada pelo código antigo).
-- Capturada em 21/11/2026 do projeto ewgest-producao.

CREATE OR REPLACE FUNCTION public.importar_materiais_cem(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid := auth.uid();
 v_obra uuid;
 v_obras_count integer;
 v_item jsonb;
 v_var jsonb;
 v_var_list jsonb;
 v_codigo text;
 v_fabricante text;
 v_descricao text;
 v_acabamento text;
 v_cor text;
 v_codcor text;
 v_tipo text;
 v_mat_id uuid;
 v_var_id uuid;
 v_qtd_rows integer;
 v_qtd_prev numeric;
 v_metros_prev numeric;
 v_unit_prev text;
 v_new_perfis integer := 0;
 v_new_acessorios integer := 0;
 v_existing_perfis integer := 0;
 v_existing_acessorios integer := 0;
 v_reactivated_perfis integer := 0;
 v_reactivated_acessorios integer := 0;
 v_new_var integer := 0;
 v_link_count integer := 0;
 v_count integer := 0;
 v_cached jsonb;
 v_result jsonb;
BEGIN
 IF v_uid IS NULL OR p_operacao_id IS NULL OR p_empresa_id IS NULL THEN
  RAISE EXCEPTION 'Sessão ou identificador da importação inválido.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id
  AND ue.perfil='administrador') THEN
  RAISE EXCEPTION 'Somente o administrador pode importar materiais do CEM.';
 END IF;
 IF coalesce(btrim(p_codigo_obra),'')='' OR length(p_codigo_obra)>100 THEN
  RAISE EXCEPTION 'Código de obra inválido.';
 END IF;
 IF jsonb_typeof(p_perfis) IS DISTINCT FROM 'array' OR jsonb_typeof(p_acessorios) IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'Dados de materiais fora do formato esperado.';
 END IF;
 IF jsonb_array_length(p_perfis)>800 OR jsonb_array_length(p_acessorios)>1200 OR
    (jsonb_array_length(p_perfis)+jsonb_array_length(p_acessorios))=0 THEN
  RAISE EXCEPTION 'Quantidade de materiais inválida.';
 END IF;
 SELECT resumo INTO v_cached FROM public.ew_cem_importacoes_materiais
  WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF FOUND THEN RETURN v_cached; END IF;
 SELECT count(*),(array_agg(id))[1] INTO v_obras_count,v_obra FROM public.obras
  WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo_obra));
 IF v_obras_count<>1 THEN
  RAISE EXCEPTION 'A obra % precisa existir uma única vez no EWGEST antes desta importação.',p_codigo_obra;
 END IF;
 FOR v_tipo IN SELECT unnest(ARRAY['perfil','acessorio']) LOOP
  FOR v_item IN SELECT value FROM jsonb_array_elements(
    CASE WHEN v_tipo='perfil' THEN p_perfis ELSE p_acessorios END
  ) LOOP
   IF jsonb_typeof(v_item)<>'object' THEN RAISE EXCEPTION 'Material inválido na importação.'; END IF;
   v_codigo := upper(btrim(coalesce(v_item->>'codigo','')));
   v_fabricante := upper(btrim(coalesce(v_item->>'fabricante','')));
   v_descricao := btrim(coalesce(v_item->>'descricao',''));
   -- Cadastro técnico já existente não precisa receber uma nova descrição do ZIP.
   -- A identificação pelo código E fabricante deve ser inequívoca; não presumimos equivalências.
   IF length(v_descricao)<2 AND length(v_codigo) BETWEEN 1 AND 90
      AND length(v_fabricante) BETWEEN 1 AND 150 THEN
     IF v_tipo='perfil' THEN
       SELECT m.descricao INTO v_descricao FROM public.ew_perfis m
       WHERE m.empresa_id=p_empresa_id
         AND upper(btrim(m.codigo))=v_codigo
         AND upper(btrim(m.fabricante))=v_fabricante
         AND length(btrim(m.descricao)) BETWEEN 2 AND 500
       LIMIT 1;
     ELSE
       SELECT m.descricao INTO v_descricao FROM public.ew_acessorios m
       WHERE m.empresa_id=p_empresa_id
         AND upper(btrim(m.codigo))=v_codigo
         AND upper(btrim(m.fabricante))=v_fabricante
         AND length(btrim(m.descricao)) BETWEEN 2 AND 500
       LIMIT 1;
     END IF;
     v_descricao:=btrim(coalesce(v_descricao,''));
   END IF;
   IF length(v_codigo) NOT BETWEEN 1 AND 90 THEN
     RAISE EXCEPTION 'Código inválido de material no arquivo CEM: %.',v_codigo;
   END IF;
   IF length(v_fabricante) NOT BETWEEN 1 AND 150 THEN
     RAISE EXCEPTION 'Fabricante não informado ou inválido no CEM para o material %. Corrija a referência no arquivo de origem.',v_codigo;
   END IF;
   IF length(v_descricao) NOT BETWEEN 2 AND 500 THEN
     RAISE EXCEPTION 'Descrição não informada ou inválida no CEM para o material %. Cadastre ou corrija o material antes de importar.',v_codigo;
   END IF;
   v_var_list := v_item->'variacoes';
   IF jsonb_typeof(v_var_list) IS DISTINCT FROM 'array' OR jsonb_array_length(v_var_list)>40
      OR jsonb_array_length(v_var_list)=0 THEN
      RAISE EXCEPTION 'O material % não possui variações válidas.',v_codigo;
   END IF;
   v_mat_id := NULL;
   IF v_tipo='perfil' THEN
    SELECT perfil_id INTO v_mat_id FROM public.ew_materiais_alias
      WHERE empresa_id=p_empresa_id AND tipo='perfil' AND fabricante=v_fabricante
      AND codigo_alternativo=v_codigo;
    IF v_mat_id IS NOT NULL THEN
      v_existing_perfis:=v_existing_perfis+1;
    ELSE
    INSERT INTO public.ew_perfis(empresa_id,codigo,fabricante,descricao,linha,prenativo,peso_kg_m,
      unidade_referencia,criado_por,atualizado_por)
    VALUES (p_empresa_id,v_codigo,v_fabricante,v_descricao,
      left(coalesce(v_item->>'linha',''),150),left(coalesce(v_item->>'prenativo',''),150),
      CASE WHEN (v_item->>'peso_kg_m')~'^[0-9]+(\.[0-9]+)?$'
         THEN (v_item->>'peso_kg_m')::numeric ELSE NULL END,
      'BARRA',v_uid,v_uid)
    ON CONFLICT DO NOTHING RETURNING id INTO v_mat_id;
    IF v_mat_id IS NULL THEN
      v_existing_perfis:=v_existing_perfis+1;
      SELECT id INTO v_mat_id FROM public.ew_perfis
       WHERE empresa_id=p_empresa_id AND upper(btrim(codigo))=v_codigo AND upper(btrim(fabricante))=v_fabricante;
    ELSE v_new_perfis:=v_new_perfis+1; END IF;
    END IF;
   ELSE
    SELECT acessorio_id INTO v_mat_id FROM public.ew_materiais_alias
      WHERE empresa_id=p_empresa_id AND tipo='acessorio' AND fabricante=v_fabricante
      AND codigo_alternativo=v_codigo;
    IF v_mat_id IS NOT NULL THEN
      v_existing_acessorios:=v_existing_acessorios+1;
    ELSE
    INSERT INTO public.ew_acessorios(empresa_id,codigo,fabricante,descricao,linha,prenativo,
      unidade_item,unidade_embalagem,quantidade_por_embalagem,criado_por,atualizado_por)
    VALUES(p_empresa_id,v_codigo,v_fabricante,v_descricao,
      left(coalesce(v_item->>'linha',''),150),left(coalesce(v_item->>'prenativo',''),150),
      left(coalesce(nullif(btrim(v_item->>'unidade'),''),'PC'),30),
      left(coalesce(v_item->>'embalagem',''),30),
      CASE WHEN (v_item->>'quantidade_por_embalagem') ~ '^[0-9]{1,6}([.][0-9]{1,3})?$'
        THEN (v_item->>'quantidade_por_embalagem')::numeric ELSE NULL END,
      v_uid,v_uid)
    ON CONFLICT DO NOTHING RETURNING id INTO v_mat_id;
    IF v_mat_id IS NULL THEN
      v_existing_acessorios:=v_existing_acessorios+1;
      SELECT id INTO v_mat_id FROM public.ew_acessorios
       WHERE empresa_id=p_empresa_id AND upper(btrim(codigo))=v_codigo AND upper(btrim(fabricante))=v_fabricante;
    ELSE v_new_acessorios:=v_new_acessorios+1; END IF;
    END IF;
   END IF;
   IF v_mat_id IS NULL THEN RAISE EXCEPTION 'Falha ao localizar o material %.',v_codigo; END IF;
   -- Materiais referenciados em uma obra do CEM são necessários: reativar somente
   -- o cadastro técnico, sem alterar nenhuma quantidade, descrição ou variação.
   IF v_tipo='perfil' THEN
     UPDATE public.ew_perfis
       SET ativo=true,atualizado_em=now(),atualizado_por=v_uid
       WHERE id=v_mat_id AND empresa_id=p_empresa_id AND ativo IS FALSE;
     IF FOUND THEN v_reactivated_perfis:=v_reactivated_perfis+1; END IF;
   ELSE
     UPDATE public.ew_acessorios
       SET ativo=true,atualizado_em=now(),atualizado_por=v_uid
       WHERE id=v_mat_id AND empresa_id=p_empresa_id AND ativo IS FALSE;
     IF FOUND THEN v_reactivated_acessorios:=v_reactivated_acessorios+1; END IF;
   END IF;
   FOR v_var IN SELECT value FROM jsonb_array_elements(v_var_list) LOOP
    IF jsonb_typeof(v_var)<>'object' THEN RAISE EXCEPTION 'Variação inválida de %.',v_codigo; END IF;
    v_acabamento:=upper(btrim(coalesce(nullif(v_var->>'acabamento',''),'NÃO INFORMADO')));
    v_cor:=upper(btrim(coalesce(nullif(v_var->>'cor',''),'NÃO INFORMADA')));
    v_codcor:=upper(btrim(coalesce(v_var->>'codigo_cor','')));
    IF length(v_acabamento)>150 OR length(v_cor)>150 OR length(v_codcor)>150 THEN
      RAISE EXCEPTION 'Cor ou acabamento demasiado longo para %.',v_codigo;
    END IF;
    v_qtd_rows := coalesce((v_var->>'linhas_calculo')::integer,0);
    IF v_qtd_rows NOT BETWEEN 1 AND 10000000 THEN
      RAISE EXCEPTION 'Quantidade de referências inválida no material %.',v_codigo;
    END IF;
    v_var_id := NULL;
    INSERT INTO public.ew_materiais_variacoes
      (empresa_id,tipo,perfil_id,acessorio_id,acabamento,cor,codigo_cor,criado_por,atualizado_por)
    VALUES(p_empresa_id,v_tipo,
      CASE WHEN v_tipo='perfil' THEN v_mat_id ELSE NULL END,
      CASE WHEN v_tipo='acessorio' THEN v_mat_id ELSE NULL END,
      v_acabamento,v_cor,v_codcor,v_uid,v_uid)
    ON CONFLICT DO NOTHING RETURNING id INTO v_var_id;
    IF v_var_id IS NOT NULL THEN v_new_var:=v_new_var+1;
    ELSE
      SELECT id INTO v_var_id FROM public.ew_materiais_variacoes
      WHERE empresa_id=p_empresa_id AND tipo=v_tipo
       AND CASE WHEN v_tipo='perfil' THEN perfil_id ELSE acessorio_id END=v_mat_id
       AND acabamento=v_acabamento AND cor=v_cor AND codigo_cor=v_codcor;
    END IF;
    IF v_var_id IS NULL THEN RAISE EXCEPTION 'Não foi possível vincular a variação %.',v_codigo; END IF;
    v_qtd_prev := CASE WHEN jsonb_typeof(v_var->'quantidade_prevista')='number'
        THEN (v_var->>'quantidade_prevista')::numeric ELSE NULL END;
    v_metros_prev := CASE WHEN jsonb_typeof(v_var->'comprimento_total_m')='number'
        THEN (v_var->>'comprimento_total_m')::numeric ELSE NULL END;
    v_unit_prev := left(upper(btrim(coalesce(v_var->>'unidade_prevista',''))),30);
    IF v_qtd_prev>1e10 OR v_metros_prev>1e10 OR v_qtd_prev<0 OR v_metros_prev<0 THEN
      RAISE EXCEPTION 'Quantitativo CEM fora dos limites para %.',v_codigo;
    END IF;
    INSERT INTO public.ew_cem_obras_materiais
      (empresa_id,obra_id,tipo,perfil_id,acessorio_id,variacao_id,linhas_calculo,
       quantidade_prevista,unidade_prevista,comprimento_total_m,origem_quantitativos)
    VALUES(p_empresa_id,v_obra,v_tipo,
       CASE WHEN v_tipo='perfil' THEN v_mat_id ELSE NULL END,
       CASE WHEN v_tipo='acessorio' THEN v_mat_id ELSE NULL END,
       v_var_id,v_qtd_rows,v_qtd_prev,nullif(v_unit_prev,''),v_metros_prev,
       CASE WHEN v_qtd_prev IS NULL THEN NULL ELSE 'CEM_CALCULO' END)
    ON CONFLICT (empresa_id,obra_id,variacao_id) DO UPDATE SET
      linhas_calculo=excluded.linhas_calculo,
      quantidade_prevista=coalesce(excluded.quantidade_prevista,ew_cem_obras_materiais.quantidade_prevista),
      unidade_prevista=coalesce(excluded.unidade_prevista,ew_cem_obras_materiais.unidade_prevista),
      comprimento_total_m=coalesce(excluded.comprimento_total_m,ew_cem_obras_materiais.comprimento_total_m),
      origem_quantitativos=coalesce(excluded.origem_quantitativos,ew_cem_obras_materiais.origem_quantitativos),
      atualizado_em=now();
    v_link_count:=v_link_count+1;
   END LOOP;
  END LOOP;
 END LOOP;
 v_result:=jsonb_build_object(
   'codigo_obra',p_codigo_obra,'obra_id',v_obra,
   'perfis_novos',v_new_perfis,'perfis_existentes',v_existing_perfis,
   'acessorios_novos',v_new_acessorios,'acessorios_existentes',v_existing_acessorios,
   'perfis_reativados',v_reactivated_perfis,'acessorios_reativados',v_reactivated_acessorios,
   'variacoes_novas',v_new_var,'vinculos_por_obra',v_link_count,
   'esquadrias_alteradas',0,'estoque_fisico_alterado',false);
 INSERT INTO public.ew_cem_importacoes_materiais
 (empresa_id,obra_id,operacao_id,codigo_obra_cem,importou_perfis,importou_acessorios,resumo,criado_por)
 VALUES(p_empresa_id,v_obra,p_operacao_id,p_codigo_obra,jsonb_array_length(p_perfis)>0,
    jsonb_array_length(p_acessorios)>0,v_result,v_uid);
 RETURN v_result;
END;
$function$;
