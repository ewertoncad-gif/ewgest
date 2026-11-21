-- EWGEST v45.6: Cadastro de unidades de medida para vidros/outros insumos.
-- Preserva saldos, itens e notas existentes. Nenhuma conversao automatica de unidades.
create table if not exists public.ew_unidades_medida (
  empresa_id uuid not null references public.empresas(id) on delete restrict,
  codigo text not null,
  nome text not null,
  ativo boolean not null default true,
  padrao boolean not null default false,
  criado_em timestamptz not null default now(),
  alterado_em timestamptz not null default now(),
  primary key(empresa_id,codigo),
  constraint ew_unidades_codigo_valido check (codigo ~ '^[A-Z0-9]{1,8}$'),
  constraint ew_unidades_nome_valido check (char_length(btrim(nome)) between 2 and 80)
);
alter table public.ew_unidades_medida enable row level security;
revoke all on table public.ew_unidades_medida from anon,authenticated;
-- Unidades basicas existentes: sem alterar os codigos historicos.
insert into public.ew_unidades_medida(empresa_id,codigo,nome,padrao)
select e.id,u.codigo,u.nome,true from public.empresas e
cross join (values
 ('PC','Peça'),('UN','Unidade'),('M2','Metro quadrado'),('MT','Metro'),
 ('KG','Quilograma'),('CX','Caixa'),('CJ','Conjunto'),('PR','Par')
) as u(codigo,nome)
on conflict (empresa_id,codigo) do nothing;
-- Garantir os padroes tambem nas empresas adicionadas depois desta migracao.
create or replace function public.ew_unidades_padrao_nova_empresa()
returns trigger language plpgsql security definer set search_path='' as $fun$
begin
 insert into public.ew_unidades_medida(empresa_id,codigo,nome,padrao)
 select new.id,x.codigo,x.nome,true from (values
 ('PC','Peça'),('UN','Unidade'),('M2','Metro quadrado'),('MT','Metro'),
 ('KG','Quilograma'),('CX','Caixa'),('CJ','Conjunto'),('PR','Par')
 ) as x(codigo,nome)
 on conflict (empresa_id,codigo) do nothing;
 return new;
end;$fun$;
drop trigger if exists ew_empresa_preencher_unidades on public.empresas;
create trigger ew_empresa_preencher_unidades after insert on public.empresas
for each row execute function public.ew_unidades_padrao_nova_empresa();
revoke all on function public.ew_unidades_padrao_nova_empresa() from public,anon,authenticated;
-- Em vez de lista fixa de oito unidades, usar referencia da propria empresa.
alter table public.ew_insumos_catalogo
 drop constraint if exists ew_insumos_catalogo_unidade_check;
alter table public.ew_insumos_catalogo
 add constraint ew_insumos_catalogo_unidade_fk foreign key (empresa_id,unidade)
 references public.ew_unidades_medida(empresa_id,codigo)
 on update restrict on delete restrict;
-- A interface e os lancamentos ja guardam os codigos em texto: nenhuma regravacao.
create or replace function public.ew_unidades_medida_listar(p_empresa_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $fun$
declare v_uid uuid:=auth.uid();v_out jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
 select 1 from public.usuarios_empresas ue where ue.empresa_id=p_empresa_id
 and ue.usuario_id=v_uid and ue.perfil in ('administrador','gerenciador','almoxarife')
 ) then raise exception 'Acesso negado a unidades desta empresa.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'codigo',u.codigo,'nome',u.nome,'ativo',u.ativo,'padrao',u.padrao)
 order by u.padrao desc,u.codigo),'[]'::jsonb) into v_out
 from public.ew_unidades_medida u where u.empresa_id=p_empresa_id;
 return v_out;
end;$fun$;
create or replace function public.ew_unidades_medida_gerenciar(
 p_empresa_id uuid,p_acao text,p_codigo text,p_nome text default null
) returns jsonb language plpgsql security definer set search_path='' as $fun$
declare v_uid uuid:=auth.uid();v_codigo text:=upper(btrim(coalesce(p_codigo,'')));
 v_nome text:=btrim(coalesce(p_nome,''));v_rec public.ew_unidades_medida%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas ue
 where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and ue.perfil='administrador')
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
end;$fun$;
revoke all on function public.ew_unidades_medida_listar(uuid) from public,anon;
revoke all on function public.ew_unidades_medida_gerenciar(uuid,text,text,text) from public,anon;
grant execute on function public.ew_unidades_medida_listar(uuid) to authenticated;
grant execute on function public.ew_unidades_medida_gerenciar(uuid,text,text,text) to authenticated;

-- Substituir apenas a validacao fixa das unidades nas RPCs existentes.
CREATE OR REPLACE FUNCTION public.ew_insumo_gerenciar_catalogo(p_empresa_id uuid, p_acao text, p_id uuid DEFAULT NULL::uuid, p_categoria text DEFAULT NULL::text, p_descricao text DEFAULT NULL::text, p_unidade text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_nome text;v_item public.ew_insumos_catalogo%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil='administrador'
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
CREATE OR REPLACE FUNCTION public.ew_receber_despesa_com_itens_almox(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_operacao_id uuid, p_itens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_item jsonb;v_despesa uuid;
 v_previous public.ew_obra_despesas%rowtype;
 v_qty numeric;v_subtotal numeric;v_total numeric:=0;
 v_descricao text;v_unidade text;v_count integer:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
    or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
      and u.usuario_id=v_uid and u.perfil='almoxarife')
 then raise exception 'Acesso não autorizado ao recebimento.';end if;
 if p_categoria not in ('vidros','outros') or p_valor is null
    or p_valor<=0 or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
    or p_data_documento is null or
    length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
    or length(coalesce(p_observacoes,''))>1000
    or jsonb_typeof(p_itens) is distinct from 'array'
    or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Nota, categoria ou itens inválidos.';end if;
 if not exists(select 1 from public.ew_obra_orcamento o
      where o.empresa_id=p_empresa_id and o.obra_id=p_obra_id)
 then raise exception 'Obra sem orçamento cadastrado.';end if;
 if not exists(select 1 from public.ew_fornecedores f where f.empresa_id=p_empresa_id
      and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione um fornecedor ativo cadastrado.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(p_fornecedor))||'|'||lower(btrim(p_numero_documento)),541890));
 select * into v_previous from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
   and d.operacao_id=p_operacao_id;
 if found then
   if v_previous.obra_id<>p_obra_id or v_previous.categoria<>p_categoria
      or v_previous.valor<>p_valor or v_previous.status<>'aprovada'
   then raise exception 'Identificador já utilizado para outro lançamento.';end if;
   select count(*) into v_count from public.ew_obra_despesas_itens i
     where i.despesa_id=v_previous.id and i.empresa_id=p_empresa_id;
   if v_count<>jsonb_array_length(p_itens) then
    raise exception 'Documento anterior não corresponde ao número de itens.';end if;
   return jsonb_build_object('id',v_previous.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
     and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
     and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
     and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Esta nota já foi lançada para o fornecedor e categoria selecionados.';end if;

 for v_item in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item->'quantidade') is distinct from 'number'
      or jsonb_typeof(v_item->'valor_total') is distinct from 'number'
   then raise exception 'Item sem quantidade ou subtotal numérico.';end if;
   v_descricao:=btrim(coalesce(v_item->>'descricao',''));
   v_unidade:=btrim(coalesce(v_item->>'unidade',''));
   v_qty:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   if char_length(v_descricao) not between 2 and 500
      or not exists(select 1 from public.ew_unidades_medida u where u.empresa_id=p_empresa_id and u.codigo=v_unidade and u.ativo)
      or v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,3)
      or v_subtotal<0 or v_subtotal>999999999999.99
      or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Descrição, unidade, quantidade ou valor inválido no item.';end if;
   v_total:=v_total+v_subtotal;
   v_count:=v_count+1;
 end loop;
 if v_total<>p_valor then raise exception 'A soma dos itens não corresponde ao total da nota.';end if;
 insert into public.ew_obra_despesas(
  empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
  data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 values(p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,
   btrim(p_numero_documento),p_data_documento,'aprovada',coalesce(p_observacoes,''),
   v_uid,v_uid,now(),p_operacao_id)
 returning id into v_despesa;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   v_qty:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   insert into public.ew_obra_despesas_itens(
     despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
     valor_unitario,valor_total,perfil_id,acessorio_id)
   values(v_despesa,p_empresa_id,'',left(btrim(v_item->>'descricao'),500),
     v_item->>'unidade',v_qty,round(v_subtotal/v_qty,6),v_subtotal,null,null);
 end loop;
 -- Nenhuma gravação em ew_nfe_recebimentos ou ew_estoque_obras_movimentos:
 -- não há catálogo físico de vidros/outros insumos neste estágio.
 return jsonb_build_object('id',v_despesa,'ja_registrado',false,
   'itens_recebidos',v_count,'sem_estoque_fisico',true);
end
$function$;
