-- CEM: reimportação só antes de histórico operacional; estoque físico não nasce do plano.
CREATE OR REPLACE FUNCTION ew_compras_interna.cem_obra_editavel(p_empresa uuid,p_codigo text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w uuid; n int;
BEGIN
 IF NOT public.ew_pode(p_empresa,'obras.importar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.importar';END IF;
 SELECT count(*),(array_agg(id))[1] INTO n,w FROM public.obras WHERE empresa_id=p_empresa AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo));
 IF n<>1 THEN RAISE EXCEPTION 'Obra ativa não identificada unicamente.';END IF;
 PERFORM 1 FROM public.obras WHERE id=w AND empresa_id=p_empresa AND arquivada_em IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Obra indisponível.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_insumos_movimentos WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_obra_despesas WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_compras_solicitacoes WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias WHERE empresa_id=p_empresa AND (origem_id=w OR destino_id=w))
 OR EXISTS(SELECT 1 FROM public.romaneios WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_romaneios_transferencia WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_liberacoes_lotes WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.ew_planos_liberados WHERE obra_id=w)
 OR EXISTS(SELECT 1 FROM public.esquadrias e WHERE e.obra_id=w AND (e.qtd_liberada<>0 OR e.qtd_fabricada<>0 OR EXISTS(SELECT 1 FROM public.liberacoes_corte l WHERE l.esquadria_id=e.id) OR EXISTS(SELECT 1 FROM public.saidas_producao s WHERE s.esquadria_id=e.id)))
 THEN RAISE EXCEPTION 'Reimportação bloqueada: obra com histórico operacional. Preserve o planejamento original e utilize uma revisão controlada.';END IF;
 RETURN w;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.cem_obra_editavel(uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.ew_conciliar_codigo_cem(p_empresa_id uuid, p_tipo text, p_material_id uuid, p_codigo_cem text, p_usar_codigo_cem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_codigo_antigo text;v_fabricante text;v_codigo text;
 v_outro uuid;v_alias uuid;v_id uuid;
BEGIN
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar';END IF;
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
  IF EXISTS(SELECT 1 FROM public.ew_materiais_alias a WHERE a.empresa_id=p_empresa_id AND a.tipo=p_tipo AND a.fabricante=v_fabricante AND a.codigo_alternativo=v_codigo_antigo AND (CASE WHEN p_tipo='perfil' THEN a.perfil_id ELSE a.acessorio_id END) IS DISTINCT FROM p_material_id) THEN RAISE EXCEPTION 'Código original já pertence a outro material.';END IF;
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

CREATE OR REPLACE FUNCTION public.ew_importar_cem_conciliado(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_d jsonb;v_tipo text;v_codigo text;v_fabricante text;v_id uuid;v_usar boolean;
 v_row jsonb;v_encontrado boolean;v_result jsonb;v_seen text[]:=ARRAY[]::text[];v_key text;v_hash text;v_obra uuid;
BEGIN
 IF NOT public.ew_pode(p_empresa_id,'obras.importar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.importar';END IF;
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode realizar importação conciliada.';END IF;
 IF jsonb_typeof(p_decisoes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_decisoes)>400
 THEN RAISE EXCEPTION 'Lista de conciliações inválida.';END IF;
 IF p_operacao_id IS NULL THEN RAISE EXCEPTION 'Operação inválida.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cem-material|'||p_operacao_id::text,70012));
 v_hash:=md5(jsonb_build_array(upper(btrim(p_codigo_obra)),p_perfis,p_acessorios,p_decisoes)::text);
 SELECT resumo,obra_id INTO v_result,v_obra FROM public.ew_cem_importacoes_materiais WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF FOUND THEN
  IF v_result->>'conciliacao_hash' IS DISTINCT FROM v_hash OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=v_obra AND empresa_id=p_empresa_id AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo_obra))) THEN RAISE EXCEPTION 'Identificador de importação já utilizado ou obra indisponível. Analise o arquivo novamente.';END IF;
  RETURN v_result;
 END IF;
 v_obra:=ew_compras_interna.cem_obra_editavel(p_empresa_id,p_codigo_obra);
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
   IF v_tipo NOT IN ('perfil','acessorio') OR v_tipo IS NULL OR v_id IS NULL OR v_usar IS NULL OR NOT (
     (v_tipo='perfil' AND EXISTS(SELECT 1 FROM public.ew_perfis WHERE empresa_id=p_empresa_id AND id=v_id AND upper(btrim(fabricante))=v_fabricante))
     OR (v_tipo='acessorio' AND EXISTS(SELECT 1 FROM public.ew_acessorios WHERE empresa_id=p_empresa_id AND id=v_id AND upper(btrim(fabricante))=v_fabricante))
   ) THEN RAISE EXCEPTION 'Equivalência inválida: material de outro fabricante, tipo ou empresa.';END IF;
   PERFORM public.ew_conciliar_codigo_cem(p_empresa_id,v_tipo,v_id,v_codigo,v_usar);
 END LOOP;
 v_result:=public.importar_materiais_cem(p_empresa_id,p_codigo_obra,p_perfis,p_acessorios,p_operacao_id)||jsonb_build_object('conciliacao_hash',v_hash);
 UPDATE public.ew_cem_importacoes_materiais SET resumo=v_result WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id AND obra_id=v_obra;
 RETURN v_result;
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_precificacao(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb, p_orcamento jsonb, p_precificacao jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_fab_origem bigint:=0;
 v_inst_origem bigint:=0;
 v_fab_atual bigint;
 v_inst_atual bigint;
 v_comb bigint;
 v_pcent integer;
 v_exp_fab bigint;
 v_exp_inst bigint;
 v_calc_fab bigint;
 v_calc_inst bigint;
 v_count integer;
 v_idx integer;
 v_soma_pesos numeric;
 v_sum_fab bigint;
 v_sum_inst bigint;
 v_total_area numeric;
 v_cat jsonb;
 v_item jsonb;
 v_origem jsonb;
 v_nome text;
 v_local text;
 v_categoria_uuid uuid;
 v_cat_map jsonb:='{}'::jsonb;
 v_result jsonb;
 v_obra_id uuid;
 v_revisao_id uuid;
 v_codigo_existente text;
 v_valor_orcado numeric;
 v_hash_existente text;
 v_request_hash text;
 v_ids jsonb;
 v_esquadria_id uuid;
 v_tipo_id uuid;
 v_categoria_nome text;
 v_categoria_base int;
 v_categoria_fab bigint;
 v_categoria_inst bigint;
 v_categoria_area numeric;
 v_valor_linha numeric;
 v_peso numeric;
 v_expected_errs integer;
 v_linha_categoria jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
    AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador'
 ) THEN RAISE EXCEPTION 'Somente ADM autenticado pode aprovar importação e precificação.'; END IF;
 v_request_hash:=md5(jsonb_build_object(
  'empresa_id',p_empresa_id,'codigo_obra',upper(btrim(coalesce(p_codigo_obra,''))),
  'nome_obra',btrim(coalesce(p_nome_obra,'')),'cliente',btrim(coalesce(p_cliente,'')),
  'esquadrias',p_esquadrias,'perfis',p_perfis,'acessorios',p_acessorios,
  'decisoes',p_decisoes,'orcamento',p_orcamento,'precificacao',p_precificacao
 )::text);
 -- A chave de operação é permanente na revisão aprovada; o retry devolve
 -- a mesma obra e a mesma revisão, sem inserir mais nenhuma linha.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|preco-cem|'||p_operacao_id::text,0));
 SELECT r.obra_id,r.id,o.codigo,orc.valor_total,r.operacao_hash
  INTO v_obra_id,v_revisao_id,v_codigo_existente,v_valor_orcado,v_hash_existente
  FROM public.ew_precificacao_revisoes r
  JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=r.empresa_id
  JOIN public.ew_obra_orcamento orc ON orc.obra_id=r.obra_id AND orc.empresa_id=r.empresa_id
 WHERE r.empresa_id=p_empresa_id AND r.operacao_id=p_operacao_id;
 IF FOUND THEN
  IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=v_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Importação anterior pertence a obra arquivada. Analise novamente o ZIP.';END IF;
  IF v_hash_existente IS DISTINCT FROM v_request_hash THEN
   RAISE EXCEPTION 'O identificador da importação já foi usado com outros dados. Refaça a conferência sem reutilizar esta operação.'; END IF;
  IF upper(btrim(v_codigo_existente))<>upper(btrim(coalesce(p_codigo_obra,''))) THEN
   RAISE EXCEPTION 'Operação de importação já vinculada a outra obra.'; END IF;
  IF EXISTS(SELECT 1 FROM public.ew_precificacao_revisoes r
    WHERE r.id=v_revisao_id AND r.estado<>'aprovada')
  THEN RAISE EXCEPTION 'A operação existe com histórico ainda não aprovado.';END IF;
  RETURN jsonb_build_object('obra_criada',true,'obra_id',v_obra_id,
     'orcamento_gravado',true,'valor_total',v_valor_orcado,
     'estoque_fisico_alterado',false,'ja_importado',true,
     'esquadrias_novas',(SELECT count(*) FROM public.esquadrias e
       WHERE e.empresa_id=p_empresa_id AND e.obra_id=v_obra_id),
     'precificacao_gravada',true,'precificacao_revisao_id',v_revisao_id);
 END IF;
 IF jsonb_typeof(p_orcamento->'niveis') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_precificacao) IS DISTINCT FROM 'object' OR
    jsonb_typeof(p_precificacao->'categorias') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_precificacao->'itens') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_esquadrias) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Orçamento ou precificação incompletos.'; END IF;
 v_count:=jsonb_array_length(p_esquadrias);
 IF v_count NOT BETWEEN 1 AND 1500 OR
    jsonb_array_length(p_precificacao->'itens')<>v_count OR
    jsonb_array_length(p_precificacao->'categorias') NOT BETWEEN 1 AND 150
 THEN RAISE EXCEPTION 'Quantidade de itens/categorias não corresponde à obra.'; END IF;
 IF p_precificacao->>'versao' IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'Versão de precificação não reconhecida.'; END IF;

 -- Percentuais e totais originais são derivados do próprio orçamento, não do
 -- JSON de precificação. Valores inteiros enviados são centavos, nunca reais.
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
  IF jsonb_typeof(v_item->'valor') IS DISTINCT FROM 'number' THEN
   RAISE EXCEPTION 'Nível sem valor monetário válido.'; END IF;
  v_valor_linha:=(v_item->>'valor')::numeric;
  IF v_valor_linha<0 OR v_valor_linha>999999999999.99 OR
     v_valor_linha<>round(v_valor_linha,2) THEN
   RAISE EXCEPTION 'Nível financeiro fora da precisão em reais.'; END IF;
  IF v_item->>'categoria_base' IN ('fabricacao','instalacao') AND v_valor_linha>0 AND
    (jsonb_typeof(v_item->'faturar') IS DISTINCT FROM 'boolean' OR
     (v_item->>'faturar')::boolean IS DISTINCT FROM true)
  THEN RAISE EXCEPTION 'Níveis de fabricação e instalação precisam ser faturáveis.'; END IF;
  IF v_item->>'categoria_base'='fabricacao' THEN
   v_fab_origem:=v_fab_origem+(v_valor_linha*100)::bigint;
  ELSIF v_item->>'categoria_base'='instalacao' THEN
   v_inst_origem:=v_inst_origem+(v_valor_linha*100)::bigint;
  END IF;
 END LOOP;
 v_comb:=v_fab_origem+v_inst_origem;
 IF v_comb<=0 OR v_comb>100000000000000 THEN
  RAISE EXCEPTION 'O orçamento não possui fabricação/instalação válidos.'; END IF;
 IF jsonb_typeof(p_precificacao->'fabricacao_original_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'instalacao_original_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'fabricacao_distribuida_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'instalacao_distribuida_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'percentual_fabricacao_bp') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'percentual_ajustado') IS DISTINCT FROM 'boolean'
 THEN RAISE EXCEPTION 'Distribuição sem os campos obrigatórios.'; END IF;
 IF (p_precificacao->>'fabricacao_original_centavos')::numeric<>v_fab_origem OR
    (p_precificacao->>'instalacao_original_centavos')::numeric<>v_inst_origem
 THEN RAISE EXCEPTION 'Valores originais divergentes do orçamento informado.'; END IF;
 v_pcent:=(p_precificacao->>'percentual_fabricacao_bp')::integer;
 IF v_pcent NOT BETWEEN 0 AND 10000 OR
    (p_precificacao->>'percentual_fabricacao_bp')::numeric<>v_pcent
 THEN RAISE EXCEPTION 'Percentual de fabricação inválido.'; END IF;
 v_fab_atual:=(p_precificacao->>'fabricacao_distribuida_centavos')::bigint;
 v_inst_atual:=(p_precificacao->>'instalacao_distribuida_centavos')::bigint;
 IF v_fab_atual<0 OR v_inst_atual<0 OR v_fab_atual+v_inst_atual<>v_comb OR
    (p_precificacao->>'fabricacao_distribuida_centavos')::numeric<>v_fab_atual OR
    (p_precificacao->>'instalacao_distribuida_centavos')::numeric<>v_inst_atual
 THEN RAISE EXCEPTION 'Distribuição não fecha o total contratado.'; END IF;
 IF (p_precificacao->>'percentual_ajustado')::boolean THEN
  IF v_fab_atual<>floor((v_comb::numeric*v_pcent+5000)/10000)::bigint THEN
   RAISE EXCEPTION 'Percentual alterado não corresponde à nova fabricação.'; END IF;
 ELSE
  IF v_fab_atual<>v_fab_origem OR v_inst_atual<>v_inst_origem OR
     v_pcent<>round(v_fab_origem::numeric/v_comb*10000)::integer
  THEN RAISE EXCEPTION 'Percentual sugerido difere do orçamento.'; END IF;
 END IF;

 -- Validar catálogo de categorias em memória, antes de criar a obra.
 IF EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') AS c
  WHERE jsonb_typeof(c) IS DISTINCT FROM 'object' OR
        jsonb_typeof(c->'preco_base_m2_centavos') IS DISTINCT FROM 'number' OR
        jsonb_typeof(c->'fabricacao_centavos') IS DISTINCT FROM 'number' OR
        jsonb_typeof(c->'instalacao_centavos') IS DISTINCT FROM 'number' OR
        char_length(btrim(c->>'nome')) NOT BETWEEN 2 AND 120 OR
        char_length(btrim(c->>'id_local')) NOT BETWEEN 1 AND 100
 ) THEN RAISE EXCEPTION 'Categoria sem nome ou valores válidos.'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p_precificacao->'categorias'))<>
    (SELECT count(DISTINCT lower(btrim(c->>'nome'))) FROM jsonb_array_elements(p_precificacao->'categorias') c) OR
    (SELECT count(*) FROM jsonb_array_elements(p_precificacao->'categorias'))<>
    (SELECT count(DISTINCT c->>'id_local') FROM jsonb_array_elements(p_precificacao->'categorias') c)
 THEN RAISE EXCEPTION 'Categorias repetidas.'; END IF;
 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  IF (v_cat->>'preco_base_m2_centavos')::numeric<>trunc((v_cat->>'preco_base_m2_centavos')::numeric) OR
     (v_cat->>'preco_base_m2_centavos')::numeric NOT BETWEEN 0 AND 100000000000 OR
     (v_cat->>'fabricacao_centavos')::numeric<>trunc((v_cat->>'fabricacao_centavos')::numeric) OR
     (v_cat->>'instalacao_centavos')::numeric<>trunc((v_cat->>'instalacao_centavos')::numeric) OR
     (v_cat->>'fabricacao_centavos')::numeric<0 OR
     (v_cat->>'instalacao_centavos')::numeric<0
  THEN RAISE EXCEPTION 'Preço/valor inválido na categoria %.',v_cat->>'nome'; END IF;
 END LOOP;

 -- Cada índice representa a posição do item no CEM, independentemente de
 -- códigos EA duplicados. Isso evita associação incorreta de preços futuros.
 v_idx:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_precificacao->'itens') LOOP
  v_origem:=p_esquadrias->v_idx;
  IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
     (v_item->>'indice_importacao')::integer IS DISTINCT FROM v_idx OR
     v_item->>'codigo' IS DISTINCT FROM v_origem->>'codigo' OR
     v_item->>'descricao' IS DISTINCT FROM v_origem->>'descricao' OR
     v_item->>'referencia_tipologia' IS DISTINCT FROM coalesce(v_origem->>'referencia_tipologia','') OR
     (v_item->>'largura_mm')::numeric<>(v_origem->>'largura_mm')::numeric OR
     (v_item->>'altura_mm')::numeric<>(v_origem->>'altura_mm')::numeric OR
     (v_item->>'quantidade')::integer<>(v_origem->>'quantidade')::integer OR
     NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') c
          WHERE c->>'id_local'=v_item->>'categoria_id_local')
  THEN RAISE EXCEPTION 'Item % diverge do CEM ou da categoria selecionada.',v_idx+1; END IF;
  IF jsonb_typeof(v_item->'definir_padrao_tipologia') IS DISTINCT FROM 'boolean'
  THEN RAISE EXCEPTION 'Definição de categoria padrão inválida no item %.',v_idx+1; END IF;
  IF jsonb_typeof(v_item->'fabricacao_centavos') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'instalacao_centavos') IS DISTINCT FROM 'number' OR
     (v_item->>'fabricacao_centavos')::numeric<0 OR
     (v_item->>'instalacao_centavos')::numeric<0 OR
     (v_item->>'fabricacao_centavos')::numeric<>trunc((v_item->>'fabricacao_centavos')::numeric) OR
     (v_item->>'instalacao_centavos')::numeric<>trunc((v_item->>'instalacao_centavos')::numeric)
  THEN RAISE EXCEPTION 'Valores fracionários ou negativos no item %.',v_idx+1; END IF;
  IF round((v_origem->>'largura_mm')::numeric*(v_origem->>'altura_mm')::numeric*
           (v_origem->>'quantidade')::numeric/1000000,6) <>
     round((v_item->>'area_m2')::numeric,6)
  THEN RAISE EXCEPTION 'Área do item % não confere com largura/altura/quantidade.',v_idx+1; END IF;
  v_idx:=v_idx+1;
 END LOOP;

 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') c
              WHERE (c->>'preco_base_m2_centavos')::numeric>0) OR
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_precificacao->'itens') p
      JOIN jsonb_array_elements(p_precificacao->'categorias') c
       ON c->>'id_local'=p->>'categoria_id_local'
      WHERE (c->>'preco_base_m2_centavos')::numeric<=0
    ) THEN RAISE EXCEPTION 'Todas as categorias em uso exigem preço-base positivo.'; END IF;

 -- O rateio é recalculado no servidor por maior resto e índice do CEM;
 -- não basta o cliente enviar somatórios aparentemente corretos.
 WITH entrada AS (
  SELECT p.ord::integer-1 idx,p.item,
   (o.item->>'largura_mm')::numeric*(o.item->>'altura_mm')::numeric*
   (o.item->>'quantidade')::numeric AS area,
   (c.item->>'preco_base_m2_centavos')::numeric AS preco
  FROM jsonb_array_elements(p_precificacao->'itens') WITH ORDINALITY p(item,ord)
  JOIN jsonb_array_elements(p_esquadrias) WITH ORDINALITY o(item,ord) USING(ord)
  JOIN jsonb_array_elements(p_precificacao->'categorias') c(item)
   ON c.item->>'id_local'=p.item->>'categoria_id_local'
 ), pesos AS (
  SELECT idx,item,area,area*preco AS peso FROM entrada
 ), total AS (
  SELECT sum(peso) AS todo FROM pesos
 ), primeira AS (
  SELECT p.*,
   floor(v_fab_atual::numeric*p.peso/t.todo)::bigint AS f0,
   mod(v_fab_atual::numeric*p.peso,t.todo) AS fr,
   floor(v_inst_atual::numeric*p.peso/t.todo)::bigint AS i0,
   mod(v_inst_atual::numeric*p.peso,t.todo) AS ir
  FROM pesos p CROSS JOIN total t
 ), ordenada AS (
  SELECT p.*,
   row_number() OVER(ORDER BY fr DESC,idx ASC) AS rank_f,
   row_number() OVER(ORDER BY ir DESC,idx ASC) AS rank_i,
   v_fab_atual-sum(f0) OVER() AS sob_f,
   v_inst_atual-sum(i0) OVER() AS sob_i
  FROM primeira p
 )
 SELECT count(*) FILTER(WHERE
  (item->>'fabricacao_centavos')::bigint<>(f0+CASE WHEN rank_f<=sob_f THEN 1 ELSE 0 END)
  OR (item->>'instalacao_centavos')::bigint<>(i0+CASE WHEN rank_i<=sob_i THEN 1 ELSE 0 END)
  ) INTO v_expected_errs FROM ordenada;
 IF v_expected_errs IS NULL OR v_expected_errs<>0 THEN
  RAISE EXCEPTION 'Valores dos itens não conferem com o rateio aprovado.'; END IF;


 -- Validar também os totais fornecidos por categoria.
 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  SELECT coalesce(sum((it->>'fabricacao_centavos')::bigint),0),
         coalesce(sum((it->>'instalacao_centavos')::bigint),0),
         coalesce(sum((it->>'area_m2')::numeric),0)
    INTO v_categoria_fab,v_categoria_inst,v_categoria_area
    FROM jsonb_array_elements(p_precificacao->'itens') it
    WHERE it->>'categoria_id_local'=v_cat->>'id_local';
  IF v_categoria_fab<>(v_cat->>'fabricacao_centavos')::bigint OR
     v_categoria_inst<>(v_cat->>'instalacao_centavos')::bigint OR
     round(v_categoria_area,6)<>round((v_cat->>'area_m2')::numeric,6)
  THEN RAISE EXCEPTION 'Total divergente da categoria %.',v_cat->>'nome'; END IF;
 END LOOP;

 -- Somente a partir daqui executar operações que criam obra/dados.
 -- A chamada continua na MESMA transação de PostgreSQL.
 v_result:=public.ew_importar_obra_cem_financeiro(
  p_empresa_id,p_codigo_obra,p_nome_obra,p_cliente,p_esquadrias,
  p_perfis,p_acessorios,p_operacao_id,p_decisoes,p_orcamento);
 v_obra_id:=(v_result->>'obra_id')::uuid;
 v_ids:=v_result->'esquadrias_ids';
 IF v_obra_id IS NULL OR v_result->>'obra_criada'<>'true' OR
    jsonb_typeof(v_ids) IS DISTINCT FROM 'array' OR
    jsonb_array_length(v_ids)<>v_count
 THEN RAISE EXCEPTION 'IDs das esquadrias não foram retornados pelo importador.'; END IF;

 INSERT INTO public.ew_precificacao_revisoes(
  empresa_id,obra_id,versao,operacao_id,operacao_hash,fabricacao_original_centavos,instalacao_original_centavos,
  fabricacao_distribuida_centavos,instalacao_distribuida_centavos,
  percentual_fabricacao_bp,area_total_m2,motivo,aprovado_por)
 VALUES(
  p_empresa_id,v_obra_id,1,p_operacao_id,v_request_hash,v_fab_origem,v_inst_origem,v_fab_atual,v_inst_atual,
  v_pcent,
  (SELECT round(sum((v_area.item->>'area_m2')::numeric),6)
   FROM jsonb_array_elements(p_precificacao->'itens') AS v_area(item)),
  'Precificação aprovada na importação do CEM',v_uid)
 RETURNING id INTO v_revisao_id;

 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  v_nome:=upper(btrim(v_cat->>'nome'));
  INSERT INTO public.ew_precificacao_categorias(empresa_id,nome,criado_por)
   VALUES(p_empresa_id,v_nome,v_uid)
   ON CONFLICT DO NOTHING;
  SELECT id INTO v_categoria_uuid FROM public.ew_precificacao_categorias
   WHERE empresa_id=p_empresa_id AND lower(btrim(nome))=lower(v_nome);
  IF v_categoria_uuid IS NULL THEN
   RAISE EXCEPTION 'Categoria não encontrada após cadastro: %.',v_nome; END IF;
  v_cat_map:=v_cat_map||jsonb_build_object(v_cat->>'id_local',v_categoria_uuid);
  INSERT INTO public.ew_precificacao_revisoes_categorias(
   empresa_id,obra_id,revisao_id,categoria_id,categoria_nome_snapshot,
   preco_base_m2_centavos,area_m2,fabricacao_centavos,instalacao_centavos)
  VALUES(
   p_empresa_id,v_obra_id,v_revisao_id,v_categoria_uuid,v_nome,
   (v_cat->>'preco_base_m2_centavos')::bigint,
   round((v_cat->>'area_m2')::numeric,6),
   (v_cat->>'fabricacao_centavos')::bigint,(v_cat->>'instalacao_centavos')::bigint
  );
 END LOOP;

 v_idx:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_precificacao->'itens') LOOP
  v_origem:=p_esquadrias->v_idx;
  v_esquadria_id:=(v_ids->>v_idx)::uuid;
  v_categoria_uuid:=(v_cat_map->>(v_item->>'categoria_id_local'))::uuid;
  -- Vínculo por código técnico somente se houver exatamente uma tipologia
  -- correspondente da mesma empresa. Nunca escolher arbitrariamente.
  SELECT CASE WHEN count(*)=1 THEN (array_agg(t.id))[1] ELSE NULL END
   INTO v_tipo_id FROM public.tipologias t
   WHERE t.empresa_id=p_empresa_id AND
    upper(btrim(t.codigo))=upper(btrim(coalesce(v_origem->>'referencia_tipologia','')));
  SELECT c->>'nome' INTO v_categoria_nome FROM jsonb_array_elements(p_precificacao->'categorias') c
    WHERE c->>'id_local'=v_item->>'categoria_id_local';
  INSERT INTO public.ew_precificacao_revisoes_itens(
   empresa_id,obra_id,revisao_id,indice_importacao,
   esquadria_id,tipologia_id,categoria_id,categoria_nome_snapshot,
   codigo_snapshot,descricao_snapshot,referencia_tipologia_snapshot,linha_snapshot,
   largura_mm,altura_mm,quantidade,area_m2,
   fabricacao_centavos,instalacao_centavos)
  VALUES(
   p_empresa_id,v_obra_id,v_revisao_id,v_idx,
   v_esquadria_id,v_tipo_id,v_categoria_uuid,upper(btrim(v_categoria_nome)),
   v_item->>'codigo',coalesce(v_item->>'descricao',''),
   coalesce(v_item->>'referencia_tipologia',''),NULL,
   (v_item->>'largura_mm')::numeric,(v_item->>'altura_mm')::numeric,
   (v_item->>'quantidade')::integer,round((v_item->>'area_m2')::numeric,6),
   (v_item->>'fabricacao_centavos')::bigint,(v_item->>'instalacao_centavos')::bigint
  );
  IF (v_item->>'definir_padrao_tipologia')::boolean THEN
   IF v_tipo_id IS NULL THEN
    RAISE EXCEPTION 'Só é possível salvar categoria padrão para tipologia cadastrada e identificada sem ambiguidades (%).',v_item->>'referencia_tipologia';
   END IF;
   IF EXISTS(
    SELECT 1 FROM jsonb_array_elements(p_precificacao->'itens') outro
    WHERE upper(btrim(coalesce(outro->>'referencia_tipologia','')))=
          upper(btrim(coalesce(v_item->>'referencia_tipologia','')))
      AND outro->>'categoria_id_local' IS DISTINCT FROM v_item->>'categoria_id_local'
      AND (outro->>'definir_padrao_tipologia')::boolean IS TRUE
   ) THEN RAISE EXCEPTION 'A mesma tipologia não pode ter duas categorias padrão diferentes na importação.';END IF;
   INSERT INTO public.ew_precificacao_tipologias_padrao(
    empresa_id,tipologia_id,categoria_id,alterado_por)
   VALUES(p_empresa_id,v_tipo_id,v_categoria_uuid,v_uid)
   ON CONFLICT (empresa_id,tipologia_id) DO UPDATE
    SET categoria_id=EXCLUDED.categoria_id,
        alterado_por=EXCLUDED.alterado_por,
        atualizado_em=now();
  END IF;
  v_idx:=v_idx+1;
 END LOOP;

 -- Verificação final independente, travada ao concluir a transação.
 IF (SELECT coalesce(sum(fabricacao_centavos),0) FROM public.ew_precificacao_revisoes_itens
     WHERE revisao_id=v_revisao_id)<>v_fab_atual OR
    (SELECT coalesce(sum(instalacao_centavos),0) FROM public.ew_precificacao_revisoes_itens
     WHERE revisao_id=v_revisao_id)<>v_inst_atual
 THEN RAISE EXCEPTION 'A gravação do histórico não conciliou os valores.'; END IF;

 RETURN v_result||jsonb_build_object('precificacao_gravada',true,
  'precificacao_revisao_id',v_revisao_id,
  'precificacao_itens',v_count,
  'precificacao_categorias',jsonb_array_length(p_precificacao->'categorias'));
END;
$function$;

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
 v_cached jsonb; v_seen_variacoes uuid[]:=array[]::uuid[]; v_hash text; v_cached_obra uuid;
 v_result jsonb;
BEGIN
 IF v_uid IS NULL OR p_operacao_id IS NULL OR p_empresa_id IS NULL THEN
  RAISE EXCEPTION 'Sessão ou identificador da importação inválido.';
 END IF;
 PERFORM public.ew_exigir_sessao_atual();
 IF NOT public.ew_pode(p_empresa_id,'obras.importar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.importar';END IF;
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
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cem-material|'||p_operacao_id::text,70012));
 v_hash:=md5(jsonb_build_array(upper(btrim(p_codigo_obra)),p_perfis,p_acessorios)::text);
 SELECT resumo,obra_id INTO v_cached,v_cached_obra FROM public.ew_cem_importacoes_materiais WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF FOUND THEN
  IF v_cached->>'request_hash' IS DISTINCT FROM v_hash OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=v_cached_obra AND empresa_id=p_empresa_id AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo_obra))) THEN RAISE EXCEPTION 'Identificador de importação já utilizado ou obra indisponível. Analise o arquivo novamente.';END IF;
  RETURN v_cached;
 END IF;
 v_obra:=ew_compras_interna.cem_obra_editavel(p_empresa_id,p_codigo_obra);
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
    IF v_var_id=ANY(v_seen_variacoes) THEN RAISE EXCEPTION 'Material/variação repetido após equivalência: %. Revise o ZIP e as equivalências.',v_codigo;END IF;
    v_seen_variacoes:=array_append(v_seen_variacoes,v_var_id);
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
   'esquadrias_alteradas',0,'estoque_fisico_alterado',false,'request_hash',v_hash);
 INSERT INTO public.ew_cem_importacoes_materiais
 (empresa_id,obra_id,operacao_id,codigo_obra_cem,importou_perfis,importou_acessorios,resumo,criado_por)
 VALUES(p_empresa_id,v_obra,p_operacao_id,p_codigo_obra,jsonb_array_length(p_perfis)>0,
    jsonb_array_length(p_acessorios)>0,v_result,v_uid);
 RETURN v_result;
END;
$function$;

-- Endpoint legado de saldo calculado não é mais uma operação permitida ao cliente.
REVOKE EXECUTE ON FUNCTION public.ew_importar_saldo_obra_cem(uuid,text,jsonb,jsonb,text,uuid) FROM PUBLIC,anon,authenticated;

-- A importação de materiais é uma etapa interna da RPC conciliada, não um segundo caminho público.
REVOKE EXECUTE ON FUNCTION public.importar_materiais_cem(uuid,text,jsonb,jsonb,uuid) FROM PUBLIC,anon,authenticated;
