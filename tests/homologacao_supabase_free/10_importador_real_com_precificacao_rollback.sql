-- EWGEST v46.9 | teste no Supabase Free (NÃO publicar nem aplicar como migração).
-- Usar com Supabase execute_sql no projeto ewgest-restauracao-teste.
-- SEMPRE BEGIN/ROLLBACK: não gera registros persistentes, nem copia dados da GVG.
-- Dependências: cinco tabelas de preços, funções CEM reais e políticas restauradas.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM public.obras)<>0 OR (SELECT count(*) FROM public.esquadrias)<>0
  OR (SELECT count(*) FROM public.ew_perfis)<>0 OR (SELECT count(*) FROM public.ew_acessorios)<>0
  OR (SELECT count(*) FROM public.ew_precificacao_revisoes)<>0
  OR (SELECT count(*) FROM public.usuarios_empresas WHERE perfil='administrador')<>1
  OR (SELECT count(*) FROM public.empresas)<>1
 THEN RAISE EXCEPTION 'Staging não está vazio/estável: recusar ensaio';END IF;
END $pre$;
SELECT set_config('request.jwt.claim.sub',(SELECT usuario_id::text FROM public.usuarios_empresas WHERE perfil='administrador' LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $full$
DECLARE
 p jsonb:=$payload${"empresa_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","codigo_obra":"STAGE-EWGEST-V469-FICTICIO","nome_obra":"OBRA FICTICIA HOMOLOGACAO V469","cliente":"CLIENTE FICTICIO SEM DADOS DA GVG","operacao_id":"feee0000-1111-4111-8111-111111111111","esquadrias":[{"codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","largura_mm":1000,"altura_mm":1000,"quantidade":1},{"codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","largura_mm":1000,"altura_mm":1000,"quantidade":1}],"perfis":[{"codigo":"CP-TEST-01","fabricante":"FABRICANTE FICTICIO","descricao":"PERFIL LABORATORIO CEM","linha":"GOLD SLIM","peso_kg_m":0.985,"variacoes":[{"acabamento":"PINTURA","cor":"BRANCO","codigo_cor":"BR","linhas_calculo":2,"quantidade_prevista":5,"unidade_prevista":"BARRA","comprimento_total_m":30,"barras_planejadas":[{"comprimento_mm":6000,"quantidade":2},{"comprimento_mm":6500,"quantidade":3}]}]}],"acessorios":[{"codigo":"AC-TEST-01","fabricante":"FABRICANTE FICTICIO","descricao":"ACESSORIO LABORATORIO CEM","unidade":"PC","variacoes":[{"acabamento":"NATURAL","cor":"PRETO","codigo_cor":"PT","linhas_calculo":1,"quantidade_prevista":10,"unidade_prevista":"PC"}]}],"decisoes":[],"orcamento":{"niveis":[{"nivel":"FABRICACAO","categoria_base":"fabricacao","valor":7000,"faturar":true,"empresa_faturamento":"FATURADORA FICTICIA"},{"nivel":"INSTALACAO","categoria_base":"instalacao","valor":3000,"faturar":true,"empresa_faturamento":"FATURADORA FICTICIA"}],"valor_total":10000},"precificacao":{"versao":1,"percentual_fabricacao_bp":6000,"percentual_ajustado":true,"fabricacao_original_centavos":700000,"instalacao_original_centavos":300000,"fabricacao_distribuida_centavos":600000,"instalacao_distribuida_centavos":400000,"categorias":[{"id_local":"esq","nome":"ESQUADRIAS","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"id_local":"gc","nome":"GUARDA-CORPO","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}],"itens":[{"indice_importacao":0,"categoria_id_local":"esq","codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","definir_padrao_tipologia":false,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"indice_importacao":1,"categoria_id_local":"gc","codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","definir_padrao_tipologia":false,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}]}}$payload$::jsonb;
 empresa uuid;obra uuid;resultado jsonb;reenvio jsonb;v_bad jsonb;err text;
BEGIN
 SELECT empresa_id INTO STRICT empresa FROM public.usuarios_empresas WHERE perfil='administrador' LIMIT 1;
 p:=jsonb_set(p,'{empresa_id}',to_jsonb(empresa::text));
 resultado:=public.ew_importar_obra_cem_precificacao(
  empresa,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 obra:=(resultado->>'obra_id')::uuid;
 IF obra IS NULL OR resultado->>'precificacao_gravada'<>'true'
  OR resultado->>'orcamento_gravado'<>'true'
  OR (resultado->>'perfis_novos')::integer<>1 OR
   (resultado->>'acessorios_novos')::integer<>1 OR
   (resultado->>'variacoes_novas')::integer<>2 OR
   (resultado->>'vinculos_por_obra')::integer<>2
  OR (SELECT count(*) FROM public.esquadrias WHERE obra_id=obra)<>2
  OR (SELECT count(*) FROM public.ew_estoques_locais WHERE obra_id=obra)<>1
  OR (SELECT count(*) FROM public.ew_cem_obras_materiais WHERE obra_id=obra)<>2
  OR (SELECT count(*) FROM public.ew_cem_importacoes_materiais WHERE obra_id=obra)<>1
  OR (SELECT count(*) FROM public.ew_obra_orcamento_niveis WHERE obra_id=obra)<>2
  OR (SELECT count(*) FROM public.ew_precificacao_revisoes_itens WHERE obra_id=obra)<>2
  OR (SELECT sum(fabricacao_centavos) FROM public.ew_precificacao_revisoes_itens WHERE obra_id=obra)<>600000
  OR (SELECT sum(instalacao_centavos) FROM public.ew_precificacao_revisoes_itens WHERE obra_id=obra)<>400000
 THEN RAISE EXCEPTION 'CEM + 60/40 + estoque previsto inconciliáveis: %',resultado;END IF;
 IF (SELECT count(*) FROM public.ew_cem_obras_materiais WHERE obra_id=obra
    AND tipo='perfil' AND quantidade_prevista=5 AND jsonb_array_length(barras_planejadas)=2)<>1
 THEN RAISE EXCEPTION 'Plano de barras foi perdido';END IF;
 reenvio:=public.ew_importar_obra_cem_precificacao(
  empresa,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 IF reenvio->>'ja_importado'<>'true' OR reenvio->>'obra_id'<>resultado->>'obra_id' OR
 (SELECT count(*) FROM public.ew_precificacao_revisoes)<>1
 THEN RAISE EXCEPTION 'Operação repetida criou duplicidade.';END IF;
 v_bad:=jsonb_set(p,'{operacao_id}',to_jsonb('ffff0000-1111-4111-8111-111111111111'::text));
 v_bad:=jsonb_set(v_bad,'{codigo_obra}',to_jsonb('STAGE-PRECO-ADULTERADO'::text));
 v_bad:=jsonb_set(v_bad,'{nome_obra}',to_jsonb('OBRA FICTICIA PRECO ADULTERADO'::text));
 v_bad:=jsonb_set(v_bad,'{precificacao,itens,0,fabricacao_centavos}','300001'::jsonb);
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   empresa,v_bad->>'codigo_obra',v_bad->>'nome_obra',v_bad->>'cliente',
   v_bad->'esquadrias',v_bad->'perfis',v_bad->'acessorios',(v_bad->>'operacao_id')::uuid,
   v_bad->'decisoes',v_bad->'orcamento',v_bad->'precificacao');
  RAISE EXCEPTION 'ERRO DO TESTE: preço adulterado aceito';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%rateio aprovado%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>1 OR
 (SELECT count(*) FROM public.ew_precificacao_revisoes)<>1
 THEN RAISE EXCEPTION 'Preço adulterado deixou registros órfãos';END IF;
 RAISE NOTICE 'OK: integração CEM real, estoque previsto, revisão, centavos e retry.';
END $full$;
RESET ROLE;
UPDATE public.usuarios_empresas SET perfil='almoxarife' WHERE perfil='administrador';
SET LOCAL ROLE authenticated;
DO $deny$
DECLARE empresa uuid;err text;
BEGIN
 SELECT empresa_id INTO STRICT empresa FROM public.usuarios_empresas LIMIT 1;
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(empresa,
    'STAGE-SEM-PERMISSAO','OBRA FICTICIA SEM PERMISSAO','CLIENTE FICTICIO',
    '[]'::jsonb,'[]'::jsonb,'[]'::jsonb,gen_random_uuid(),
    '[]'::jsonb,'{}'::jsonb,'{}'::jsonb);
  RAISE EXCEPTION 'ERRO DO TESTE: almoxarife importou';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM autenticado%' THEN RAISE;END IF;
 END;
END $deny$;
RESET ROLE;
ROLLBACK;
SELECT (SELECT count(*) FROM public.obras) obras_persistidas,
 (SELECT count(*) FROM public.esquadrias) esquadrias_persistidas,
 (SELECT count(*) FROM public.ew_perfis) perfis_persistidos,
 (SELECT count(*) FROM public.ew_acessorios) acessorios_persistidos,
 (SELECT count(*) FROM public.ew_precificacao_revisoes) revisoes_persistidas,
 (SELECT count(*) FROM public.usuarios_empresas WHERE perfil='administrador') administradores_preservados;
