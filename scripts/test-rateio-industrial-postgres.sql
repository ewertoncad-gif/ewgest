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
CREATE TABLE public.liberacoes_corte(id uuid PRIMARY KEY,esquadria_id uuid,cancelado_em timestamptz,fabrica text,quantidade int,tipo_componente text,data_liberacao date);
CREATE TABLE public.ew_liberacoes_lotes(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,cancelado_em timestamptz,fabrica text);
CREATE TABLE public.ew_estoque_obras_movimentos(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,origem text,quantidade_delta numeric,liberacao_id uuid,lote_id uuid,local_estoque text,estorno_de_id uuid,criado_em timestamptz);
CREATE TABLE public.ew_estornos_parcelas(empresa_id uuid,movimento_original_id uuid,movimento_estorno_id uuid,quantidade numeric);
CREATE TABLE ew_compras_interna.custo_consumos_integrados(empresa_id uuid,movimento_id uuid,operacao_custo uuid,quantidade numeric,estornado_em timestamptz);
CREATE TABLE ew_compras_interna.custo_eventos(empresa_id uuid,lote_id uuid,operacao_id uuid,quantidade numeric,destino_tipo text,destino_id uuid,destino_galpao text,custo_centavos bigint,estornado_em timestamptz);
CREATE TABLE ew_compras_interna.custo_lotes(empresa_id uuid,lote_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,quantidade numeric,custo_centavos bigint,categoria text,cancelado_em timestamptz);
CREATE TABLE ew_compras_interna.lotes_aquisicao_evidencias(empresa_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,quantidade numeric,custo_centavos bigint,categoria text);
CREATE TABLE ew_financeiro_interna.titulos(id uuid PRIMARY KEY,empresa_id uuid,tipo text,origem_tipo text,cancelado_em timestamptz,competencia date,categoria text,centro_custo text,valor_centavos bigint,descricao text,galpao_id uuid,UNIQUE(empresa_id,id));
CREATE FUNCTION ew_financeiro_interna.exigir(p_empresa uuid) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN PERFORM public.ew_exigir_sessao_atual(); IF NOT public.ew_pode(p_empresa,'financeiro.consultar') OR NOT public.ew_pode(p_empresa,'relatorios.financeiros') THEN RAISE EXCEPTION 'Sem acesso'; END IF; END $$;
\ir ../database/proposals/20261128_resultados_gerenciais_v462940.sql
\ir ../database/proposals/20261128_dre_classificacao_v462941.sql
\ir ../database/proposals/20261128_rateio_industrial_v462942.sql
\ir ../database/proposals/20261128_rateio_lote_v462947.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.perm='yes';
CREATE TABLE public.test_rateio_race(titulo_id uuid,liberacao_id uuid,versao int);
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';e2 uuid:=gen_random_uuid();o uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();l uuid:=gen_random_uuid();l2 uuid:=gen_random_uuid();t uuid:=gen_random_uuid();t2 uuid:=gen_random_uuid();g uuid:=gen_random_uuid();f uuid:=gen_random_uuid();rom uuid:=gen_random_uuid();m uuid:=gen_random_uuid();op uuid:=gen_random_uuid();lt uuid:=gen_random_uuid();item uuid:=gen_random_uuid();orig uuid:=gen_random_uuid();op_id uuid:=gen_random_uuid();rid uuid;r jsonb;negado boolean;
BEGIN
 IF has_function_privilege('anon','public.ew_rateio_industrial_consultar(uuid,date,date)','EXECUTE') OR has_table_privilege('authenticated','ew_financeiro_interna.rateios_industriais','SELECT') THEN RAISE EXCEPTION 'acesso direto indevido';END IF;
 INSERT INTO public.obras VALUES(o,e,'Obra A','A');
 INSERT INTO public.esquadrias VALUES(a,e,o,'EA',1000,1000),(b,e,o,'EB',1000,1000);
 INSERT INTO public.liberacoes_corte VALUES(l,a,NULL,'AFOGADOS',1,'completo','2026-11-01'),(l2,b,NULL,'IMBIRIBEIRA',1,'completo','2026-11-01');
 INSERT INTO public.romaneios VALUES(rom,e,o,'emitido',NULL,'2026-11-09','2026-11-09T10:00:00Z');
 INSERT INTO public.romaneios_itens VALUES(rom,'esquadria',a,'AFOGADOS',1);
 INSERT INTO public.ew_obra_faturamentos VALUES(f,e,o,'fabricacao',100,'emitido',NULL,'2026-11-10','2026-11-10T10:00:00Z','001');
 INSERT INTO public.ew_obra_faturamentos_itens VALUES(f,e,a,1,100,1);
 INSERT INTO public.ew_estoque_obras_movimentos VALUES(m,e,o,'PLANO_CORTE',-2,l,NULL,'ESTOQUE CENTRAL',NULL,'2026-11-05T10:00:00Z');
 INSERT INTO ew_compras_interna.custo_consumos_integrados VALUES(e,m,op,2,NULL);
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,lt,'NFE_DIRETA',item,orig,10,10000,'aluminio',NULL);
 INSERT INTO ew_compras_interna.lotes_aquisicao_evidencias VALUES(e,'NFE_DIRETA',item,orig,10,10000,'aluminio');
 INSERT INTO ew_compras_interna.custo_eventos VALUES(e,lt,op,2,'PRODUCAO',o,'ESTOQUE CENTRAL',2000,NULL);
 PERFORM public.ew_dre_reconhecer_material(e,m,f,gen_random_uuid(),2000,'Material vendido');
 INSERT INTO ew_financeiro_interna.titulos VALUES(t,e,'PAGAR','MANUAL',NULL,'2026-11-30','Salários','AFOGADOS',5000,'Folha industrial',g),(t2,e,'PAGAR','MANUAL',NULL,'2026-11-30','Energia','GERAL',3000,'Energia industrial',NULL);
 PERFORM public.ew_dre_classificar_titulo(e,t,gen_random_uuid(),0,'CUSTO_MAO_OBRA','Folha reconhecida');
 PERFORM public.ew_dre_classificar_titulo(e,t2,gen_random_uuid(),0,'CUSTO_INDIRETO','Energia reconhecida');
 r:=public.ew_rateio_industrial_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'receita_centavos')::bigint<>10000 OR (r->>'material_centavos')::bigint<>2000 OR (r->>'industrial_classificado_centavos')::bigint<>8000 OR (r->>'rateado_centavos')::bigint<>0 THEN RAISE EXCEPTION 'base incorreta: %',r;END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_criar(e,t,l2,1,gen_random_uuid(),100,'Fábrica errada');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'A fábrica não corresponde%';END;
 IF NOT negado THEN RAISE EXCEPTION 'centro de custo desrespeitado';END IF;
 r:=public.ew_rateio_industrial_criar(e,t,l,1,op_id,3000,'Horas trabalhadas');rid:=(r->>'id')::uuid;
 r:=public.ew_rateio_industrial_criar(e,t,l,1,op_id,3000,'Horas trabalhadas');IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'idempotência';END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_criar(e,t,l,1,gen_random_uuid(),2001,'Acima do saldo');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Rateio supera%';END;
 IF NOT negado THEN RAISE EXCEPTION 'rateio excedente';END IF;
 PERFORM public.ew_rateio_industrial_criar(e,t2,l,1,gen_random_uuid(),1000,'Rateio de energia');
 r:=public.ew_rateio_industrial_consultar(e,'2026-11-01','2026-11-30');
 IF (r->>'rateado_centavos')::bigint<>4000 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'itens') x WHERE x->>'codigo'='EA' AND (x->>'receita_centavos')::bigint=10000 AND (x->>'material_centavos')::bigint=2000 AND (x->>'rateio_centavos')::bigint=4000) THEN RAISE EXCEPTION 'contribuição por código incorreta: %',r;END IF;
 r:=public.ew_dre_consultar(e,'2026-11-01','2026-11-30');IF (r->'classes'->>'CUSTO_MAO_OBRA')::bigint<>5000 OR (r->'classes'->>'CUSTO_INDIRETO')::bigint<>3000 THEN RAISE EXCEPTION 'rateio duplicou DRE';END IF;
 PERFORM public.ew_dre_classificar_titulo(e,t,gen_random_uuid(),1,'CUSTO_MAO_OBRA','Revisão de classificação');
 r:=public.ew_rateio_industrial_consultar(e,'2026-11-01','2026-11-30');IF (r->>'rateios_pendentes')::int<>1 OR (r->>'rateado_centavos')::bigint<>1000 THEN RAISE EXCEPTION 'classificação alterada não sinalizada';END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_criar(e,t,l,2,gen_random_uuid(),100,'Versão revisada');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Revise e estorne%';END;
 IF NOT negado THEN RAISE EXCEPTION 'rateio anterior não reservado';END IF;
 PERFORM public.ew_rateio_industrial_estornar(e,rid,gen_random_uuid(),'Revisão de rateio');
 INSERT INTO public.test_rateio_race VALUES(t,l,2);
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_consultar(e2,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso cruzado';END IF;
END $$;
SELECT 'OK: rateio por liberação, classificação, centro de custo, contribuição e DRE sem duplicidade' AS resultado;

DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';t uuid:=gen_random_uuid();a uuid;b uuid;op uuid:=gen_random_uuid();sel jsonb;p jsonb;r jsonb;negado boolean;
BEGIN
 SELECT id INTO a FROM public.liberacoes_corte WHERE fabrica='AFOGADOS' LIMIT 1;
 SELECT id INTO b FROM public.liberacoes_corte WHERE fabrica='IMBIRIBEIRA' LIMIT 1;
 UPDATE public.esquadrias SET largura_mm=2000 WHERE id=(SELECT esquadria_id FROM public.liberacoes_corte WHERE id=b);
 INSERT INTO ew_financeiro_interna.titulos VALUES(t,e,'PAGAR','MANUAL',NULL,'2026-11-30','Energia','GERAL',101,'Energia lote',NULL);
 PERFORM public.ew_dre_classificar_titulo(e,t,gen_random_uuid(),0,'CUSTO_INDIRETO','Energia reconhecida');
 sel:=jsonb_build_array(jsonb_build_object('id',a,'peso_kg',1),jsonb_build_object('id',b,'peso_kg',3));
 IF has_function_privilege('anon','public.ew_rateio_industrial_lote(uuid,uuid,int,uuid,text,jsonb,text,boolean,jsonb)','EXECUTE') OR has_table_privilege('authenticated','ew_financeiro_interna.rateios_lotes','SELECT') THEN RAISE EXCEPTION 'acesso direto indevido';END IF;
 p:=public.ew_rateio_industrial_lote(e,t,1,op,'PESO_INFORMADO',sel,'Peso informado',false,NULL);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'linhas') x WHERE (x->>'id')::uuid=b AND (x->>'centavos')::int=76) THEN RAISE EXCEPTION 'peso incorreto %',p;END IF;
 p:=public.ew_rateio_industrial_lote(e,t,1,op,'QUANTIDADE',sel,'Quantidade',false,NULL);
 IF (SELECT sum((x->>'centavos')::int) FROM jsonb_array_elements(p->'linhas') x)<>101 THEN RAISE EXCEPTION 'centavos';END IF;
 p:=public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Área liberada',false,NULL);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'linhas') x WHERE (x->>'id')::uuid=b AND (x->>'centavos')::int=67) THEN RAISE EXCEPTION 'area incorreta %',p;END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.rateios_industriais WHERE titulo_id=t) THEN RAISE EXCEPTION 'previa gravou';END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Área liberada',true,'[]');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Saldo ou critérios%';END;
 IF NOT negado THEN RAISE EXCEPTION 'previa divergente aceita';END IF;
 r:=public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Área liberada',true,p->'linhas');
 IF (SELECT sum(valor_centavos) FROM ew_financeiro_interna.rateios_industriais WHERE titulo_id=t)<>101 THEN RAISE EXCEPTION 'lote não fecha';END IF;
 r:=public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Área liberada',true,p->'linhas');
 IF NOT (r->>'repetido')::boolean OR (SELECT count(*) FROM ew_financeiro_interna.rateios_industriais WHERE titulo_id=t)<>2 THEN RAISE EXCEPTION 'repetição duplicou';END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Outra justificativa',true,p->'linhas');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Identificador do lote%';END;
 IF NOT negado THEN RAISE EXCEPTION 'reuso de lote alterado';END IF;
 SET LOCAL test.perm='no';
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_lote(e,t,1,op,'AREA',sel,'Área liberada',true,p->'linhas');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'permissao indevida';END IF;
 SET LOCAL test.perm='yes';
END $$;
SELECT 'OK: lote atomico, area, peso informado, previa, centavos e idempotencia' AS resultado;

ALTER TABLE public.ew_estoque_obras_movimentos ADD COLUMN variacao_id uuid, ADD COLUMN comprimento_mm integer, ADD COLUMN unidade text;
CREATE TABLE public.ew_materiais_variacoes(id uuid PRIMARY KEY,empresa_id uuid,tipo text,perfil_id uuid);
CREATE TABLE public.ew_perfis(id uuid PRIMARY KEY,empresa_id uuid,peso_kg_m numeric);
\ir ../database/proposals/20261128_indicadores_industriais_v462949.sql
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';v uuid:=gen_random_uuid();p uuid:=gen_random_uuid();v2 uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();m uuid;l uuid;o uuid;r jsonb;row jsonb;negado boolean;
BEGIN
 INSERT INTO public.ew_perfis VALUES(p,e,0.5),(p2,e,NULL);
 INSERT INTO public.ew_materiais_variacoes VALUES(v,e,'perfil',p),(v2,e,'perfil',p2);
 SELECT id,liberacao_id,obra_id INTO m,l,o FROM public.ew_estoque_obras_movimentos WHERE origem='PLANO_CORTE' LIMIT 1;
 UPDATE public.ew_estoque_obras_movimentos SET variacao_id=v,comprimento_mm=6000,unidade='BARRA' WHERE id=m;
 INSERT INTO public.ew_estoque_obras_movimentos(id,empresa_id,obra_id,origem,quantidade_delta,liberacao_id,criado_em,variacao_id,unidade,comprimento_mm) VALUES(gen_random_uuid(),e,o,'PLANO_CORTE',-3,l,'2026-11-05T10:00:00Z',v,'KG',NULL),(gen_random_uuid(),e,o,'PLANO_CORTE',-1,l,'2026-11-05T10:00:00Z',v2,'BARRA',6000);
 r:=public.ew_indicadores_industriais(e,'2026-11-01','2026-11-30');
 SELECT x INTO row FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='AFOGADOS';
 IF (row->>'kg_estimado')::numeric IS DISTINCT FROM 6::numeric OR (row->>'kg_registrado')::numeric IS DISTINCT FROM 3::numeric OR (row->>'peso_pendente')::int IS DISTINCT FROM 1 OR (row->>'area_m2')::numeric IS DISTINCT FROM 1::numeric THEN RAISE EXCEPTION 'indicadores incorretos %',r;END IF;
 INSERT INTO public.ew_estoque_obras_movimentos(id,empresa_id,obra_id,origem,quantidade_delta,estorno_de_id,criado_em) VALUES(gen_random_uuid(),e,o,'ESTORNO',1,m,'2026-11-06T10:00:00Z');
 r:=public.ew_indicadores_industriais(e,'2026-11-01','2026-11-30');
 SELECT x INTO row FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='AFOGADOS';
 IF (row->>'kg_estimado')::numeric IS DISTINCT FROM 3::numeric THEN RAISE EXCEPTION 'estorno incorreto %',r;END IF;
 -- Restaurar a fixture usada pelo teste concorrente (nenhum rateio é alterado).
 IF has_function_privilege('anon','public.ew_indicadores_industriais(uuid,date,date)','EXECUTE') THEN RAISE EXCEPTION 'acesso anonimo';END IF;
 SET LOCAL test.perm='no';negado:=false;BEGIN PERFORM public.ew_indicadores_industriais(e,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'permissao indevida';END IF;
END $$;
SELECT 'OK: peso registrado, estimado, pendências, estorno e área atribuída' AS resultado;

\ir ../database/proposals/20261128_peso_historico_v462950.sql
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001'; o uuid; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); la uuid:=gen_random_uuid(); lb uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); t uuid:=gen_random_uuid(); op uuid:=gen_random_uuid(); sel jsonb; r jsonb; negado boolean;
BEGIN
 SELECT id INTO o FROM public.obras WHERE empresa_id=e LIMIT 1;
 INSERT INTO public.esquadrias VALUES(a,e,o,'H1',1000,1000),(b,e,o,'H2',1000,1000);
 INSERT INTO public.liberacoes_corte VALUES(la,a,NULL,'AFOGADOS',1,'completo','2026-11-10'),(lb,b,NULL,'IMBIRIBEIRA',1,'completo','2026-11-10');
 INSERT INTO public.ew_perfis VALUES(p,e,0.5);
 INSERT INTO public.ew_materiais_variacoes VALUES(v,e,'perfil',p);
 INSERT INTO public.ew_estoque_obras_movimentos(id,empresa_id,obra_id,origem,quantidade_delta,liberacao_id,criado_em,variacao_id,unidade,comprimento_mm)
 VALUES(m,e,o,'PLANO_CORTE',-2,la,'2026-11-10T10:00:00Z',v,'BARRA',6000),
 (gen_random_uuid(),e,o,'PLANO_CORTE',-3,lb,'2026-11-10T10:00:00Z',v,'KG',NULL);
 UPDATE public.ew_perfis SET peso_kg_m=1 WHERE id=p;
 IF ew_compras_interna.peso_liberacao(e,la,'2026-11-30') IS DISTINCT FROM 6::numeric OR ew_compras_interna.peso_liberacao(e,lb,'2026-11-30') IS DISTINCT FROM 3::numeric THEN RAISE EXCEPTION 'peso histórico alterado';END IF;
 INSERT INTO ew_financeiro_interna.titulos VALUES(t,e,'PAGAR','MANUAL',NULL,'2026-11-30','Energia','GERAL',101,'Energia peso',NULL);
 PERFORM public.ew_dre_classificar_titulo(e,t,gen_random_uuid(),0,'CUSTO_INDIRETO','Energia reconhecida');
 sel:=jsonb_build_array(jsonb_build_object('id',la,'peso_kg',null),jsonb_build_object('id',lb,'peso_kg',null));
 r:=public.ew_rateio_industrial_lote(e,t,1,op,'PESO_CONSUMO',sel,'Peso histórico',false,NULL);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'linhas') x WHERE (x->>'id')::uuid=la AND (x->>'centavos')::int=67) THEN RAISE EXCEPTION 'rateio por consumo incorreto %',r;END IF;
 INSERT INTO public.ew_estoque_obras_movimentos(id,empresa_id,obra_id,origem,quantidade_delta,estorno_de_id,criado_em) VALUES(gen_random_uuid(),e,o,'ESTORNO',1,m,'2026-11-11T10:00:00Z');
 IF ew_compras_interna.peso_liberacao(e,la,'2026-11-30') IS DISTINCT FROM 3::numeric THEN RAISE EXCEPTION 'peso não estornado';END IF;
 negado:=false;BEGIN PERFORM public.ew_rateio_industrial_lote(e,t,1,op,'PESO_CONSUMO',sel,'Peso histórico',true,r->'linhas');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Saldo ou critérios%';END;
 IF NOT negado THEN RAISE EXCEPTION 'prévia antiga aceita';END IF;
 r:=public.ew_rateio_industrial_lote(e,t,1,op,'PESO_CONSUMO',sel,'Peso histórico',false,NULL);
 PERFORM public.ew_rateio_industrial_lote(e,t,1,op,'PESO_CONSUMO',sel,'Peso histórico',true,r->'linhas');
 IF (SELECT sum(valor_centavos) FROM ew_financeiro_interna.rateios_industriais WHERE titulo_id=t)<>101 THEN RAISE EXCEPTION 'rateio não fecha';END IF;
 r:=public.ew_indicadores_industriais(e,'2026-11-01','2026-11-30');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='AFOGADOS' AND (x->>'kg_historico')::numeric=3) THEN RAISE EXCEPTION 'indicador histórico incorreto %',r;END IF;
 IF has_table_privilege('authenticated','ew_compras_interna.pesos_consumo','SELECT') THEN RAISE EXCEPTION 'acesso direto indevido';END IF;
END $$;
SELECT 'OK: histórico congelado, estorno, rateio por consumo e prévia invalidada' AS resultado;

\ir ../database/proposals/20261128_produtividade_v462951.sql
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';o uuid;esq uuid:=gen_random_uuid();lib uuid:=gen_random_uuid();rom uuid:=gen_random_uuid();r jsonb;
BEGIN
 SELECT id INTO o FROM public.obras WHERE empresa_id=e LIMIT 1;
 INSERT INTO public.esquadrias VALUES(esq,e,o,'PROD',2000,1500);
 INSERT INTO public.liberacoes_corte VALUES(lib,esq,NULL,'TESTE-PROD',2,'completo','2026-11-20');
 INSERT INTO public.romaneios VALUES(rom,e,o,'emitido',NULL,'2026-11-21','2026-11-21T10:00:00Z');
 INSERT INTO public.romaneios_itens VALUES(rom,'esquadria',esq,'TESTE-PROD',3);
 r:=public.ew_industrial_produtividade(e,'2026-11-20','2026-11-21');
 IF (r->>'dias')::int<>2 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='TESTE-PROD' AND (x->>'area_liberada')::numeric=6 AND (x->>'area_expedida')::numeric=3 AND (x->>'unidades_liberadas')::int=2) THEN RAISE EXCEPTION 'produtividade incorreta %',r;END IF;
 UPDATE public.romaneios SET cancelado_em=now() WHERE id=rom;
 r:=public.ew_industrial_produtividade(e,'2026-11-20','2026-11-21');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='TESTE-PROD' AND (x->>'area_expedida')::numeric=0) THEN RAISE EXCEPTION 'cancelamento ignorado';END IF;
END $$;
SELECT 'OK: produtividade por fábrica, período, dimensões e cancelamentos' AS resultado;

CREATE TABLE public.ew_locais_fisicos(id uuid PRIMARY KEY,empresa_id uuid,nome text,ativo boolean);
\ir ../database/proposals/20261128_horas_industriais_v462952.sql
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';g uuid:=gen_random_uuid();op uuid:=gen_random_uuid();rev uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 INSERT INTO public.ew_locais_fisicos VALUES(g,e,'AFOGADOS',true);
 PERFORM public.ew_industrial_registrar_horas(e,op,g,'2026-11-20',480,'Apontamento diário');
 r:=public.ew_industrial_registrar_horas(e,op,g,'2026-11-20',480,'Apontamento diário');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'duplicidade';END IF;
 negado:=false;BEGIN PERFORM public.ew_industrial_registrar_horas(e,gen_random_uuid(),g,'2026-11-20',480,'Outro registro');EXCEPTION WHEN unique_violation THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'dia duplicado';END IF;
 PERFORM public.ew_industrial_estornar_horas(e,rev,op,'Corrigir apontamento');
 r:=public.ew_industrial_estornar_horas(e,rev,op,'Corrigir apontamento');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'estorno não idempotente';END IF;
 PERFORM public.ew_industrial_registrar_horas(e,gen_random_uuid(),g,'2026-11-20',600,'Registro corrigido');
 PERFORM public.ew_industrial_registrar_horas(e,gen_random_uuid(),g,'2026-11-21',0,'Sem trabalho');
 r:=public.ew_industrial_horas_consultar(e,'2026-11-20','2026-11-21');
 IF (r->>'total')::int<>3 OR (r->'totais'->0->>'minutos')::bigint<>600 OR (r->'totais'->0->>'dias_informados')::int<>2 THEN RAISE EXCEPTION 'total incorreto %',r;END IF;
 IF has_table_privilege('authenticated','ew_financeiro_interna.horas_industriais','SELECT') OR has_function_privilege('anon','public.ew_industrial_horas_consultar(uuid,date,date)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
 SET LOCAL test.perm='no';negado:=false;BEGIN PERFORM public.ew_industrial_horas_consultar(e,'2026-11-20','2026-11-21');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'permissão indevida';END IF;
END $$;
SELECT 'OK: horas agregadas, estorno, idempotência e permissões' AS resultado;

\ir ../database/proposals/20261128_pessoal_patrimonio_v462953.sql
CREATE OR REPLACE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT $1='00000000-0000-0000-0000-000000000001' AND current_setting('test.perm',true)='yes' AND ($2<>'usuarios.gerenciar' OR current_setting('test.rh',true)='yes') $$;
SET test.perm='yes';
SET test.rh='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';g uuid;emp uuid:=gen_random_uuid();folha uuid:=gen_random_uuid();ativo uuid:=gen_random_uuid();dep uuid:=gen_random_uuid();rev uuid:=gen_random_uuid();dados jsonb;r jsonb;negado boolean;
BEGIN
 SELECT id INTO g FROM public.ew_locais_fisicos WHERE empresa_id=e LIMIT 1;
 dados:=jsonb_build_object('galpao_id',g,'codigo','F001','nome','Funcionário teste','funcao','Operador','data','2026-09-01');
 PERFORM public.ew_industrial_cadastrar(e,emp,'FUNCIONARIO',dados);
 r:=public.ew_industrial_cadastrar(e,emp,'FUNCIONARIO',dados);
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'cadastro duplicado';END IF;
 dados:=jsonb_build_object('galpao_id',g,'data','2026-11-01','salarios',10000,'encargos',3000,'beneficios',2000,'referencia','Folha teste');
 PERFORM public.ew_industrial_cadastrar(e,folha,'FOLHA',dados);
 negado:=false;BEGIN PERFORM public.ew_industrial_cadastrar(e,gen_random_uuid(),'FOLHA',dados);EXCEPTION WHEN unique_violation THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'folha duplicada';END IF;
 PERFORM public.ew_industrial_estornar_folha(e,rev,folha,'Correção da folha');
 r:=public.ew_industrial_estornar_folha(e,rev,folha,'Correção da folha');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'estorno repetido';END IF;
 PERFORM public.ew_industrial_cadastrar(e,gen_random_uuid(),'FOLHA',dados||'{"salarios":12000}');
 dados:=jsonb_build_object('galpao_id',g,'codigo','MAQ-1','nome','Máquina teste','data','2026-09-01','valor',111,'residual',10,'vida',3);
 PERFORM public.ew_industrial_cadastrar(e,ativo,'ATIVO',dados);
 negado:=false;BEGIN PERFORM public.ew_industrial_depreciar(e,gen_random_uuid(),ativo,'2026-10-01');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Registre as competências%';END;
 IF NOT negado THEN RAISE EXCEPTION 'pulou competência';END IF;
 PERFORM public.ew_industrial_depreciar(e,dep,ativo,'2026-09-01');
 r:=public.ew_industrial_depreciar(e,dep,ativo,'2026-09-01');
 IF NOT (r->>'repetido')::boolean OR (r->>'valor_centavos')::bigint<>34 THEN RAISE EXCEPTION 'primeira depreciação incorreta %',r;END IF;
 PERFORM public.ew_industrial_depreciar(e,gen_random_uuid(),ativo,'2026-10-01');
 PERFORM public.ew_industrial_depreciar(e,gen_random_uuid(),ativo,'2026-11-01');
 IF (SELECT sum(valor_centavos) FROM ew_financeiro_interna.depreciacoes_industriais WHERE ativo_id=ativo)<>101 THEN RAISE EXCEPTION 'depreciação não fecha';END IF;
 r:=public.ew_industrial_cadastros_consultar(e,'2026-09-01','2026-11-30');
 IF jsonb_array_length(r->'funcionarios')<>1 OR jsonb_array_length(r->'folhas')<>2 OR jsonb_array_length(r->'depreciacoes')<>3 THEN RAISE EXCEPTION 'histórico incorreto %',r;END IF;
 SET LOCAL test.rh='no';
 r:=public.ew_industrial_cadastros_consultar(e,'2026-09-01','2026-11-30');
 IF (r->>'pessoal_permitido')::boolean OR jsonb_array_length(r->'funcionarios')<>0 OR jsonb_array_length(r->'folhas')<>0 OR jsonb_array_length(r->'ativos')<>1 THEN RAISE EXCEPTION 'dados de pessoal expostos';END IF;
 negado:=false;BEGIN PERFORM public.ew_industrial_cadastrar(e,gen_random_uuid(),'FOLHA',jsonb_build_object('galpao_id',g,'data','2026-11-01'));EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso à gestão%';END;
 IF NOT negado OR has_table_privilege('authenticated','ew_financeiro_interna.funcionarios_industriais','SELECT') OR has_function_privilege('anon','public.ew_industrial_cadastros_consultar(uuid,date,date)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
END $$;
SELECT 'OK: folha, depreciação, centavos e restrição de dados de pessoal' AS resultado;

\ir ../database/proposals/20261128_movimentacoes_industriais_v462954.sql
\ir ../database/proposals/20261128_conferencia_mensal_v462954.sql
SET test.perm='yes';
SET test.rh='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';g uuid;g2 uuid:=gen_random_uuid();emp uuid;ativo uuid:=gen_random_uuid();op uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 SELECT id INTO g FROM public.ew_locais_fisicos WHERE empresa_id=e AND nome='AFOGADOS' LIMIT 1;
 INSERT INTO public.ew_locais_fisicos VALUES(g2,e,'IMBIRIBEIRA',true);
 SELECT id INTO emp FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=e LIMIT 1;
 PERFORM public.ew_industrial_movimentar(e,op,'FUNCIONARIO',emp,'TRANSFERENCIA','2026-10-01',g2,'Transferência teste');
 r:=public.ew_industrial_movimentar(e,op,'FUNCIONARIO',emp,'TRANSFERENCIA','2026-10-01',g2,'Transferência teste');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'duplicidade';END IF;
 PERFORM public.ew_industrial_movimentar(e,gen_random_uuid(),'FUNCIONARIO',emp,'DESLIGAMENTO','2026-11-15',NULL,'Desligamento teste');
 negado:=false;BEGIN PERFORM public.ew_industrial_movimentar(e,gen_random_uuid(),'FUNCIONARIO',emp,'TRANSFERENCIA','2026-11-20',g,'Transferência indevida');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Histórico encerrado%';END;
 IF NOT negado THEN RAISE EXCEPTION 'movimentou desligado';END IF;
 PERFORM public.ew_industrial_cadastrar(e,ativo,'ATIVO',jsonb_build_object('galpao_id',g,'codigo','MAQ-2','nome','Máquina transferência','data','2026-09-01','valor',1200,'residual',0,'vida',12));
 PERFORM public.ew_industrial_depreciar(e,gen_random_uuid(),ativo,'2026-09-01');
 PERFORM public.ew_industrial_movimentar(e,gen_random_uuid(),'ATIVO',ativo,'TRANSFERENCIA','2026-10-01',g2,'Transferência máquina');
 PERFORM public.ew_industrial_depreciar(e,gen_random_uuid(),ativo,'2026-10-01');
 negado:=false;BEGIN PERFORM public.ew_industrial_movimentar(e,gen_random_uuid(),'ATIVO',ativo,'TRANSFERENCIA','2026-10-01',g,'Retroação indevida');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'alterou histórico';END IF;
 r:=public.ew_industrial_cadastros_consultar(e,'2026-09-01','2026-11-30');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'funcionarios') x WHERE x->>'id'=emp::text AND x->>'desligado_em'='2026-11-15') OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'depreciacoes') x WHERE x->>'codigo'='MAQ-2' AND x->>'competencia'='2026-09-01' AND x->>'local'='AFOGADOS') OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'depreciacoes') x WHERE x->>'codigo'='MAQ-2' AND x->>'competencia'='2026-10-01' AND x->>'local'='IMBIRIBEIRA') THEN RAISE EXCEPTION 'histórico patrimonial incorreto %',r;END IF;
 r:=public.ew_industrial_conferencia_mes(e,'2026-11-01');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='IMBIRIBEIRA' AND (x->>'depreciacoes_pendentes')::int=1) OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fabrica') x WHERE x->>'fabrica'='AFOGADOS' AND (x->>'folha_centavos')::bigint=17000) THEN RAISE EXCEPTION 'conferência incorreta %',r;END IF;
 SET LOCAL test.rh='no';
 r:=public.ew_industrial_movimentos_consultar(e);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'tipo'='FUNCIONARIO') THEN RAISE EXCEPTION 'movimento pessoal exposto';END IF;
 negado:=false;BEGIN PERFORM public.ew_industrial_conferencia_mes(e,'2026-11-01');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso à gestão%';END;
 IF NOT negado OR has_function_privilege('anon','public.ew_industrial_movimentos_consultar(uuid)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
END $$;
SELECT 'OK: transferências, desligamento, histórico de depreciação, conferência mensal e privacidade' AS resultado;

CREATE TABLE public.ew_permissoes_catalogo(chave text PRIMARY KEY,grupo text,descricao text,ordem smallint);
CREATE TABLE public.ew_niveis_acesso(empresa_id uuid,nivel smallint,nome text,PRIMARY KEY(empresa_id,nivel));
CREATE TABLE public.ew_niveis_permissoes(empresa_id uuid,nivel smallint,chave text,permitido boolean,PRIMARY KEY(empresa_id,nivel,chave));
CREATE TABLE public.usuarios_empresas(empresa_id uuid,nivel_acesso smallint);
INSERT INTO public.ew_niveis_acesso SELECT '00000000-0000-0000-0000-000000000001',i,'Nível '||i FROM generate_series(1,8)i;
\ir ../database/proposals/20261128_rh_permissoes_v462955.sql
\ir ../database/proposals/20261128_ferramentas_custodia_v462955.sql
CREATE OR REPLACE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT $1='00000000-0000-0000-0000-000000000001' AND CASE WHEN $2 LIKE 'rh.%' THEN current_setting('test.rh',true)='yes' WHEN $2 LIKE 'ferramentas.%' THEN current_setting('test.tools',true)='yes' ELSE current_setting('test.perm',true)='yes' END $$;
SET test.perm='no';
SET test.rh='yes';
SET test.tools='no';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';g uuid;emp uuid:=gen_random_uuid();f uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();m uuid:=gen_random_uuid();op uuid:=gen_random_uuid();dv uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 IF (SELECT count(*) FROM public.ew_niveis_permissoes WHERE nivel=8 AND permitido AND chave LIKE 'rh.%')<>6 OR EXISTS(SELECT 1 FROM public.ew_niveis_permissoes WHERE nivel=8 AND permitido AND chave LIKE 'ferramentas.%') THEN RAISE EXCEPTION 'permissões RH incorretas';END IF;
 SELECT id INTO g FROM public.ew_locais_fisicos WHERE empresa_id=e LIMIT 1;
 PERFORM public.ew_industrial_cadastrar(e,emp,'FUNCIONARIO',jsonb_build_object('galpao_id',g,'codigo','F002','nome','Operador teste','funcao','Operador','data','2026-11-01'));
 PERFORM public.ew_industrial_registrar_horas(e,gen_random_uuid(),g,'2026-11-22',120,'Apontamento RH');
 r:=public.ew_rh_consultar(e,'2026-11-01','2026-11-30');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'funcionarios') x WHERE x->>'id'=emp::text) OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'horas') x WHERE x->>'data'='2026-11-22' AND (x->>'minutos')::int=120) THEN RAISE EXCEPTION 'RH sem acesso independente';END IF;
 negado:=false;BEGIN PERFORM public.ew_ferramentas_consultar(e);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso às ferramentas%';END;
 IF NOT negado THEN RAISE EXCEPTION 'RH acessou ferramentas';END IF;
 SET LOCAL test.rh='no';SET LOCAL test.tools='yes';
 PERFORM public.ew_ferramenta_cadastrar(e,f,'FUR-1','Furadeira','FERRAMENTA',g);
 PERFORM public.ew_ferramenta_cadastrar(e,b,'BAT-1','Bateria','BATERIA',g);
 PERFORM public.ew_ferramenta_cadastrar(e,c,'CAR-1','Carregador','CARREGADOR',g);
 PERFORM public.ew_ferramenta_cadastrar(e,m,'MAL-1','Maleta','MALETA',g);
 PERFORM public.ew_ferramenta_compor_maleta(e,m,ARRAY[f,b,c]);
 PERFORM public.ew_ferramenta_entregar(e,op,emp,ARRAY[f,b],'Entrega parcial do kit');
 r:=public.ew_ferramenta_entregar(e,op,emp,ARRAY[b,f],'Entrega parcial do kit');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'entrega duplicada';END IF;
 negado:=false;BEGIN PERFORM public.ew_ferramenta_entregar(e,gen_random_uuid(),emp,ARRAY[f],'Tentativa duplicada');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Item indisponível%';END;
 IF NOT negado THEN RAISE EXCEPTION 'dupla custódia';END IF;
 r:=public.ew_ferramentas_consultar(e);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'entregas') x WHERE x->>'id'=op::text AND jsonb_array_length(x->'itens')=2 AND jsonb_array_length(x->'pendentes')=2) OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'itens') x WHERE x->>'id'=c::text AND x->>'entrega_id' IS NULL) THEN RAISE EXCEPTION 'kit parcial incorreto';END IF;
 PERFORM public.ew_ferramenta_devolver(e,dv,op,jsonb_build_array(jsonb_build_object('id',f,'condicao','Em bom estado')));
 r:=public.ew_ferramenta_devolver(e,dv,op,jsonb_build_array(jsonb_build_object('id',f,'condicao','Em bom estado')));
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'devolução duplicada';END IF;
 negado:=false;BEGIN PERFORM public.ew_ferramenta_devolver(e,gen_random_uuid(),op,jsonb_build_array(jsonb_build_object('id',c,'condicao','Em bom estado')));EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Item não pertence%';END;
 IF NOT negado THEN RAISE EXCEPTION 'devolveu item não entregue';END IF;
 r:=public.ew_ferramentas_consultar(e);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'entregas') x WHERE x->>'id'=op::text AND x->'pendentes'=jsonb_build_array(b)) THEN RAISE EXCEPTION 'bateria pendente perdida';END IF;
 negado:=false;BEGIN PERFORM public.ew_rh_consultar(e,'2026-11-01','2026-11-30');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso ao RH%';END;
 IF NOT negado OR has_table_privilege('authenticated','ew_financeiro_interna.ferramentas_custodia','SELECT') OR has_function_privilege('anon','public.ew_ferramentas_consultar(uuid)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
END $$;
SET test.perm='yes';
SELECT 'OK: RH independente, kit parcial, custódia única, devolução parcial e permissões' AS resultado;

\ir ../database/proposals/20261128_ferramentas_ocorrencias_v462956.sql
SET test.tools='yes';
SET test.rh='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';emp uuid;f uuid;b uuid;c uuid;en uuid;op uuid:=gen_random_uuid();dv uuid:=gen_random_uuid();rev uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 SELECT id INTO emp FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=e AND matricula='F002';
 SELECT id INTO f FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND codigo='FUR-1';
 SELECT id INTO b FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND codigo='BAT-1';
 SELECT id INTO c FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND codigo='CAR-1';
 SELECT entrega_id INTO en FROM ew_financeiro_interna.ferramentas_custodia WHERE empresa_id=e AND item_id=b AND devolucao_id IS NULL;
 IF (SELECT estado FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND id=f)<>'CONFERIR' THEN RAISE EXCEPTION 'devolução antiga não bloqueada';END IF;
 PERFORM public.ew_ferramenta_ocorrencia(e,gen_random_uuid(),f,'MANUTENCAO','Reparo necessário');
 negado:=false;BEGIN PERFORM public.ew_ferramenta_entregar(e,gen_random_uuid(),emp,ARRAY[f],'Entrega indevida');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Item indisponível%';END;
 IF NOT negado THEN RAISE EXCEPTION 'entregou item em manutenção';END IF;
 PERFORM public.ew_ferramenta_ocorrencia(e,gen_random_uuid(),f,'DISPONIVEL','Reparo concluído');
 PERFORM public.ew_ferramenta_entregar(e,op,emp,ARRAY[f],'Entrega após reparo');
 PERFORM public.ew_ferramenta_devolver(e,dv,op,jsonb_build_array(jsonb_build_object('id',f,'condicao','Avaria identificada','estado','AVARIADA')));
 IF (SELECT estado FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND id=f)<>'AVARIADA' THEN RAISE EXCEPTION 'avaria não registrada';END IF;
 PERFORM public.ew_ferramenta_estornar(e,rev,'DEVOLUCAO',dv,'Corrigir devolução');
 r:=public.ew_ferramenta_estornar(e,rev,'DEVOLUCAO',dv,'Corrigir devolução');
 IF NOT (r->>'repetido')::boolean OR (SELECT estado FROM ew_financeiro_interna.ferramentas WHERE empresa_id=e AND id=f)<>'DISPONIVEL' THEN RAISE EXCEPTION 'estorno incorreto';END IF;
 PERFORM public.ew_ferramenta_estornar(e,gen_random_uuid(),'ENTREGA',op,'Corrigir entrega');
 PERFORM public.ew_ferramenta_ocorrencia(e,gen_random_uuid(),b,'EXTRAVIADA','Bateria não localizada');
 r:=public.ew_rh_consultar(e,'2026-11-01','2026-11-30');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'funcionarios') x WHERE x->>'id'=emp::text AND (x->>'ferramentas_pendentes')::int=1) THEN RAISE EXCEPTION 'perdeu pendência no extravio %',r;END IF;
 negado:=false;BEGIN PERFORM public.ew_ferramenta_estornar(e,gen_random_uuid(),'ENTREGA',en,'Estorno indevido');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'estornou entrega com extravio';END IF;
 r:=public.ew_ferramentas_consultar(e);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'entregas') x WHERE x->>'id'=op::text AND x->>'estornado_em' IS NOT NULL AND jsonb_array_length(x->'pendentes')=0) OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'itens') x WHERE x->>'id'=b::text AND x->>'estado'='EXTRAVIADA' AND x->>'entrega_id'=en::text) THEN RAISE EXCEPTION 'histórico ou custódia perdida';END IF;
END $$;
SELECT 'OK: bloqueio por manutenção, avaria, extravio com custódia, estornos e pendências RH' AS resultado;
