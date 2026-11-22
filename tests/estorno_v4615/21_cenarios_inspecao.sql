-- Testar funções reais atualizadas contra o esquema fictício ampliado.
\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

-- Um original estornado em dois galpões deixa as transferências internas
-- somente como histórico conciliado. Registro de conciliação NÃO cria estoque.
DO $inspecao$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 v jsonb;r jsonb;antes integer;apos integer;op uuid:='ffff0013-0000-4000-8000-000000000013';
BEGIN
 v:=public.ew_inspecionar_reversao_obra(a);
 IF (v->>'permitido')::boolean IS DISTINCT FROM true OR
    (v->'resumo'->>'movimentos_pendentes')::int<>0 OR
    (v->'resumo'->>'transferencias_conciliadas')::int<>2 OR
    (v->'resumo'->>'saldos_nao_zerados')::int<>0
 THEN RAISE EXCEPTION 'Inspeção não reconheceu duas pernas conciliadas após estorno de entrada por parcelas: %',v;END IF;
 SELECT count(*) INTO antes FROM public.ew_estoque_obras_movimentos WHERE obra_id=a;
 r:=public.ew_estornar_estoque_obra(a,'Registrar conciliação de transferências internas',op);
 SELECT count(*) INTO apos FROM public.ew_estoque_obras_movimentos WHERE obra_id=a;
 IF antes<>apos OR (r->>'conciliados')::int<>2 OR (r->>'estornados')::int<>0
 THEN RAISE EXCEPTION 'Conciliação criou movimento físico ou perdeu histórico: %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_auditoria_operacoes
    WHERE operacao_id=op AND acao='ESTORNAR_ESTOQUE'
    AND detalhes->>'modo'='CONCILIAR_TRANSFERENCIAS_HISTORICAS')
 THEN RAISE EXCEPTION 'Conciliação não foi auditada';END IF;
 IF (public.ew_estornar_estoque_obra(a,'Registrar conciliação de transferências internas',op)->>'repetida')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Conciliação repetida não é idempotente';END IF;
END $inspecao$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $simples$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001'; v jsonb;r jsonb;op uuid:='ffff0014-0000-4000-8000-000000000014';
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 v:=public.ew_inspecionar_reversao_obra(a);
 IF (v->'resumo'->>'movimentos_pendentes')::int<>1 THEN
  RAISE EXCEPTION 'Entrada não estornada deveria aparecer como pendência: %',v;END IF;
 r:=public.ew_estornar_estoque_obra(a,'Reverter somente entradas independentes',op);
 IF (r->>'estornados')::int<>1 THEN RAISE EXCEPTION 'Estorno simples rejeitado: %',r;END IF;
 v:=public.ew_inspecionar_reversao_obra(a);
 IF (v->'resumo'->>'movimentos_pendentes')::int<>0 OR
    (v->'resumo'->>'saldos_nao_zerados')::int<>0
 THEN RAISE EXCEPTION 'Contrapartida de estorno não pode ser pendência: %',v;END IF;
END $simples$;

-- Transferência interna ativa NÃO é revertida pelo botão estornar tudo:
-- somente a operação individual ou a conciliação final pode tratá-la.
TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $transferencia$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 id uuid:='ffff0015-0000-4000-8000-000000000015';err text;
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-2,'TRANSFERENCIA','AFOGADOS',id);
 PERFORM public.test_mov(a,2,'TRANSFERENCIA','IMBIRIBEIRA',id);
 BEGIN
  PERFORM public.ew_estornar_estoque_obra(a,'Não reverter transporte histórico em lote',gen_random_uuid());
  RAISE EXCEPTION 'Não bloqueou reversão em lote de transferência ativa';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Há transferências, consumo ou saídas ainda ativos%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos)<>3
 THEN RAISE EXCEPTION 'Estorno em lote bloqueado não deve criar registros';END IF;
END $transferencia$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $consumo$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';err text;
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-1,'SAIDA_MANUAL','AFOGADOS');
 BEGIN
  PERFORM public.ew_estornar_estoque_obra(a,'Não estornar consumo em lote',gen_random_uuid());
  RAISE EXCEPTION 'Não bloqueou consumo na reversão total';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Há transferências, consumo ou saídas ainda ativos%' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos)<>2
 THEN RAISE EXCEPTION 'Tentativa bloqueada criou movimentos';END IF;
END $consumo$;

-- Romaneio ativo na obra impede a reversão de estoque mesmo em entrada simples.
TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $romaneio$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';err text;
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 INSERT INTO public.romaneios(obra_id,status) VALUES(a,'emitido');
 BEGIN
  PERFORM public.ew_estornar_estoque_obra(a,'Não estornar estoque com romaneio',gen_random_uuid());
  RAISE EXCEPTION 'Romaneio ativo não bloqueou estorno total';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Cancele romaneios, saídas e liberações%' THEN RAISE;END IF;
 END;
 DELETE FROM public.romaneios;
END $romaneio$;

SELECT 'OK v46.15: inspeção, saldos, conciliação histórica sem movimentos, total simples e bloqueios de consumo/romaneio.' AS resultado;
