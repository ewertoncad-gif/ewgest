-- Executar SOMENTE em ewgest-restauracao-teste. Fixture completamente revertida.
BEGIN;
SELECT set_config('request.jwt.claim.sub','040b8754-8557-449c-8ad4-eaa34155c920',true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,ativo,nome,login)
 VALUES('040b8754-8557-449c-8ad4-eaa34155c920','9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'administrador',true,'Teste de estoque','teste_almox');
INSERT INTO public.obras(id,empresa_id,codigo,nome) VALUES
 ('b1111111-1111-4111-8111-111111111111','9ea7617c-6603-4bc1-91e1-c5e274c334d9','TESTE-V4617','Obra Ficticia V4617');
INSERT INTO public.ew_estoques_locais(empresa_id,obra_id) VALUES
 ('9ea7617c-6603-4bc1-91e1-c5e274c334d9','b1111111-1111-4111-8111-111111111111');
INSERT INTO public.ew_locais_fisicos(empresa_id,nome,ativo) VALUES
 ('9ea7617c-6603-4bc1-91e1-c5e274c334d9','IMBIRIBEIRA',true);
INSERT INTO public.ew_perfis(id,empresa_id,codigo,descricao,fabricante,peso_kg_m)
 VALUES('b2222222-2222-4222-8222-222222222222','9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'TESTE-PERFIL','Perfil de teste','TESTE',1.5);
INSERT INTO public.ew_materiais_variacoes(id,empresa_id,tipo,perfil_id,ativo,cor)
 VALUES('b3333333-3333-4333-8333-333333333333','9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'perfil','b2222222-2222-4222-8222-222222222222',true,'NATURAL');
INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,usuario_id,local_estoque)
 VALUES('9ea7617c-6603-4bc1-91e1-c5e274c334d9','b1111111-1111-4111-8111-111111111111',
 'b3333333-3333-4333-8333-333333333333',6000,'BARRA',5,'ABERTURA',
 gen_random_uuid(),'fixture de homologacao','040b8754-8557-449c-8ad4-eaa34155c920','IMBIRIBEIRA');
INSERT INTO public.ew_acessorios(id,empresa_id,codigo,descricao,fabricante)
 VALUES('b8888888-8888-4888-8888-888888888888','9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'TESTE-AC','Acessório de teste','TESTE');
INSERT INTO public.ew_materiais_variacoes(id,empresa_id,tipo,acessorio_id,ativo)
 VALUES('b9999999-9999-4999-8999-999999999999','9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'acessorio','b8888888-8888-4888-8888-888888888888',true);
INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,
 comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,usuario_id,local_estoque)
 VALUES('9ea7617c-6603-4bc1-91e1-c5e274c334d9','b1111111-1111-4111-8111-111111111111',
 'b9999999-9999-4999-8999-999999999999',null,'PC',3,'ABERTURA',gen_random_uuid(),
 'fixture de acessório','040b8754-8557-449c-8ad4-eaa34155c920','IMBIRIBEIRA');
DO $check$
DECLARE result jsonb;repeated jsonb;c jsonb;saldo numeric;n integer;v_rom_id uuid;err text;
  v_items jsonb:='[{"natureza":"material","variacao_id":"b3333333-3333-4333-8333-333333333333",
  "comprimento_mm":6000,"local_estoque":"IMBIRIBEIRA","unidade":"BARRA","quantidade":2}]'::jsonb;
BEGIN
 BEGIN
  PERFORM public.emitir_romaneio_com_saidas(
    'b4444444-4444-4444-8444-444444444444','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Tentativa sem saldo',
    jsonb_set(v_items,'{0,quantidade}','8'::jsonb));
  RAISE EXCEPTION 'FALHA: permitiu emitir sem saldo suficiente';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%sem saldo%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.emitir_romaneio_com_saidas(
    'b4444444-4444-4444-8444-444444444445','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Tentativa sem vínculo',
    '[{"natureza":"material","descricao":"Item sem saldo","codigo":"X","unidade":"BARRA","quantidade":1}]'::jsonb);
  RAISE EXCEPTION 'FALHA: aceitou material sem vínculo de estoque';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%deve ser escolhido do estoque%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.emitir_romaneio_com_saidas(
    'b7777777-7777-4777-8777-777777777777','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Duplicação de saldo no mesmo romaneio',
    jsonb_build_array(jsonb_set(v_items,'{0,quantidade}','3'::jsonb)->0,
      jsonb_set(v_items,'{0,quantidade}','3'::jsonb)->0));
  RAISE EXCEPTION 'FALHA: permitiu duas linhas que somavam acima do saldo';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%sem saldo%' THEN RAISE; END IF;
 END;
 result:=public.emitir_romaneio_com_saidas(
    'b5555555-5555-4555-8555-555555555555','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Saída de teste',v_items);
 v_rom_id:=(result->>'id')::uuid;
 SELECT coalesce(sum(m.quantidade_delta),0) INTO saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id='b1111111-1111-4111-8111-111111111111'
   AND m.variacao_id='b3333333-3333-4333-8333-333333333333';
 IF saldo<>3 THEN RAISE EXCEPTION 'Saldo após saída deveria ser 3, obtido %',saldo;END IF;
 SELECT count(*) INTO n FROM public.ew_romaneios_materiais_saidas x WHERE x.romaneio_id=v_rom_id;
 IF n<>1 THEN RAISE EXCEPTION 'Romaneio não vinculou material ao movimento';END IF;
 repeated:=public.emitir_romaneio_com_saidas(
    'b5555555-5555-4555-8555-555555555555','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Repetição da saída de teste',v_items);
 IF (repeated->>'repetido')::boolean IS DISTINCT FROM true
   THEN RAISE EXCEPTION 'Idempotência não funcionou';END IF;
 SELECT count(*) INTO n FROM public.ew_romaneios_materiais_saidas x WHERE x.romaneio_id=v_rom_id;
 IF n<>1 THEN RAISE EXCEPTION 'Idempotência criou vínculo duplicado';END IF;
 BEGIN
  PERFORM public.ew_estornar_movimento_obra(
    'b1111111-1111-4111-8111-111111111111',
    (SELECT x.movimento_id FROM public.ew_romaneios_materiais_saidas x
     WHERE x.romaneio_id=v_rom_id),
    'Tentativa de estorno sem cancelar o romaneio',gen_random_uuid());
  RAISE EXCEPTION 'FALHA: permitiu estorno isolado de material ainda expedido';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Cancele o romaneio%' THEN RAISE; END IF;
 END;
 c:=public.cancelar_romaneio_com_estorno(v_rom_id,'Devolução física confirmada na obra fictícia');
 SELECT coalesce(sum(m.quantidade_delta),0) INTO saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id='b1111111-1111-4111-8111-111111111111'
   AND m.variacao_id='b3333333-3333-4333-8333-333333333333';
 IF saldo<>5 THEN RAISE EXCEPTION 'Saldo após devolução deveria ser 5, obtido %',saldo;END IF;
 IF (c->>'materiais_devolvidos')::integer<>1 THEN RAISE EXCEPTION 'Devolução não conciliada';END IF;
 SELECT count(*) INTO n FROM public.ew_romaneios_materiais_saidas x
  WHERE x.romaneio_id=v_rom_id AND x.estorno_movimento_id IS NOT NULL;
 IF n<>1 THEN RAISE EXCEPTION 'Estorno sem vínculo auditável';END IF;
 result:=public.emitir_romaneio_com_saidas(
    'baaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Acessório direto',
    '[{"natureza":"material","variacao_id":"b9999999-9999-4999-8999-999999999999",
    "local_estoque":"IMBIRIBEIRA","unidade":"PC","quantidade":2}]'::jsonb);
 SELECT coalesce(sum(m.quantidade_delta),0) INTO saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.obra_id='b1111111-1111-4111-8111-111111111111'
   AND m.variacao_id='b9999999-9999-4999-8999-999999999999';
 IF saldo<>1 THEN RAISE EXCEPTION 'Acessório deveria ficar com saldo 1, obtido %',saldo;END IF;
 PERFORM public.cancelar_romaneio_com_estorno((result->>'id')::uuid,'Devolução física de acessório ao galpão fictício');
 SELECT coalesce(sum(m.quantidade_delta),0) INTO saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.obra_id='b1111111-1111-4111-8111-111111111111'
   AND m.variacao_id='b9999999-9999-4999-8999-999999999999';
 IF saldo<>3 THEN RAISE EXCEPTION 'Acessório não foi devolvido; saldo %',saldo;END IF;
 UPDATE public.usuarios_empresas SET perfil='supervisor'
  WHERE usuario_id='040b8754-8557-449c-8ad4-eaa34155c920';
 UPDATE public.usuarios_login SET perfil='supervisor'
  WHERE usuario_id='040b8754-8557-449c-8ad4-eaa34155c920';
 BEGIN
  PERFORM public.emitir_romaneio_com_saidas(
    'b6666666-6666-4666-8666-666666666666','b1111111-1111-4111-8111-111111111111',
    current_date,'Motorista ficticio','ABC1D23','Teste de perfil',v_items);
  RAISE EXCEPTION 'FALHA: supervisor fez baixa física de materiais';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Somente ADM ou almoxarife%' THEN RAISE; END IF;
 END;
END $check$;
ROLLBACK;
SELECT 'PASSOU: saldo, vínculo, idempotência, devolução e permissão em transação fictícia revertida' as resultado;