-- Faturamento: executar a RPC real da v46.9 em um banco PostgreSQL descartável.
-- A importação preexistente é simulada apenas no teste anterior.
\set ON_ERROR_STOP on
INSERT INTO public.esquadrias_saida_config(esquadria_id,folhas_por_unidade)
SELECT id,2 FROM public.esquadrias WHERE codigo='EA01';
WITH nr AS(
 INSERT INTO public.romaneios(empresa_id,obra_id,status)
 SELECT empresa_id,id,'emitido' FROM public.obras
 WHERE codigo='HOMOLOG-V469-001' RETURNING id,obra_id
)
INSERT INTO public.romaneios_itens(romaneio_id,esquadria_id,tipo_saida,quantidade)
SELECT r.id,e.id,x.tipo_saida,1 FROM nr r
JOIN public.esquadrias e ON e.obra_id=r.obra_id
CROSS JOIN (VALUES('marco'),('folha'),('completo')) x(tipo_saida)
WHERE (e.codigo='EA01' AND x.tipo_saida IN('marco','folha'))
   OR (e.codigo='GC01' AND x.tipo_saida='completo');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $finance$
DECLARE
 empresa uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 obra uuid;ea uuid;gc uuid;resp jsonb;antigo jsonb;err text;
BEGIN
 SELECT id INTO obra FROM public.obras WHERE codigo='HOMOLOG-V469-001';
 SELECT id INTO ea FROM public.esquadrias WHERE obra_id=obra AND codigo='EA01';
 SELECT id INTO gc FROM public.esquadrias WHERE obra_id=obra AND codigo='GC01';
 IF obra IS NULL OR ea IS NULL OR gc IS NULL THEN
  RAISE EXCEPTION 'A importação não preservou os IDs';END IF;
 -- 0.75 EA01: 50% marco + 25% uma folha de 2, preço integral fab R$ 3.000.
 resp:=public.ew_registrar_faturamento_financeiro(empresa,obra,'fabricacao',
  current_date,'NF-FAB-001','',jsonb_build_array(jsonb_build_object(
   'esquadria_id',ea,'quantidade',0.75,'valor_unitario',3000)),
  '66666666-6666-4666-8666-666666666666',false);
 IF (resp->>'valor_total')::numeric<>2250 OR resp->>'ja_registrado'<>'false'
 THEN RAISE EXCEPTION 'Faturamento parcial incorreto: %',resp;END IF;
 -- Reenvio da mesma NF com a mesma operacao_id não pode cobrar novamente.
 antigo:=public.ew_registrar_faturamento_financeiro(empresa,obra,'fabricacao',
  current_date,'NF-FAB-001','',jsonb_build_array(jsonb_build_object(
   'esquadria_id',ea,'quantidade',0.75,'valor_unitario',3000)),
  '66666666-6666-4666-8666-666666666666',false);
 IF antigo->>'ja_registrado'<>'true' OR
  (SELECT count(*) FROM public.ew_obra_faturamentos)<>1
 THEN RAISE EXCEPTION 'Repetição de NF duplicou receita';END IF;
 -- Impedir a quarta parte ainda não expedida.
 BEGIN
  PERFORM public.ew_registrar_faturamento_financeiro(empresa,obra,'fabricacao',
   current_date,'NF-FAB-EXCESSO','',jsonb_build_array(jsonb_build_object(
    'esquadria_id',ea,'quantidade',0.25,'valor_unitario',3000)),
   '77777777-7777-4777-8777-777777777777',false);
  RAISE EXCEPTION 'Aceitou quantidade não expedida';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Quantidade equivalente não faturável%' THEN RAISE;END IF;
 END;
 -- Fabricação restante caberia no orçamento ORIGINAL 7k mas não no AJUSTADO 6k.
 BEGIN
  PERFORM public.ew_registrar_faturamento_financeiro(empresa,obra,'fabricacao',
   current_date,'NF-FAB-ACIMA-60','',jsonb_build_array(jsonb_build_object(
    'esquadria_id',gc,'quantidade',1,'valor_unitario',4000)),
   '88888888-8888-4888-8888-888888888888',false);
  RAISE EXCEPTION 'Aceitou R$ 6.250 contra teto ajustado R$ 6.000';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%supera o valor contratado%' THEN RAISE;END IF;
 END;
 -- Completo GC1, dentro do limite de fabricação ajustado.
 resp:=public.ew_registrar_faturamento_financeiro(empresa,obra,'fabricacao',
  current_date,'NF-FAB-GC','',jsonb_build_array(jsonb_build_object(
   'esquadria_id',gc,'quantidade',1,'valor_unitario',3000)),
  '99999999-9999-4999-8999-999999999999',false);
 IF (resp->>'valor_total')::numeric<>3000
 THEN RAISE EXCEPTION 'Faturamento de GC incorreto';END IF;

 -- Instalação é independente, mas exige confirmação.
 BEGIN
  PERFORM public.ew_registrar_faturamento_financeiro(empresa,obra,'instalacao',
   current_date,'NF-INST-SEM-CONF','',jsonb_build_array(jsonb_build_object(
    'esquadria_id',ea,'quantidade',0.75,'valor_unitario',2000)),
   'aaaaaaaa-1111-4111-8111-111111111111',false);
  RAISE EXCEPTION 'Instalação faturada sem confirmação';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Confirme a instalação%' THEN RAISE;END IF;
 END;
 resp:=public.ew_registrar_faturamento_financeiro(empresa,obra,'instalacao',
  current_date,'NF-INST-EA','',jsonb_build_array(jsonb_build_object(
   'esquadria_id',ea,'quantidade',0.75,'valor_unitario',2000)),
  'bbbbbbbb-1111-4111-8111-111111111111',true);
 IF (resp->>'valor_total')::numeric<>1500 THEN
  RAISE EXCEPTION 'Instalação parcial incorreta';END IF;
 -- Valor EDITADO manualmente de GC = 2.500 (aprovado era 2.000).
 -- Total instalacao 1.500+2.500 = R$ 4.000, permitido pelo novo 40%;
 -- seria bloqueado pelo teto original de R$ 3.000.
 resp:=public.ew_registrar_faturamento_financeiro(empresa,obra,'instalacao',
  current_date,'NF-INST-GC-EDITADA','',jsonb_build_array(jsonb_build_object(
   'esquadria_id',gc,'quantidade',1,'valor_unitario',2500)),
  'cccccccc-1111-4111-8111-111111111111',true);
 IF (resp->>'valor_total')::numeric<>2500 THEN
  RAISE EXCEPTION 'Valor editável de instalação não foi aceito';END IF;
 IF (SELECT sum(valor_total) FROM public.ew_obra_faturamentos
     WHERE categoria='fabricacao')<>5250 OR
    (SELECT sum(valor_total) FROM public.ew_obra_faturamentos
     WHERE categoria='instalacao')<>4000 OR
    (SELECT count(*) FROM public.ew_obra_faturamentos)<>4 OR
    (SELECT count(*) FROM public.ew_obra_faturamentos_itens)<>4
 THEN RAISE EXCEPTION 'Faturamentos não fecharam com histórico e tetos';END IF;
 -- Nenhuma fatura altera o preço original aprovado.
 IF (SELECT sum(instalacao_centavos) FROM public.ew_precificacao_revisoes_itens)<>400000
 THEN RAISE EXCEPTION 'Faturas editaram indevidamente o preço aprovado';END IF;
 RAISE NOTICE 'OK: faturamento real 75%% marco+folha, teto fab 60%%, instalação 40%% e edição manual sem alterar histórico';
END $finance$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $almox$
DECLARE obra uuid;ea uuid;err text;
BEGIN
 SELECT id INTO obra FROM public.obras WHERE codigo='HOMOLOG-V469-001';
 SELECT id INTO ea FROM public.esquadrias WHERE obra_id=obra AND codigo='EA01';
 BEGIN
  PERFORM public.ew_registrar_faturamento_financeiro(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',obra,'fabricacao',current_date,
   'NF-ALMOX','',jsonb_build_array(jsonb_build_object(
    'esquadria_id',ea,'quantidade',0.1,'valor_unitario',100)),
   'dddddddd-1111-4111-8111-111111111111',false);
  RAISE EXCEPTION 'Almoxarife faturou sem ADM';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Somente ADM%' THEN RAISE;END IF;
 END;
 RAISE NOTICE 'OK: almoxarife não pode emitir fatura';
END $almox$;
RESET ROLE;
SELECT 'FATURAMENTO PARCIAL E TETOS APROVADOS' AS status;
