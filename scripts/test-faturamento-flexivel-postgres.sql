-- Banco descartável exclusivo dos testes. Não executar em produção.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_permissao(text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('test.perm',true) IS DISTINCT FROM 'yes' THEN RAISE EXCEPTION 'Sem permissão'; END IF; END $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida'; END IF; END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql AS $$ SELECT current_setting('test.perm',true)='yes' $$;
CREATE TABLE public.usuarios_empresas(usuario_id uuid,empresa_id uuid);
CREATE TABLE public.obras(id uuid PRIMARY KEY,empresa_id uuid,arquivada_em timestamptz);
CREATE TABLE public.esquadrias(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,codigo text,quantidade integer,largura_mm numeric,altura_mm numeric);
CREATE TABLE public.ew_obra_orcamento(empresa_id uuid,obra_id uuid,fabricacao numeric,instalacao numeric);
CREATE TABLE public.ew_precificacao_revisoes(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,estado text,versao int,fabricacao_distribuida_centavos bigint,instalacao_distribuida_centavos bigint);
CREATE TABLE public.ew_precificacao_revisoes_itens(revisao_id uuid,empresa_id uuid,obra_id uuid,esquadria_id uuid,quantidade integer,largura_mm numeric,altura_mm numeric,area_m2 numeric(20,6),fabricacao_centavos bigint,instalacao_centavos bigint);
CREATE TABLE public.ew_obra_faturamentos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid,obra_id uuid,categoria text,data_faturamento date,numero_documento text,observacoes text,valor_total numeric(14,2) CHECK(valor_total>0),criado_por uuid,operacao_id uuid,status text DEFAULT 'emitido',cancelado_por uuid,cancelado_em timestamptz,UNIQUE(empresa_id,operacao_id));
CREATE TABLE public.ew_obra_faturamentos_itens(faturamento_id uuid,empresa_id uuid,esquadria_id uuid,quantidade numeric(14,6) CHECK(quantidade>0),valor_unitario numeric(14,4) CHECK(valor_unitario>0),valor_total numeric(14,2) CHECK(valor_total>0),area_m2 numeric(18,6),preco_m2 numeric(16,4));
CREATE TABLE public.romaneios(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,status text,cancelado_em timestamptz);
CREATE TABLE public.romaneios_itens(romaneio_id uuid,esquadria_id uuid,natureza text,tipo_saida text,quantidade numeric,composicao_revisao_id uuid,equivalente_expedido numeric);
CREATE TABLE public.esquadrias_saida_config(esquadria_id uuid,folhas_por_unidade int);
\ir ../database/proposals/20261128_faturamento_flexivel_v462937.sql
INSERT INTO public.usuarios_empresas VALUES('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
INSERT INTO public.obras(id,empresa_id) VALUES('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002');
INSERT INTO public.esquadrias VALUES
 ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','EA',1,1000,1000),
 ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','EB',1,1000,1000);
INSERT INTO public.ew_obra_orcamento VALUES('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003',1000,200);
INSERT INTO public.ew_precificacao_revisoes VALUES('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','aprovada',1,100000,20000);
INSERT INTO public.ew_precificacao_revisoes_itens SELECT '00000000-0000-0000-0000-000000000004',empresa_id,obra_id,id,quantidade,largura_mm,altura_mm,1,50000,10000 FROM public.esquadrias;
INSERT INTO public.romaneios(id,empresa_id,obra_id,status) VALUES('00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','emitido');
INSERT INTO public.romaneios_itens(romaneio_id,esquadria_id,natureza,tipo_saida,quantidade) SELECT '00000000-0000-0000-0000-000000000005',id,'esquadria','completo',1 FROM public.esquadrias;
CREATE FUNCTION public.test_fatura(cod text,area numeric,preco numeric,modo text,centavos bigint,saldo bigint,tipo text DEFAULT 'fabricacao',op uuid DEFAULT gen_random_uuid()) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.ew_registrar_faturamento_financeiro('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003',tipo,'2026-11-28','TESTE','',
 jsonb_build_array(jsonb_build_object('esquadria_id','00000000-0000-0000-0000-00000000000'||cod,'quantidade',area,'valor_unitario',preco,'area_m2',area,'preco_m2',preco)||CASE WHEN modo IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('modo_preco',modo,'valor_centavos',centavos,'saldo_antes_centavos',saldo) END),op,true)
$$;
SET test.uid='00000000-0000-0000-0000-000000000001';
SET test.perm='yes';
DO $$
DECLARE r jsonb; b uuid; op uuid:=gen_random_uuid(); blocked boolean;
BEGIN
 IF has_function_privilege('anon','public.ew_registrar_faturamento_financeiro(uuid,uuid,text,date,text,text,jsonb,uuid,boolean)','EXECUTE') THEN RAISE EXCEPTION 'anon indevidamente autorizado';END IF;
 r:=public.test_fatura('a',.25,800,'manual',20000,100000,'fabricacao',op);
 IF (r->>'valor_total')::numeric<>200 THEN RAISE EXCEPTION 'antecipação incorreta';END IF;
 r:=public.test_fatura('a',.25,800,'manual',20000,100000,'fabricacao',op);
 IF NOT (r->>'ja_registrado')::boolean THEN RAISE EXCEPTION 'idempotência perdida';END IF;
 blocked:=false;BEGIN PERFORM public.test_fatura('b',1,800,'manual',80000,80000);EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'Reserve saldo%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'consumo de todo saldo com área aberta não bloqueado';END IF;
 blocked:=false;BEGIN PERFORM public.test_fatura('b',1,457.14,'auto',45714,100000);EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'Saldo ou valor%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'saldo antigo não bloqueado';END IF;
 r:=public.test_fatura('b',1,457.14,'auto',45714,80000);b:=(r->>'id')::uuid;
 IF (r->>'valor_total')::numeric<>457.14 THEN RAISE EXCEPTION 'compensação cruzada incorreta';END IF;
 blocked:=false;BEGIN PERFORM public.test_fatura('a',.75,400,'manual',30000,34286);EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'Último faturamento%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'fechamento incompleto não bloqueado';END IF;
 r:=public.test_fatura('a',.75,457.1467,'auto',34286,34286);
 IF (r->>'valor_total')::numeric<>342.86 THEN RAISE EXCEPTION 'últimos centavos incorretos';END IF;
 IF (SELECT sum(valor_total) FROM public.ew_obra_faturamentos WHERE status='emitido' AND categoria='fabricacao')<>1000 THEN RAISE EXCEPTION 'contrato não fechado';END IF;
 r:=public.test_fatura('a',1,100,'auto',10000,20000,'instalacao');
 IF (r->>'valor_total')::numeric<>100 THEN RAISE EXCEPTION 'instalação afetada indevidamente';END IF;
 PERFORM public.ew_cancelar_faturamento_financeiro('00000000-0000-0000-0000-000000000002',b,'Estorno para teste');
 r:=public.test_fatura('b',1,457.14,'auto',45714,45714);
 IF (r->>'valor_total')::numeric<>457.14 THEN RAISE EXCEPTION 'saldo não restaurado após estorno';END IF;
 PERFORM set_config('test.perm','no',true);
 blocked:=false;BEGIN PERFORM public.test_fatura('b',1,100,'auto',10000,10000,'instalacao');EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT blocked THEN RAISE EXCEPTION 'permissão não respeitada';END IF;
 PERFORM set_config('test.perm','yes',true);
 -- Segunda categoria ficou com saldo 100; chamada antiga sem modo ainda é compatível.
 r:=public.test_fatura('b',.25,100,NULL,0,0,'instalacao');
 IF (r->>'valor_total')::numeric<>25 THEN RAISE EXCEPTION 'cliente anterior incompatível';END IF;
END $$;
-- Reiniciar somente dados do banco de teste para a corrida de duas conexões.
TRUNCATE public.ew_obra_faturamentos_itens,public.ew_obra_faturamentos;
SELECT 'OK: antecipação, compensação entre códigos, fechamento, estorno, categoria e permissões' AS resultado;
