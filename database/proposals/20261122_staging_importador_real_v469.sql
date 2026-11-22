-- EWGEST v46.9 | instalar funções REAIS do importador CEM no Supabase Free de testes
-- Implementações obtidas APENAS do código de funções do banco de produção e proposal v46.9.
-- Chaves, dados e contas de produção não são lidos ou copiados.
-- NÃO aplicar esta migração na produção nem usar como substituto do Auth real.
-- Requisitos: 41 tabelas públicas, 44 funções e as duas migrações de integridade CEM do staging.
-- Função de sessão do staging permanece simulada (NÃO é a função de produção).
BEGIN;
DO $guard$
DECLARE n int; old_hash text;
BEGIN
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
 WHERE s.nspname='public' AND c.relkind IN ('r','p');
 IF n<>41 OR (SELECT count(*) FROM auth.users)<>1 OR
 (SELECT count(*) FROM public.empresas)<>1 OR
 (SELECT count(*) FROM public.obras)<>0 OR
 (SELECT count(*) FROM public.ew_cem_importacoes_materiais)<>0
 THEN RAISE EXCEPTION 'Staging inesperado, 41 tabelas, 1 auth, 1 empresa, 0 obras/importações esperados.';END IF;
 SELECT md5(pg_get_functiondef(oid)) INTO old_hash FROM pg_proc
 WHERE oid='public.ew_importar_obra_cem(uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb)'::regprocedure;
 IF old_hash<>'2878a8711b4934a08ed100ded1dee638' THEN
  RAISE EXCEPTION 'Função legada do staging mudou. Abortando para preservar código.';END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
 WHERE s.nspname='public' AND p.proname IN ('ew_criar_obra_estoque','ew_conciliar_codigo_cem','importar_materiais_cem','ew_importar_cem_conciliado'))
 THEN RAISE EXCEPTION 'Uma das 4 funções do catálogo já existe. Reavaliar.';END IF;
END $guard$;
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

CREATE OR REPLACE FUNCTION public.ew_conciliar_codigo_cem(p_empresa_id uuid, p_tipo text, p_material_id uuid, p_codigo_cem text, p_usar_codigo_cem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_codigo_antigo text;v_fabricante text;v_codigo text;
 v_outro uuid;v_alias uuid;v_id uuid;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
  AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode conciliar códigos de materiais.';END IF;
 v_codigo:=upper(btrim(coalesce(p_codigo_cem,'')));
 IF p_tipo NOT IN ('perfil','acessorio') OR p_usar_codigo_cem IS NULL
   OR length(v_codigo) NOT BETWEEN 1 AND 90 THEN
   RAISE EXCEPTION 'Decisão de conciliação inválida.';END IF;
 IF p_tipo='perfil' THEN
  SELECT codigo,fabricante INTO v_codigo_antigo,v_fabricante FROM public.ew_perfis
   WHERE id=p_material_id AND empresa_id=p_empresa_id FOR UPDATE;
 ELSE
  SELECT codigo,fabricante INTO v_codigo_antigo,v_fabricante FROM public.ew_acessorios
   WHERE id=p_material_id AND empresa_id=p_empresa_id FOR UPDATE;
 END IF;
 IF v_codigo_antigo IS NULL THEN RAISE EXCEPTION 'Cadastro manual não encontrado.';END IF;
 v_fabricante:=upper(btrim(v_fabricante));v_codigo_antigo:=upper(btrim(v_codigo_antigo));
 IF v_codigo=v_codigo_antigo THEN
  RETURN jsonb_build_object('codigo_principal',v_codigo,'codigo_alternativo',null);
 END IF;
 IF p_tipo='perfil' THEN
  SELECT id INTO v_outro FROM public.ew_perfis WHERE empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fabricante AND upper(btrim(codigo))=v_codigo
    AND id<>p_material_id;
 ELSE
  SELECT id INTO v_outro FROM public.ew_acessorios WHERE empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fabricante AND upper(btrim(codigo))=v_codigo
    AND id<>p_material_id;
 END IF;
 IF v_outro IS NOT NULL THEN RAISE EXCEPTION 'Já existe outro material com este código CEM. Revise os cadastros.'; END IF;
 SELECT id,CASE WHEN p_tipo='perfil' THEN perfil_id ELSE acessorio_id END
 INTO v_alias,v_id FROM public.ew_materiais_alias
 WHERE empresa_id=p_empresa_id AND tipo=p_tipo AND fabricante=v_fabricante AND codigo_alternativo=v_codigo;
 IF v_alias IS NOT NULL AND v_id<>p_material_id THEN
  RAISE EXCEPTION 'Código CEM já vinculado a outro material.';END IF;
 IF p_usar_codigo_cem THEN
  IF NOT EXISTS (SELECT 1 FROM public.ew_materiais_alias WHERE empresa_id=p_empresa_id
    AND tipo=p_tipo AND fabricante=v_fabricante AND codigo_alternativo=v_codigo_antigo) THEN
   INSERT INTO public.ew_materiais_alias
   (empresa_id,tipo,perfil_id,acessorio_id,fabricante,codigo_alternativo,criado_por)
   VALUES(p_empresa_id,p_tipo,
      CASE WHEN p_tipo='perfil' THEN p_material_id ELSE NULL END,
      CASE WHEN p_tipo='acessorio' THEN p_material_id ELSE NULL END,
      v_fabricante,v_codigo_antigo,v_uid);
  END IF;
  IF p_tipo='perfil' THEN UPDATE public.ew_perfis SET codigo=v_codigo,atualizado_em=now(),atualizado_por=v_uid WHERE id=p_material_id;
  ELSE UPDATE public.ew_acessorios SET codigo=v_codigo,atualizado_em=now(),atualizado_por=v_uid WHERE id=p_material_id;END IF;
  -- Se o CEM já era um alias do mesmo material, pode permanecer para reconhecimento.
 ELSE
  IF v_alias IS NULL THEN
   INSERT INTO public.ew_materiais_alias
    (empresa_id,tipo,perfil_id,acessorio_id,fabricante,codigo_alternativo,criado_por)
   VALUES(p_empresa_id,p_tipo,
     CASE WHEN p_tipo='perfil' THEN p_material_id ELSE NULL END,
     CASE WHEN p_tipo='acessorio' THEN p_material_id ELSE NULL END,
     v_fabricante,v_codigo,v_uid);
  END IF;
 END IF;
 RETURN jsonb_build_object('material_id',p_material_id,
  'codigo_principal',CASE WHEN p_usar_codigo_cem THEN v_codigo ELSE v_codigo_antigo END,
  'codigo_alternativo',CASE WHEN p_usar_codigo_cem THEN v_codigo_antigo ELSE v_codigo END);
END;$function$;

-- ew_importar_cem_conciliado
CREATE OR REPLACE FUNCTION public.ew_importar_cem_conciliado(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_d jsonb;v_tipo text;v_codigo text;v_fabricante text;v_id uuid;v_usar boolean;
 v_row jsonb;v_encontrado boolean;v_result jsonb;v_seen text[]:=ARRAY[]::text[];v_key text;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode realizar importação conciliada.';END IF;
 IF jsonb_typeof(p_decisoes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_decisoes)>400
 THEN RAISE EXCEPTION 'Lista de conciliações inválida.';END IF;
 -- Se operação foi anteriormente concluída, não repetir os efeitos de conciliação.
 SELECT resumo INTO v_result FROM public.ew_cem_importacoes_materiais
 WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF FOUND THEN RETURN v_result;END IF;
 FOR v_d IN SELECT value FROM jsonb_array_elements(p_decisoes) LOOP
   v_tipo:=v_d->>'tipo';v_codigo:=upper(btrim(v_d->>'codigo_cem'));
   v_fabricante:=upper(btrim(v_d->>'fabricante'));
   v_id:=(v_d->>'material_id')::uuid;
   v_usar:=(v_d->>'usar_codigo_cem')::boolean;
   v_key:=v_tipo||'|'||v_fabricante||'|'||v_codigo;
   IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'Decisão repetida para código CEM %.',v_codigo;END IF;
   v_seen:=array_append(v_seen,v_key);
   v_encontrado:=false;
   FOR v_row IN SELECT value FROM jsonb_array_elements(CASE WHEN v_tipo='perfil' THEN p_perfis ELSE p_acessorios END) LOOP
      IF upper(btrim(coalesce(v_row->>'codigo','')))=v_codigo AND upper(btrim(coalesce(v_row->>'fabricante','')))=v_fabricante
      THEN v_encontrado:=true;EXIT; END IF;
   END LOOP;
   IF NOT v_encontrado THEN RAISE EXCEPTION 'A conciliação não corresponde ao arquivo CEM: %.',v_codigo;END IF;
   PERFORM public.ew_conciliar_codigo_cem(p_empresa_id,v_tipo,v_id,v_codigo,v_usar);
 END LOOP;
 RETURN public.importar_materiais_cem(p_empresa_id,p_codigo_obra,p_perfis,p_acessorios,p_operacao_id);
END;$function$;

-- importar_materiais_cem
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
 v_barras_plan jsonb;
 v_bar jsonb;
 v_bar_mm numeric;
 v_bar_qty numeric;
 v_seen_bar_lengths integer[];
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
    -- O plano comercial vem de OBAPROV (NUMBARRAS/BARRA), separado
    -- da quantidade de cortes e do estoque efetivamente recebido.
    v_barras_plan := NULL;
    IF v_tipo='perfil' AND (v_var ? 'barras_planejadas') THEN
     v_barras_plan:=v_var->'barras_planejadas';
     IF jsonb_typeof(v_barras_plan) IS DISTINCT FROM 'array' OR
        jsonb_array_length(v_barras_plan)>100 THEN
      RAISE EXCEPTION 'Plano de barras inválido para %.',v_codigo;
     END IF;
     v_seen_bar_lengths:=ARRAY[]::integer[];
     FOR v_bar IN SELECT value FROM jsonb_array_elements(v_barras_plan) LOOP
      IF jsonb_typeof(v_bar) IS DISTINCT FROM 'object' OR
         jsonb_typeof(v_bar->'comprimento_mm') IS DISTINCT FROM 'number' OR
         jsonb_typeof(v_bar->'quantidade') IS DISTINCT FROM 'number' THEN
       RAISE EXCEPTION 'Medida ou quantidade de barras inválida para %.',v_codigo;
      END IF;
      v_bar_mm:=(v_bar->>'comprimento_mm')::numeric;
      v_bar_qty:=(v_bar->>'quantidade')::numeric;
      IF v_bar_mm<>trunc(v_bar_mm) OR v_bar_mm NOT BETWEEN 100 AND 20000 OR
         v_bar_qty<>trunc(v_bar_qty) OR v_bar_qty NOT BETWEEN 1 AND 1000000 THEN
       RAISE EXCEPTION 'Barras do CEM fora dos limites para %.',v_codigo;
      END IF;
      IF v_bar_mm::integer=ANY(v_seen_bar_lengths) THEN
       RAISE EXCEPTION 'Comprimento duplicado no plano do perfil %.',v_codigo;
      END IF;
      v_seen_bar_lengths:=array_append(v_seen_bar_lengths,v_bar_mm::integer);
     END LOOP;
    END IF;
    IF v_qtd_prev>1e10 OR v_metros_prev>1e10 OR v_qtd_prev<0 OR v_metros_prev<0 THEN
      RAISE EXCEPTION 'Quantitativo CEM fora dos limites para %.',v_codigo;
    END IF;
    INSERT INTO public.ew_cem_obras_materiais
      (empresa_id,obra_id,tipo,perfil_id,acessorio_id,variacao_id,linhas_calculo,
       quantidade_prevista,unidade_prevista,comprimento_total_m,origem_quantitativos,barras_planejadas)
    VALUES(p_empresa_id,v_obra,v_tipo,
       CASE WHEN v_tipo='perfil' THEN v_mat_id ELSE NULL END,
       CASE WHEN v_tipo='acessorio' THEN v_mat_id ELSE NULL END,
       v_var_id,v_qtd_rows,v_qtd_prev,nullif(v_unit_prev,''),v_metros_prev,
       CASE WHEN v_qtd_prev IS NULL THEN NULL ELSE 'CEM_CALCULO' END,
       v_barras_plan)
    ON CONFLICT (empresa_id,obra_id,variacao_id) DO UPDATE SET
      linhas_calculo=excluded.linhas_calculo,
      quantidade_prevista=coalesce(excluded.quantidade_prevista,ew_cem_obras_materiais.quantidade_prevista),
      unidade_prevista=coalesce(excluded.unidade_prevista,ew_cem_obras_materiais.unidade_prevista),
      comprimento_total_m=coalesce(excluded.comprimento_total_m,ew_cem_obras_materiais.comprimento_total_m),
      origem_quantitativos=coalesce(excluded.origem_quantitativos,ew_cem_obras_materiais.origem_quantitativos),
      -- Cliente anterior sem este campo não apaga o planejamento já salvo.
      -- Novo ZIP com [] declara explicitamente ausência do plano nesta variação.
      barras_planejadas=coalesce(excluded.barras_planejadas,ew_cem_obras_materiais.barras_planejadas),
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

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_codigo text:=upper(btrim(coalesce(p_codigo_obra,'')));
  v_nome text:=btrim(coalesce(p_nome_obra,''));
  v_cliente text:=btrim(coalesce(p_cliente,''));
  v_obra_id uuid;
  v_obra_result jsonb;
  v_material_result jsonb:='{}'::jsonb;
  v_row jsonb;
  v_codigo_esq text;
  v_descricao text;
  v_localizacao text;
  v_rotulo text;
  v_qtd numeric;
  v_largura numeric;
  v_altura numeric;
  v_modulos integer;
  v_geradas integer:=0;
  v_esquadria_id uuid;
  v_esquadrias_ids jsonb:='[]'::jsonb;
  v_materials_selected boolean;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
     NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
       WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
  THEN RAISE EXCEPTION 'Somente um ADM autenticado pode importar uma obra do CEM.'; END IF;
  IF length(v_codigo) NOT BETWEEN 1 AND 80 OR length(v_nome) NOT BETWEEN 3 AND 180 OR
     length(v_cliente)>250
  THEN RAISE EXCEPTION 'Confira código (1–80), nome (3–180) e cliente (até 250 caracteres) da obra.'; END IF;
  IF jsonb_typeof(p_esquadrias) IS DISTINCT FROM 'array' OR
     jsonb_array_length(p_esquadrias) NOT BETWEEN 1 AND 1500 OR
     jsonb_typeof(p_perfis) IS DISTINCT FROM 'array' OR
     jsonb_typeof(p_acessorios) IS DISTINCT FROM 'array' OR
     jsonb_typeof(p_decisoes) IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'Os dados de esquadrias e materiais são inválidos.'; END IF;
  IF jsonb_array_length(p_perfis)>800 OR jsonb_array_length(p_acessorios)>1200 OR
     jsonb_array_length(p_decisoes)>400 THEN
    RAISE EXCEPTION 'Arquivo CEM acima do limite de importação segura.'; END IF;
  v_materials_selected:=jsonb_array_length(p_perfis)+jsonb_array_length(p_acessorios)>0;
  IF NOT v_materials_selected AND jsonb_array_length(p_decisoes)>0
  THEN RAISE EXCEPTION 'Há conciliações sem materiais selecionados.'; END IF;
  -- Serializa tentativas simultâneas de importação do mesmo código/empresa.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_empresa_id::text||'|'||v_codigo,0));
  IF EXISTS (SELECT 1 FROM public.obras
     WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL
       AND upper(btrim(codigo))=v_codigo)
  THEN RAISE EXCEPTION 'Esta obra já está cadastrada no EWGEST (%). Nenhum item foi duplicado.',v_codigo;
  END IF;
  -- Reutiliza o cadastro protegido existente, que também configura o local de estoque.
  v_obra_result:=public.ew_criar_obra_estoque(p_empresa_id,v_nome,v_codigo);
  v_obra_id:=(v_obra_result->>'id')::uuid;
  IF v_obra_id IS NULL THEN RAISE EXCEPTION 'Não foi possível confirmar o cadastro da obra.';END IF;
  UPDATE public.obras SET cliente=nullif(v_cliente,'') WHERE id=v_obra_id AND empresa_id=p_empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Não foi possível atualizar o cliente da obra.'; END IF;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_esquadrias) LOOP
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR
       jsonb_typeof(v_row->'quantidade') IS DISTINCT FROM 'number' OR
       jsonb_typeof(v_row->'largura_mm') IS DISTINCT FROM 'number' OR
       jsonb_typeof(v_row->'altura_mm') IS DISTINCT FROM 'number'
    THEN RAISE EXCEPTION 'Esquadria incompleta no ZIP.'; END IF;
    v_codigo_esq:=btrim(coalesce(v_row->>'codigo',''));
    v_descricao:=btrim(coalesce(v_row->>'descricao',''));
    v_localizacao:=btrim(coalesce(v_row->>'localizacao',''));
    v_rotulo:=btrim(coalesce(v_row->>'referencia_tipologia',''));
    v_qtd:=(v_row->>'quantidade')::numeric;
    v_largura:=(v_row->>'largura_mm')::numeric;
    v_altura:=(v_row->>'altura_mm')::numeric;
    IF length(v_codigo_esq) NOT BETWEEN 1 AND 100 OR length(v_descricao)>1000 OR
       length(v_localizacao)>500 OR length(v_rotulo)>150 OR
       v_qtd<>trunc(v_qtd) OR v_qtd NOT BETWEEN 1 AND 100000 OR
       v_largura<=0 OR v_largura>100000 OR v_altura<=0 OR v_altura>100000
    THEN RAISE EXCEPTION 'Dados inválidos da esquadria %: confira medidas e quantidade.',v_codigo_esq; END IF;
    v_modulos:=NULL;
    IF jsonb_typeof(v_row->'quantidade_modulos')='number' AND
       (v_row->>'quantidade_modulos')::numeric BETWEEN 1 AND 100 AND
       (v_row->>'quantidade_modulos')::numeric=trunc((v_row->>'quantidade_modulos')::numeric)
    THEN v_modulos:=(v_row->>'quantidade_modulos')::integer;END IF;
    INSERT INTO public.esquadrias(
      empresa_id,obra_id,codigo,descricao,localizacao,largura_mm,altura_mm,quantidade,
      qtd_liberada,qtd_fabricada,rotulo_tipologia_relatorio,quantidade_modulos)
    VALUES(p_empresa_id,v_obra_id,v_codigo_esq,nullif(v_descricao,''),nullif(v_localizacao,''),
      v_largura,v_altura,v_qtd::integer,0,0,
      nullif(v_rotulo,''),v_modulos) RETURNING id INTO v_esquadria_id;
    v_esquadrias_ids:=v_esquadrias_ids||jsonb_build_array(v_esquadria_id);
    v_geradas:=v_geradas+1;
  END LOOP;
  IF v_materials_selected THEN
    -- Chamada transacional: erro em qualquer material desfaz TUDO, inclusive obra e esquadrias.
    v_material_result:=public.ew_importar_cem_conciliado(
      p_empresa_id,v_codigo,p_perfis,p_acessorios,p_operacao_id,p_decisoes);
    IF (v_material_result->>'esquadrias_alteradas')::integer<>0 OR
       (v_material_result->>'estoque_fisico_alterado')::boolean IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'A importação de materiais não garantiu a preservação do estoque.';END IF;
  END IF;
  RETURN jsonb_build_object(
    'obra_criada',true,'obra_id',v_obra_id,'codigo_obra',v_codigo,
    'nome_obra',v_nome,'cliente',nullif(v_cliente,''),
    'esquadrias_novas',v_geradas,'esquadrias_ids',v_esquadrias_ids,
    'perfis_novos',coalesce((v_material_result->>'perfis_novos')::integer,0),
    'perfis_existentes',coalesce((v_material_result->>'perfis_existentes')::integer,0),
    'acessorios_novos',coalesce((v_material_result->>'acessorios_novos')::integer,0),
    'acessorios_existentes',coalesce((v_material_result->>'acessorios_existentes')::integer,0),
    'variacoes_novas',coalesce((v_material_result->>'variacoes_novas')::integer,0),
    'vinculos_por_obra',coalesce((v_material_result->>'vinculos_por_obra')::integer,0),
    'estoque_fisico_alterado',false);
END;
$function$;


REVOKE ALL ON FUNCTION public.ew_conciliar_codigo_cem(uuid,text,uuid,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_conciliar_codigo_cem(uuid,text,uuid,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.ew_criar_obra_estoque(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_criar_obra_estoque(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.ew_importar_cem_conciliado(uuid,text,jsonb,jsonb,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_importar_cem_conciliado(uuid,text,jsonb,jsonb,uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.ew_importar_obra_cem(uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_importar_obra_cem(uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.importar_materiais_cem(uuid,text,jsonb,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.importar_materiais_cem(uuid,text,jsonb,jsonb,uuid) TO authenticated;
DO $verify$
DECLARE total int; n int;
BEGIN
 SELECT count(*) INTO total FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='public';
 IF total<>48 THEN RAISE EXCEPTION 'Era esperado 48 funções no staging, há %.',total;END IF;
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
 WHERE s.nspname='public' AND (has_function_privilege('anon',p.oid,'EXECUTE'));
 IF n<>0 THEN RAISE EXCEPTION 'Restam % funções executáveis anon.',n;END IF;
END $verify$;
COMMIT;
