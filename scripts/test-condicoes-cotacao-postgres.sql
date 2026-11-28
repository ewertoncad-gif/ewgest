-- Banco descartável: estrutura mínima, RPC de criação original.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida';END IF;END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT $1='00000000-0000-0000-0000-000000000001' AND current_setting('test.perm',true)='yes' $$;
CREATE TABLE public.ew_compras_solicitacoes(id uuid PRIMARY KEY,empresa_id uuid,status text,itens jsonb);
CREATE TABLE public.ew_fornecedores(id uuid PRIMARY KEY,empresa_id uuid,ativo boolean);
CREATE TABLE public.ew_compras_cotacoes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid,solicitacao_id uuid,fornecedor_id uuid,operacao_id uuid UNIQUE,itens jsonb,total_centavos bigint,criado_por uuid);
ALTER TABLE public.ew_compras_cotacoes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.ew_compras_cotacoes TO authenticated;
CREATE POLICY cot_leitura ON public.ew_compras_cotacoes FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'compras.consultar_valores'));
create or replace function public.ew_compras_criar_cotacao(
 p_solicitacao_id uuid,p_fornecedor_id uuid,p_precos jsonb,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_s public.ew_compras_solicitacoes%rowtype;v_prev public.ew_compras_cotacoes%rowtype;
 v_i jsonb;v_price jsonb;v_old_prices jsonb;v_new_prices jsonb;
 v_id uuid;v_value bigint;v_total bigint:=0;v_items jsonb:='[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 select * into v_s from public.ew_compras_solicitacoes where id=p_solicitacao_id;
 if not found then raise exception 'Solicitação não encontrada.';end if;
 if not public.ew_pode(v_s.empresa_id,'compras.cotar') then raise exception 'Sem permissão para cotar.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'COMPRAS_COTACAO|'||p_operacao_id::text,38640));
 select * into v_prev from public.ew_compras_cotacoes where operacao_id=p_operacao_id;
 if found then
  select jsonb_agg(jsonb_build_object('chave',x.value->>'chave',
    'preco_unitario_centavos',(x.value->>'preco_unitario_centavos')::bigint)
    order by x.value->>'chave') into v_old_prices
  from jsonb_array_elements(v_prev.itens) x;
  select jsonb_agg(jsonb_build_object('chave',x.value->>'chave',
    'preco_unitario_centavos',(x.value->>'preco_unitario_centavos')::bigint)
    order by x.value->>'chave') into v_new_prices
  from jsonb_array_elements(p_precos) x;
  if v_prev.empresa_id<>v_s.empresa_id OR v_prev.solicitacao_id<>v_s.id
    OR v_prev.fornecedor_id<>p_fornecedor_id OR v_old_prices IS DISTINCT FROM v_new_prices
  then raise exception 'Identificador de cotação usado anteriormente para outros dados.';end if;
  return jsonb_build_object('id',v_prev.id,'total_centavos',v_prev.total_centavos,'repetida',true);
 end if;
 if v_s.status<>'ABERTA' then raise exception 'Solicitação indisponível.';end if;
 if not exists(select 1 from public.ew_fornecedores
 where id=p_fornecedor_id and empresa_id=v_s.empresa_id and ativo) then raise exception 'Fornecedor inválido.';end if;
 if jsonb_typeof(p_precos) is distinct from 'array' or jsonb_array_length(p_precos)<>jsonb_array_length(v_s.itens)
 then raise exception 'Cotação deve ter preço para cada item.';end if;
 for v_i in select value from jsonb_array_elements(v_s.itens) loop
  select value into v_price from jsonb_array_elements(p_precos) where value->>'chave'=v_i->>'chave';
  if not found then raise exception 'Falta preço de item da solicitação.';end if;
  v_value:=(v_price->>'preco_unitario_centavos')::bigint;
  if v_value is null or v_value<0 or v_value>100000000000 then raise exception 'Preço inválido.';end if;
  v_total:=v_total+round((v_i->>'quantidade')::numeric*v_value)::bigint;
  v_items:=v_items||jsonb_build_array(v_i||jsonb_build_object('preco_unitario_centavos',v_value));
 end loop;
 insert into public.ew_compras_cotacoes(empresa_id,solicitacao_id,fornecedor_id,operacao_id,itens,total_centavos,criado_por)
 values(v_s.empresa_id,v_s.id,p_fornecedor_id,p_operacao_id,v_items,v_total,auth.uid()) returning id into v_id;
 return jsonb_build_object('id',v_id,'total_centavos',v_total);
end;$f$;
\ir ../database/proposals/20261128_condicoes_cotacao_v462948.sql
SET test.uid='00000000-0000-0000-0000-000000000099';
SET test.perm='yes';
DO $$
DECLARE e uuid:='00000000-0000-0000-0000-000000000001';s uuid:=gen_random_uuid();f uuid:=gen_random_uuid();op uuid:=gen_random_uuid();cond jsonb;precos jsonb:='[{"chave":"1","preco_unitario_centavos":12500}]';r jsonb;negado boolean;
BEGIN
 INSERT INTO public.ew_compras_solicitacoes VALUES(s,e,'ABERTA','[{"chave":"1","quantidade":4}]');
 INSERT INTO public.ew_fornecedores VALUES(f,e,true);
 cond:='{"prazo_dias":15,"validade":"2026-12-15","pagamento":"30/60 dias","frete":"INCLUSO"}';
 r:=public.ew_compras_cotar_com_condicoes(e,s,f,precos,op,cond);
 IF (r->>'total_centavos')::bigint<>50000 OR r->'condicoes_comerciais'->>'pagamento'<>'30/60 dias' THEN RAISE EXCEPTION 'condições não persistidas';END IF;
 r:=public.ew_compras_cotar_com_condicoes(e,s,f,precos,op,cond);
 IF NOT (r->>'repetida')::boolean OR (SELECT count(*) FROM public.ew_compras_cotacoes)<>1 THEN RAISE EXCEPTION 'duplicidade';END IF;
 negado:=false;BEGIN PERFORM public.ew_compras_cotar_com_condicoes(e,s,f,precos,op,cond||'{"prazo_dias":20}');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Identificador já utilizado%';END;
 IF NOT negado THEN RAISE EXCEPTION 'revisão indevida';END IF;
 negado:=false;BEGIN PERFORM public.ew_compras_cotar_com_condicoes(e,s,f,precos,gen_random_uuid(),cond||'{"frete":"INVALIDO"}');EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Condições comerciais inválidas%';END;
 IF NOT negado OR (SELECT count(*) FROM public.ew_compras_cotacoes)<>1 THEN RAISE EXCEPTION 'condição inválida persistida';END IF;
 SET LOCAL test.perm='no';
 negado:=false;BEGIN PERFORM public.ew_compras_cotar_com_condicoes(e,s,f,precos,op,cond);EXCEPTION WHEN OTHERS THEN negado:=SQLERRM LIKE 'Sem permissão%';END;
 IF NOT negado OR has_function_privilege('anon','public.ew_compras_cotar_com_condicoes(uuid,uuid,uuid,jsonb,uuid,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'acesso indevido';END IF;
END $$;
SELECT 'OK: condições persistidas, total intacto, permissão e repetição' AS resultado;
