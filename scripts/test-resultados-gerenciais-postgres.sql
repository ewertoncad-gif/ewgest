-- Banco descartável com estrutura mínima das fontes de relatório.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA ew_compras_interna;
CREATE SCHEMA ew_financeiro_interna;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida';END IF;END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT $1='00000000-0000-0000-0000-000000000001' AND current_setting('test.perm',true)='yes' $$;
CREATE TABLE public.obras(id uuid PRIMARY KEY,empresa_id uuid,nome text,codigo text);
CREATE TABLE public.esquadrias(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,codigo text,largura_mm numeric,altura_mm numeric);
CREATE TABLE public.ew_obra_faturamentos(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,categoria text,valor_total numeric,status text,cancelado_em timestamptz,data_faturamento date,criado_em timestamptz);
CREATE TABLE public.ew_obra_faturamentos_itens(faturamento_id uuid,empresa_id uuid,esquadria_id uuid,quantidade numeric,valor_total numeric,area_m2 numeric);
CREATE TABLE public.romaneios(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,status text,cancelado_em timestamptz,data_saida date,criado_em timestamptz);
CREATE TABLE public.romaneios_itens(romaneio_id uuid,natureza text,esquadria_id uuid,fabrica text,area_m2 numeric);
CREATE TABLE public.liberacoes_corte(id uuid PRIMARY KEY,esquadria_id uuid,cancelado_em timestamptz,fabrica text);
CREATE TABLE public.ew_liberacoes_lotes(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,cancelado_em timestamptz,fabrica text);
CREATE TABLE public.ew_estoque_obras_movimentos(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,origem text,quantidade_delta numeric,liberacao_id uuid,lote_id uuid,local_estoque text,estorno_de_id uuid,criado_em timestamptz);
CREATE TABLE public.ew_estornos_parcelas(empresa_id uuid,movimento_original_id uuid,movimento_estorno_id uuid,quantidade numeric);
CREATE TABLE ew_compras_interna.custo_consumos_integrados(empresa_id uuid,movimento_id uuid,operacao_custo uuid,quantidade numeric,estornado_em timestamptz);
CREATE TABLE ew_compras_interna.custo_eventos(empresa_id uuid,lote_id uuid,operacao_id uuid,quantidade numeric,destino_tipo text,destino_id uuid,destino_galpao text,custo_centavos bigint,estornado_em timestamptz);
CREATE TABLE ew_compras_interna.custo_lotes(empresa_id uuid,lote_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,quantidade numeric,custo_centavos bigint,categoria text,cancelado_em timestamptz);
CREATE TABLE ew_compras_interna.lotes_aquisicao_evidencias(empresa_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,quantidade numeric,custo_centavos bigint,categoria text);
CREATE TABLE ew_financeiro_interna.titulos(empresa_id uuid,tipo text,origem_tipo text,cancelado_em timestamptz,competencia date,categoria text,centro_custo text,valor_centavos bigint);
\ir ../database/proposals/20261128_resultados_gerenciais_v462940.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001'; e2 uuid:=gen_random_uuid();o uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();
 r1 uuid:=gen_random_uuid();r2 uuid:=gen_random_uuid();r3 uuid:=gen_random_uuid();f1 uuid:=gen_random_uuid();f2 uuid:=gen_random_uuid();f3 uuid:=gen_random_uuid();f4 uuid:=gen_random_uuid();f5 uuid:=gen_random_uuid();
 l uuid:=gen_random_uuid();bl uuid:=gen_random_uuid();m1 uuid:=gen_random_uuid();m2 uuid:=gen_random_uuid();m3 uuid:=gen_random_uuid();m4 uuid:=gen_random_uuid();m5 uuid:=gen_random_uuid();op uuid:=gen_random_uuid();op2 uuid:=gen_random_uuid();lt uuid:=gen_random_uuid();item uuid:=gen_random_uuid();orig uuid:=gen_random_uuid();res jsonb;negado boolean;
BEGIN
 IF has_function_privilege('anon','public.ew_resultados_gerenciais(uuid,date,date)','EXECUTE') THEN RAISE EXCEPTION 'anon autorizado';END IF;
 res:=public.ew_resultados_gerenciais(e,'2026-11-01','2026-11-30');
 IF (res->>'fabricacao_centavos')::bigint<>0 OR jsonb_array_length(res->'fabrica')<>0 THEN RAISE EXCEPTION 'vazio incorreto';END IF;
 INSERT INTO public.obras VALUES(o,e,'Obra A','A');
 INSERT INTO public.esquadrias VALUES(a,e,o,'EA',1000,1000),(b,e,o,'EB',1000,1000),(c,e,o,'EC',1000,1000);
 INSERT INTO public.romaneios VALUES(r1,e,o,'emitido',NULL,'2026-11-02','2026-11-02T10:00:00Z'),(r2,e,o,'emitido',NULL,'2026-11-03','2026-11-03T10:00:00Z'),(r3,e,o,'emitido',NULL,'2026-11-25','2026-11-25T10:00:00Z');
 INSERT INTO public.romaneios_itens VALUES(r1,'esquadria',a,'AFOGADOS',1),(r1,'esquadria',b,'AFOGADOS',.5),(r2,'esquadria',b,'IMBIRIBEIRA',.5),(r3,'esquadria',a,'IMBIRIBEIRA',1),(r2,'esquadria',c,NULL,1);
 INSERT INTO public.ew_obra_faturamentos VALUES(f1,e,o,'fabricacao',100,'emitido',NULL,'2026-11-10','2026-11-10T10:00:00Z'),(f2,e,o,'fabricacao',50,'emitido',NULL,'2026-11-11','2026-11-11T10:00:00Z'),(f3,e,o,'instalacao',30,'emitido',NULL,'2026-11-12','2026-11-12T10:00:00Z'),(f4,e,o,'fabricacao',10,'emitido',NULL,'2026-11-13','2026-11-13T10:00:00Z'),(f5,e,o,'fabricacao',999,'cancelado',now(),'2026-11-13','2026-11-13T10:00:00Z');
 INSERT INTO public.ew_obra_faturamentos_itens VALUES(f1,e,a,1,100,1),(f2,e,b,1,50,1),(f3,e,a,1,30,1),(f4,e,c,1,9,1),(f5,e,a,1,999,1);
 INSERT INTO public.liberacoes_corte VALUES(l,a,NULL,'AFOGADOS');
 INSERT INTO public.ew_liberacoes_lotes VALUES(bl,e,o,NULL,'IMBIRIBEIRA');
 INSERT INTO public.ew_estoque_obras_movimentos VALUES
 (m1,e,o,'PLANO_CORTE',-2,l,NULL,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z'),
 (m2,e,o,'PLANO_CORTE',-1,l,NULL,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z'),
 (m3,e,o,'PLANO_CORTE_LOTE',-1,NULL,bl,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z'),
 (m4,e,o,'PLANO_CORTE',-1,l,NULL,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z'),
 (m5,e,o,'ESTORNO',1,l,NULL,'ESTOQUE CENTRAL',m4,'2026-11-06T10:00:00Z');
 INSERT INTO ew_compras_interna.custo_consumos_integrados VALUES(e,m1,op,2,NULL),(e,m3,op2,1,NULL);
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,lt,'NFE_DIRETA',item,orig,10,10000,'aluminio',NULL);
 INSERT INTO ew_compras_interna.lotes_aquisicao_evidencias VALUES(e,'NFE_DIRETA',item,orig,10,10000,'aluminio');
 INSERT INTO ew_compras_interna.custo_eventos VALUES(e,lt,op,2,'PRODUCAO',o,'ESTOQUE CENTRAL',2000,NULL),(e,lt,op2,1,'PRODUCAO',o,'ESTOQUE CENTRAL',1000,NULL);
 INSERT INTO ew_financeiro_interna.titulos VALUES(e,'PAGAR','MANUAL',NULL,'2026-11-10','Energia','AFOGADOS',5000),(e,'PAGAR','DESPESA_OBRA',NULL,'2026-11-10','aluminio','GERAL',5000),(e2,'PAGAR','MANUAL',NULL,'2026-11-10','Energia','OUTRO',99999);
 res:=public.ew_resultados_gerenciais(e,'2026-11-01','2026-11-30');
 IF (res->>'fabricacao_centavos')::bigint<>16000 OR (res->>'instalacao_centavos')::bigint<>3000 OR (res->>'material_centavos')::bigint<>3000 OR (res->>'consumos')::bigint<>3 OR (res->>'consumos_pendentes')::bigint<>1 OR (res->>'material_sem_item_centavos')::bigint<>1000 OR (res->>'manuais_pagar_centavos')::bigint<>5000 THEN RAISE EXCEPTION 'totais incorretos: %',res;END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(res->'fabrica') x WHERE x->>'fabrica'='AFOGADOS' AND (x->>'faturamento_centavos')::bigint=10000 AND (x->>'material_centavos')::bigint=2000) THEN RAISE EXCEPTION 'fábrica correta não atribuída: %',res;END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(res->'fabrica') x WHERE x->>'fabrica' IS NULL AND (x->>'faturamento_centavos')::bigint=6000) THEN RAISE EXCEPTION 'receita ambígua não separada: %',res;END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(res->'itens') x WHERE x->>'codigo'='EA' AND (x->>'material_centavos')::bigint=2000 AND (x->>'pendencias')::int=1) THEN RAISE EXCEPTION 'custo por código incorreto: %',res;END IF;
 DELETE FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=e;
 res:=public.ew_resultados_gerenciais(e,'2026-11-01','2026-11-30');
 IF (res->>'material_centavos')::bigint<>0 OR (res->>'consumos_pendentes')::bigint<>3 THEN RAISE EXCEPTION 'custo sem evidência reconhecido';END IF;
 negado:=false;BEGIN PERFORM public.ew_resultados_gerenciais(e2,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso cruzado';END IF;
 PERFORM set_config('test.perm','no',true);
 negado:=false;BEGIN PERFORM public.ew_resultados_gerenciais(e,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'consulta sem flags';END IF;
END $$;
SELECT 'OK: atribuição, fábrica ambígua, estornos, materiais e competência sem duplicidade' AS resultado;
