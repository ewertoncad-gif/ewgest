-- EWGEST v46.9 — PROPOSTA DE RPC transacional (NÃO APLICADA EM PRODUÇÃO)
-- Dependências:
-- 1. 20261122_precificacao_categorias_historico_fase1.sql
-- 2. 20261122_precificacao_importador_mapeamento_v469.sql
-- 3. Esta RPC, em seguida atualização do frontend.
--
-- O orçamento e a obra são criados por ew_importar_obra_cem_financeiro na mesma
-- transação da gravação de categorias, revisão aprovada e itens individuais.
-- Falha em qualquer etapa cancela TUDO. Requer homologação/banco compatível.
-- A função privilegiada exige sessão válida + perfil administrador na empresa.
BEGIN;

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_precificacao(
 p_empresa_id uuid,p_codigo_obra text,p_nome_obra text,p_cliente text,
 p_esquadrias jsonb,p_perfis jsonb,p_acessorios jsonb,p_operacao_id uuid,
 p_decisoes jsonb,p_orcamento jsonb,p_precificacao jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $func$
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
 IF p_precificacao->>'versao'<>'1' THEN
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
     (v_item->>'indice_importacao')::integer<>v_idx OR
     v_item->>'codigo' IS DISTINCT FROM v_origem->>'codigo' OR
     v_item->>'descricao' IS DISTINCT FROM v_origem->>'descricao' OR
     (v_item->>'largura_mm')::numeric<>(v_origem->>'largura_mm')::numeric OR
     (v_item->>'altura_mm')::numeric<>(v_origem->>'altura_mm')::numeric OR
     (v_item->>'quantidade')::integer<>(v_origem->>'quantidade')::integer OR
     NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') c
          WHERE c->>'id_local'=v_item->>'categoria_id_local')
  THEN RAISE EXCEPTION 'Item % diverge do CEM ou da categoria selecionada.',v_idx+1; END IF;
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
  (SELECT round(sum((item->>'area_m2')::numeric),6)
   FROM jsonb_array_elements(p_precificacao->'itens')),
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
  SELECT c->>'nome' INTO v_categoria_nome FROM jsonb_array_elements(p_precificacao->'categorias') c
    WHERE c->>'id_local'=v_item->>'categoria_id_local';
  INSERT INTO public.ew_precificacao_revisoes_itens(
   empresa_id,obra_id,revisao_id,indice_importacao,
   esquadria_id,tipologia_id,categoria_id,categoria_nome_snapshot,
   codigo_snapshot,descricao_snapshot,linha_snapshot,
   largura_mm,altura_mm,quantidade,area_m2,
   fabricacao_centavos,instalacao_centavos)
  VALUES(
   p_empresa_id,v_obra_id,v_revisao_id,v_idx,
   v_esquadria_id,NULL,v_categoria_uuid,upper(btrim(v_categoria_nome)),
   v_item->>'codigo',coalesce(v_item->>'descricao',''),NULL,
   (v_item->>'largura_mm')::numeric,(v_item->>'altura_mm')::numeric,
   (v_item->>'quantidade')::integer,round((v_item->>'area_m2')::numeric,6),
   (v_item->>'fabricacao_centavos')::bigint,(v_item->>'instalacao_centavos')::bigint
  );
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
$func$;

REVOKE ALL ON FUNCTION public.ew_importar_obra_cem_precificacao(
 uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_importar_obra_cem_precificacao(
 uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb,jsonb,jsonb) TO authenticated;
COMMIT;
