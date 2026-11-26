-- Executar com motor e ponte no pg_temp, dentro de transação de teste.
-- Criar os mocks ANTES de carregar a ponte, executar o bloco DO após a ponte.
CREATE TABLE pg_temp.transferencias_fisicas_custo(empresa_id uuid,fluxo text,transferencia_id uuid,estado text,quantidade numeric,origem_tipo text,origem_id uuid,origem_galpao text,destino_tipo text,destino_id uuid,destino_galpao text,tipo_material text,material_id uuid,comprimento_mm int,unidade text);
CREATE TABLE pg_temp.lotes_aquisicao_evidencias(empresa_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,tipo_material text,material_id uuid,comprimento_mm int,unidade text,quantidade numeric,custo_centavos bigint,categoria text);
DO $t$
DECLARE emp uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); tr uuid:=gen_random_uuid(); mat uuid:=gen_random_uuid(); l uuid; f uuid; i uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); op uuid; al jsonb; rev uuid:=gen_random_uuid();
BEGIN
 INSERT INTO pg_temp.lotes_aquisicao_evidencias VALUES(emp,'NFE_DIRETA',i,m,'TECNICO',mat,6000,'BARRA',3,10000,'aluminio');
 INSERT INTO pg_temp.transferencias_fisicas_custo VALUES(emp,'OBRAS',tr,'ATIVA',2,'OBRA',a,'G1','OBRA',b,'G2','TECNICO',mat,6000,'BARRA');
 l:=pg_temp.custo_abrir_lote(emp,'NFE_DIRETA',i,m,'aluminio',3,10000,'OBRA',a,'G1');
 SELECT fragmento_id INTO f FROM pg_temp.custo_saldos_fragmentos WHERE empresa_id=emp AND lote_id=l;
 al:=jsonb_build_array(jsonb_build_object('lote_id',l,'fragmento_id',f,'quantidade',2));
 BEGIN PERFORM pg_temp.custo_integrar_transferencia(emp,'OBRAS',tr,jsonb_build_array(jsonb_build_object('lote_id',l,'fragmento_id',f,'quantidade',1)),usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 op:=pg_temp.custo_integrar_transferencia(emp,'OBRAS',tr,al,usr);
 IF op<>pg_temp.custo_integrar_transferencia(emp,'OBRAS',tr,al,usr) THEN RAISE EXCEPTION 'Idempotência incorreta'; END IF;
 IF (SELECT ajuste_centavos FROM pg_temp.custo_transferencias_ajustes_financeiros WHERE empresa_id=emp AND obra_id=b)<>6667 THEN RAISE EXCEPTION 'Custo incorreto'; END IF;
 BEGIN PERFORM pg_temp.custo_integrar_estorno(emp,'OBRAS',tr,rev,usr); RAISE EXCEPTION 'TESTE_FALHOU'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='TESTE_FALHOU' THEN RAISE; END IF; END;
 UPDATE pg_temp.transferencias_fisicas_custo SET estado='ESTORNADA' WHERE empresa_id=emp AND transferencia_id=tr;
 PERFORM pg_temp.custo_integrar_estorno(emp,'OBRAS',tr,rev,usr);
 PERFORM pg_temp.custo_integrar_estorno(emp,'OBRAS',tr,rev,usr);
 IF EXISTS(SELECT 1 FROM pg_temp.custo_transferencias_ajustes_financeiros WHERE empresa_id=emp AND ajuste_centavos<>0) THEN RAISE EXCEPTION 'Estorno incorreto'; END IF;
END;$t$;