-- Reimportações devem buscar somente obras ativas. Obras arquivadas mantêm o código original no histórico.
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


CREATE OR REPLACE FUNCTION public.ew_importar_saldo_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_nome_arquivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_usuario uuid:=auth.uid();v_obra_id uuid;v_obra_count integer;
 v_tipo text;v_row jsonb;v_codigo text;v_cor text;v_qtd numeric;v_comp integer;
 v_variacao uuid;v_matches uuid[];v_unidade text;v_existente integer;
 v_novos integer:=0;v_ja_existiam integer:=0;v_linhas integer:=0;
 v_barras numeric:=0;v_acessorios numeric:=0;
 v_pendencias jsonb:='[]'::jsonb;v_result jsonb;v_id uuid;
 v_chave text;v_vistas text[]:=ARRAY[]::text[];
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
     WHERE ue.usuario_id=v_usuario AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode importar o estoque calculado do CEM.';END IF;
 IF length(coalesce(p_nome_arquivo,''))>240 OR length(coalesce(p_codigo_obra,''))>100
 OR jsonb_typeof(p_perfis) IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_acessorios) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Arquivo ou dados de importação inválidos.';END IF;
 IF jsonb_array_length(p_perfis)>500 OR jsonb_array_length(p_acessorios)>1500 OR
  jsonb_array_length(p_perfis)+jsonb_array_length(p_acessorios)=0
 THEN RAISE EXCEPTION 'Quantidade de registros do CEM inválida.';END IF;
 SELECT count(*),(array_agg(id))[1] INTO v_obra_count,v_obra_id FROM public.obras
 WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo_obra));
 IF v_obra_count<>1 THEN
  RAISE EXCEPTION 'A obra do arquivo (%) não foi encontrada unicamente no EWGEST.',p_codigo_obra;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|'||v_obra_id::text||'|CEM',74421));
 SELECT resumo INTO v_result FROM public.ew_estoque_importacoes_cem
 WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN RETURN v_result||jsonb_build_object('repetida',true);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais
  WHERE obra_id=v_obra_id AND empresa_id=p_empresa_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Este estoque não existe ou está arquivado. Restaure-o primeiro.';END IF;
 FOR v_tipo IN SELECT unnest(ARRAY['perfil','acessorio']) LOOP
  FOR v_row IN SELECT value FROM jsonb_array_elements(
    CASE WHEN v_tipo='perfil' THEN p_perfis ELSE p_acessorios END) LOOP
   IF jsonb_typeof(v_row)<>'object' THEN RAISE EXCEPTION 'Registro CEM inválido.';END IF;
   v_codigo:=upper(btrim(coalesce(v_row->>'codigo','')));
   v_cor:=upper(btrim(coalesce(v_row->>'cor','')));
   IF v_tipo='acessorio' AND v_cor IN ('','-') THEN v_cor:='NÃO INFORMADA';END IF;
   v_qtd:=(v_row->>'quantidade')::numeric;
   v_comp:=CASE WHEN v_tipo='perfil' THEN (v_row->>'comprimento_mm')::integer ELSE NULL END;
   IF length(v_codigo) NOT BETWEEN 1 AND 90 OR
    length(v_cor) NOT BETWEEN 1 AND 150 OR
    v_qtd IS NULL OR v_qtd<=0 OR v_qtd>10000000 OR v_qtd<>trunc(v_qtd,3) OR
    (v_tipo='perfil' AND (v_comp NOT BETWEEN 100 AND 20000 OR v_qtd<>trunc(v_qtd)))
   THEN RAISE EXCEPTION 'Código, comprimento ou quantidade incorretos: %.',v_codigo;END IF;
   v_chave:=v_tipo||'|'||v_codigo||'|'||v_cor||'|'||coalesce(v_comp::text,'-');
   IF v_chave=ANY(v_vistas) THEN
    RAISE EXCEPTION 'Registro do CEM repetido para %; agrupe as quantidades.',v_codigo;END IF;
   v_vistas:=array_append(v_vistas,v_chave);
   v_linhas:=v_linhas+1;
   v_variacao:=NULL;v_unidade:='';
   IF v_tipo='perfil' THEN
    SELECT array_agg(v.id) INTO v_matches FROM public.ew_perfis m
     JOIN public.ew_materiais_variacoes v ON v.perfil_id=m.id
     WHERE m.empresa_id=p_empresa_id AND v.empresa_id=p_empresa_id
      AND upper(btrim(m.codigo))=v_codigo AND
         (upper(btrim(v.cor))=v_cor OR upper(btrim(v.codigo_cor))=v_cor);
    v_unidade:='BARRA';
   ELSE
    SELECT array_agg(v.id) INTO v_matches FROM public.ew_acessorios m
     JOIN public.ew_materiais_variacoes v ON v.acessorio_id=m.id
     WHERE m.empresa_id=p_empresa_id AND v.empresa_id=p_empresa_id
      AND upper(btrim(m.codigo))=v_codigo AND upper(btrim(v.cor))=v_cor;
    SELECT upper(btrim(m.unidade_item)) INTO v_unidade FROM public.ew_acessorios m
     WHERE m.empresa_id=p_empresa_id AND upper(btrim(m.codigo))=v_codigo;
    v_unidade:=CASE v_unidade WHEN 'M' THEN 'MT' WHEN 'PÇ' THEN 'PC'
      WHEN 'PEÇA' THEN 'PC' WHEN 'PAR' THEN 'PR' WHEN 'CONJUNTO' THEN 'CJ'
      ELSE v_unidade END;
   END IF;
   IF coalesce(array_length(v_matches,1),0)=0 THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Sem cadastro correspondente'));
     CONTINUE;
   END IF;
   IF array_length(v_matches,1)>1 THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Mais de uma variação correspondente'));
     CONTINUE;
   END IF;
   IF v_tipo='acessorio' AND v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Unidade de acessório precisa de revisão'));
     CONTINUE;
   END IF;
   v_variacao:=v_matches[1];
   SELECT count(*) INTO v_existente FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND obra_id=v_obra_id AND variacao_id=v_variacao
      AND comprimento_mm IS NOT DISTINCT FROM v_comp AND unidade=v_unidade;
   IF v_existente>0 THEN v_ja_existiam:=v_ja_existiam+1;CONTINUE;END IF;
   INSERT INTO public.ew_estoque_obras_movimentos
     (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
      origem,operacao_id,observacao,usuario_id)
   VALUES(p_empresa_id,v_obra_id,v_variacao,v_comp,v_unidade,v_qtd,
     'IMPORTACAO_CEM',pg_catalog.gen_random_uuid(),
     'Saldo inicial calculado pelo CEM · '||left(coalesce(p_nome_arquivo,'arquivo'),240),v_usuario);
   v_novos:=v_novos+1;
   IF v_tipo='perfil' THEN v_barras:=v_barras+v_qtd; ELSE v_acessorios:=v_acessorios+v_qtd;END IF;
  END LOOP;
 END LOOP;
 v_result:=jsonb_build_object('obra_id',v_obra_id,'codigo_obra',p_codigo_obra,
  'linhas_lidas',v_linhas,'linhas_importadas',v_novos,'linhas_preservadas',v_ja_existiam,
  'barras_importadas',v_barras,'quantidade_acessorios_importada',v_acessorios,
  'pendencias',v_pendencias,'repetida',false);
 INSERT INTO public.ew_estoque_importacoes_cem
   (empresa_id,obra_id,operacao_id,nome_arquivo,resumo,usuario_id)
 VALUES(p_empresa_id,v_obra_id,p_operacao_id,p_nome_arquivo,v_result,v_usuario);
 RETURN v_result;
END;$function$;


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
   IF length(v_codigo) NOT BETWEEN 1 AND 90 OR
      length(v_fabricante) NOT BETWEEN 1 AND 150 OR length(v_descricao) NOT BETWEEN 2 AND 500 THEN
      RAISE EXCEPTION 'Cadastro incompleto ou inválido do CEM: %. ',v_codigo;
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
      unidade_item,unidade_embalagem,criado_por,atualizado_por)
    VALUES(p_empresa_id,v_codigo,v_fabricante,v_descricao,
      left(coalesce(v_item->>'linha',''),150),left(coalesce(v_item->>'prenativo',''),150),
      left(coalesce(nullif(btrim(v_item->>'unidade'),''),'PC'),30),
      left(coalesce(v_item->>'embalagem',''),30),v_uid,v_uid)
    ON CONFLICT DO NOTHING RETURNING id INTO v_mat_id;
    IF v_mat_id IS NULL THEN
      v_existing_acessorios:=v_existing_acessorios+1;
      SELECT id INTO v_mat_id FROM public.ew_acessorios
       WHERE empresa_id=p_empresa_id AND upper(btrim(codigo))=v_codigo AND upper(btrim(fabricante))=v_fabricante;
    ELSE v_new_acessorios:=v_new_acessorios+1; END IF;
    END IF;
   END IF;
   IF v_mat_id IS NULL THEN RAISE EXCEPTION 'Falha ao localizar o material %.',v_codigo; END IF;
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
   'variacoes_novas',v_new_var,'vinculos_por_obra',v_link_count,
   'esquadrias_alteradas',0,'estoque_fisico_alterado',false);
 INSERT INTO public.ew_cem_importacoes_materiais
 (empresa_id,obra_id,operacao_id,codigo_obra_cem,importou_perfis,importou_acessorios,resumo,criado_por)
 VALUES(p_empresa_id,v_obra,p_operacao_id,p_codigo_obra,jsonb_array_length(p_perfis)>0,
    jsonb_array_length(p_acessorios)>0,v_result,v_uid);
 RETURN v_result;
END;
$function$
;