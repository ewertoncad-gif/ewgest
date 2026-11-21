-- EWGEST #31: exclusão de cadastros técnicos SEM vínculos, auditável por transação.
-- Proposta para homologação; não aplicar em produção sem revisão.
create or replace function public.ew_excluir_cadastro_tecnico_sem_vinculo(
  p_empresa_id uuid, p_tipo text, p_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();
 v_nome text;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_id is null
    or not exists(select 1 from public.usuarios_empresas u
       where u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode excluir cadastros técnicos.'; end if;
 if p_tipo='perfil' then
    select p.codigo into v_nome from public.ew_perfis p where p.id=p_id
     and p.empresa_id=p_empresa_id for update;
    if not found then raise exception 'Perfil inexistente nesta empresa.';end if;
    if exists(select 1 from public.ew_materiais_variacoes v
     where v.empresa_id=p_empresa_id and v.perfil_id=p_id)
     or exists(select 1 from public.ew_materiais_alias a
     where a.empresa_id=p_empresa_id and a.perfil_id=p_id)
     or exists(select 1 from public.ew_cem_obras_materiais m
     where m.empresa_id=p_empresa_id and m.perfil_id=p_id)
     or exists(select 1 from public.ew_obra_despesas_itens i
     where i.empresa_id=p_empresa_id and i.perfil_id=p_id)
    then raise exception 'Perfil vinculado a variações, obras, notas ou equivalências: exclusão bloqueada.';end if;
    delete from public.ew_perfis where id=p_id and empresa_id=p_empresa_id;
 elsif p_tipo='acessorio' then
    select a.codigo into v_nome from public.ew_acessorios a where a.id=p_id
      and a.empresa_id=p_empresa_id for update;
    if not found then raise exception 'Acessório inexistente nesta empresa.';end if;
    if exists(select 1 from public.ew_materiais_variacoes v
     where v.empresa_id=p_empresa_id and v.acessorio_id=p_id)
     or exists(select 1 from public.ew_materiais_alias a
     where a.empresa_id=p_empresa_id and a.acessorio_id=p_id)
     or exists(select 1 from public.ew_cem_obras_materiais m
     where m.empresa_id=p_empresa_id and m.acessorio_id=p_id)
     or exists(select 1 from public.ew_obra_despesas_itens i
     where i.empresa_id=p_empresa_id and i.acessorio_id=p_id)
    then raise exception 'Acessório vinculado a variações, obras, notas ou equivalências: exclusão bloqueada.';end if;
    delete from public.ew_acessorios where id=p_id and empresa_id=p_empresa_id;
 elsif p_tipo='variacao' then
    select v.id::text into v_nome from public.ew_materiais_variacoes v where v.id=p_id
      and v.empresa_id=p_empresa_id for update;
    if not found then raise exception 'Variação inexistente nesta empresa.';end if;
    if exists(select 1 from public.ew_cem_obras_materiais m
      where m.empresa_id=p_empresa_id and m.variacao_id=p_id)
     or exists(select 1 from public.ew_estoque_movimentacoes m
      where m.empresa_id=p_empresa_id and m.variacao_id=p_id)
     or exists(select 1 from public.ew_estoque_obras_movimentos m
      where m.empresa_id=p_empresa_id and m.variacao_id=p_id)
     or exists(select 1 from public.ew_nfe_recebimentos n
      where n.empresa_id=p_empresa_id and n.variacao_id=p_id)
    then raise exception 'Variação utilizada em obras, estoque ou notas: exclusão bloqueada.';end if;
    delete from public.ew_materiais_variacoes where id=p_id and empresa_id=p_empresa_id;
 elsif p_tipo='fabricante' then
    select f.nome into v_nome from public.fabricantes f where f.id=p_id
      and f.empresa_id=p_empresa_id for update;
    if not found then raise exception 'Fabricante inexistente nesta empresa.';end if;
    if exists(select 1 from public.tipologias t where t.empresa_id=p_empresa_id and t.fabricante=v_nome)
      or exists(select 1 from public.ew_perfis p where p.empresa_id=p_empresa_id and p.fabricante=v_nome)
      or exists(select 1 from public.ew_acessorios a where a.empresa_id=p_empresa_id and a.fabricante=v_nome)
      or exists(select 1 from public.ew_materiais_alias a where a.empresa_id=p_empresa_id and a.fabricante=v_nome)
    then raise exception 'Fabricante já utilizado por tipologias ou materiais: exclusão bloqueada.';end if;
    delete from public.fabricantes where id=p_id and empresa_id=p_empresa_id;
 elsif p_tipo='tipologia' then
    select t.codigo into v_nome from public.tipologias t where t.id=p_id
      and t.empresa_id=p_empresa_id for update;
    if not found then raise exception 'Tipologia inexistente nesta empresa.';end if;
    -- As relações de negócio e histórico possuem FKs restritivas.
    -- A tentativa é segura: se houver qualquer FK restante, a transação é abortada.
    delete from public.tipologias where id=p_id and empresa_id=p_empresa_id;
 else
    raise exception 'Tipo de cadastro não permitido para exclusão.';
 end if;
 return jsonb_build_object('excluido',true,'tipo',p_tipo,'nome',v_nome);
exception
 when foreign_key_violation then
  raise exception 'Este cadastro possui vínculos com outros cadastros ou históricos. Exclusão bloqueada.';
end
$func$;

create or replace function public.ew_renomear_fabricante_sem_vinculo(
 p_empresa_id uuid,p_id uuid,p_novo_nome text
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_nome text;v_novo text:=upper(btrim(coalesce(p_novo_nome,'')));
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
   where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='administrador')
 then raise exception 'Somente ADM pode alterar o fabricante.';end if;
 select f.nome into v_nome from public.fabricantes f where f.id=p_id and f.empresa_id=p_empresa_id for update;
 if not found then raise exception 'Fabricante não encontrado.';end if;
 if char_length(v_novo) not between 2 and 80
 then raise exception 'Informe nome de 2 a 80 caracteres.';end if;
 if exists(select 1 from public.fabricantes f where f.empresa_id=p_empresa_id and f.nome=v_novo and f.id<>p_id)
 then raise exception 'Já existe fabricante com este nome.';end if;
 if exists(select 1 from public.tipologias t where t.empresa_id=p_empresa_id and t.fabricante=v_nome)
    or exists(select 1 from public.ew_perfis p where p.empresa_id=p_empresa_id and p.fabricante=v_nome)
    or exists(select 1 from public.ew_acessorios a where a.empresa_id=p_empresa_id and a.fabricante=v_nome)
    or exists(select 1 from public.ew_materiais_alias a where a.empresa_id=p_empresa_id and a.fabricante=v_nome)
 then raise exception 'Fabricante em uso: altere os vínculos antes de renomear.';end if;
 update public.fabricantes set nome=v_novo where id=p_id and empresa_id=p_empresa_id;
 return jsonb_build_object('alterado',true,'nome',v_novo);
end
$func$;

revoke all on function public.ew_excluir_cadastro_tecnico_sem_vinculo(uuid,text,uuid) from public;
revoke execute on function public.ew_excluir_cadastro_tecnico_sem_vinculo(uuid,text,uuid) from anon;
grant execute on function public.ew_excluir_cadastro_tecnico_sem_vinculo(uuid,text,uuid) to authenticated;
revoke all on function public.ew_renomear_fabricante_sem_vinculo(uuid,uuid,text) from public;
revoke execute on function public.ew_renomear_fabricante_sem_vinculo(uuid,uuid,text) from anon;
grant execute on function public.ew_renomear_fabricante_sem_vinculo(uuid,uuid,text) to authenticated;
