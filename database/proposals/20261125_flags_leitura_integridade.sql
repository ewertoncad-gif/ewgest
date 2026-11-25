-- EWGEST: protege consultas operacionais e financeiras segundo flags existentes.
CREATE POLICY ew_flag_financeiro_select ON public.ew_precificacao_revisoes AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_precificacao_revisoes AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_precificacao_revisoes_categorias AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_precificacao_revisoes_categorias AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_precificacao_revisoes_itens AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_precificacao_revisoes_itens AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_precificacao_categorias AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_precificacao_categorias AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_precificacao_tipologias_padrao AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_precificacao_tipologias_padrao AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_empresas_faturamento_catalogo AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_empresas_faturamento_catalogo AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_select ON public.ew_niveis_orcamento_catalogo AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_financeiro_acesso ON public.ew_niveis_orcamento_catalogo AS PERMISSIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros'));
CREATE POLICY ew_flag_operacional_select ON public.ew_estoques_locais AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'estoque.receber') OR public.ew_pode(empresa_id,'estoque.gerenciar_locais') OR public.ew_pode(empresa_id,'obras.importar'));
CREATE POLICY ew_flag_operacional_select ON public.ew_estoque_movimentacoes AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais'));
CREATE POLICY ew_flag_operacional_select ON public.ew_comprimentos_comerciais AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'estoque.receber') OR public.ew_pode(empresa_id,'obras.importar'));
CREATE POLICY ew_flag_operacional_select ON public.ew_fornecedores AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'compras.consultar') OR public.ew_pode(empresa_id,'compras.cotar') OR public.ew_pode(empresa_id,'estoque.receber') OR public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'financeiro.despesas'));
CREATE POLICY ew_flag_operacional_select ON public.ew_locais_fisicos AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'estoque.receber') OR public.ew_pode(empresa_id,'estoque.gerenciar_locais') OR public.ew_pode(empresa_id,'obras.importar') OR public.ew_pode(empresa_id,'romaneios.emitir') OR public.ew_pode(empresa_id,'romaneios.transferir'));
CREATE POLICY ew_flag_operacional_select ON public.ew_liberacoes_lotes AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'liberacoes.consultar') OR public.ew_pode(empresa_id,'liberacoes.criar') OR public.ew_pode(empresa_id,'estoque.baixar') OR public.ew_pode(empresa_id,'relatorios.operacionais'));
CREATE POLICY ew_flag_operacional_select ON public.ew_planos_liberados AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'liberacoes.consultar') OR public.ew_pode(empresa_id,'liberacoes.criar') OR public.ew_pode(empresa_id,'estoque.baixar') OR public.ew_pode(empresa_id,'relatorios.operacionais'));
CREATE POLICY ew_flag_operacional_select ON public.ew_cem_obras_materiais AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'obras.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'compras.solicitar'));
CREATE POLICY ew_flag_operacional_select ON public.ew_cem_importacoes_materiais AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'obras.consultar') OR public.ew_pode(empresa_id,'obras.importar') OR public.ew_pode(empresa_id,'estoque.consultar'));
CREATE POLICY ew_flag_operacional_select ON public.ew_estoque_importacoes_cem AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'obras.importar'));
CREATE POLICY ew_flag_operacional_select ON public.ew_materiais_alias AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'obras.importar'));
CREATE POLICY ew_flag_operacional_select ON public.romaneios_motoristas AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'romaneios.consultar') OR public.ew_pode(empresa_id,'romaneios.emitir') OR public.ew_pode(empresa_id,'romaneios.transferir'));
CREATE POLICY ew_flag_operacional_select ON public.romaneios_veiculos AS RESTRICTIVE FOR SELECT TO authenticated USING (public.ew_pode(empresa_id,'romaneios.consultar') OR public.ew_pode(empresa_id,'romaneios.emitir') OR public.ew_pode(empresa_id,'romaneios.transferir'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_fornecedores AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
CREATE POLICY ew_flag_operacional_update ON public.ew_fornecedores AS RESTRICTIVE FOR UPDATE TO authenticated USING (public.ew_pode(empresa_id,'cadastros.editar')) WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_locais_fisicos AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'estoque.gerenciar_locais'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_cem_importacoes_materiais AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'obras.importar'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_planos_liberados AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'liberacoes.criar'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_empresas_faturamento_catalogo AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
CREATE POLICY ew_flag_operacional_insert ON public.ew_niveis_orcamento_catalogo AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
CREATE POLICY ew_flag_operacional_select ON public.saidas_producao AS RESTRICTIVE FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.esquadrias e WHERE e.id=esquadria_id AND (public.ew_pode(e.empresa_id,'romaneios.consultar') OR public.ew_pode(e.empresa_id,'relatorios.operacionais'))));

CREATE OR REPLACE FUNCTION public.ew_insumos_catalogo_listar(p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not (public.ew_pode(p_empresa_id,'cadastros.consultar') or public.ew_pode(p_empresa_id,'estoque.consultar') or public.ew_pode(p_empresa_id,'estoque.receber') or public.ew_pode(p_empresa_id,'financeiro.despesas')) then raise exception 'PERMISSAO_NEGADA: consulta de cadastro';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'categoria',c.categoria,'descricao',c.descricao,
  'unidade',c.unidade,'ativo',c.ativo) order by c.categoria,c.descricao,c.unidade),'[]'::jsonb)
 into v_result
 from public.ew_insumos_catalogo c where c.empresa_id=p_empresa_id;
 return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumos_estornar_transferencia(p_empresa_id uuid, p_transferencia_operacao_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_saida public.ew_insumos_movimentos%rowtype;
 v_entrada public.ew_insumos_movimentos%rowtype;v_total integer;
 v_saldo numeric;v_op uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,'estoque.estornar')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode estornar transferências.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400 or p_transferencia_operacao_id is null
 then raise exception 'Informe motivo de 5 a 400 caracteres e operação válida.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_transferencia_operacao_id::text,9011));
 select count(*) into v_total from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_transferencia_operacao_id
   and m.origem='TRANSFERENCIA';
 if v_total<>2 then raise exception 'Transferência original não encontrada ou incompleta.';end if;
 select * into v_saida from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 for update;
 select * into v_entrada from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta>0 for update;
 if v_saida.id is null or v_entrada.id is null or v_saida.insumo_id<>v_entrada.insumo_id
    or v_saida.quantidade_delta<>-v_entrada.quantidade_delta
 then raise exception 'Movimentos da transferência não conferem.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m where m.estorno_de_id in (v_saida.id,v_entrada.id))
 then raise exception 'Transferência já estornada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||v_entrada.obra_id::text||'|'||
   v_entrada.insumo_id::text||'|'||v_entrada.local_estoque,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_entrada.obra_id
   and m.insumo_id=v_entrada.insumo_id and m.local_estoque=v_entrada.local_estoque;
 if v_saldo<v_entrada.quantidade_delta then
  raise exception 'Estorno bloqueado: destino já utilizou/transferiu parte do material.';end if;
 insert into public.ew_insumos_movimentos(
  empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
  origem,operacao_id,estorno_de_id,observacao,usuario_id
 ) values
 (p_empresa_id,v_entrada.obra_id,v_entrada.insumo_id,v_entrada.local_estoque,
  -v_entrada.quantidade_delta,'ESTORNO',v_op,v_entrada.id,btrim(p_motivo),v_uid),
 (p_empresa_id,v_saida.obra_id,v_saida.insumo_id,v_saida.local_estoque,
  -v_saida.quantidade_delta,'ESTORNO',v_op,v_saida.id,btrim(p_motivo),v_uid);
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumos_receber(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_operacao_id uuid, p_itens jsonb, p_local_estoque text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_item jsonb;v_despesa uuid;v_despesa_item uuid;v_catalogo uuid;
 v_antiga public.ew_obra_despesas%rowtype;
 v_qtd numeric;v_subtotal numeric;v_total numeric:=0;v_count integer:=0;
 v_desc text;v_unit text;v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_cad public.ew_insumos_catalogo%rowtype;
begin
 IF NOT (public.ew_pode(p_empresa_id,'financeiro.despesas') AND public.ew_pode(p_empresa_id,'estoque.receber')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;
 PERFORM public.ew_exigir_permissao('financeiro.despesas');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
    and u.usuario_id=v_uid and u.perfil in ('administrador','almoxarife'))
 then raise exception 'Usuário sem permissão para recebimento.';end if;
 if p_categoria not in ('vidros','outros') or p_valor is null or p_valor<=0
  or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
  or p_data_documento is null or length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
  or length(coalesce(p_observacoes,''))>1000
  or jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Categoria, valor ou itens de NF inválidos.';end if;
 if not exists(select 1 from public.ew_obra_orcamento b
    where b.empresa_id=p_empresa_id and b.obra_id=p_obra_id)
  or not exists(select 1 from public.ew_estoques_locais l
    where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Selecione obra com orçamento e estoque ativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_local and l.ativo)
 then raise exception 'Galpão de recebimento não cadastrado/ativo.';end if;
 if not exists(select 1 from public.ew_fornecedores f
    where f.empresa_id=p_empresa_id and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione fornecedor ativo cadastrado.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(p_fornecedor))||'|'||lower(btrim(p_numero_documento)),541890));
 select * into v_antiga from public.ew_obra_despesas d
 where d.empresa_id=p_empresa_id and d.operacao_id=p_operacao_id;
 if found then
  if v_antiga.obra_id<>p_obra_id or v_antiga.categoria<>p_categoria
   or v_antiga.valor<>p_valor or v_antiga.status<>'aprovada'
   then raise exception 'Identificador de operação reutilizado para outro documento.';end if;
  select count(*) into v_count from public.ew_insumos_movimentos m
   join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
   where i.despesa_id=v_antiga.id and m.empresa_id=p_empresa_id and m.origem='RECEBIMENTO';
  if v_count<>jsonb_array_length(p_itens) then
   raise exception 'Nota anterior não possui os itens físicos esperados.';end if;
  return jsonb_build_object('id',v_antiga.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
  and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
  and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
  and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Nota já recebida deste fornecedor/categoria nesta obra.';end if;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_item) is distinct from 'object'
    or jsonb_typeof(v_item->'quantidade') is distinct from 'number'
    or jsonb_typeof(v_item->'valor_total') is distinct from 'number'
   then raise exception 'Item da nota deve ter quantidade e subtotal numéricos.';end if;
   v_desc:=upper(btrim(pg_catalog.regexp_replace(coalesce(v_item->>'descricao',''),'\s+',' ','g')));
   v_unit:=btrim(coalesce(v_item->>'unidade',''));
   v_qtd:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   if length(v_desc) not between 2 and 500
    or not exists(select 1 from public.ew_unidades_medida u where u.empresa_id=p_empresa_id and u.codigo=v_unit and u.ativo)
    or v_qtd<=0 or v_qtd>1000000 or v_qtd<>round(v_qtd,3)
    or (v_unit in ('PC','UN','CX','CJ','PR') and v_qtd<>trunc(v_qtd))
    or v_subtotal<0 or v_subtotal>999999999999.99 or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Descrição, unidade, quantidade ou subtotal inválidos.';end if;
   v_count:=v_count+1;v_total:=v_total+v_subtotal;
 end loop;
 if v_total<>p_valor then raise exception 'A soma dos itens não confere com o valor da nota.';end if;
 insert into public.ew_obra_despesas(
  empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,data_documento,
  status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id
 ) values(
  p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,btrim(p_numero_documento),
  p_data_documento,'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id
 ) returning id into v_despesa;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   v_desc:=upper(btrim(pg_catalog.regexp_replace(v_item->>'descricao','\s+',' ','g')));
   v_unit:=v_item->>'unidade';v_qtd:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   -- Cadastro compartilhado, sem mesclar itens de unidades distintas.
   insert into public.ew_insumos_catalogo(empresa_id,categoria,descricao,unidade,criado_por)
   values(p_empresa_id,p_categoria,v_desc,v_unit,v_uid)
   on conflict(empresa_id,categoria,descricao,unidade) do nothing;
   select * into v_cad from public.ew_insumos_catalogo c
    where c.empresa_id=p_empresa_id and c.categoria=p_categoria
     and c.descricao=v_desc and c.unidade=v_unit for update;
   if not found or not v_cad.ativo then raise exception 'Insumo desativado ou indisponível no catálogo.';end if;
   v_catalogo:=v_cad.id;
   insert into public.ew_obra_despesas_itens(
    despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
    valor_unitario,valor_total,perfil_id,acessorio_id
   ) values(v_despesa,p_empresa_id,'',v_desc,v_unit,v_qtd,
     round(v_subtotal/v_qtd,6),v_subtotal,null,null)
   returning id into v_despesa_item;
   insert into public.ew_insumos_movimentos(
    empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
    origem,despesa_item_id,operacao_id,observacao,usuario_id
   ) values(p_empresa_id,p_obra_id,v_catalogo,v_local,v_qtd,'RECEBIMENTO',
    v_despesa_item,p_operacao_id,'Recebimento NF '||left(p_numero_documento,70),v_uid);
 end loop;
 return jsonb_build_object('id',v_despesa,'ja_registrado',false,'itens',v_count,'estoque_fisico',true);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumos_transferir(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_insumo_id uuid, p_origem_local text, p_destino_local text, p_quantidade numeric, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_saldo numeric;v_qtd integer;v_transfer uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,case when p_origem_obra_id=p_destino_obra_id then 'estoque.transferir_galpoes' else 'estoque.transferir_obras' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;
 PERFORM public.ew_exigir_permissao('estoque.transferir_obras');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='administrador')
 then raise exception 'Somente ADM transfere estes materiais.';end if;
 if p_operacao_id is null or p_origem_obra_id is null or p_destino_obra_id is null
  or p_insumo_id is null or (p_origem_obra_id=p_destino_obra_id and v_origem=v_destino)
  or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
  or p_quantidade<>round(p_quantidade,3) or length(coalesce(p_observacao,''))>400
 then raise exception 'Transferência inválida.';end if;
 if not exists(select 1 from public.ew_insumos_catalogo c where c.id=p_insumo_id
    and c.empresa_id=p_empresa_id and c.ativo)
 then raise exception 'Material não pertence à empresa ou está inativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_origem and l.ativo)
 or not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_destino and l.ativo)
 then raise exception 'Galpão de origem/destino inválido.';end if;
 if not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_origem_obra_id and l.excluido_em is null)
 or not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_destino_obra_id and l.excluido_em is null)
 then raise exception 'Obras com estoque ativo são obrigatórias.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,9011));
 select count(*) into v_qtd from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.origem='TRANSFERENCIA';
 if v_qtd>0 then
   if v_qtd<>2 or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_origem_obra_id and m.local_estoque=v_origem
     and m.quantidade_delta=-p_quantidade
   ) or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_destino_obra_id and m.local_estoque=v_destino
     and m.quantidade_delta=p_quantidade
   ) then raise exception 'Operação já utilizada em outra transferência.';end if;
   return jsonb_build_object('ja_registrado',true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_origem_obra_id::text||'|'||
   p_insumo_id::text||'|'||v_origem,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo
 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
  and m.obra_id=p_origem_obra_id and m.insumo_id=p_insumo_id
  and m.local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente na origem. Disponível: %',v_saldo;end if;
 insert into public.ew_insumos_movimentos(
   empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
   operacao_id,transferencia_id,observacao,usuario_id
 ) values
 (p_empresa_id,p_origem_obra_id,p_insumo_id,v_origem,-p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid),
 (p_empresa_id,p_destino_obra_id,p_insumo_id,v_destino,p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid);
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_unidades_medida_listar(p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_out jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not (public.ew_pode(p_empresa_id,'cadastros.consultar') or public.ew_pode(p_empresa_id,'estoque.consultar') or public.ew_pode(p_empresa_id,'estoque.receber') or public.ew_pode(p_empresa_id,'financeiro.despesas')) then raise exception 'PERMISSAO_NEGADA: consulta de cadastro';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'codigo',u.codigo,'nome',u.nome,'ativo',u.ativo,'padrao',u.padrao)
 order by u.padrao desc,u.codigo),'[]'::jsonb) into v_out
 from public.ew_unidades_medida u where u.empresa_id=p_empresa_id;
 return v_out;
end;$function$;

CREATE OR REPLACE FUNCTION public.movimentar_estoque_ewgest(p_empresa_id uuid, p_variacao_id uuid, p_tipo text, p_quantidade numeric, p_unidade text, p_observacao text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_saldo numeric;v_registros integer;v_unidade text;v_real text;
BEGIN
 IF NOT (public.ew_pode(p_empresa_id,case when p_quantidade<0 then 'estoque.baixar' else 'estoque.receber' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
 IF v_user IS NULL OR NOT EXISTS(
 SELECT 1 FROM public.usuarios_empresas u
 JOIN public.usuarios_login l ON l.empresa_id=u.empresa_id AND l.usuario_id=u.usuario_id
 WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_user AND u.perfil IN ('administrador','gerenciador')
 AND l.ativo AND l.perfil IN ('administrador','gerenciador')) THEN RAISE EXCEPTION 'Somente ADM pode registrar movimentações de estoque.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_materiais_variacoes v WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id)
 THEN RAISE EXCEPTION 'Variação de material não encontrada na empresa.';END IF;
 IF p_tipo NOT IN ('INVENTARIO_INICIAL','ENTRADA','SAIDA','AJUSTE') OR
 p_quantidade IS NULL OR p_quantidade=0 OR abs(p_quantidade)>1e9
 THEN RAISE EXCEPTION 'Tipo ou quantidade inválida.';END IF;
 IF p_tipo IN ('INVENTARIO_INICIAL','ENTRADA') AND p_quantidade<0
 THEN RAISE EXCEPTION 'Use quantidade positiva para inventário e entradas.';END IF;
 IF p_tipo='SAIDA' AND p_quantidade>0
 THEN RAISE EXCEPTION 'Saídas devem ser negativas.';END IF;
 IF length(coalesce(p_observacao,''))>500 THEN RAISE EXCEPTION 'Observação demasiado longa.';END IF;
 v_unidade:=upper(btrim(coalesce(p_unidade,'')));
 IF v_unidade NOT IN ('M','PC','MT','PR','CJ','KG','UN') THEN RAISE EXCEPTION 'Unidade de estoque inválida.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_variacao_id::text,90041));
 SELECT count(*),coalesce(sum(quantidade_delta),0),min(unidade)
 INTO v_registros,v_saldo,v_real FROM public.ew_estoque_movimentacoes
 WHERE empresa_id=p_empresa_id AND variacao_id=p_variacao_id;
 IF v_registros>0 AND v_real<>v_unidade THEN
 RAISE EXCEPTION 'Unidade divergente. Estoque deste item é controlado em %.',v_real;END IF;
 IF p_tipo='INVENTARIO_INICIAL' AND v_registros>0 THEN
 RAISE EXCEPTION 'Inventário inicial já realizado. Use entrada, saída ou ajuste.';END IF;
 IF v_saldo+p_quantidade<0 THEN
 RAISE EXCEPTION 'Saldo insuficiente. Disponível: % %.',v_saldo,v_unidade;END IF;
 INSERT INTO public.ew_estoque_movimentacoes(empresa_id,variacao_id,tipo,quantidade_delta,unidade,observacao,criado_por)
 VALUES(p_empresa_id,p_variacao_id,p_tipo,p_quantidade,v_unidade,btrim(coalesce(p_observacao,'')),v_user);
 RETURN jsonb_build_object('saldo',v_saldo+p_quantidade,'unidade',v_unidade,'tipo',p_tipo);
END;$function$;
