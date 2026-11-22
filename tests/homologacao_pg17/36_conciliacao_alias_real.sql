-- Conciliação real de código CEM alternativo para perfil existente.
-- Simula apenas materiais e identificadores ficticios em Postgres descartavel.
\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $alias$
DECLARE p jsonb; q jsonb;r jsonb;perfil uuid;obra uuid;obranova uuid;msg text;
 antes_obra integer;antes_alias integer;
BEGIN
 SELECT payload INTO STRICT p FROM public._homolog_payload_real;
 SELECT id INTO STRICT perfil FROM public.ew_perfis WHERE codigo='CG1016' AND fabricante='HYDRO';
 p:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-CEM-ALIAS'::text));
 p:=jsonb_set(p,'{nome_obra}',to_jsonb('OBRA FICTICIA COM ALIAS'::text));
 p:=jsonb_set(p,'{operacao_id}',to_jsonb('f6f6f6f6-f6f6-46f6-86f6-f6f6f6f6f6f6'::text));
 p:=jsonb_set(p,'{perfis}',
 '[{"codigo":"CG179","fabricante":"HYDRO","descricao":"PERFIL ESTRUTURAL FICTICIO",
   "variacoes":[{"acabamento":"PINTURA","cor":"BRANCO","codigo_cor":"BR",
    "linhas_calculo":1,"quantidade_prevista":4,"unidade_prevista":"BARRA",
    "barras_planejadas":[{"comprimento_mm":6000,"quantidade":4}]}]}]'::jsonb);
 p:=jsonb_set(p,'{decisoes}',
  jsonb_build_array(jsonb_build_object(
   'tipo','perfil','codigo_cem','CG179','fabricante','HYDRO',
   'material_id',perfil,'usar_codigo_cem',false)));
 r:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 obra:=(r->>'obra_id')::uuid;
 IF r->>'precificacao_gravada'<>'true' OR
    (r->>'perfis_existentes')::integer<>1 OR
    (r->>'perfis_novos')::integer<>0 OR
    (SELECT count(*) FROM public.ew_perfis)<>1 OR
    (SELECT count(*) FROM public.ew_perfis WHERE id=perfil AND codigo='CG1016')<>1 OR
    (SELECT count(*) FROM public.ew_materiais_alias WHERE perfil_id=perfil
       AND fabricante='HYDRO' AND codigo_alternativo='CG179')<>1 OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais
       WHERE obra_id=obra AND tipo='perfil' AND perfil_id=perfil
       AND quantidade_prevista=4)<>1
 THEN RAISE EXCEPTION 'Conciliação real não preservou o perfil principal e alias: %',r;END IF;

 -- Nova obra agora reconhece o mesmo alias diretamente, sem decisão manual.
 q:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-REUSO-ALIAS'::text));
 q:=jsonb_set(q,'{nome_obra}',to_jsonb('OBRA FICTICIA REUSANDO ALIAS'::text));
 q:=jsonb_set(q,'{operacao_id}',to_jsonb('f7f7f7f7-f7f7-47f7-87f7-f7f7f7f7f7f7'::text));
 q:=jsonb_set(q,'{decisoes}','[]'::jsonb);
 r:=public.ew_importar_obra_cem_precificacao(
  (q->>'empresa_id')::uuid,q->>'codigo_obra',q->>'nome_obra',q->>'cliente',
  q->'esquadrias',q->'perfis',q->'acessorios',(q->>'operacao_id')::uuid,
  q->'decisoes',q->'orcamento',q->'precificacao');
 obranova:=(r->>'obra_id')::uuid;
 IF r->>'precificacao_gravada'<>'true' OR
    (r->>'perfis_existentes')::integer<>1 OR
    (r->>'variacoes_novas')::integer<>0 OR
    (SELECT count(*) FROM public.ew_perfis)<>1 OR
    (SELECT count(*) FROM public.ew_materiais_alias WHERE perfil_id=perfil)<>1 OR
    (SELECT count(*) FROM public.ew_cem_obras_materiais
     WHERE obra_id=obranova AND perfil_id=perfil AND quantidade_prevista=4)<>1
 THEN RAISE EXCEPTION 'Reutilização posterior de alias real falhou: %',r;END IF;

 -- Escolha manual divergente do CEM não pode criar obra parcial.
 SELECT count(*) INTO antes_obra FROM public.obras;
 SELECT count(*) INTO antes_alias FROM public.ew_materiais_alias;
 q:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-ALIAS-ERRADO'::text));
 q:=jsonb_set(q,'{nome_obra}',to_jsonb('OBRA FICTICIA COM DECISAO INVALIDA'::text));
 q:=jsonb_set(q,'{operacao_id}',to_jsonb('f8f8f8f8-f8f8-48f8-88f8-f8f8f8f8f8f8'::text));
 q:=jsonb_set(q,'{decisoes,0,codigo_cem}',to_jsonb('CODIGO-NAO-PRESENTE'::text));
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (q->>'empresa_id')::uuid,q->>'codigo_obra',q->>'nome_obra',q->>'cliente',
   q->'esquadrias',q->'perfis',q->'acessorios',(q->>'operacao_id')::uuid,
   q->'decisoes',q->'orcamento',q->'precificacao');
  RAISE EXCEPTION 'ERRO DO TESTE: aceitou decisao sem material CEM';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%não corresponde ao arquivo CEM%' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>antes_obra OR
    (SELECT count(*) FROM public.ew_materiais_alias)<>antes_alias OR
    EXISTS (SELECT 1 FROM public.obras WHERE codigo='HOMOLOG-ALIAS-ERRADO')
 THEN RAISE EXCEPTION 'Conciliação inválida deixou obra/alias parcial';END IF;
 RAISE NOTICE 'OK: vinculo real entre CG179 e CG1016, reuso do alias e rejeicao de decisao incorreta';
END $alias$;
RESET ROLE;
SELECT 'CONCILIACAO DE CODIGOS CEM REAL: APROVADA' AS status;
