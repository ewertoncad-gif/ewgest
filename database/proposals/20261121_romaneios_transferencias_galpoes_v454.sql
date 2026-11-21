-- EWGEST v45.4 — romaneios de transferencias fisicas entre galpoes.
-- Nao altera os lancamentos de estoque existentes nem reprocessa transferencias antigas.
-- A emissao/agrupamento/impressao NUNCA executa nova movimentacao de estoque.
create table if not exists public.ew_romaneios_transferencia (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 numero text not null unique,
 obra_id uuid not null references public.obras(id),
 origem_galpao text not null,
 destino_galpao text not null,
 data_saida date not null default current_date,
 motorista text not null default '',
 placa text not null default '',
 observacoes text not null default '',
 status text not null default 'RASCUNHO'
  check (status in ('RASCUNHO','EMITIDO','AGRUPADO','CANCELADO')),
 agrupado_em uuid references public.ew_romaneios_transferencia(id),
 criado_por uuid,
 criado_em timestamptz not null default now(),
 atualizado_em timestamptz not null default now(),
 emitido_em timestamptz,
 cancelado_em timestamptz
);
create index if not exists ew_romaneios_transf_empresa on public.ew_romaneios_transferencia(empresa_id,criado_em desc);
create table if not exists public.ew_romaneios_transferencia_itens (
 id uuid primary key default gen_random_uuid(),
 documento_id uuid not null references public.ew_romaneios_transferencia(id),
 tipo text not null check(tipo in ('TRANSFERENCIA','AVULSO')),
 transferencia_id uuid unique,
 movimento_saida_id uuid references public.ew_estoque_obras_movimentos(id),
 movimento_entrada_id uuid references public.ew_estoque_obras_movimentos(id),
 obra_origem_id uuid references public.obras(id),
 obra_destino_id uuid references public.obras(id),
 variacao_id uuid references public.ew_materiais_variacoes(id),
 codigo text not null default '',
 descricao text not null,
 quantidade numeric not null check(quantidade>0),
 unidade text not null,
 comprimento_mm integer,
 cor text not null default '',
 criado_em timestamptz not null default now(),
 constraint ew_transf_item_vinculo check (
  (tipo='TRANSFERENCIA' and transferencia_id is not null and movimento_saida_id is not null and movimento_entrada_id is not null)
  or (tipo='AVULSO' and transferencia_id is null and movimento_saida_id is null and movimento_entrada_id is null)
 )
);
create index if not exists ew_rom_transf_itens_doc on public.ew_romaneios_transferencia_itens(documento_id);
create table if not exists public.ew_romaneios_transferencia_auditoria (
 id uuid primary key default gen_random_uuid(),
 documento_id uuid not null references public.ew_romaneios_transferencia(id),
 usuario_id uuid,
 evento text not null,
 detalhes jsonb not null default '{}'::jsonb,
 criado_em timestamptz not null default now()
);
create index if not exists ew_rom_transf_audit_doc on public.ew_romaneios_transferencia_auditoria(documento_id,criado_em);
alter table public.ew_romaneios_transferencia enable row level security;
alter table public.ew_romaneios_transferencia_itens enable row level security;
alter table public.ew_romaneios_transferencia_auditoria enable row level security;
revoke all on public.ew_romaneios_transferencia,public.ew_romaneios_transferencia_itens,
 public.ew_romaneios_transferencia_auditoria from anon,authenticated;

-- O par de movimentacoes ja esta inserido pelo RPC de transferencia.
-- Os gatilhos AFTER ROW enxergam o lote completo de INSERT.
create or replace function public.ew_gerar_romaneio_de_transferencia()
returns trigger language plpgsql security definer set search_path='' as $body$
declare v_entrada public.ew_estoque_obras_movimentos%rowtype;
 v_numero text;v_documento uuid;v_codigo text;v_descricao text;v_cor text;
begin
 if new.origem<>'TRANSFERENCIA' or new.quantidade_delta>=0
    or new.transferencia_id is null or new.estorno_de_id is not null then return new;end if;
 select * into v_entrada from public.ew_estoque_obras_movimentos m
 where m.transferencia_id=new.transferencia_id and m.empresa_id=new.empresa_id
   and m.quantidade_delta=-new.quantidade_delta and m.quantidade_delta>0
   and m.variacao_id=new.variacao_id and m.unidade=new.unidade
   and m.comprimento_mm is not distinct from new.comprimento_mm
   and m.origem='TRANSFERENCIA'
 limit 1;
 if v_entrada.id is null then
  raise exception 'Transferencia sem par de entrada: romaneio nao pode ser gerado.';
 end if;
 if exists(select 1 from public.ew_romaneios_transferencia_itens
  where transferencia_id=new.transferencia_id) then return new;end if;
 select coalesce(p.codigo,a.codigo,'SEM CODIGO'),
   coalesce(p.descricao,a.descricao,'Material sem descricao'),
   coalesce(nullif(to_jsonb(v)->>'cor',''),nullif(to_jsonb(v)->>'acabamento',''),'')
 into v_codigo,v_descricao,v_cor
 from public.ew_materiais_variacoes v
 left join public.ew_perfis p on p.id=v.perfil_id
 left join public.ew_acessorios a on a.id=v.acessorio_id
 where v.id=new.variacao_id and v.empresa_id=new.empresa_id;
 v_numero:='RM'||lpad(nextval('public.romaneios_numero_seq'::regclass)::text,3,'0');
 insert into public.ew_romaneios_transferencia
  (empresa_id,numero,obra_id,origem_galpao,destino_galpao,criado_por)
 values(new.empresa_id,v_numero,new.obra_id,new.local_estoque,
  v_entrada.local_estoque,new.usuario_id) returning id into v_documento;
 insert into public.ew_romaneios_transferencia_itens
 (documento_id,tipo,transferencia_id,movimento_saida_id,movimento_entrada_id,
  obra_origem_id,obra_destino_id,variacao_id,codigo,descricao,
  quantidade,unidade,comprimento_mm,cor)
 values(v_documento,'TRANSFERENCIA',new.transferencia_id,new.id,v_entrada.id,
  new.obra_id,v_entrada.obra_id,new.variacao_id,coalesce(v_codigo,'SEM CODIGO'),
  coalesce(v_descricao,'Material'),-new.quantidade_delta,new.unidade,new.comprimento_mm,
  coalesce(v_cor,''));
 insert into public.ew_romaneios_transferencia_auditoria
  (documento_id,usuario_id,evento,detalhes)
 values(v_documento,new.usuario_id,'GERADO_POR_TRANSFERENCIA',
  jsonb_build_object('transferencia_id',new.transferencia_id,
  'origem',new.local_estoque,'destino',v_entrada.local_estoque));
 return new;
end;$body$;
drop trigger if exists ew_gera_romaneio_transferencia on public.ew_estoque_obras_movimentos;
create trigger ew_gera_romaneio_transferencia
 after insert on public.ew_estoque_obras_movimentos for each row
 execute function public.ew_gerar_romaneio_de_transferencia();
revoke all on function public.ew_gerar_romaneio_de_transferencia() from public,anon,authenticated;

-- Listagem inclui itens e marca transferencias revertidas sem apagar historico.
create or replace function public.ew_romaneios_transferencia_listar(p_empresa_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not exists(select 1 from public.usuarios_empresas ue
 join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
 where ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','supervisor','almoxarife'))
 then raise exception 'Sem acesso aos romaneios desta empresa.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',d.id,'numero',d.numero,'obra_id',d.obra_id,
   'origem',d.origem_galpao,'destino',d.destino_galpao,'data',d.data_saida,
   'motorista',d.motorista,'placa',d.placa,'observacoes',d.observacoes,
   'status',d.status,'agrupado_em',d.agrupado_em,'criado_em',d.criado_em,
   'itens',coalesce((select jsonb_agg(jsonb_build_object(
     'id',i.id,'tipo',i.tipo,'transferencia_id',i.transferencia_id,
     'origem_obra_id',i.obra_origem_id,'destino_obra_id',i.obra_destino_id,
     'codigo',i.codigo,'descricao',i.descricao,'quantidade',i.quantidade,
     'unidade',i.unidade,'comprimento_mm',i.comprimento_mm,'cor',i.cor,
     'estornado', (i.tipo='TRANSFERENCIA' and exists(
        select 1 from public.ew_estoque_obras_movimentos e
        where e.estorno_de_id in (i.movimento_saida_id,i.movimento_entrada_id))))
     order by i.criado_em,i.id) from public.ew_romaneios_transferencia_itens i
     where i.documento_id=d.id),'[]'::jsonb)
 ) order by d.criado_em desc),'[]'::jsonb) into v_result
 from public.ew_romaneios_transferencia d where d.empresa_id=p_empresa_id;
 return coalesce(v_result,'[]'::jsonb);
end;$body$;

-- Edita apenas documentos ainda nao emitidos; itens de estoque sao imutaveis.
create or replace function public.ew_romaneio_transferencia_salvar(
 p_empresa_id uuid,p_documento_id uuid,p_data date,p_motorista text,
 p_placa text,p_observacoes text,p_avulsos jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare v_uid uuid:=auth.uid();v_doc public.ew_romaneios_transferencia%rowtype;
 v_item jsonb;v_qtd numeric;v_antigos jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not exists(select 1 from public.usuarios_empresas ue
 join public.usuarios_login ul on ul.empresa_id=ue.empresa_id and ul.usuario_id=ue.usuario_id
 where ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','almoxarife')) then
 raise exception 'Sem permissao para editar romaneio.';end if;
 select * into v_doc from public.ew_romaneios_transferencia
 where id=p_documento_id and empresa_id=p_empresa_id for update;
 if v_doc.id is null or v_doc.status<>'RASCUNHO' then
 raise exception 'Somente romaneios de transferencia em rascunho podem ser editados.';end if;
 if p_data is null or length(coalesce(p_motorista,''))>100
 or length(coalesce(p_placa,''))>20 or length(coalesce(p_observacoes,''))>1500
 then raise exception 'Dados de transporte invalidos.';end if;
 if p_avulsos is null then p_avulsos:='[]'::jsonb;end if;
 if jsonb_typeof(p_avulsos)<>'array' or jsonb_array_length(p_avulsos)>40 then
 raise exception 'Lista de itens avulsos invalida.';end if;
 for v_item in select value from jsonb_array_elements(p_avulsos) loop
  if jsonb_typeof(v_item)<>'object' then raise exception 'Item avulso invalido.';end if;
  begin v_qtd:=(v_item->>'quantidade')::numeric;
  exception when invalid_text_representation then raise exception 'Quantidade avulsa invalida.';end;
  if v_qtd is null or v_qtd<=0 or v_qtd>1000000 or
   length(btrim(coalesce(v_item->>'descricao',''))) not between 2 and 250 or
   length(coalesce(v_item->>'codigo',''))>40 or
   length(btrim(coalesce(v_item->>'unidade',''))) not between 1 and 12 then
   raise exception 'Preencha descricao, quantidade e unidade validas para os itens avulsos.';end if;
 end loop;
 select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) into v_antigos
 from public.ew_romaneios_transferencia_itens i where i.documento_id=v_doc.id and i.tipo='AVULSO';
 update public.ew_romaneios_transferencia set data_saida=p_data,
  motorista=btrim(coalesce(p_motorista,'')),placa=upper(btrim(coalesce(p_placa,''))),
  observacoes=coalesce(p_observacoes,''),atualizado_em=now()
 where id=v_doc.id;
 delete from public.ew_romaneios_transferencia_itens where documento_id=v_doc.id and tipo='AVULSO';
 for v_item in select value from jsonb_array_elements(p_avulsos) loop
  insert into public.ew_romaneios_transferencia_itens
   (documento_id,tipo,codigo,descricao,quantidade,unidade)
  values(v_doc.id,'AVULSO',btrim(coalesce(v_item->>'codigo','')),
   btrim(v_item->>'descricao'),(v_item->>'quantidade')::numeric,
   upper(btrim(v_item->>'unidade')));
 end loop;
 insert into public.ew_romaneios_transferencia_auditoria(documento_id,usuario_id,evento,detalhes)
 values(v_doc.id,v_uid,'EDITADO',jsonb_build_object(
  'antes',to_jsonb(v_doc),'itens_avulsos_anteriores',v_antigos));
 return jsonb_build_object('id',v_doc.id,'numero',v_doc.numero);
end;$body$;

create or replace function public.ew_romaneios_transferencia_juntar(
 p_empresa_id uuid,p_principal_id uuid,p_outros uuid[])
returns jsonb language plpgsql security definer set search_path='' as $body$
declare v_uid uuid:=auth.uid();v_master public.ew_romaneios_transferencia%rowtype;
 v_doc public.ew_romaneios_transferencia%rowtype;v_id uuid;v_count integer:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if not exists(select 1 from public.usuarios_empresas ue
 join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
 where ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','almoxarife')) then
 raise exception 'Sem permissao para juntar romaneios.';end if;
 if p_outros is null or cardinality(p_outros) not between 1 and 30
 then raise exception 'Selecione ao menos outro romaneio.';end if;
 -- Lock transacional por empresa: evita edicoes e agrupamentos simultaneos.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ROMTRANS|'||p_empresa_id::text,61741));
 select * into v_master from public.ew_romaneios_transferencia
 where id=p_principal_id and empresa_id=p_empresa_id for update;
 if v_master.id is null or v_master.status<>'RASCUNHO' then
 raise exception 'O romaneio principal deve estar em rascunho.';end if;
 for v_id in select distinct x from unnest(p_outros) as x order by x loop
  if v_id=p_principal_id then continue;end if;
  select * into v_doc from public.ew_romaneios_transferencia
   where id=v_id and empresa_id=p_empresa_id for update;
  if v_doc.id is null or v_doc.status<>'RASCUNHO' or
   v_doc.origem_galpao<>v_master.origem_galpao or
   v_doc.destino_galpao<>v_master.destino_galpao then
   raise exception 'Somente rascunhos da mesma rota (galpao de origem e destino) podem ser agrupados.';end if;
  if exists(select 1 from public.ew_romaneios_transferencia_itens i
   join public.ew_estoque_obras_movimentos e on e.estorno_de_id in
    (i.movimento_saida_id,i.movimento_entrada_id)
   where i.documento_id=v_id and i.tipo='TRANSFERENCIA') then
   raise exception 'Existe transferencia estornada; nao pode agrupar.';end if;
  update public.ew_romaneios_transferencia_itens set documento_id=p_principal_id
   where documento_id=v_id;
  update public.ew_romaneios_transferencia set status='AGRUPADO',agrupado_em=p_principal_id,
   atualizado_em=now() where id=v_id;
  insert into public.ew_romaneios_transferencia_auditoria(documento_id,usuario_id,evento,detalhes)
   values(p_principal_id,v_uid,'AGRUPADO',jsonb_build_object('documento_origem',v_id,'numero',v_doc.numero));
  v_count:=v_count+1;
 end loop;
 if v_count=0 then raise exception 'Nenhum documento selecionado para agrupamento.';end if;
 update public.ew_romaneios_transferencia set atualizado_em=now()
 where id=p_principal_id;
 return jsonb_build_object('id',p_principal_id,'numero',v_master.numero,'agrupados',v_count);
end;$body$;

create or replace function public.ew_romaneio_transferencia_emitir(p_empresa_id uuid,p_documento_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare v_uid uuid:=auth.uid();v_doc public.ew_romaneios_transferencia%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if not exists(select 1 from public.usuarios_empresas ue join public.usuarios_login ul
  on ul.empresa_id=ue.empresa_id and ul.usuario_id=ue.usuario_id
 where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','almoxarife')) then
 raise exception 'Sem permissao para emitir romaneio.';end if;
 select * into v_doc from public.ew_romaneios_transferencia
 where id=p_documento_id and empresa_id=p_empresa_id for update;
 if v_doc.id is null then raise exception 'Romaneio inexistente.';end if;
 if v_doc.status='EMITIDO' then return jsonb_build_object('id',v_doc.id,'numero',v_doc.numero,'repetida',true);end if;
 if v_doc.status<>'RASCUNHO' then raise exception 'Romaneio agrupado ou cancelado nao pode ser emitido.';end if;
 if length(btrim(v_doc.motorista))<2 or length(btrim(v_doc.placa))<6 then
 raise exception 'Preencha motorista e placa antes da emissao.';end if;
 if not exists(select 1 from public.ew_romaneios_transferencia_itens i where i.documento_id=v_doc.id and i.tipo='TRANSFERENCIA') then
 raise exception 'Nao ha transferencia de estoque vinculada.';end if;
 if exists(select 1 from public.ew_romaneios_transferencia_itens i
  join public.ew_estoque_obras_movimentos e on e.estorno_de_id in
   (i.movimento_saida_id,i.movimento_entrada_id)
  where i.documento_id=v_doc.id and i.tipo='TRANSFERENCIA') then
 raise exception 'Romaneio contem transferencia estornada; regularize antes de emitir.';end if;
 update public.ew_romaneios_transferencia set status='EMITIDO',emitido_em=now(),atualizado_em=now()
 where id=v_doc.id;
 insert into public.ew_romaneios_transferencia_auditoria(documento_id,usuario_id,evento)
 values(v_doc.id,v_uid,'EMITIDO');
 return jsonb_build_object('id',v_doc.id,'numero',v_doc.numero,'repetida',false);
end;$body$;
revoke all on function public.ew_romaneios_transferencia_listar(uuid) from public,anon;
revoke all on function public.ew_romaneio_transferencia_salvar(uuid,uuid,date,text,text,text,jsonb) from public,anon;
revoke all on function public.ew_romaneios_transferencia_juntar(uuid,uuid,uuid[]) from public,anon;
revoke all on function public.ew_romaneio_transferencia_emitir(uuid,uuid) from public,anon;
grant execute on function public.ew_romaneios_transferencia_listar(uuid) to authenticated;
grant execute on function public.ew_romaneio_transferencia_salvar(uuid,uuid,date,text,text,text,jsonb) to authenticated;
grant execute on function public.ew_romaneios_transferencia_juntar(uuid,uuid,uuid[]) to authenticated;
grant execute on function public.ew_romaneio_transferencia_emitir(uuid,uuid) to authenticated;
