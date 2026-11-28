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
CREATE TABLE public.ew_obra_faturamentos(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,categoria text,valor_total numeric,status text,cancelado_em timestamptz,data_faturamento date,criado_em timestamptz,numero_documento text);
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
CREATE TABLE ew_financeiro_interna.titulos(id uuid PRIMARY KEY,empresa_id uuid,tipo text,origem_tipo text,cancelado_em timestamptz,competencia date,categoria text,centro_custo text,valor_centavos bigint,descricao text,UNIQUE(empresa_id,id));
CREATE FUNCTION ew_financeiro_interna.exigir(p_empresa uuid) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN PERFORM public.ew_exigir_sessao_atual(); IF NOT public.ew_pode(p_empresa,'financeiro.consultar') OR NOT public.ew_pode(p_empresa,'relatorios.financeiros') THEN RAISE EXCEPTION 'Sem acesso'; END IF; END $$;
\ir ../database/proposals/20261128_dre_classificacao_v462941.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.perm='yes';
CREATE TABLE public.test_race(movimento_id uuid,faturamento_id uuid);
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';e2 uuid:=gen_random_uuid();o uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 f uuid:=gen_random_uuid();f2 uuid:=gen_random_uuid();inst uuid:=gen_random_uuid();l uuid:=gen_random_uuid();m uuid:=gen_random_uuid();op uuid:=gen_random_uuid();lt uuid:=gen_random_uuid();item uuid:=gen_random_uuid();orig uuid:=gen_random_uuid();
 t uuid:=gen_random_uuid();t2 uuid:=gen_random_uuid();t3 uuid:=gen_random_uuid();t4 uuid:=gen_random_uuid();rec uuid;op_id uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 IF has_function_privilege('anon','public.ew_dre_consultar(uuid,date,date)','EXECUTE') OR has_table_privilege('authenticated','ew_financeiro_interna.reconhecimento_material','SELECT') THEN RAISE EXCEPTION 'acesso direto indevido';END IF;
 INSERT INTO public.obras VALUES(o,e,'Obra A','A');
 INSERT INTO public.esquadrias VALUES(a,e,o,'EA',1000,1000),(b,e,o,'EB',1000,1000);
 INSERT INTO public.ew_obra_faturamentos VALUES(f,e,o,'fabricacao',100,'emitido',NULL,'2026-11-10','2026-11-10T10:00:00Z','001'),(f2,e,o,'fabricacao',50,'emitido',NULL,'2026-11-11','2026-11-11T10:00:00Z','002'),(inst,e,o,'instalacao',30,'emitido',NULL,'2026-11-12','2026-11-12T10:00:00Z','003');
 INSERT INTO public.ew_obra_faturamentos_itens VALUES(f,e,a,1,100,1),(f2,e,b,1,50,1),(inst,e,a,1,30,1);
 INSERT INTO public.liberacoes_corte VALUES(l,a,NULL,'AFOGADOS');
 INSERT INTO public.ew_estoque_obras_movimentos VALUES(m,e,o,'PLANO_CORTE',-2,l,NULL,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z');
 INSERT INTO ew_compras_interna.custo_consumos_integrados VALUES(e,m,op,2,NULL);
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,lt,'NFE_DIRETA',item,orig,10,10000,'aluminio',NULL);
 INSERT INTO ew_compras_interna.lotes_aquisicao_evidencias VALUES(e,'NFE_DIRETA',item,orig,10,10000,'aluminio');
 INSERT INTO ew_compras_interna.custo_eventos VALUES(e,lt,op,2,'PRODUCAO',o,'ESTOQUE CENTRAL',2000,NULL);
 INSERT INTO ew_financeiro_interna.titulos VALUES
 (t,e,'PAGAR','MANUAL',NULL,'2026-11-10','Energia','AFOGADOS',5000,'Energia do período'),
 (t2,e,'RECEBER','MANUAL',NULL,'2026-11-10','Outras receitas','GERAL',1000,'Receita complementar'),
 (t3,e,'PAGAR','DESPESA_OBRA',NULL,'2026-11-10','aluminio','GERAL',5000,'Compra de material'),
 (t4,e,'PAGAR','MANUAL',NULL,'2026-10-10','Energia','GERAL',999,'Fora do período');
 r:=public.ew_dre_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'manuais_pendentes')::int<>2 OR (r->>'material_reconhecido_centavos')::bigint<>0 OR (r->>'materiais_disponiveis_total')::int<>1 THEN RAISE EXCEPTION 'base inicial incorreta: %',r;END IF;
 PERFORM public.ew_dre_classificar_titulo(e,t,op_id,0,'CUSTO_INDIRETO','Custo reconhecido na competência');
 r:=public.ew_dre_classificar_titulo(e,t,op_id,0,'CUSTO_INDIRETO','Custo reconhecido na competência');IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'idempotência classificação';END IF;
 negado:=false;BEGIN PERFORM public.ew_dre_classificar_titulo(e,t,gen_random_uuid(),0,'DESPESA_ADMIN','Versão anterior');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Classificação foi alterada%';END;
 IF NOT negado THEN RAISE EXCEPTION 'revisão concorrente não bloqueada';END IF;
 negado:=false;BEGIN PERFORM public.ew_dre_classificar_titulo(e,t3,gen_random_uuid(),0,'CUSTO_INDIRETO','Compra de material');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Somente títulos manuais%';END;
 IF NOT negado THEN RAISE EXCEPTION 'compra duplicada na DRE';END IF;
 PERFORM public.ew_dre_classificar_titulo(e,t2,gen_random_uuid(),0,'RECEITA_OPERACIONAL','Receita não registrada na obra');
 negado:=false;BEGIN PERFORM public.ew_dre_reconhecer_material(e,m,f2,gen_random_uuid(),100,'Documento errado');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Faturamento não contém%';END;
 IF NOT negado THEN RAISE EXCEPTION 'código de esquadria incompatível';END IF;
 negado:=false;BEGIN PERFORM public.ew_dre_reconhecer_material(e,m,inst,gen_random_uuid(),100,'Documento errado');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Faturamento incompatível%';END;
 IF NOT negado THEN RAISE EXCEPTION 'instalação indevidamente aceita';END IF;
 op_id:=gen_random_uuid();r:=public.ew_dre_reconhecer_material(e,m,f,op_id,1000,'Material vendido parcialmente');rec:=(r->>'id')::uuid;
 r:=public.ew_dre_reconhecer_material(e,m,f,op_id,1000,'Material vendido parcialmente');IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'idempotência reconhecimento';END IF;
 negado:=false;BEGIN PERFORM public.ew_dre_reconhecer_material(e,m,f,gen_random_uuid(),1001,'Valor acima do custo');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Reconhecimento supera%';END;
 IF NOT negado THEN RAISE EXCEPTION 'custo duplicado';END IF;
 r:=public.ew_dre_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'fabricacao_centavos')::bigint<>15000 OR (r->>'instalacao_centavos')::bigint<>3000 OR (r->>'material_reconhecido_centavos')::bigint<>1000 OR (r->>'manuais_pendentes')::int<>0 OR (r->'classes'->>'CUSTO_INDIRETO')::bigint<>5000 OR (r->'classes'->>'RECEITA_OPERACIONAL')::bigint<>1000 THEN RAISE EXCEPTION 'DRE incorreta: %',r;END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado',cancelado_em=now() WHERE id=f;
 r:=public.ew_dre_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'reconhecimentos_pendentes')::int<>1 OR (r->>'material_reconhecido_centavos')::bigint<>0 THEN RAISE EXCEPTION 'origem cancelada permanece na DRE';END IF;
 UPDATE public.ew_obra_faturamentos SET status='emitido',cancelado_em=NULL WHERE id=f;
 PERFORM public.ew_dre_estornar_material(e,rec,gen_random_uuid(),'Reconhecimento incorreto');
 r:=public.ew_dre_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'material_reconhecido_centavos')::bigint<>0 OR (r->'materiais'->0->>'saldo_centavos')::bigint<>2000 THEN RAISE EXCEPTION 'estorno não recompõe saldo';END IF;
 INSERT INTO public.test_race VALUES(m,f);
 negado:=false;BEGIN PERFORM public.ew_dre_consultar(e2,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso cruzado';END IF;
 PERFORM set_config('test.perm','no',true);
 negado:=false;BEGIN PERFORM public.ew_dre_reconhecer_material(e,m,f,gen_random_uuid(),100,'Sem permissão');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'sem flags gravou';END IF;
END $$;
SELECT 'OK: classificação, reconhecimento, idempotência, estornos e DRE por competência' AS resultado;
