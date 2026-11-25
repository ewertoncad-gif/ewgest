BEGIN;
-- Proposta de preços históricos e compromisso. Não reescreve orçamento/itens importados.
CREATE OR REPLACE FUNCTION public.ew_compras_criar_pedido(p_cotacao_id uuid, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_q public.ew_compras_cotacoes%rowtype;v_s public.ew_compras_solicitacoes%rowtype;
 v_prev public.ew_compras_pedidos%rowtype;v_id uuid;v_numero bigint;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 select * into v_q from public.ew_compras_cotacoes where id=p_cotacao_id;
 if not found then raise exception 'Cotação não encontrada.';end if;
 select * into v_s from public.ew_compras_solicitacoes where id=v_q.solicitacao_id for update;
 if not found then raise exception 'Solicitação da cotação não encontrada.';end if;
 if not(public.ew_pode(v_s.empresa_id,'compras.pedir') AND public.ew_pode(v_s.empresa_id,'compras.aprovar_pedido') AND public.ew_pode(v_s.empresa_id,'compras.consultar_valores')) then raise exception 'Sem permissão para aprovar pedidos.';end if;
 select * into v_q from public.ew_compras_cotacoes where id=p_cotacao_id and solicitacao_id=v_s.id for update;
 if not found or v_q.status<>'ABERTA' then raise exception 'Cotação cancelada ou indisponível.';end if;
 if not exists(select 1 from public.ew_fornecedores f where f.id=v_q.fornecedor_id and f.empresa_id=v_s.empresa_id and f.ativo) then raise exception 'Fornecedor inativo.';end if;
 select * into v_prev from public.ew_compras_pedidos where operacao_id=p_operacao_id;
 if found then
  if v_prev.empresa_id<>v_s.empresa_id OR v_prev.cotacao_id<>v_q.id
  then raise exception 'Identificador de pedido usado anteriormente para outra cotação.';end if;
  return jsonb_build_object('id',v_prev.id,'numero',v_prev.numero,'repetida',true);
 end if;
 if v_s.status<>'ABERTA' then raise exception 'Solicitação já convertida ou cancelada.';end if;
 insert into public.ew_compras_pedidos(empresa_id,solicitacao_id,cotacao_id,fornecedor_id,
  obra_id,local_empresa_id,operacao_id,itens,total_centavos,criado_por)
 values(v_q.empresa_id,v_s.id,v_q.id,v_q.fornecedor_id,v_s.obra_id,v_s.local_empresa_id,
  p_operacao_id,v_q.itens,v_q.total_centavos,auth.uid()) returning id,numero into v_id,v_numero;
 update public.ew_compras_solicitacoes set status='PEDIDO_GERADO' where id=v_s.id;
 return jsonb_build_object('id',v_id,'numero',v_numero,'repetida',false);
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_compras_criar_cotacao(p_solicitacao_id uuid, p_fornecedor_id uuid, p_precos jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s public.ew_compras_solicitacoes%rowtype;v_prev public.ew_compras_cotacoes%rowtype;
 v_i jsonb;v_price jsonb;v_old_prices jsonb;v_new_prices jsonb;
 v_id uuid;v_value bigint;v_total bigint:=0;v_items jsonb:='[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 select * into v_s from public.ew_compras_solicitacoes where id=p_solicitacao_id;
 if not found then raise exception 'Solicitação não encontrada.';end if;
 if not (public.ew_pode(v_s.empresa_id,'compras.cotar') AND public.ew_pode(v_s.empresa_id,'compras.consultar_valores')) then raise exception 'Sem permissão para cotar.';end if;
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
end;$function$;
CREATE FUNCTION public.ew_compras_historico_precos(p_empresa_id uuid,p_fornecedor_id uuid DEFAULT NULL,p_variacao_id uuid DEFAULT NULL,p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.consultar_valores') AND public.ew_pode(p_empresa_id,'compras.historico_precos')) THEN RAISE EXCEPTION 'Sem permissão para histórico de preços.';END IF;
 IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'Página inválida.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.criado_em DESC,h.cotacao_id,h.chave),'[]'::jsonb) FROM (
 SELECT q.id cotacao_id,q.solicitacao_id,q.fornecedor_id,f.nome fornecedor,q.criado_em,q.status,
 x->>'chave' chave,(x->>'variacao_id')::uuid variacao_id,x->>'unidade' unidade,(x->>'comprimento_mm')::integer comprimento_mm,
 (x->>'quantidade')::numeric quantidade,(x->>'preco_unitario_centavos')::bigint preco_unitario_centavos,
 coalesce(p.codigo,a.codigo) codigo,coalesce(p.descricao,a.descricao) descricao,v.cor,v.acabamento,
 EXISTS(SELECT 1 FROM public.ew_compras_pedidos pe WHERE pe.cotacao_id=q.id AND pe.status<>'CANCELADO') pedido_aprovado
 FROM public.ew_compras_cotacoes q
 JOIN public.ew_fornecedores f ON f.id=q.fornecedor_id AND f.empresa_id=q.empresa_id
 CROSS JOIN LATERAL jsonb_array_elements(q.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=q.empresa_id
 LEFT JOIN public.ew_perfis p ON p.id=v.perfil_id AND p.empresa_id=q.empresa_id
 LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id AND a.empresa_id=q.empresa_id
 WHERE q.empresa_id=p_empresa_id AND (p_fornecedor_id IS NULL OR q.fornecedor_id=p_fornecedor_id) AND (p_variacao_id IS NULL OR (x->>'variacao_id')::uuid=p_variacao_id)
 ORDER BY q.criado_em DESC,q.id,x->>'chave' OFFSET p_offset LIMIT 500
 ) h);
END;$f$;
CREATE FUNCTION public.ew_compras_compromissos_obra(p_empresa_id uuid,p_obra_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem acesso financeiro à obra.';END IF;
 RETURN (WITH linhas AS (
 SELECT p.id pedido_id,x->>'chave' chave,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END categoria,
 (x->>'quantidade')::numeric qtd,(x->>'preco_unitario_centavos')::bigint preco
 FROM public.ew_compras_pedidos p CROSS JOIN LATERAL jsonb_array_elements(p.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=p.empresa_id
 WHERE p.empresa_id=p_empresa_id AND p.obra_id=p_obra_id AND p.status<>'CANCELADO'
 ), conciliado AS (
 SELECT c.pedido_id,v.chave,sum(v.quantidade_fisica) qtd
 FROM public.ew_compras_nfe_conciliacoes c JOIN public.ew_compras_nfe_vinculos v ON v.conciliacao_id=c.id AND v.desvinculado_em IS NULL
 JOIN public.ew_obra_despesas d ON d.id=c.despesa_id AND d.empresa_id=c.empresa_id AND d.obra_id=p_obra_id AND d.status='aprovada'
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 WHERE c.empresa_id=p_empresa_id AND c.desvinculado_em IS NULL GROUP BY c.pedido_id,v.chave
 ), compromissos AS (
 SELECT l.categoria,sum(round(l.qtd*l.preco)) total_pedido_centavos,
 sum(round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) conciliado_centavos,
 sum(round(l.qtd*l.preco)-round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) pendente_centavos
 FROM linhas l LEFT JOIN conciliado c ON c.pedido_id=l.pedido_id AND c.chave=l.chave GROUP BY l.categoria
 ), despesas AS (
 SELECT categoria,sum(round(valor*100)) realizado_centavos FROM public.ew_obra_despesas WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND status='aprovada' GROUP BY categoria
 ), categorias AS (SELECT categoria FROM compromissos UNION SELECT categoria FROM despesas)
 SELECT coalesce(jsonb_agg(jsonb_build_object('categoria',k.categoria,'pedido_centavos',coalesce(c.total_pedido_centavos,0),'conciliado_centavos',coalesce(c.conciliado_centavos,0),'comprometido_pendente_centavos',coalesce(c.pendente_centavos,0),'realizado_centavos',coalesce(d.realizado_centavos,0),'consumido_centavos',coalesce(c.pendente_centavos,0)+coalesce(d.realizado_centavos,0)) ORDER BY k.categoria),'[]'::jsonb)
 FROM categorias k LEFT JOIN compromissos c USING(categoria) LEFT JOIN despesas d USING(categoria));
END;$f$;
REVOKE ALL ON FUNCTION public.ew_compras_historico_precos(uuid,uuid,uuid,integer),public.ew_compras_compromissos_obra(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_historico_precos(uuid,uuid,uuid,integer),public.ew_compras_compromissos_obra(uuid,uuid) TO authenticated;
COMMIT;
