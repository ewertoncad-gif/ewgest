-- Homologação com CRIACAO DE OBRA e FINANCEIRO LEGADOS REAIS.
-- Cada execucao usa um Postgres 17 descartavel, sem credenciais Supabase.
-- Ainda NAO exercita importacao de materiais nao vazios (coberta em fase seguinte).
\set ON_ERROR_STOP on
CREATE TABLE public._homolog_payload_real (payload jsonb NOT NULL);
INSERT INTO public._homolog_payload_real VALUES ('{"empresa_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","codigo_obra":"HOMOLOG-V469-001","nome_obra":"OBRA FICTICIA 01","cliente":"CLIENTE DE HOMOLOGACAO","operacao_id":"33333333-3333-4333-8333-333333333333","esquadrias":[{"codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","largura_mm":1000,"altura_mm":1000,"quantidade":1,"localizacao":"COZINHA"},{"codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","largura_mm":1000,"altura_mm":1000,"quantidade":1,"quantidade_modulos":2}],"perfis":[],"acessorios":[],"decisoes":[],"orcamento":{"niveis":[{"nivel":"FABRICACAO","categoria_base":"fabricacao","valor":7000,"faturar":true,"empresa_faturamento":"EMPRESA FICTICIA A"},{"nivel":"INSTALACAO","categoria_base":"instalacao","valor":3000,"faturar":true,"empresa_faturamento":"EMPRESA FICTICIA A"}],"valor_total":10000},"precificacao":{"versao":1,"percentual_fabricacao_bp":6000,"percentual_ajustado":true,"fabricacao_original_centavos":700000,"instalacao_original_centavos":300000,"fabricacao_distribuida_centavos":600000,"instalacao_distribuida_centavos":400000,"categorias":[{"id_local":"esq","nome":"ESQUADRIAS","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"id_local":"gc","nome":"GUARDA-CORPO","preco_base_m2_centavos":10000,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}],"itens":[{"indice_importacao":0,"categoria_id_local":"esq","codigo":"EA01","descricao":"JANELA CORRER","referencia_tipologia":"GOLD-JCR101","definir_padrao_tipologia":true,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000},{"indice_importacao":1,"categoria_id_local":"gc","codigo":"GC01","descricao":"GUARDA CORPO","referencia_tipologia":"GC100","definir_padrao_tipologia":false,"largura_mm":1000,"altura_mm":1000,"quantidade":1,"area_m2":1,"fabricacao_centavos":300000,"instalacao_centavos":200000}]}}'::jsonb);
GRANT SELECT ON public._homolog_payload_real TO authenticated;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $test$
DECLARE
 p jsonb; a jsonb; r jsonb; d jsonb; out_id uuid; revisao uuid;
 old_count integer;old_locais integer;old_esquadrias integer;old_precos integer;
 msg text;
BEGIN
 SELECT payload INTO STRICT p FROM public._homolog_payload_real;
 a:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 out_id:=(a->>'obra_id')::uuid;
 IF a->>'obra_criada'<>'true' OR a->>'precificacao_gravada'<>'true'
    OR a->>'orcamento_gravado'<>'true' OR out_id IS NULL
    OR a->>'estoque_fisico_alterado'<>'false'
    OR (a->>'esquadrias_novas')::integer<>2
 THEN RAISE EXCEPTION 'Importação real não confirmou obra/orçamento/precificação: %',a;END IF;
 IF (SELECT count(*) FROM public.obras WHERE id=out_id AND cliente='CLIENTE DE HOMOLOGACAO')<>1
    OR (SELECT count(*) FROM public.ew_estoques_locais WHERE obra_id=out_id)<>1
    OR (SELECT count(*) FROM public.esquadrias WHERE obra_id=out_id)<>2
    OR (SELECT count(*) FROM public.esquadrias WHERE obra_id=out_id
      AND qtd_liberada=0 AND qtd_fabricada=0)<>2
 THEN RAISE EXCEPTION 'Obra real, estoque local ou esquadrias inconsistentes';END IF;
 IF (SELECT count(*) FROM public.esquadrias WHERE obra_id=out_id
      AND codigo='EA01' AND localizacao='COZINHA')<>1
    OR (SELECT count(*) FROM public.esquadrias WHERE obra_id=out_id
      AND codigo='GC01' AND quantidade_modulos=2)<>1
 THEN RAISE EXCEPTION 'Os detalhes do CEM não foram persistidos';END IF;
 IF (SELECT count(*) FROM public.ew_obra_orcamento
    WHERE obra_id=out_id AND valor_total=10000 AND fabricacao=7000 AND instalacao=3000)<>1
    OR (SELECT count(*) FROM public.ew_obra_orcamento_niveis
      WHERE obra_id=out_id AND faturar IS TRUE)<>2
 THEN RAISE EXCEPTION 'Orçamento REAL e níveis não fecharam';END IF;
 SELECT id INTO revisao FROM public.ew_precificacao_revisoes WHERE obra_id=out_id;
 IF revisao IS NULL
    OR (SELECT count(*) FROM public.ew_precificacao_revisoes_itens
       WHERE revisao_id=revisao AND esquadria_id IN (
        SELECT id FROM public.esquadrias WHERE obra_id=out_id))<>2
    OR (SELECT sum(fabricacao_centavos) FROM public.ew_precificacao_revisoes_itens
       WHERE revisao_id=revisao)<>600000
    OR (SELECT sum(instalacao_centavos) FROM public.ew_precificacao_revisoes_itens
       WHERE revisao_id=revisao)<>400000
 THEN RAISE EXCEPTION 'Preços aprovados descolaram das esquadrias reais'; END IF;

 -- Mesma operacao repetida deve devolver a MESMA obra sem criar linhas.
 r:=public.ew_importar_obra_cem_precificacao(
  (p->>'empresa_id')::uuid,p->>'codigo_obra',p->>'nome_obra',p->>'cliente',
  p->'esquadrias',p->'perfis',p->'acessorios',(p->>'operacao_id')::uuid,
  p->'decisoes',p->'orcamento',p->'precificacao');
 IF r->>'ja_importado'<>'true' OR r->>'obra_id'<>out_id::text
 THEN RAISE EXCEPTION 'Retry duplicou a obra';END IF;

 -- Códigos CEM repetidos não podem colidir os IDs, posições ou preços.
 d:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-EA-IGUAL-REAL'::text));
 d:=jsonb_set(d,'{operacao_id}',to_jsonb('f1f1f1f1-f1f1-41f1-81f1-f1f1f1f1f1f1'::text));
 d:=jsonb_set(d,'{esquadrias,1,codigo}',to_jsonb('EA01'::text));
 d:=jsonb_set(d,'{precificacao,itens,1,codigo}',to_jsonb('EA01'::text));
 r:=public.ew_importar_obra_cem_precificacao(
  (d->>'empresa_id')::uuid,d->>'codigo_obra',d->>'nome_obra',d->>'cliente',
  d->'esquadrias',d->'perfis',d->'acessorios',(d->>'operacao_id')::uuid,
  d->'decisoes',d->'orcamento',d->'precificacao');
 IF r->>'precificacao_gravada'<>'true' OR
    (SELECT count(*) FROM public.esquadrias
     WHERE obra_id=(r->>'obra_id')::uuid AND codigo='EA01')<>2 OR
    (SELECT count(DISTINCT esquadria_id) FROM public.ew_precificacao_revisoes_itens
     WHERE obra_id=(r->>'obra_id')::uuid)<>2
 THEN RAISE EXCEPTION 'Código técnico repetido colidiu no importador REAL';END IF;

 -- Forcar falha DEPOIS de a obra + esquadrias serem criadas:
 -- cadastra um nivel FABRICACAO que ja existe na empresa como INSTALACAO.
 SELECT count(*) INTO old_count FROM public.obras;
 SELECT count(*) INTO old_locais FROM public.ew_estoques_locais;
 SELECT count(*) INTO old_esquadrias FROM public.esquadrias;
 SELECT count(*) INTO old_precos FROM public.ew_precificacao_revisoes;
 d:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-ERRO-REAL'::text));
 d:=jsonb_set(d,'{operacao_id}',to_jsonb('f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f2f2'::text));
 d:=jsonb_set(d,'{orcamento,niveis,0,nivel}',to_jsonb('INSTALACAO'::text));
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (d->>'empresa_id')::uuid,d->>'codigo_obra',d->>'nome_obra',d->>'cliente',
   d->'esquadrias',d->'perfis',d->'acessorios',(d->>'operacao_id')::uuid,
   d->'decisoes',d->'orcamento',d->'precificacao');
  RAISE EXCEPTION 'ERRO DO TESTE: nivel conflitante nao foi rejeitado';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%já existe com outro grupo financeiro%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>old_count
    OR (SELECT count(*) FROM public.ew_estoques_locais)<>old_locais
    OR (SELECT count(*) FROM public.esquadrias)<>old_esquadrias
    OR (SELECT count(*) FROM public.ew_precificacao_revisoes)<>old_precos
    OR EXISTS(SELECT 1 FROM public.obras WHERE codigo='HOMOLOG-ERRO-REAL')
 THEN RAISE EXCEPTION 'Erro no financeiro LEGADO deixou importacao parcial';END IF;

 RAISE NOTICE 'OK: criação REAL de obra, estoque local, esquadrias, orçamento/níveis e preços, idempotência, EA repetido e rollback tardio';
END $test$;
RESET ROLE;
SELECT 'IMPORTADOR CEM + FINANCEIRO REAIS (SEM MATERIAIS): APROVADO' AS status;
