-- Confirma várias esquadrias do mesmo ZIP e a baixa de materiais em uma transação.
create or replace function public.ew_liberar_lote_cem(
 p_obra_id uuid,p_data_liberacao date,p_fabrica text,p_itens jsonb,p_materiais jsonb,
 p_arquivo_nome text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_empresa uuid;v_lote uuid;v_item jsonb;v_esq public.esquadrias%rowtype;
 v_variacao uuid;v_tipo text;v_length integer;v_unit text;v_qty numeric;v_local text;
 v_key text;v_keys text[]:=array[]::text[];v_seen uuid[]:=array[]::uuid[];v_saldo numeric;
 v_reply jsonb;v_release_id uuid;v_items int:=0;v_total int:=0;v_mat_count int;
begin
 if v_uid is null or p_operacao_id is null then raise exception 'Sessão ou operação inválida.';end if;
 select id into v_lote from public.ew_liberacoes_lotes where operacao_id=p_operacao_id;
 if found then return jsonb_build_object('repetida',true,'lote_id',v_lote);end if;
 select empresa_id into v_empresa from public.obras where id=p_obra_id;
 if v_empresa is null then raise exception 'Obra não encontrada.';end if;
 if not exists(select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
  and u.empresa_id=v_empresa and u.perfil in ('administrador','supervisor'))
 then raise exception 'Usuário sem permissão para liberar corte.';end if;
 if p_data_liberacao is null or p_data_liberacao<date '2000-01-01'
  or p_data_liberacao>current_date or p_fabrica not in ('IMBIRIBEIRA','AFOGADOS')
 then raise exception 'Data ou fábrica de produção inválida.';end if;
 if char_length(btrim(coalesce(p_arquivo_nome,''))) not between 1 and 240
  then raise exception 'Informe um arquivo CEM válido.';end if;
 if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 150
 then raise exception 'Selecione de 1 a 150 esquadrias.';end if;
 if jsonb_typeof(p_materiais) is distinct from 'array'
 then raise exception 'Espelho de materiais inválido.';end if;
 v_mat_count:=jsonb_array_length(p_materiais);
 if v_mat_count>250 then raise exception 'Espelho excedeu 250 materiais.';end if;
 if v_mat_count>0 and not exists(select 1 from public.ew_estoques_locais
   where obra_id=p_obra_id and empresa_id=v_empresa and excluido_em is null)
 then raise exception 'Estoque da obra não existe ou está arquivado.';end if;
 -- Bloqueia apenas as esquadrias escolhidas, na mesma ordem em tentativas concorrentes.
 for v_item in select value from jsonb_array_elements(p_itens) order by value->>'esquadria_id' loop
   if jsonb_typeof(v_item)<>'object' then raise exception 'Linha de esquadria inválida.';end if;
   select * into v_esq from public.esquadrias
     where id=(v_item->>'esquadria_id')::uuid and obra_id=p_obra_id and empresa_id=v_empresa for update;
   if not found then raise exception 'Esquadria do espelho não pertence à obra.';end if;
   if v_esq.id=any(v_seen) then raise exception 'Esquadria duplicada no espelho.';end if;
   v_seen:=array_append(v_seen,v_esq.id);
   if nullif(v_item->>'quantidade','')::integer is null
     or (v_item->>'quantidade')::numeric<>trunc((v_item->>'quantidade')::numeric)
     or (v_item->>'quantidade')::integer<1
     or (v_item->>'quantidade')::integer>v_esq.quantidade-v_esq.qtd_liberada
   then raise exception 'Quantidade supera as unidades aguardando liberação da esquadria %.',v_esq.codigo;end if;
 end loop;
 -- Confere todos os materiais antes de lançar QUALQUER saída de estoque.
 for v_item in select value from jsonb_array_elements(p_materiais) loop
   if jsonb_typeof(v_item)<>'object' then raise exception 'Linha de material inválida.';end if;
   v_variacao:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';
   v_qty:=(v_item->>'quantidade')::numeric;
   v_local:=upper(btrim(coalesce(v_item->>'local_estoque','')));
   select tipo into v_tipo from public.ew_materiais_variacoes where id=v_variacao and
     empresa_id=v_empresa and ativo;
   if v_tipo is null then raise exception 'Material não encontrado no catálogo da empresa.';end if;
   if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=v_empresa and l.nome=v_local and l.ativo)
   then raise exception 'Escolha o galpão do material.';end if;
   if v_qty is null or v_qty<=0 or v_qty>1000000 or
      (v_tipo='perfil' and (v_unit<>'BARRA' or v_length not between 100 and 20000 or v_qty<>trunc(v_qty))) or
      (v_tipo='acessorio' and (v_length is not null or v_unit not in ('PC','PR','CJ','MT','KG','UN')))
   then raise exception 'Quantidade, unidade ou comprimento inválidos no espelho.';end if;
   v_key:=v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit||'|'||v_local;
   if v_key=any(v_keys) then raise exception 'Material repetido no mesmo galpão: agrupe a quantidade.';end if;
   v_keys:=array_append(v_keys,v_key);
 end loop;
 -- Registra lote antes das demais operações, idempotência por UUID único.
 insert into public.ew_liberacoes_lotes
 (operacao_id,empresa_id,obra_id,data_liberacao,fabrica,arquivo_nome,itens_confirmados,materiais_confirmados,criado_por)
 values(p_operacao_id,v_empresa,p_obra_id,p_data_liberacao,p_fabrica,p_arquivo_nome,p_itens,p_materiais,v_uid)
 returning id into v_lote;
 for v_item in select value from jsonb_array_elements(p_itens) order by value->>'esquadria_id' loop
   v_reply:=public.registrar_liberacao_corte_fabrica(
      (v_item->>'esquadria_id')::uuid,(v_item->>'quantidade')::integer,p_data_liberacao,p_fabrica);
   v_release_id:=(v_reply->>'registro_id')::uuid;
   insert into public.ew_planos_liberados
   (operacao_id,empresa_id,obra_id,esquadria_id,liberacao_id,fonte,arquivo_nome,
     materiais_confirmados,data_liberacao,usuario_id)
   values(gen_random_uuid(),v_empresa,p_obra_id,(v_item->>'esquadria_id')::uuid,v_release_id,
     'CEM_CONFERIDO',p_arquivo_nome,'[]'::jsonb,p_data_liberacao,v_uid);
   v_items:=v_items+1;
   v_total:=v_total+(v_item->>'quantidade')::integer;
 end loop;
 -- Debita os materiais UMA VEZ POR LOTE, não uma vez para cada esquadria.
 for v_item in select value from jsonb_array_elements(p_materiais) loop
   v_variacao:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';v_qty:=(v_item->>'quantidade')::numeric;
   v_local:=upper(btrim(v_item->>'local_estoque'));
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
     p_obra_id::text||'|'||v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit,34777));
   select coalesce(sum(quantidade_delta),0) into v_saldo
   from public.ew_estoque_obras_movimentos where empresa_id=v_empresa and obra_id=p_obra_id
     and variacao_id=v_variacao and comprimento_mm is not distinct from v_length
     and unidade=v_unit and local_estoque=v_local;
   if v_saldo<v_qty then raise exception
     'Saldo insuficiente em %: disponível % %, solicitado % %.',v_local,v_saldo,v_unit,v_qty,v_unit;end if;
   insert into public.ew_estoque_obras_movimentos
   (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
     lote_id,operacao_id,observacao,usuario_id,local_estoque)
   values(v_empresa,p_obra_id,v_variacao,v_length,v_unit,-v_qty,'PLANO_CORTE_LOTE',v_lote,
     gen_random_uuid(),'Baixa única da liberação CEM em lote '||v_lote::text,v_uid,v_local);
 end loop;
 return jsonb_build_object('repetida',false,'lote_id',v_lote,'itens_liberados',v_items,
   'unidades_liberadas',v_total,'linhas_baixadas',v_mat_count);
end;$$;
revoke all on function public.ew_liberar_lote_cem(uuid,date,text,jsonb,jsonb,text,uuid) from public,anon;
grant execute on function public.ew_liberar_lote_cem(uuid,date,text,jsonb,jsonb,text,uuid) to authenticated;
