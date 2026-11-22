-- Testes complementares v46.9: códigos CEM repetidos, rollback tardio
-- e isolamento entre empresas. Apenas PostgreSQL descartável (CI).
\set ON_ERROR_STOP on
BEGIN;
-- Usuário fictício administrador de outra empresa, somente nesta transação.
INSERT INTO auth.users(id) VALUES ('33333333-3333-4333-8333-333333333333');
INSERT INTO public.usuarios_empresas(empresa_id,usuario_id,perfil)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        '33333333-3333-4333-8333-333333333333','administrador');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $testes$
DECLARE
 p jsonb; d jsonb; tentativa jsonb; retorno jsonb; obra uuid; rev uuid;
 antes_obras integer; antes_revisoes integer; antes_itens integer;
 msg text;
BEGIN
 SELECT payload INTO STRICT p FROM public._homolog_payload;

 -- Mesmo código EA01 em posições diferentes do arquivo, mas IDs distintos.
 d:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-EA-REPETIDA'::text));
 d:=jsonb_set(d,'{operacao_id}',to_jsonb('abababab-abab-4bab-8bab-abababababab'::text));
 d:=jsonb_set(d,'{esquadrias,1,codigo}',to_jsonb('EA01'::text));
 d:=jsonb_set(d,'{precificacao,itens,1,codigo}',to_jsonb('EA01'::text));
 retorno:=public.ew_importar_obra_cem_precificacao(
  (d->>'empresa_id')::uuid,d->>'codigo_obra',d->>'nome_obra',d->>'cliente',
  d->'esquadrias',d->'perfis',d->'acessorios',(d->>'operacao_id')::uuid,
  d->'decisoes',d->'orcamento',d->'precificacao');
 obra:=(retorno->>'obra_id')::uuid;
 SELECT id INTO rev FROM public.ew_precificacao_revisoes
 WHERE obra_id=obra AND empresa_id=(d->>'empresa_id')::uuid;
 IF retorno->>'precificacao_gravada'<>'true' OR rev IS NULL
    OR (SELECT count(*) FROM public.esquadrias WHERE obra_id=obra AND codigo='EA01')<>2
    OR (SELECT count(DISTINCT esquadria_id)
        FROM public.ew_precificacao_revisoes_itens WHERE revisao_id=rev)<>2
    OR (SELECT count(*) FROM public.ew_precificacao_revisoes_itens
        WHERE revisao_id=rev AND indice_importacao IN(0,1)
        AND codigo_snapshot='EA01' AND fabricacao_centavos=300000
        AND instalacao_centavos=200000)<>2
 THEN RAISE EXCEPTION 'Código CEM duplicado vinculou incorretamente os UUIDs/preços';END IF;

 -- Erro APÓS criar obra e parte da revisão deve reverter a transação inteira.
 -- As duas esquadrias solicitam padrão de categorias diferentes para mesma tipologia.
 SELECT count(*) INTO antes_obras FROM public.obras;
 SELECT count(*) INTO antes_revisoes FROM public.ew_precificacao_revisoes;
 SELECT count(*) INTO antes_itens FROM public.ew_precificacao_revisoes_itens;
 tentativa:=jsonb_set(p,'{codigo_obra}',to_jsonb('HOMOLOG-ROLLBACK-TARDIO'::text));
 tentativa:=jsonb_set(tentativa,'{operacao_id}',
   to_jsonb('bcbcbcbc-bcbc-4cbc-8cbc-bcbcbcbcbcbc'::text));
 tentativa:=jsonb_set(tentativa,'{esquadrias,1,referencia_tipologia}',
   to_jsonb('GOLD-JCR101'::text));
 tentativa:=jsonb_set(tentativa,'{precificacao,itens,1,referencia_tipologia}',
   to_jsonb('GOLD-JCR101'::text));
 tentativa:=jsonb_set(tentativa,'{precificacao,itens,1,definir_padrao_tipologia}',
   'true'::jsonb);
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (tentativa->>'empresa_id')::uuid,tentativa->>'codigo_obra',
   tentativa->>'nome_obra',tentativa->>'cliente',tentativa->'esquadrias',
   tentativa->'perfis',tentativa->'acessorios',(tentativa->>'operacao_id')::uuid,
   tentativa->'decisoes',tentativa->'orcamento',tentativa->'precificacao');
  RAISE EXCEPTION 'ERRO TESTE: foi aceito padrão conflitante';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%mesma tipologia%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.obras)<>antes_obras OR
    (SELECT count(*) FROM public.ew_precificacao_revisoes)<>antes_revisoes OR
    (SELECT count(*) FROM public.ew_precificacao_revisoes_itens)<>antes_itens OR
    EXISTS(SELECT 1 FROM public.obras WHERE codigo='HOMOLOG-ROLLBACK-TARDIO')
 THEN RAISE EXCEPTION 'Falha tardia deixou obra, revisão ou item órfão';END IF;
 RAISE NOTICE 'OK: EA repetido por UUID, centavos e rollback transacional tardio';
END $testes$;

-- ADM da empresa B não deve ler histórico nem importar/precificar pela empresa A.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $isolar$
DECLARE p jsonb;msg text;
BEGIN
 IF (SELECT count(*) FROM public.ew_precificacao_revisoes)<>0 OR
    (SELECT count(*) FROM public.ew_precificacao_revisoes_itens)<>0 OR
    (SELECT count(*) FROM public.ew_precificacao_categorias)<>0
 THEN RAISE EXCEPTION 'RLS vazou dados da empresa A para ADM da B';END IF;
 SELECT payload INTO p FROM public._homolog_payload;
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (p->>'empresa_id')::uuid,'HOMOLOG-ATAQUE-OUTRA-EMPRESA',
   p->>'nome_obra',p->>'cliente',p->'esquadrias',
   p->'perfis',p->'acessorios','cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd'::uuid,
   p->'decisoes',p->'orcamento',p->'precificacao');
  RAISE EXCEPTION 'ERRO TESTE: administrador da B importou para A';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%Somente ADM%' THEN RAISE;END IF;
 END;
 RAISE NOTICE 'OK: segregação de empresas no RLS e autorização de escrita';
END $isolar$;

-- Sem sessão autenticada, o mesmo endpoint não deve gravar dados.
SELECT set_config('request.jwt.claim.sub','',false);
DO $anonimo$
DECLARE p jsonb;msg text;
BEGIN
 SELECT payload INTO p FROM public._homolog_payload;
 BEGIN
  PERFORM public.ew_importar_obra_cem_precificacao(
   (p->>'empresa_id')::uuid,'HOMOLOG-SEM-SESSAO',
   p->>'nome_obra',p->>'cliente',p->'esquadrias',
   p->'perfis',p->'acessorios','dededede-dede-4ede-8ede-dededededede'::uuid,
   p->'decisoes',p->'orcamento',p->'precificacao');
  RAISE EXCEPTION 'ERRO TESTE: importação sem sessão foi permitida';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%Sessão obrigatória%' THEN RAISE;END IF;
 END;
 RAISE NOTICE 'OK: operação sem sessão rejeitada';
END $anonimo$;
RESET ROLE;
ROLLBACK;
SELECT 'CASOS CRITICOS: CODIGO REPETIDO, ATOMICIDADE E ISOLAMENTO' AS status;
