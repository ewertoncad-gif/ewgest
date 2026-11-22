-- Testes transacionais no banco descartável do GitHub Actions.
-- Não reproduz o importador legado completo: chama a RPC nova com stub explícito.
\set ON_ERROR_STOP on
CREATE TABLE public._homolog_payload (payload jsonb NOT NULL);
INSERT INTO public._homolog_payload VALUES ('{"empresa_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","codigo_obra":"HOMOLOG-V469-001","nome_obra":"OBRA FICTICIA 01","cliente":"CLIENTE DE HOMOLOGACAO","operacao_id":"33333333-3333-4333-8333-333333333333","esquadrias":[{"codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","largura_mm":1000,"altura_mm":1000,"quantidade":1},{"codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","largura_mm":1000,"altura_mm":1000,"quantidade":1}],"perfis":[],"acessorios":[],"decisoes":[],"orcamento":{"niveis":[{"nivel":"FABRICACAO","categoria_base":"fabricacao","valor":7000,"faturar":true},{"nivel":"INSTALACAO","categoria_base":"instalacao","valor":3000,"faturar":true}]},"precificacao":{"versao":1,"percentual_fabricacao_bp":6000,"percentual_ajustado":true,"fabricacao_original_centavos":700000,"instalacao_original_centavos":300000,"fabricacao_distribuida_centavos":600000,"instalacao_distribuida_centavos":400000,"categorias":[{"id_local":"esq","nome":"ESQUADRIAS","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"id_local":"gc","nome":"GUARDA-CORPO","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}],"itens":[{"indice_importacao":0,"categoria_id_local":"esq","codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","definir_padrao_tipologia":true,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"indice_importacao":1,"categoria_id_local":"gc","codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","definir_padrao_tipologia":false,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}]}}'::jsonb);
GRANT SELECT ON public._homolog_payload TO authenticated;
DO $assert$
BEGIN
 IF has_function_privilege('anon',
 'public.ew_importar_obra_cem_precificacao(uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb,jsonb,jsonb)',
 'EXECUTE')
 THEN RAISE EXCEPTION 'Falha de segurança: anon recebeu EXECUTE na importação'; END IF;
END $assert$;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $cases$
DECLARE
 p jsonb;v1 jsonb;v2 jsonb;
 changed jsonb;other jsonb;
 before_count integer;after_count integer;
 cnt integer;err text;tentativas integer:=0;
BEGIN
 SELECT payload INTO p FROM public._homolog_payload;
 v1:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 IF v1->>'precificacao_gravada'<>'true' OR
    (v1->>'esquadrias_novas')::integer<>2 OR
    (SELECT count(*) FROM public.ew_precificacao_revisoes)<>1 OR
    (SELECT count(*) FROM public.ew_precificacao_revisoes_itens)<>2
 THEN RAISE EXCEPTION 'Falhou importação atômica %',v1;END IF;

 -- Conferir distribuição 70/30 contratual => 60/40 aprovado.
 IF (SELECT fabricacao_original_centavos FROM public.ew_precificacao_revisoes)<>700000 OR
    (SELECT instalacao_original_centavos FROM public.ew_precificacao_revisoes)<>300000 OR
    (SELECT fabricacao_distribuida_centavos FROM public.ew_precificacao_revisoes)<>600000 OR
    (SELECT instalacao_distribuida_centavos FROM public.ew_precificacao_revisoes)<>400000 OR
    (SELECT sum(fabricacao_centavos) FROM public.ew_precificacao_revisoes_itens)<>600000 OR
    (SELECT sum(instalacao_centavos) FROM public.ew_precificacao_revisoes_itens)<>400000
 THEN RAISE EXCEPTION 'Os valores não fecharam em centavos';END IF;
 IF (SELECT count(*) FROM public.ew_precificacao_revisoes_itens i
     JOIN public.esquadrias e ON e.id=i.esquadria_id AND e.obra_id=i.obra_id
     WHERE i.codigo_snapshot=e.codigo AND i.indice_importacao IN(0,1))<>2
 THEN RAISE EXCEPTION 'Esquadrias não vinculadas pelos UUIDs'; END IF;
 IF (SELECT count(*) FROM public.ew_precificacao_tipologias_padrao)<>1
 THEN RAISE EXCEPTION 'Padrão de tipologia deveria ser opt-in'; END IF;
 IF (SELECT count(*) FROM public.ew_precificacao_revisoes_itens
     WHERE referencia_tipologia_snapshot IN('GOLD-JCR101','GC100')
       AND tipologia_id IS NOT NULL)<>2
 THEN RAISE EXCEPTION 'Não preservou a tipologia'; END IF;

 -- Retry identico: nenhum registro novo.
 v2:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 IF v2->>'ja_importado'<>'true' OR v2->>'obra_id'<>v1->>'obra_id' OR
  (SELECT count(*) FROM public.obras)<>1 OR
  (SELECT count(*) FROM public.ew_precificacao_revisoes)<>1
 THEN RAISE EXCEPTION 'Retry gerou duplicidade';END IF;

 -- Mesma operação com payload diferente não pode reutilizar a revisão.
 changed:=jsonb_set(p,'{precificacao,percentual_fabricacao_bp}','5000'::jsonb);
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (changed->>'empresa_id')::uuid,changed->>'codigo_obra',
   changed->>'nome_obra',changed->>'cliente',changed->'esquadrias',
   changed->'perfis',changed->'acessorios',(changed->>'operacao_id')::uuid,
   changed->'decisoes',changed->'orcamento',changed->'precificacao');
  RAISE EXCEPTION 'Falhou: aceitou operação repetida com outro payload';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%outros dados%' THEN RAISE;END IF;
 END;

 -- Novo documento adulterando um centavo: sem gravar obra parcial.
 changed:=jsonb_set(p,'{operacao_id}',
   to_jsonb('44444444-4444-4444-8444-444444444444'::text));
 changed:=jsonb_set(changed,'{codigo_obra}',to_jsonb('HOMOLOG-NEG-01'::text));
 changed:=jsonb_set(changed,'{precificacao,itens,0,fabricacao_centavos}','300001'::jsonb);
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (changed->>'empresa_id')::uuid,changed->>'codigo_obra',
   changed->>'nome_obra',changed->>'cliente',changed->'esquadrias',
   changed->'perfis',changed->'acessorios',(changed->>'operacao_id')::uuid,
   changed->'decisoes',changed->'orcamento',changed->'precificacao');
  RAISE EXCEPTION 'Falhou: aceitou preço adulterado';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%rateio aprovado%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>1
 THEN RAISE EXCEPTION 'Falha parcial deixou obra adicional';END IF;

 RAISE NOTICE 'OK: importação aprovada, 70/30 => 60/40, IDs, categoria opt-in, retry e adulteração barrada';
END $cases$;
-- Almoxarife não pode ler preços nem aprovar obra.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $almox$
DECLARE p jsonb;err text;
BEGIN
 IF (SELECT count(*) FROM public.ew_precificacao_revisoes)<>0
 THEN RAISE EXCEPTION 'Almoxarife enxerga precificação privada';END IF;
 SELECT payload INTO p FROM public._homolog_payload;
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
   p->'esquadrias',p->'perfis',p->'acessorios',
   '55555555-5555-4555-8555-555555555555'::uuid,
   p->'decisoes',p->'orcamento',p->'precificacao');
  RAISE EXCEPTION 'Falhou: almoxarife aprovou preços';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Somente ADM%' THEN RAISE;END IF;
 END;
END $almox$;
RESET ROLE;
-- Testar atualização/destruição de revisão aprovada: proibidas pelo trigger.
DO $immut$
DECLARE err text;
BEGIN
 BEGIN
  UPDATE public.ew_precificacao_revisoes
  SET fabricacao_distribuida_centavos=0;
  RAISE EXCEPTION 'Falhou: histórico pôde ser editado';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%imutável%' THEN RAISE;END IF;
 END;
 BEGIN
  DELETE FROM public.ew_precificacao_revisoes_itens;
  RAISE EXCEPTION 'Falhou: preço histórico pôde ser apagado';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%imutável%' THEN RAISE;END IF;
 END;
 RAISE NOTICE 'OK: RLS de leitura, ADM, imutabilidade e preço histórico';
END $immut$;
SELECT 'HOMOLOGAÇÃO DE BANCO DESCARTÁVEL APROVADA' AS status;
