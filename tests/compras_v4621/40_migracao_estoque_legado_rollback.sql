-- EWGEST v46.21 — migração de estoque legado cadastrado como obra fictícia.
-- Ensaio sintético da situação observada (4 MT transferidos a outra obra).
-- Somente em transação com ROLLBACK no banco ewgest-restauracao-teste.
DO $legacy$
DECLARE
 v_uid uuid;v_emp uuid;v_a uuid;v_b uuid;v_local uuid;
 v_acc uuid;v_var uuid;v_mov_id uuid:=gen_random_uuid();
 v_legacy_saida uuid;v_legacy_entrada uuid;v_mig uuid;v_result jsonb;
 v_saldo_origem numeric;v_saldo_antigo numeric;v_saldo_empresa numeric;v_total numeric;
BEGIN
 SELECT ue.usuario_id,ue.empresa_id INTO STRICT v_uid,v_emp
 FROM public.usuarios_empresas ue WHERE ue.nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_emp,'administrador',1,'Teste migração estoque legado',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_emp,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_emp,'OBRA TREINAMENTO SINTETICA','TESTE-TRAIN-4621') RETURNING id INTO v_a;
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_emp,'ESTOQUE ANTIGO SINTETICO','MAN-ESTOQUE-4621') RETURNING id INTO v_b;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_emp,v_a,v_uid),(v_emp,v_b,v_uid);
 INSERT INTO public.ew_acessorios(empresa_id,codigo,descricao,fabricante,unidade_item)
 VALUES(v_emp,'FIT2130PTO-TESTE','Fita vedadora teste por metro','FAB TESTE','MT')
 RETURNING id INTO v_acc;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,acessorio_id,cor,acabamento)
 VALUES(v_emp,'acessorio',v_acc,'PRETO','PRETO') RETURNING id INTO v_var;
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,
  comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,usuario_id,local_estoque)
 VALUES(v_emp,v_a,v_var,null,'MT',4,'ABERTURA',gen_random_uuid(),
  'Saldo original antes de transferência simulada',v_uid,'IMBIRIBEIRA');
 -- Transferência antiga (dois movimentos referenciados pelo mesmo UUID).
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,
  comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,
  usuario_id,local_estoque,transferencia_id)
 VALUES(v_emp,v_b,v_var,null,'MT',4,'TRANSFERENCIA',gen_random_uuid(),
  'Destino transferência legado',v_uid,'IMBIRIBEIRA',v_mov_id)
 RETURNING id INTO v_legacy_entrada;
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,
  comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,
  usuario_id,local_estoque,transferencia_id)
 VALUES(v_emp,v_a,v_var,null,'MT',-4,'TRANSFERENCIA',gen_random_uuid(),
  'Origem transferência legado',v_uid,'IMBIRIBEIRA',v_mov_id)
 RETURNING id INTO v_legacy_saida;
 v_result:=public.ew_compras_criar_local_empresa(v_emp,'ESTOQUE EMPRESA SINTETICO');
 v_local:=(v_result->>'id')::uuid;
 -- Um único novo par de movimentos: -4 da obra artificial, +4 no local empresa.
 v_result:=public.ew_compras_transferir_locais(
  v_emp,'OBRA',v_b,'EMPRESA',v_local,v_var,null,'MT',4,
  'IMBIRIBEIRA','IMBIRIBEIRA','Migração auditada de estoque antigo',gen_random_uuid());
 v_mig:=(v_result->>'id')::uuid;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo_origem
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_a AND variacao_id=v_var;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo_antigo
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_b AND variacao_id=v_var;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo_empresa
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local AND variacao_id=v_var;
 v_total:=v_saldo_origem+v_saldo_antigo+v_saldo_empresa;
 IF v_saldo_origem<>0 OR v_saldo_antigo<>0 OR v_saldo_empresa<>4 OR v_total<>4
 THEN RAISE EXCEPTION 'Migração duplicou/perdeu saldo: original %, antiga %, empresa %, total %.',
   v_saldo_origem,v_saldo_antigo,v_saldo_empresa,v_total;END IF;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos
   WHERE transferencia_id=v_mov_id AND id IN (v_legacy_saida,v_legacy_entrada))<>2
 THEN RAISE EXCEPTION 'Movimentação histórica entre obras foi modificada.';END IF;
 -- O novo estorno devolve os 4 MT ao estoque legado antes de eventual estorno anterior.
 v_result:=public.ew_compras_estornar_transferencia(
  v_mig,'Estorno de migração para ensaio',gen_random_uuid());
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo_antigo
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_b AND variacao_id=v_var;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo_empresa
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local AND variacao_id=v_var;
 IF v_saldo_antigo<>4 OR v_saldo_empresa<>0
 THEN RAISE EXCEPTION 'Estorno migração perdeu saldo: antiga %, empresa %.',v_saldo_antigo,v_saldo_empresa;END IF;
 RAISE NOTICE 'PASS LEGADO: 4 MT, transferência entre obras preservada, obra antiga zerada, estoque empresa 4 MT, reversão segura.';
END;$legacy$;
