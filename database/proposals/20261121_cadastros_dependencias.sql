-- EWGEST #31. PROPOSTA: aplicar somente após homologação.
-- Atualizar/excluir fornecedores e galpões; operações bloqueadas quando houver
-- referências históricas (nome é a chave hoje utilizada pelos lançamentos).
create or replace function public.ew_gerenciar_cadastro_auxiliar(
 p_empresa_id uuid,p_tipo text,p_id uuid,p_acao text,p_nome text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_antigo text;v_novo text;v_em_uso boolean;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='administrador')
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
$func$;
revoke all on function public.ew_gerenciar_cadastro_auxiliar(uuid,text,uuid,text,text) from public;
grant execute on function public.ew_gerenciar_cadastro_auxiliar(uuid,text,uuid,text,text) to authenticated;
