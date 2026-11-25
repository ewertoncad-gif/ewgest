-- Autorizações por flag e empresa alvo. Preserva validações de negócio.
CREATE OR REPLACE FUNCTION public.ew_gerenciar_cadastro_auxiliar(p_empresa_id uuid, p_tipo text, p_id uuid, p_acao text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_antigo text;v_novo text;v_em_uso boolean;
begin
 IF NOT public.ew_pode(p_empresa_id,case when p_tipo='galpao' then 'estoque.gerenciar_locais' else 'cadastros.editar' end) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastro auxiliar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
 then raise exception 'Somente administrador pode alterar/excluir cadastros.';end if;
 if p_tipo not in ('fornecedor','galpao') or p_acao not in ('editar','excluir')
  or p_id is null
 then raise exception 'Tipo ou operação inválida.';end if;
 if p_tipo='fornecedor' then
   select nome into v_antigo from public.ew_fornecedores
     where empresa_id=p_empresa_id and id=p_id for update;
   if not found then raise exception 'Fornecedor não encontrado nesta empresa.';end if;
   select exists(select 1 from public.ew_obra_despesas d
     where d.empresa_id=p_empresa_id and lower(btrim(d.fornecedor))=lower(btrim(v_antigo)))
     into v_em_uso;
 else
   select nome into v_antigo from public.ew_locais_fisicos
     where empresa_id=p_empresa_id and id=p_id for update;
   if not found then raise exception 'Galpão não encontrado nesta empresa.';end if;
   select exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=p_empresa_id and upper(btrim(m.local_estoque))=upper(btrim(v_antigo)))
    or exists(select 1 from public.ew_nfe_recebimentos n
     where n.empresa_id=p_empresa_id and upper(btrim(n.local_estoque))=upper(btrim(v_antigo)))
    or exists(select 1 from public.ew_insumos_movimentos m
     where m.empresa_id=p_empresa_id and upper(btrim(m.local_estoque))=upper(btrim(v_antigo)))
     into v_em_uso;
 end if;
 if v_em_uso then
  raise exception 'Cadastro em uso em notas ou estoque. Histórico preservado; não é possível editar/excluir.';
 end if;
 if p_acao='excluir' then
   if p_tipo='fornecedor' then
     delete from public.ew_fornecedores where id=p_id and empresa_id=p_empresa_id;
   else
     delete from public.ew_locais_fisicos where id=p_id and empresa_id=p_empresa_id;
   end if;
   return jsonb_build_object('acao','excluido','tipo',p_tipo);
 end if;
 v_novo:=upper(btrim(pg_catalog.regexp_replace(coalesce(p_nome,''),'\s+',' ','g')));
 if char_length(v_novo)<3 or char_length(v_novo)>
   (case when p_tipo='fornecedor' then 180 else 80 end)
 then raise exception 'Nome inválido.';end if;
 if p_tipo='fornecedor' then
  if exists(select 1 from public.ew_fornecedores f
    where f.empresa_id=p_empresa_id and upper(btrim(f.nome))=v_novo and f.id<>p_id)
  then raise exception 'Já existe fornecedor com este nome.';end if;
  update public.ew_fornecedores set nome=v_novo where id=p_id and empresa_id=p_empresa_id;
 else
  if exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and upper(btrim(l.nome))=v_novo and l.id<>p_id)
  then raise exception 'Já existe galpão com este nome.';end if;
  update public.ew_locais_fisicos set nome=v_novo where id=p_id and empresa_id=p_empresa_id;
 end if;
 return jsonb_build_object('acao','editado','tipo',p_tipo,'nome',v_novo);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumo_gerenciar_catalogo(p_empresa_id uuid, p_acao text, p_id uuid DEFAULT NULL::uuid, p_categoria text DEFAULT NULL::text, p_descricao text DEFAULT NULL::text, p_unidade text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_nome text;v_item public.ew_insumos_catalogo%rowtype;
begin
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid
 ) then raise exception 'Somente ADM gerencia catálogo de insumos.';end if;
 if p_acao not in ('criar','editar','excluir') then raise exception 'Ação inválida.';end if;
 if p_acao<>'criar' then
  select * into v_item from public.ew_insumos_catalogo where empresa_id=p_empresa_id and id=p_id for update;
  if not found then raise exception 'Cadastro não encontrado nesta empresa.';end if;
  if exists(select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id and m.insumo_id=p_id)
  then raise exception 'Este material possui movimentações/histórico. Não pode editar ou excluir.';end if;
 end if;
 if p_acao='excluir' then
   delete from public.ew_insumos_catalogo where empresa_id=p_empresa_id and id=p_id;
   return jsonb_build_object('excluido',true,'id',p_id);
 end if;
 v_nome:=upper(btrim(pg_catalog.regexp_replace(coalesce(p_descricao,''),'\s+',' ','g')));
 if length(v_nome) not between 2 and 500 or p_categoria not in ('vidros','outros')
  or not exists(select 1 from public.ew_unidades_medida u where u.empresa_id=p_empresa_id and u.codigo=p_unidade and u.ativo)
 then raise exception 'Tipo, descrição ou unidade inválidos.';end if;
 if p_acao='criar' then
  insert into public.ew_insumos_catalogo(empresa_id,categoria,descricao,unidade,criado_por)
    values(p_empresa_id,p_categoria,v_nome,p_unidade,v_uid) returning id into p_id;
 else
  update public.ew_insumos_catalogo set categoria=p_categoria,descricao=v_nome,unidade=p_unidade
   where empresa_id=p_empresa_id and id=p_id;
 end if;
 return jsonb_build_object('id',p_id,'acao',p_acao);
exception when unique_violation then
 raise exception 'Este material e unidade já estão cadastrados.';
when foreign_key_violation then
 raise exception 'Cadastro usado por outro registro; exclusão bloqueada.';
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

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid)
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

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
    and u.usuario_id=v_uid)
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

CREATE OR REPLACE FUNCTION public.ew_insumos_saldos_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 IF NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.consultar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid
 ) or not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id)
 then raise exception 'Sem acesso aos saldos desta obra.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'insumo_id',s.insumo_id,'categoria',s.categoria,'descricao',s.descricao,
  'unidade',s.unidade,'galpao',s.local_estoque,'saldo',s.saldo)
  order by s.categoria,s.descricao,s.unidade,s.local_estoque),'[]'::jsonb)
 into v_result
 from (
  select m.insumo_id,c.categoria,c.descricao,c.unidade,m.local_estoque,
    sum(m.quantidade_delta) saldo
  from public.ew_insumos_movimentos m join public.ew_insumos_catalogo c
    on c.id=m.insumo_id and c.empresa_id=m.empresa_id
  where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
  group by m.insumo_id,c.categoria,c.descricao,c.unidade,m.local_estoque
 ) s;
 return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumos_transferencias_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 IF NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.consultar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
   where u.empresa_id=p_empresa_id and u.usuario_id=v_uid)
 then raise exception 'Somente ADM pode consultar os estornos de transferências.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'operacao_id',s.operacao_id,'material',s.descricao,'unidade',s.unidade,
  'quantidade',s.quantidade,'obra_origem',s.obra_origem,'galpao_origem',s.galpao_origem,
  'obra_destino',s.obra_destino,'galpao_destino',s.galpao_destino,
  'estornada',s.estornada,'criado_em',s.criado_em)
  order by s.criado_em desc),'[]'::jsonb) into v_result
 from (
  select m.operacao_id,c.descricao,c.unidade,-m.quantidade_delta quantidade,
   o1.nome obra_origem,m.local_estoque galpao_origem,
   o2.nome obra_destino,p.local_estoque galpao_destino,
   m.criado_em,
   exists(select 1 from public.ew_insumos_movimentos e
    where e.empresa_id=p_empresa_id and e.estorno_de_id in (m.id,p.id)) estornada
  from public.ew_insumos_movimentos m
   join public.ew_insumos_movimentos p on p.empresa_id=m.empresa_id
     and p.transferencia_id=m.transferencia_id and p.quantidade_delta>0
   join public.ew_insumos_catalogo c on c.empresa_id=m.empresa_id and c.id=m.insumo_id
   join public.obras o1 on o1.empresa_id=m.empresa_id and o1.id=m.obra_id
   join public.obras o2 on o2.empresa_id=p.empresa_id and o2.id=p.obra_id
  where m.empresa_id=p_empresa_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 and (m.obra_id=p_obra_id or p.obra_id=p_obra_id)
  order by m.criado_em desc limit 150
 ) s;
 return v_result;
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

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
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

CREATE OR REPLACE FUNCTION public.ew_unidades_medida_gerenciar(p_empresa_id uuid, p_acao text, p_codigo text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_codigo text:=upper(btrim(coalesce(p_codigo,'')));
 v_nome text:=btrim(coalesce(p_nome,''));v_rec public.ew_unidades_medida%rowtype;
begin
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas ue
 where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid)
 then raise exception 'Somente ADM pode gerenciar unidades de medida.';end if;
 if v_codigo !~ '^[A-Z0-9]{1,8}$'
 then raise exception 'Código inválido. Use 1 a 8 letras ou números sem espaços (ex.: L, ML, M3).';end if;
 if p_acao not in ('criar','renomear','excluir') then raise exception 'Ação inválida.';end if;
 if p_acao<>'excluir' and char_length(v_nome) not between 2 and 80
 then raise exception 'Informe a descrição com 2 a 80 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_empresa_id::text||'|'||v_codigo,47440));
 if p_acao='criar' then
  if exists(select 1 from public.ew_unidades_medida
    where empresa_id=p_empresa_id and codigo=v_codigo)
  then raise exception 'Unidade % já cadastrada.',v_codigo;end if;
  insert into public.ew_unidades_medida(empresa_id,codigo,nome)
   values(p_empresa_id,v_codigo,v_nome);
 else
  select * into v_rec from public.ew_unidades_medida
   where empresa_id=p_empresa_id and codigo=v_codigo for update;
  if not found then raise exception 'Unidade não encontrada nesta empresa.';end if;
  if p_acao='renomear' then
   update public.ew_unidades_medida
   set nome=v_nome,alterado_em=now()
   where empresa_id=p_empresa_id and codigo=v_codigo;
  else
   if v_rec.padrao then raise exception 'Unidades padrão não podem ser excluídas.';end if;
   if exists(select 1 from public.ew_insumos_catalogo c
    where c.empresa_id=p_empresa_id and c.unidade=v_codigo)
    or exists(select 1 from public.ew_obra_despesas_itens i
     where i.empresa_id=p_empresa_id and i.unidade=v_codigo)
   then raise exception 'Unidade já usada por material ou nota: exclusão bloqueada.';end if;
   delete from public.ew_unidades_medida
    where empresa_id=p_empresa_id and codigo=v_codigo;
  end if;
 end if;
 return jsonb_build_object('codigo',v_codigo,'acao',p_acao);
end;$function$;

ALTER POLICY "ADM cadastra fornecedores da empresa" ON public.ew_fornecedores TO authenticated WITH CHECK (criado_por=auth.uid() AND public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM cadastra galpoes" ON public.ew_locais_fisicos TO authenticated WITH CHECK (criado_por=auth.uid() AND public.ew_pode(empresa_id,'estoque.gerenciar_locais'));
-- Edição de nome e exclusão somente pela RPC, que verifica histórico.
REVOKE UPDATE,DELETE ON public.ew_fornecedores,public.ew_locais_fisicos FROM authenticated,anon,PUBLIC;
