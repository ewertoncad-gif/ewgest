-- DDL ORIGINAL de ew_importar_obra_cem capturado de produção em 2026-11-22.
-- Apenas referência de rollback; não executar sem revisão.
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
      nullif(v_rotulo,''),v_modulos);
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
    'esquadrias_novas',v_geradas,
    'perfis_novos',coalesce((v_material_result->>'perfis_novos')::integer,0),
    'perfis_existentes',coalesce((v_material_result->>'perfis_existentes')::integer,0),
    'acessorios_novos',coalesce((v_material_result->>'acessorios_novos')::integer,0),
    'acessorios_existentes',coalesce((v_material_result->>'acessorios_existentes')::integer,0),
    'variacoes_novas',coalesce((v_material_result->>'variacoes_novas')::integer,0),
    'vinculos_por_obra',coalesce((v_material_result->>'vinculos_por_obra')::integer,0),
    'estoque_fisico_alterado',false);
END;
$function$;
