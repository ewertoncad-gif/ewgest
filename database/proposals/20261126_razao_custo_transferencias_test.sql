-- Executar APENAS em ambiente isolado; preparar a proposta em pg_temp, dentro da mesma transação.
-- BEGIN; carregar DDL com ew_compras_interna. substituído por pg_temp.; executar este teste; ROLLBACK.
DO $t$
DECLARE emp uuid:=gen_random_uuid(); emp2 uuid:=gen_random_uuid(); tr uuid:=gen_random_uuid();
orig uuid:=gen_random_uuid(); dest uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid();
op uuid:=gen_random_uuid(); n int; s numeric;
BEGIN
 INSERT INTO pg_temp.transferencia_custo_apropriacoes(empresa_id,fluxo,transferencia_id,origem_tipo,origem_id,destino_tipo,destino_id,categoria,custo_centavos,evidencias,criado_por)
 VALUES(emp,'OBRAS',tr,'OBRA',orig,'OBRA',dest,'aluminio',12345,'[{"teste":true}]',usr);
 SELECT count(*),sum(delta_centavos) INTO n,s FROM pg_temp.transferencia_custo_razao WHERE empresa_id=emp AND transferencia_id=tr;
 IF n<>2 OR s<>0 THEN RAISE EXCEPTION 'Lançamento não balanceado'; END IF;
 IF (SELECT delta_centavos FROM pg_temp.transferencia_custo_razao WHERE empresa_id=emp AND transferencia_id=tr AND local_id=orig)<>-12345 THEN RAISE EXCEPTION 'Sinal de origem incorreto'; END IF;
 BEGIN
  INSERT INTO pg_temp.transferencia_custo_apropriacoes SELECT * FROM pg_temp.transferencia_custo_apropriacoes WHERE empresa_id=emp AND transferencia_id=tr;
  RAISE EXCEPTION 'Aceitou apropriação duplicada';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO pg_temp.transferencia_custo_estornos(empresa_id,fluxo,transferencia_id,operacao_id,motivo,criado_por)
  VALUES(emp2,'OBRAS',tr,op,'teste de isolamento',usr);
  RAISE EXCEPTION 'Aceitou estorno em empresa errada';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 INSERT INTO pg_temp.transferencia_custo_estornos(empresa_id,fluxo,transferencia_id,operacao_id,motivo,criado_por)
 VALUES(emp,'OBRAS',tr,op,'teste de reversão',usr);
 SELECT count(*),sum(delta_centavos) INTO n,s FROM pg_temp.transferencia_custo_razao WHERE empresa_id=emp AND transferencia_id=tr;
 IF n<>4 OR s<>0 OR EXISTS(SELECT 1 FROM pg_temp.transferencia_custo_razao WHERE empresa_id=emp AND transferencia_id=tr GROUP BY tipo,local_id HAVING sum(delta_centavos)<>0) THEN RAISE EXCEPTION 'Estorno não devolveu os centavos'; END IF;
 BEGIN
  INSERT INTO pg_temp.transferencia_custo_estornos(empresa_id,fluxo,transferencia_id,operacao_id,motivo,criado_por)
  VALUES(emp,'OBRAS',tr,gen_random_uuid(),'teste repetido',usr);
  RAISE EXCEPTION 'Aceitou segundo estorno';
 EXCEPTION WHEN unique_violation THEN NULL; END;
END;$t$;
