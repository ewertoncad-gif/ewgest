-- Banco descartável. Validação do resumo com a estrutura real das fontes de custo.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA ew_compras_interna;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida'; END IF; END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT $1='00000000-0000-0000-0000-000000000001' AND current_setting('test.perm',true)='yes' $$;
CREATE TABLE public.obras(empresa_id uuid,id uuid,arquivada_em timestamptz);
CREATE TABLE public.ew_compras_locais_empresa(empresa_id uuid,id uuid,excluido_em timestamptz,ativo boolean);
CREATE TABLE public.ew_estornos_parcelas(empresa_id uuid,movimento_original_id uuid,movimento_estorno_id uuid,quantidade numeric);
CREATE TABLE ew_compras_interna.custo_movimentos_fisicos(empresa_id uuid,id uuid,tipo text,local_id uuid,galpao text,tipo_material text,material_id uuid,comprimento_mm integer,unidade text,quantidade_delta numeric,origem text,estorno_de_id uuid);
CREATE TABLE ew_compras_interna.custo_movimentos_reconhecidos(empresa_id uuid,id uuid,estornado boolean);
CREATE TABLE ew_compras_interna.custo_lotes(empresa_id uuid,lote_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,categoria text,quantidade numeric,custo_centavos bigint);
CREATE TABLE ew_compras_interna.custo_saldos_fragmentos(empresa_id uuid,lote_id uuid,fragmento_id uuid,tipo text,local_id uuid,galpao text,quantidade numeric,custo_centavos bigint);
CREATE TABLE ew_compras_interna.lotes_aquisicao_evidencias(empresa_id uuid,fonte text,item_fiscal_id uuid,movimento_id uuid,tipo_material text,material_id uuid,comprimento_mm integer,unidade text,categoria text,quantidade numeric,custo_centavos bigint);
\ir ../database/proposals/20261128_estoque_valorizado_resumo_v462938.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001'; e2 uuid:=gen_random_uuid();
 o uuid:=gen_random_uuid(); l uuid:=gen_random_uuid(); mat uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); lote uuid:=gen_random_uuid(); item uuid:=gen_random_uuid(); t1 uuid:=gen_random_uuid();t2 uuid:=gen_random_uuid(); consumo uuid:=gen_random_uuid(); x uuid:=gen_random_uuid();y uuid:=gen_random_uuid(); z uuid:=gen_random_uuid(); r jsonb; negado boolean;
BEGIN
 IF has_function_privilege('anon','public.ew_estoque_valorizado_resumo(uuid)','EXECUTE') THEN RAISE EXCEPTION 'anon tem acesso';END IF;
 r:=public.ew_estoque_valorizado_resumo(e);
 IF (r->>'total_centavos')::bigint<>0 OR jsonb_array_length(r->'galpoes')<>0 THEN RAISE EXCEPTION 'estoque vazio não fecha';END IF;
 INSERT INTO public.obras VALUES(e,o,NULL);
 INSERT INTO public.ew_compras_locais_empresa VALUES(e,l,NULL,true);
 -- Compra física 10 barras de R$ 100, transferiu 4, consumiu 1 na obra.
 INSERT INTO ew_compras_interna.custo_movimentos_fisicos VALUES
  (e,m,'EMPRESA',l,'IMBIRIBEIRA','TECNICO',mat,6000,'BARRA',10,'COMPRA',NULL),
  (e,t1,'EMPRESA',l,'IMBIRIBEIRA','TECNICO',mat,6000,'BARRA',-4,'TRANSFERENCIA',NULL),
  (e,t2,'OBRA',o,'AFOGADOS','TECNICO',mat,6000,'BARRA',4,'TRANSFERENCIA',NULL),
  (e,consumo,'OBRA',o,'AFOGADOS','TECNICO',mat,6000,'BARRA',-1,'PLANO_CORTE',NULL),
  (e2,gen_random_uuid(),'OBRA',gen_random_uuid(),'OUTRA EMPRESA','TECNICO',mat,6000,'BARRA',100,'COMPRA',NULL);
 INSERT INTO ew_compras_interna.custo_movimentos_reconhecidos VALUES(e,m,false),(e,t1,false),(e,t2,false),(e,consumo,false);
 INSERT INTO ew_compras_interna.custo_lotes VALUES(e,lote,'PEDIDO_EMPRESA',item,m,'aluminio',10,100000);
 INSERT INTO ew_compras_interna.lotes_aquisicao_evidencias VALUES(e,'PEDIDO_EMPRESA',item,m,'TECNICO',mat,6000,'BARRA','aluminio',10,100000);
 INSERT INTO ew_compras_interna.custo_saldos_fragmentos VALUES
  (e,lote,gen_random_uuid(),'EMPRESA',l,'IMBIRIBEIRA',6,60000),
  (e,lote,gen_random_uuid(),'OBRA',o,'AFOGADOS',3,30000),
  (e,lote,gen_random_uuid(),'PRODUCAO',o,'AFOGADOS',1,10000);
 r:=public.ew_estoque_valorizado_resumo(e);
 IF (r->>'total_centavos')::bigint<>90000 OR (r->>'linhas_conciliadas')::int<>2 OR jsonb_array_length(r->'galpoes')<>2 THEN RAISE EXCEPTION 'transferência/consumo duplicado ou custo incorreto: %',r;END IF;
 -- Movimento não comprovado e sua compensação: saldo líquido igual, custo não garantido.
 INSERT INTO ew_compras_interna.custo_movimentos_fisicos VALUES(e,x,'OBRA',o,'AFOGADOS','TECNICO',mat,6000,'BARRA',1,'AJUSTE',NULL),(e,y,'OBRA',o,'AFOGADOS','TECNICO',mat,6000,'BARRA',-1,'AJUSTE',NULL);
 r:=public.ew_estoque_valorizado_resumo(e);
 IF r->'total_centavos'<>'null'::jsonb OR (r->>'valor_comprovado_centavos')::bigint<>60000 OR (r->>'pendencias')::int<>1 THEN RAISE EXCEPTION 'saldo não comprovado tratado como custo: %',r;END IF;
 DELETE FROM ew_compras_interna.custo_movimentos_fisicos WHERE id IN (x,y);
 -- Lote perdeu a evidência fiscal: nem o fragmento nem o saldo podem ser tratados como custo certo.
 DELETE FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=e;
 r:=public.ew_estoque_valorizado_resumo(e);
 IF r->'total_centavos'<>'null'::jsonb OR (r->>'fragmentos_sem_evidencia')::int<>2 OR (r->>'valor_comprovado_centavos')::bigint<>0 THEN RAISE EXCEPTION 'evidência ausente ignorada: %',r;END IF;
 negado:=false;BEGIN PERFORM public.ew_estoque_valorizado_resumo(e2);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso a outra empresa';END IF;
 PERFORM set_config('test.perm','no',true);
 negado:=false;BEGIN PERFORM public.ew_estoque_valorizado_resumo(e);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado THEN RAISE EXCEPTION 'acesso sem flags';END IF;
END $$;
SELECT 'OK: estoque valorizado, transferências, consumo, pendências e isolamento' AS resultado;
