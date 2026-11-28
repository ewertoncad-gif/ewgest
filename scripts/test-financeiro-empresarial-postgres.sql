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
