-- Testar o importador legado REAL de perfis e acessorios no CEM.
-- Dados inteiramente ficticios. Nao ha estoque fisico neste banco descartavel.
\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $materiais$
DECLARE
 p jsonb; d jsonb; resposta jsonb; obra uuid; obra2 uuid;falha text;
 antes_obras integer;antes_perfis integer;antes_acess integer;
 antes_vars integer;antes_links integer;antes_importacoes integer;
BEGIN
 SELECT payload INTO STRICT p FROM public._homolog_payload_real;
 p:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-MATERIAIS-REAL'::text));
 p:=jsonb_set(p,'{nome_obra}',to_jsonb('OBRA FICTICIA COM MATERIAIS'::text));
 p:=jsonb_set(p,'{operacao_id}',to_jsonb('f3f3f3f3-f3f3-43f3-83f3-f3f3f3f3f3f3'::text));
 p:=jsonb_set(p,'{perfis}',
 '[{"codigo":"CG1016","fabricante":"HYDRO","descricao":"PERFIL ESTRUTURAL FICTICIO","linha":"GOLD SLIM","peso_kg_m":0.985,
    "variacoes":[{"acabamento":"PINTURA","cor":"BRANCO","codigo_cor":"BR",
      "linhas_calculo":2,"quantidade_prevista":5,"unidade_prevista":"BARRA",
      "comprimento_total_m":30,
      "barras_planejadas":[{"comprimento_mm":6000,"quantidade":2},{"comprimento_mm":6500,"quantidade":3}]}]}]'::jsonb);
 p:=jsonb_set(p,'{acessorios}',
 '[{"codigo":"AC001","fabricante":"HYDRO","descricao":"FECHO FICTICIO","unidade":"PC",
   "variacoes":[{"acabamento":"NATURAL","cor":"PRETO","codigo_cor":"PT",
    "linhas_calculo":1,"quantidade_prevista":10,"unidade_prevista":"PC"}]}]'::jsonb);
 resposta:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 obra:=(resposta->>'obra_id')::uuid;
 IF resposta->>'obra_criada'<>'true' OR resposta->>'precificacao_gravada'<>'true'
   OR resposta->>'estoque_fisico_alterado'<>'false' OR
   (resposta->>'perfis_novos')::integer<>1 OR
   (resposta->>'acessorios_novos')::integer<>1 OR
   (resposta->>'variacoes_novas')::integer<>2 OR
   (resposta->>'vinculos_por_obra')::integer<>2
 THEN RAISE EXCEPTION 'Importador de materiais real retornou contadores incorretos: %',resposta;END IF;
 IF obra IS NULL OR
    (SELECT count(*) FROM public.ew_perfis WHERE empresa_id=(p->>'empresa_id')::uuid AND codigo='CG1016')<>1 OR
    (SELECT count(*) FROM public.ew_acessorios WHERE empresa_id=(p->>'empresa_id')::uuid AND codigo='AC001')<>1 OR
    (SELECT count(*) FROM public.ew_materiais_variacoes)<>2 OR
    (SELECT count(*) FROM public.ew_cem_importacoes_materiais WHERE obra_id=obra)<>1 OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais WHERE obra_id=obra)<>2
 THEN RAISE EXCEPTION 'Perfis/acessorios/variacoes/vinculos nao persistiram corretamente';END IF;
 IF (SELECT count(*) FROM public.ew_cem_obras_materiais
       WHERE obra_id=obra AND tipo='perfil' AND quantidade_prevista=5
       AND unidade_prevista='BARRA' AND linhas_calculo=2
       AND jsonb_array_length(barras_planejadas)=2
       AND (barras_planejadas->0->>'comprimento_mm')::integer=6000
       AND (barras_planejadas->0->>'quantidade')::integer=2
       AND (barras_planejadas->1->>'comprimento_mm')::integer=6500
       AND (barras_planejadas->1->>'quantidade')::integer=3)<>1 OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais
       WHERE obra_id=obra AND tipo='acessorio' AND quantidade_prevista=10
       AND unidade_prevista='PC')<>1
 THEN RAISE EXCEPTION 'Planejamento de BARRAS/ACESSORIOS real divergente do CEM'; END IF;
 IF (SELECT count(*) FROM public.ew_estoque_movimentos_sentinela)<>0
 THEN RAISE EXCEPTION 'Sentinela de estoque fisico inesperadamente preenchida'; END IF;

 -- Reenvio com a mesma operação deve devolver a obra sem duplicar quantidades.
 resposta:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 IF resposta->>'ja_importado'<>'true' OR resposta->>'obra_id'<>obra::text
  OR (SELECT count(*) FROM public.ew_cem_importacoes_materiais WHERE obra_id=obra)<>1
 THEN RAISE EXCEPTION 'Retry duplicou obra ou importacao de materiais';END IF;

 -- Nova obra com mesmos materiais reutiliza catálogos, mas cria seu estoque previsto.
 d:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-REUTILIZACAO-REAL'::text));
 d:=jsonb_set(d,'{nome_obra}',to_jsonb('OBRA FICTICIA COM MATERIAIS EXISTENTES'::text));
 d:=jsonb_set(d,'{operacao_id}',to_jsonb('f4f4f4f4-f4f4-44f4-84f4-f4f4f4f4f4f4'::text));
 resposta:=public.ew_importar_obra_cem_precificacao(
  (d->>'empresa_id')::uuid,d->>'codigo_obra',d->>'nome_obra',d->>'cliente',
  d->'esquadrias',d->'perfis',d->'acessorios',(d->>'operacao_id')::uuid,
  d->'decisoes',d->'orcamento',d->'precificacao');
 obra2:=(resposta->>'obra_id')::uuid;
 IF resposta->>'precificacao_gravada'<>'true' OR
    (resposta->>'perfis_existentes')::integer<>1 OR
    (resposta->>'acessorios_existentes')::integer<>1 OR
    (resposta->>'variacoes_novas')::integer<>0 OR
    (resposta->>'vinculos_por_obra')::integer<>2 OR
    (SELECT count(*) FROM public.ew_perfis)<>1 OR
    (SELECT count(*) FROM public.ew_acessorios)<>1 OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais WHERE obra_id=obra2)<>2
 THEN RAISE EXCEPTION 'Reutilizacao de cadastros reais falhou: %',resposta; END IF;

 -- Plano de barras adulterado: erro DEPOIS de iniciar transacao de obra;
 -- deve desfazer TODAS as insercoes da tentativa.
 SELECT count(*) INTO antes_obras FROM public.obras;
 SELECT count(*) INTO antes_perfis FROM public.ew_perfis;
 SELECT count(*) INTO antes_acess FROM public.ew_acessorios;
 SELECT count(*) INTO antes_vars FROM public.ew_materiais_variacoes;
 SELECT count(*) INTO antes_links FROM public.ew_cem_obras_materiais;
 SELECT count(*) INTO antes_importacoes FROM public.ew_cem_importacoes_materiais;
 d:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-BARRAS-INVALIDAS'::text));
 d:=jsonb_set(d,'{nome_obra}',to_jsonb('OBRA FICTICIA COM PLANO INVALIDO'::text));
 d:=jsonb_set(d,'{operacao_id}',to_jsonb('f5f5f5f5-f5f5-45f5-85f5-f5f5f5f5f5f5'::text));
 d:=jsonb_set(d,'{perfis,0,variacoes,0,barras_planejadas,1,comprimento_mm}','6000'::jsonb);
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (d->>'empresa_id')::uuid,d->>'codigo_obra',d->>'nome_obra',d->>'cliente',
   d->'esquadrias',d->'perfis',d->'acessorios',(d->>'operacao_id')::uuid,
   d->'decisoes',d->'orcamento',d->'precificacao');
  RAISE EXCEPTION 'ERRO DO TESTE: barras duplicadas aceitas';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS falha=MESSAGE_TEXT;
  IF falha NOT LIKE '%Comprimento duplicado no plano%' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>antes_obras OR
    (SELECT count(*) FROM public.ew_perfis)<>antes_perfis OR
    (SELECT count(*) FROM public.ew_acessorios)<>antes_acess OR
    (SELECT count(*) FROM public.ew_materiais_variacoes)<>antes_vars OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais)<>antes_links OR
    (SELECT count(*) FROM public.ew_cem_importacoes_materiais)<>antes_importacoes OR
    EXISTS(SELECT 1 FROM public.obras WHERE codigo='HOMOLOG-BARRAS-INVALIDAS')
 THEN RAISE EXCEPTION 'Falha de material deixou dados parciais';END IF;
 RAISE NOTICE 'OK: importacao real de perfis, barras previstas, acessorios, reuso sem duplicar, idempotencia, rollback';
END $materiais$;
RESET ROLE;
SELECT 'MATERIAIS CEM COM IMPORTADOR REAL: APROVADO' AS status;
