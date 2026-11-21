-- SOMENTE ewgest-restauracao-teste. Simulação sintética com ROLLBACK.
begin;
do $test$
declare
  v_empresa uuid:=gen_random_uuid();
  v_usuario uuid:=gen_random_uuid();
  v_perfil uuid:=gen_random_uuid();
  v_variacao uuid:=gen_random_uuid();
  v_acessorio uuid:=gen_random_uuid();
  v_fabricante uuid:=gen_random_uuid();
  v_tipologia uuid:=gen_random_uuid();
  v_fornecedor uuid:=gen_random_uuid();
  v_galpao uuid:=gen_random_uuid();
  v_result jsonb;
  v_count integer;
begin
  insert into auth.users(id,aud,role,email)
   values(v_usuario,'authenticated','authenticated','cadastro-test-'||v_usuario::text||'@example.invalid');
  insert into public.empresas(id,nome) values(v_empresa,'EMPRESA FICTICIA CADASTROS EWGEST');
  insert into public.usuarios_empresas(empresa_id,usuario_id,perfil) values(v_empresa,v_usuario,'administrador');
  perform set_config('request.jwt.claim.sub',v_usuario::text,true);
  insert into public.ew_perfis(id,empresa_id,codigo,descricao) values(v_perfil,v_empresa,'P-LIVRE','Perfil não usado');
  insert into public.ew_materiais_variacoes(id,empresa_id,tipo,perfil_id,ativo) values(v_variacao,v_empresa,'perfil',v_perfil,true);
  v_result:=public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'variacao',v_variacao);
  if v_result->>'excluido'<>'true' then raise exception 'Variação sem vínculos deveria excluir';end if;
  v_result:=public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'perfil',v_perfil);
  if v_result->>'excluido'<>'true' then raise exception 'Perfil sem vínculos deveria excluir';end if;
  select count(*) into v_count from public.ew_perfis p where p.id=v_perfil;
  if v_count<>0 then raise exception 'Perfil deveria ter sido excluído';end if;

  insert into public.ew_acessorios(id,empresa_id,codigo,descricao,unidade_item)
    values(v_acessorio,v_empresa,'A-LIVRE','Acessório fictício','PC');
  v_result:=public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'acessorio',v_acessorio);
  if v_result->>'excluido'<>'true' then raise exception 'Acessório sem vínculos não foi excluído';end if;

  insert into public.fabricantes(id,empresa_id,nome) values(v_fabricante,v_empresa,'TESTE FABRICANTE UM');
  v_result:=public.ew_renomear_fabricante_sem_vinculo(v_empresa,v_fabricante,'TESTE FABRICANTE DOIS');
  if v_result->>'nome'<>'TESTE FABRICANTE DOIS' then raise exception 'Renomeação de fabricante falhou';end if;
  v_result:=public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'fabricante',v_fabricante);
  if v_result->>'excluido'<>'true' then raise exception 'Fabricante sem vínculos deveria ser excluído';end if;

  insert into public.tipologias(id,empresa_id,codigo,descricao) values(v_tipologia,v_empresa,'T-LIVRE','Tipologia fictícia');
  v_result:=public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'tipologia',v_tipologia);
  if v_result->>'excluido'<>'true' then raise exception 'Tipologia sem vínculos deveria ser excluída';end if;

  insert into public.ew_fornecedores(id,empresa_id,nome,ativo) values(v_fornecedor,v_empresa,'FORNECEDOR TESTE',true);
  v_result:=public.ew_gerenciar_cadastro_auxiliar(v_empresa,'fornecedor',v_fornecedor,'editar','FORNECEDOR RENOMEADO');
  if v_result->>'nome'<>'FORNECEDOR RENOMEADO' then raise exception 'Renomeação fornecedor falhou';end if;
  v_result:=public.ew_gerenciar_cadastro_auxiliar(v_empresa,'fornecedor',v_fornecedor,'excluir',null);
  if v_result->>'acao'<>'excluido' then raise exception 'Fornecedor livre deveria excluir';end if;

  insert into public.ew_locais_fisicos(id,empresa_id,nome,ativo)
   values(v_galpao,v_empresa,'TESTE GALPAO LIVRE',true);
  v_result:=public.ew_gerenciar_cadastro_auxiliar(v_empresa,'galpao',v_galpao,'editar','GALPAO RENOMEADO');
  if v_result->>'nome'<>'GALPAO RENOMEADO' then raise exception 'Renomeação galpão falhou';end if;
  v_result:=public.ew_gerenciar_cadastro_auxiliar(v_empresa,'galpao',v_galpao,'excluir',null);
  if v_result->>'acao'<>'excluido' then raise exception 'Galpão livre deveria excluir';end if;

  raise notice 'PASSOU: exclusão e edição de cadastros não vinculados';
end $test$;
rollback;
