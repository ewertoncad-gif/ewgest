-- Executar com os mesmos mocks e instalação temporária do teste da ponte.
DO $t$
DECLARE emp uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); tr uuid:=gen_random_uuid(); mat uuid:=gen_random_uuid(); l1 uuid; l2 uuid; f1 uuid; f2 uuid; i1 uuid:=gen_random_uuid(); m1 uuid:=gen_random_uuid(); i2 uuid:=gen_random_uuid(); m2 uuid:=gen_random_uuid(); op uuid; al jsonb; rev uuid:=gen_random_uuid(); e uuid;
BEGIN
 INSERT INTO pg_temp.lotes_aquisicao_evidencias VALUES
 (emp,'PEDIDO_EMPRESA',i1,m1,'TECNICO',mat,6000,'BARRA',2,10001,'aluminio'),
 (emp,'PEDIDO_EMPRESA',i2,m2,'TECNICO',mat,6000,'BARRA',3,20000,'aluminio');
 INSERT INTO pg_temp.transferencias_fisicas_custo VALUES(emp,'LOCAIS',tr,'ATIVA',2,'EMPRESA',a,'G1','OBRA',b,'G2','TECNICO',mat,6000,'BARRA');
 l1:=pg_temp.custo_abrir_lote(emp,'PEDIDO_EMPRESA',i1,m1,'aluminio',2,10001,'EMPRESA',a,'G1');
 l2:=pg_temp.custo_abrir_lote(emp,'PEDIDO_EMPRESA',i2,m2,'aluminio',3,20000,'EMPRESA',a,'G1');
 SELECT fragmento_id INTO f1 FROM pg_temp.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l1;
 SELECT fragmento_id INTO f2 FROM pg_temp.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l2;
 al:=jsonb_build_array(jsonb_build_object('lote_id',l1,'fragmento_id',f1,'quantidade',1),jsonb_build_object('lote_id',l2,'fragmento_id',f2,'quantidade',1));
 BEGIN PERFORM pg_temp.custo_integrar_transferencia(emp,'LOCAIS',tr,jsonb_build_array(al->0,al->0),usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 op:=pg_temp.custo_integrar_transferencia(emp,'LOCAIS',tr,al,usr);
 IF (SELECT ajuste_centavos FROM pg_temp.custo_transferencias_ajustes_financeiros WHERE empresa_id=emp AND obra_id=b) IS DISTINCT FROM 11668::numeric THEN RAISE EXCEPTION 'Mistura de lotes: custo incorreto'; END IF;
 IF (SELECT sum(custo_centavos) FROM pg_temp.custo_saldos_fragmentos WHERE empresa_id=emp) IS DISTINCT FROM 30001::numeric THEN RAISE EXCEPTION 'Custo total alterado'; END IF;
 UPDATE pg_temp.transferencias_fisicas_custo SET estado='ESTORNADA' WHERE empresa_id=emp AND transferencia_id=tr;
 PERFORM pg_temp.custo_integrar_estorno(emp,'LOCAIS',tr,rev,usr);
 IF EXISTS(SELECT 1 FROM pg_temp.custo_transferencias_ajustes_financeiros WHERE empresa_id=emp AND ajuste_centavos<>0) THEN RAISE EXCEPTION 'Estorno de múltiplos lotes incorreto'; END IF;
 IF (SELECT sum(quantidade) FROM pg_temp.custo_saldos_fragmentos WHERE empresa_id=emp AND local_id=a) IS DISTINCT FROM 5::numeric THEN RAISE EXCEPTION 'Saldo não restaurado'; END IF;
END;$t$;
