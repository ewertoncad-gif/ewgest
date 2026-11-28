-- Banco descartável. Fontes documentais mínimas, sem dados reais.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida';END IF;END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT $1='00000000-0000-0000-0000-000000000001' AND CASE
  WHEN $2='compras.consultar_valores' THEN current_setting('test.compra',true)='yes'
  WHEN $2 IN ('financeiro.consultar','relatorios.financeiros') THEN true
  ELSE current_setting('test.write',true)='yes' END $$;
CREATE TABLE public.empresas(id uuid PRIMARY KEY);
CREATE TABLE public.obras(id uuid PRIMARY KEY,empresa_id uuid,nome text,cliente text);
CREATE TABLE public.ew_obra_faturamentos(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,categoria text,data_faturamento date,numero_documento text,valor_total numeric,status text,cancelado_em timestamptz);
CREATE TABLE public.ew_obra_despesas(id uuid PRIMARY KEY,empresa_id uuid,obra_id uuid,categoria text,data_documento date,fornecedor text,numero_documento text,valor numeric,status text,cancelado_em timestamptz);
CREATE TABLE public.ew_compras_notas_empresa(id uuid PRIMARY KEY,empresa_id uuid,fornecedor_id uuid,data_documento date,numero_documento text,valor_centavos bigint,status text,cancelado_em timestamptz);
CREATE TABLE public.ew_fornecedores(id uuid PRIMARY KEY,empresa_id uuid,nome text);
CREATE TABLE public.ew_locais_fisicos(id uuid PRIMARY KEY,empresa_id uuid,nome text,ativo boolean);
\ir ../database/proposals/20261128_financeiro_empresarial_v462939.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.compra='yes';
SET test.write='yes';
CREATE TABLE public.test_titulo_race(id uuid);
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';e2 uuid:=gen_random_uuid();o uuid:=gen_random_uuid();f uuid:=gen_random_uuid();d uuid:=gen_random_uuid();n uuid:=gen_random_uuid();forn uuid:=gen_random_uuid();g uuid:=gen_random_uuid();
 t_rec uuid;t_pag uuid;t_nota uuid;b_rec uuid;op uuid:=gen_random_uuid();r jsonb;j jsonb;negado boolean;
BEGIN
 IF has_schema_privilege('authenticated','ew_financeiro_interna','USAGE') OR has_table_privilege('authenticated','ew_financeiro_interna.titulos','SELECT') OR has_function_privilege('anon','public.ew_fin_empresa_consultar(uuid,date,date)','EXECUTE') THEN RAISE EXCEPTION 'acesso direto indevido';END IF;
 INSERT INTO public.empresas VALUES(e),(e2);
 INSERT INTO public.obras VALUES(o,e,'Obra A','Cliente A');
 INSERT INTO public.ew_fornecedores VALUES(forn,e,'Fornecedor A');
 INSERT INTO public.ew_locais_fisicos VALUES(g,e,'AFOGADOS',true);
 INSERT INTO public.ew_obra_faturamentos VALUES(f,e,o,'fabricacao',current_date,'001',100,'emitido',NULL);
 INSERT INTO public.ew_obra_despesas VALUES(d,e,o,'aluminio',current_date,'Fornecedor A','002',50,'aprovada',NULL);
 INSERT INTO public.ew_compras_notas_empresa VALUES(n,e,forn,current_date,'003',2000,'ATIVA',NULL);
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'documentos_sem_programacao')::int<>3 OR (r->>'a_receber_centavos')::bigint<>0 OR (r->>'entradas_centavos')::bigint<>0 THEN RAISE EXCEPTION 'documento gerou caixa ou título sozinho';END IF;
 j:=jsonb_build_object('tipo','RECEBER','origem_tipo','FATURAMENTO_OBRA','origem_id',f,'valor_centavos',10000,'vencimento',current_date+1);
 r:=public.ew_fin_empresa_criar_titulo(e,op,j);t_rec:=(r->>'id')::uuid;
 r:=public.ew_fin_empresa_criar_titulo(e,op,j);
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'idempotência perdida';END IF;
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_criar_titulo(e,gen_random_uuid(),j);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Documento já programado%';END;
 IF NOT negado THEN RAISE EXCEPTION 'documento duplicado';END IF;
 r:=public.ew_fin_empresa_criar_titulo(e,gen_random_uuid(),jsonb_build_object('tipo','PAGAR','origem_tipo','MANUAL','descricao','Energia elétrica','contraparte','Fornecedor B','categoria','Energia','centro',g,'competencia',current_date,'vencimento',current_date-1,'valor_centavos',20000));t_pag:=(r->>'id')::uuid;
 INSERT INTO public.test_titulo_race VALUES(t_pag);
 PERFORM public.ew_fin_empresa_criar_titulo(e,gen_random_uuid(),jsonb_build_object('tipo','PAGAR','origem_tipo','DESPESA_OBRA','origem_id',d,'valor_centavos',5000,'vencimento',current_date));
 r:=public.ew_fin_empresa_criar_titulo(e,gen_random_uuid(),jsonb_build_object('tipo','PAGAR','origem_tipo','NOTA_ESTOQUE','origem_id',n,'valor_centavos',2000,'vencimento',current_date));t_nota:=(r->>'id')::uuid;
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'a_pagar_centavos')::bigint<>27000 OR (r->>'a_receber_centavos')::bigint<>10000 OR (r->>'vencido_pagar_centavos')::bigint<>20000 OR (r->>'documentos_sem_programacao')::int<>0 THEN RAISE EXCEPTION 'saldos programados incorretos: %',r;END IF;
 op:=gen_random_uuid();r:=public.ew_fin_empresa_baixar(e,t_rec,op,4000,current_date,'Pix','');b_rec:=(r->>'id')::uuid;
 r:=public.ew_fin_empresa_baixar(e,t_rec,op,4000,current_date,'Pix','');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'baixa duplicada';END IF;
 PERFORM public.ew_fin_empresa_baixar(e,t_pag,gen_random_uuid(),3000,current_date,'Pix','');
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_baixar(e,t_rec,gen_random_uuid(),6001,current_date,'Pix','');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Baixa supera%';END;
 IF NOT negado THEN RAISE EXCEPTION 'baixa acima do saldo';END IF;
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'entradas_centavos')::bigint<>4000 OR (r->>'saidas_centavos')::bigint<>3000 OR (r->>'a_receber_centavos')::bigint<>6000 OR (r->>'a_pagar_centavos')::bigint<>24000 THEN RAISE EXCEPTION 'caixa ou saldos incorretos';END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado',cancelado_em=now() WHERE id=f;
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'origens_pendentes')::int<>1 OR (r->>'a_receber_centavos')::bigint<>0 OR (r->>'entradas_centavos')::bigint<>4000 THEN RAISE EXCEPTION 'cancelamento de origem apagou caixa ou saldo inválido';END IF;
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_baixar(e,t_rec,gen_random_uuid(),100,current_date,'Pix','');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Documento de origem%';END;
 IF NOT negado THEN RAISE EXCEPTION 'baixa de documento cancelado';END IF;
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_cancelar_titulo(e,t_rec,gen_random_uuid(),'Cancelamento teste');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Estorne as baixas%';END;
 IF NOT negado THEN RAISE EXCEPTION 'cancelou título com dinheiro registrado';END IF;
 PERFORM public.ew_fin_empresa_estornar_baixa(e,b_rec,gen_random_uuid(),'Registro incorreto');
 PERFORM public.ew_fin_empresa_cancelar_titulo(e,t_rec,gen_random_uuid(),'Origem cancelada');
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'entradas_centavos')::bigint<>0 OR (r->>'origens_pendentes')::int<>0 THEN RAISE EXCEPTION 'estorno não recalculou caixa';END IF;
 PERFORM set_config('test.compra','no',true);
 r:=public.ew_fin_empresa_consultar(e,current_date-1,current_date);
 IF (r->>'escopo_completo')::boolean OR (r->>'a_pagar_centavos')::bigint<>22000 OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'titulos') x WHERE x->>'origem_tipo'='NOTA_ESTOQUE') THEN RAISE EXCEPTION 'restrição de valores de compras não respeitada';END IF;
 PERFORM set_config('test.write','no',true);
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_baixar(e,t_pag,gen_random_uuid(),100,current_date,'Pix','');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'usuário consulta gravou baixa';END IF;
 negado:=false;BEGIN PERFORM public.ew_fin_empresa_consultar(e2,current_date-1,current_date);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso cruzado';END IF;
END $$;
SELECT 'OK: títulos, fontes, baixas, estornos, centros de custo e segurança' AS resultado;

CREATE TABLE public.ew_compras_pedidos(id uuid PRIMARY KEY,empresa_id uuid,numero bigint,status text,cancelado_em timestamptz);
CREATE TABLE public.ew_compras_nfe_conciliacoes(empresa_id uuid,despesa_id uuid,pedido_id uuid,desvinculado_em timestamptz);
ALTER TABLE public.ew_compras_notas_empresa ADD COLUMN pedido_id uuid;
\ir ../database/proposals/20261128_frete_previsao_v462951.sql
SET test.compra='yes';
SET test.write='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';p uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();d uuid;nota uuid;t uuid;op uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 SELECT id INTO d FROM public.ew_obra_despesas WHERE empresa_id=e LIMIT 1;
 SELECT id INTO nota FROM public.ew_compras_notas_empresa WHERE empresa_id=e LIMIT 1;
 INSERT INTO public.ew_compras_pedidos VALUES(p,e,1,'ABERTO',NULL),(p2,e,2,'ABERTO',NULL);
 INSERT INTO public.ew_compras_nfe_conciliacoes VALUES(e,d,p,NULL),(e,d,p2,NULL);
 UPDATE public.ew_compras_notas_empresa SET pedido_id=p WHERE id=nota;
 r:=public.ew_fin_compras_previsao(e);
 IF (r->>'total')::int<>2 OR (r->>'saldo_programado_centavos')::bigint<>7000 THEN RAISE EXCEPTION 'previsão duplicada: %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'linhas') x WHERE x->>'origem_tipo'='DESPESA_OBRA' AND jsonb_array_length(x->'pedidos')=2) THEN RAISE EXCEPTION 'documento compartilhado perdido';END IF;
 r:=public.ew_fin_empresa_criar_titulo(e,gen_random_uuid(),jsonb_build_object('tipo','PAGAR','origem_tipo','MANUAL','descricao','Frete externo','contraparte','Transportadora','numero_documento','CTE-1','categoria','Frete','centro','GERAL','competencia',current_date,'vencimento',current_date+15,'valor_centavos',1000));t:=(r->>'id')::uuid;
 PERFORM public.ew_fin_vincular_frete(e,t,p,op,'Frete separado');
 r:=public.ew_fin_vincular_frete(e,t,p,op,'Frete separado');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'repetição perdeu idempotência';END IF;
 negado:=false;BEGIN PERFORM public.ew_fin_vincular_frete(e,t,p2,gen_random_uuid(),'Outro pedido');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Título de frete já vinculado%';END;
 IF NOT negado THEN RAISE EXCEPTION 'frete duplicado';END IF;
 PERFORM public.ew_fin_empresa_baixar(e,t,gen_random_uuid(),300,current_date,'Pix','');
 r:=public.ew_fin_compras_previsao(e);
 IF (r->>'total')::int<>3 OR (r->>'saldo_programado_centavos')::bigint<>7700 THEN RAISE EXCEPTION 'saldo frete incorreto: %',r;END IF;
 UPDATE public.ew_compras_pedidos SET cancelado_em=now(),status='CANCELADO' WHERE id=p2;
 r:=public.ew_fin_compras_previsao(e);
 IF (r->>'pendencias')::int<>1 OR (r->>'saldo_programado_centavos')::bigint<>2700 THEN RAISE EXCEPTION 'cancelamento sem conferência: %',r;END IF;
 SET LOCAL test.compra='no';
 negado:=false;BEGIN PERFORM public.ew_fin_compras_previsao(e);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem acesso%';END;
 IF NOT negado OR has_table_privilege('authenticated','ew_financeiro_interna.fretes_pedidos','SELECT') OR has_function_privilege('anon','public.ew_fin_compras_previsao(uuid)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
END $$;
SELECT 'OK: pagamentos documentais, frete único, baixa parcial e origem pendente' AS resultado;

ALTER TABLE public.ew_compras_pedidos ADD COLUMN itens jsonb, ADD COLUMN total_centavos bigint;
\ir ../database/proposals/20261128_frete_estorno_v462952.sql
SET test.compra='yes';
SET test.write='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';f ew_financeiro_interna.fretes_pedidos%ROWTYPE;op uuid:=gen_random_uuid();r jsonb;p uuid;
BEGIN
 SELECT * INTO f FROM ew_financeiro_interna.fretes_pedidos WHERE empresa_id=e LIMIT 1;
 UPDATE public.ew_compras_pedidos SET itens='[{"chave":"1","quantidade":2,"preco_unitario_centavos":100},{"chave":"2","quantidade":1,"preco_unitario_centavos":100}]',total_centavos=300 WHERE id=f.pedido_id;
 r:=public.ew_fin_frete_previa(e,f.operacao_id);
 IF (r->>'frete_centavos')::bigint<>1000 OR (SELECT sum((x->>'frete_centavos')::bigint) FROM jsonb_array_elements(r->'itens') x)<>1000 OR (r->'itens'->0->>'frete_centavos')::bigint<>667 THEN RAISE EXCEPTION 'rateio incorreto %',r;END IF;
 PERFORM public.ew_fin_estornar_vinculo_frete(e,f.titulo_id,f.operacao_id,op,'Corrigir vínculo');
 r:=public.ew_fin_estornar_vinculo_frete(e,f.titulo_id,f.operacao_id,op,'Corrigir vínculo');
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'estorno repetido';END IF;
 r:=public.ew_fin_compras_previsao(e);
 IF (r->>'saldo_programado_centavos')::bigint<>2000 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'fretes_disponiveis') x WHERE x->>'id'=f.titulo_id::text) THEN RAISE EXCEPTION 'desvinculação incorreta %',r;END IF;
 IF (SELECT sum(valor_centavos) FROM ew_financeiro_interna.baixas WHERE titulo_id=f.titulo_id AND estornado_em IS NULL)<>300 THEN RAISE EXCEPTION 'baixa alterada';END IF;
 PERFORM public.ew_fin_vincular_frete(e,f.titulo_id,f.pedido_id,gen_random_uuid(),'Vincular novamente');
 r:=public.ew_fin_fretes_historico(e);
 IF jsonb_array_length(r)<>2 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'estorno_motivo'='Corrigir vínculo') THEN RAISE EXCEPTION 'histórico perdido';END IF;
END $$;
SELECT 'OK: prévia de frete em centavos, estorno e novo vínculo preservando baixa' AS resultado;

CREATE SCHEMA ew_compras_interna;
CREATE TABLE public.ew_compras_recebimentos(id uuid PRIMARY KEY,empresa_id uuid,pedido_id uuid,itens jsonb,estornado_em timestamptz);
CREATE TABLE public.ew_compras_recebimentos_movimentos(empresa_id uuid,recebimento_id uuid,chave text,movimento_obra_id uuid,movimento_empresa_id uuid);
CREATE TABLE ew_compras_interna.lotes_aquisicao_evidencias(empresa_id uuid,recebimento_id uuid,movimento_id uuid,fonte text,item_fiscal_id uuid,quantidade numeric,custo_centavos bigint);
CREATE TABLE ew_compras_interna.custo_lotes(empresa_id uuid,lote_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,quantidade numeric,custo_centavos bigint,cancelado_em timestamptz);
CREATE FUNCTION ew_financeiro_interna.exigir_resultado(uuid,boolean,boolean) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$ BEGIN PERFORM ew_financeiro_interna.exigir($1);IF NOT public.ew_pode($1,'compras.consultar_valores') OR NOT public.ew_pode($1,'estoque.consultar') THEN RAISE EXCEPTION 'Sem acesso';END IF;END $$;
\ir ../database/proposals/20261128_frete_base_fiscal_v462953.sql
SET test.compra='yes';
SET test.write='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';f ew_financeiro_interna.fretes_pedidos%ROWTYPE;rec uuid:=gen_random_uuid();m1 uuid:=gen_random_uuid();m2 uuid:=gen_random_uuid();i1 uuid:=gen_random_uuid();i2 uuid:=gen_random_uuid();l1 uuid:=gen_random_uuid();l2 uuid:=gen_random_uuid();r jsonb;negado boolean;
BEGIN
 SELECT * INTO f FROM ew_financeiro_interna.fretes_pedidos WHERE empresa_id=e AND estornado_em IS NULL LIMIT 1;
 UPDATE public.ew_compras_pedidos SET status='CONCLUIDO' WHERE id=f.pedido_id;
 INSERT INTO public.ew_compras_recebimentos VALUES(rec,e,f.pedido_id,'[{"chave":"1","quantidade":2},{"chave":"2","quantidade":1}]',NULL);
 INSERT INTO public.ew_compras_recebimentos_movimentos VALUES(e,rec,'1',m1,NULL),(e,rec,'2',m2,NULL);
 INSERT INTO ew_compras_interna.lotes_aquisicao_evidencias VALUES(e,rec,m1,'PEDIDO_OBRA',i1,2,600),(e,rec,m2,'PEDIDO_OBRA',i2,1,400);
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,l1,'PEDIDO_OBRA',i1,m1,2,600,NULL);
 negado:=false;BEGIN PERFORM public.ew_fin_frete_previa_fiscal(e,f.operacao_id);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Existem recebimentos%';END;
 IF NOT negado THEN RAISE EXCEPTION 'aceitou lote incompleto';END IF;
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,l2,'PEDIDO_OBRA',i2,m2,1,400,NULL);
 r:=public.ew_fin_frete_previa_fiscal(e,f.operacao_id);
 IF (r->>'material_centavos')::bigint<>1000 OR (SELECT sum((x->>'frete_centavos')::bigint) FROM jsonb_array_elements(r->'itens') x)<>1000 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'itens') x WHERE x->>'lote_id'=l1::text AND (x->>'frete_centavos')::bigint=600) THEN RAISE EXCEPTION 'base fiscal incorreta %',r;END IF;
 UPDATE ew_compras_interna.custo_lotes SET cancelado_em=now() WHERE lote_id=l2;
 negado:=false;BEGIN PERFORM public.ew_fin_frete_previa_fiscal(e,f.operacao_id);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Existem recebimentos%';END;
 IF NOT negado THEN RAISE EXCEPTION 'aceitou lote cancelado';END IF;
END $$;
SELECT 'OK: base fiscal, lotes ativos e frete em centavos' AS resultado;
