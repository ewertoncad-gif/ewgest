-- Executar apenas em transação de testes e reverter ao final.
DO $t$
DECLARE emp uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); l uuid; f uuid; f2 uuid; e1 uuid; e2 uuid; e3 uuid; op uuid:=gen_random_uuid(); rev uuid:=gen_random_uuid(); item uuid:=gen_random_uuid(); mov uuid:=gen_random_uuid(); n numeric;
BEGIN
 l:=ew_compras_interna.custo_abrir_lote(emp,'NFE_DIRETA',item,mov,'aluminio',3,10000,'OBRA',a,'G1');
 IF l<>ew_compras_interna.custo_abrir_lote(emp,'NFE_DIRETA',item,mov,'aluminio',3,10000,'OBRA',a,'G1') THEN RAISE EXCEPTION 'Falha idempotência lote'; END IF;
 SELECT fragmento_id INTO f FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l;
 e1:=ew_compras_interna.custo_mover_fragmento(emp,l,f,op,1,2,'OBRA',b,'G2',usr);
 IF e1<>ew_compras_interna.custo_mover_fragmento(emp,l,f,op,1,2,'OBRA',b,'G2',usr) THEN RAISE EXCEPTION 'Falha idempotência transferência'; END IF;
 SELECT fragmento_id INTO f2 FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l AND local_id=b;
 e2:=ew_compras_interna.custo_mover_fragmento(emp,l,f2,gen_random_uuid(),1,1,'OBRA',c,'G3',usr);
 SELECT fragmento_id INTO f2 FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l AND local_id=c;
 e3:=ew_compras_interna.custo_mover_fragmento(emp,l,f2,gen_random_uuid(),1,1,'PRODUCAO',c,'FAB',usr);
 IF (SELECT sum(custo_centavos) FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l)<>10000 THEN RAISE EXCEPTION 'Custo não conservado'; END IF;
 IF (SELECT sum(delta_centavos) FROM ew_compras_interna.custo_ajustes_obra WHERE empresa_id=emp AND obra_id=a)<>-6667 OR
 (SELECT sum(delta_centavos) FROM ew_compras_interna.custo_ajustes_obra WHERE empresa_id=emp AND obra_id=b)<>3334 OR
 (SELECT sum(delta_centavos) FROM ew_compras_interna.custo_ajustes_obra WHERE empresa_id=emp AND obra_id=c)<>3333 THEN RAISE EXCEPTION 'Apropriação incorreta'; END IF;
 BEGIN PERFORM ew_compras_interna.custo_estornar_evento(emp,l,e1,rev,usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 BEGIN PERFORM ew_compras_interna.custo_cancelar_lote(emp,l,rev,usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 BEGIN PERFORM ew_compras_interna.custo_mover_fragmento(gen_random_uuid(),l,f,gen_random_uuid(),1,1,'OBRA',b,'G2',usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 PERFORM ew_compras_interna.custo_estornar_evento(emp,l,e3,rev,usr);
 PERFORM ew_compras_interna.custo_estornar_evento(emp,l,e2,rev,usr);
 PERFORM ew_compras_interna.custo_estornar_evento(emp,l,e1,rev,usr);
 PERFORM ew_compras_interna.custo_estornar_evento(emp,l,e1,rev,usr);
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_ajustes_obra WHERE empresa_id=emp GROUP BY obra_id HAVING sum(delta_centavos)<>0) THEN RAISE EXCEPTION 'Estorno não zerou valores'; END IF;
 IF (SELECT count(*) FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l AND local_id=a AND quantidade=3 AND custo_centavos=10000)<>1 THEN RAISE EXCEPTION 'Saldo não retornou'; END IF;
 PERFORM ew_compras_interna.custo_cancelar_lote(emp,l,rev,usr);
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l) THEN RAISE EXCEPTION 'Lote cancelado disponível'; END IF;
 IF (SELECT count(*) FROM ew_compras_interna.custo_eventos WHERE empresa_id=emp AND lote_id=l)<>3 THEN RAISE EXCEPTION 'Histórico apagado'; END IF;
END;$t$;