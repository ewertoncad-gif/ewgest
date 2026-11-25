-- Auditoria de autorização EWGEST: flags vinculadas à empresa-alvo.
-- Mantém perfis e níveis existentes; preserva demais regras de negócio.
CREATE OR REPLACE FUNCTION public.cadastrar_fabricante_admin(p_empresa_id uuid, p_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_nome text:=upper(btrim(p_nome));
  v_id uuid;
  v_criado boolean:=false;
BEGIN
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_empresa_id IS NULL OR v_nome IS NULL OR length(v_nome) NOT BETWEEN 2 AND 80 THEN
    RAISE EXCEPTION 'Informe um nome de fabricante válido (2 a 80 caracteres).';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue WHERE ue.empresa_id=p_empresa_id
      AND ue.usuario_id=v_uid AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN RAISE EXCEPTION 'Somente o administrador pode cadastrar fabricantes.'; END IF;
  INSERT INTO public.fabricantes(empresa_id,nome,criado_por)
  VALUES(p_empresa_id,v_nome,v_uid)
  ON CONFLICT (empresa_id,nome) DO NOTHING
  RETURNING id INTO v_id;
  v_criado:=v_id IS NOT NULL;
  IF NOT v_criado THEN
    SELECT id INTO v_id FROM public.fabricantes
    WHERE empresa_id=p_empresa_id AND nome=v_nome;
  END IF;
  RETURN jsonb_build_object('id',v_id,'nome',v_nome,'criado',v_criado);
END;
$function$;

CREATE OR REPLACE FUNCTION public.classificar_tipologia_pendente_admin(p_esquadria_id uuid, p_codigo text, p_descricao text, p_manter_vinculo_origem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_orig_code text;
  v_orig_desc text;
  v_tipologia_id uuid;
  v_modulacao_id uuid;
  v_modulacao_codigo text;
  v_qtd integer;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.esquadrias where id=p_esquadria_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_esquadria_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000 THEN
    RAISE EXCEPTION 'Informe uma esquadria, um codigo, uma descricao e a opcao de vinculo validos.';
  END IF;

  SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria nao encontrada.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_item.empresa_id
      AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN
    RAISE EXCEPTION 'Somente o administrador pode classificar tipologias da empresa.';
  END IF;
  IF v_item.tipologia_id IS NOT NULL THEN
    RAISE EXCEPTION 'Esta esquadria ja possui uma tipologia. Atualize a tela antes de classificar.';
  END IF;
  v_orig_code:=nullif(btrim(v_item.rotulo_tipologia_relatorio),'');
  v_orig_desc:=nullif(btrim(v_item.descricao),'');
  IF v_orig_code IS NULL OR v_orig_desc IS NULL THEN
    RAISE EXCEPTION 'Este item nao tem codigo e descricao de origem para classificacao.';
  END IF;

  -- Garante que duas tentativas sobre o mesmo codigo e descricao nao abram
  -- simultaneamente novas tipologias para o mesmo grupo de esquadrias.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_item.empresa_id::text||'|'||v_item.obra_id::text||'|'||v_orig_code||'|'||v_orig_desc));
  IF EXISTS (
    SELECT 1 FROM public.esquadrias e WHERE e.id=p_esquadria_id
       AND e.tipologia_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Este grupo ja foi classificado. Recarregue o catalogo.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tipologias t
    WHERE t.empresa_id=v_item.empresa_id
      AND upper(btrim(t.codigo))=upper(v_codigo)
  ) THEN
    RAISE EXCEPTION 'O codigo % ja existe no catalogo. Escolha outro codigo. A unificacao com uma tipologia existente exige uma operacao propria.',v_codigo;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tipologias_origens r
    WHERE r.empresa_id=v_item.empresa_id
      AND r.codigo_origem=v_orig_code
      AND r.descricao_origem=v_orig_desc
  ) THEN
    RAISE EXCEPTION 'Esta origem ja tem regra de vinculo. Revise a classificacao antes de continuar.';
  END IF;

  INSERT INTO public.tipologias(empresa_id,codigo,descricao,provisoria)
    VALUES (v_item.empresa_id,v_codigo,v_descricao,true)
    RETURNING id INTO v_tipologia_id;

  -- Uma tipologia nova ja recebe seu primeiro codigo MOD, sem presumir quantidade de modulos.
  INSERT INTO public.tipologias_modulacoes(
    empresa_id,tipologia_principal_id,descricao,quantidade_modulos,tipologia_legada_id,criado_por
  ) VALUES (
    v_item.empresa_id,v_tipologia_id,v_descricao,null,v_tipologia_id,v_uid
  ) RETURNING id,codigo_interno INTO v_modulacao_id,v_modulacao_codigo;

  UPDATE public.esquadrias e
  SET tipologia_id=v_tipologia_id,modulacao_id=v_modulacao_id
  WHERE e.empresa_id=v_item.empresa_id
    AND e.obra_id=v_item.obra_id
    AND e.tipologia_id IS NULL
    AND btrim(e.rotulo_tipologia_relatorio)=v_orig_code
    AND btrim(e.descricao)=v_orig_desc;
  GET DIAGNOSTICS v_qtd=ROW_COUNT;
  IF v_qtd<1 THEN RAISE EXCEPTION 'Nenhuma esquadria foi classificada.'; END IF;

  INSERT INTO public.tipologias_origens(
    empresa_id,tipologia_id,codigo_origem,descricao_origem,ativo)
  VALUES(v_item.empresa_id,v_tipologia_id,v_orig_code,v_orig_desc,
    false);

  INSERT INTO public.tipologias_edicoes(
    empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,
    descricao_depois,era_provisoria,manter_vinculo_origem,usuario_id)
  VALUES(
    v_item.empresa_id,v_tipologia_id,v_orig_code,v_orig_desc,v_codigo,
    v_descricao,true,false,v_uid);


  -- Confirmação limitada à obra de origem; códigos EA são locais.
  -- Cadastro provisório criado sem regra de reconhecimento automático global.
  INSERT INTO public.classificacoes_tipologias_auditoria(
    empresa_id,obra_id,esquadria_referencia_id,tipologia_id,modulacao_id,
    codigo_origem,descricao_origem,registros_vinculados,confirmou_divergencia,confirmado_por
  ) VALUES (
    v_item.empresa_id,v_item.obra_id,v_item.id,v_tipologia_id,v_modulacao_id,
    v_orig_code,v_orig_desc,v_qtd,false,v_uid
  );

  RETURN jsonb_build_object(
    'tipologia_id',v_tipologia_id,
    'modulacao_id',v_modulacao_id,
    'codigo_interno',v_modulacao_codigo,
    'codigo',v_codigo,
    'esquadrias_classificadas',v_qtd,
    'codigo_origem',v_orig_code,
    'manter_vinculo_origem',false,
    'provisoria',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.configurar_variacao_tipologia_admin(p_tipologia_id uuid, p_tipologia_principal_id uuid, p_quantidade_modulos integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_empresa uuid;
  v_principal_empresa uuid;
  v_principal_pai uuid;
  v_fabricante text;
  v_principal_fabricante text;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  if v_uid is null then raise exception 'Entre na EWGEST.'; end if;
  if p_tipologia_id is null then raise exception 'Selecione um cadastro.'; end if;
  if p_quantidade_modulos is not null and (p_quantidade_modulos < 1 or p_quantidade_modulos > 100) then
    raise exception 'Quantidade de módulos deve ficar entre 1 e 100.';
  end if;
  select t.empresa_id, t.fabricante into v_empresa,v_fabricante
    from public.tipologias t where t.id=p_tipologia_id for update;
  if v_empresa is null then raise exception 'Tipologia não encontrada.'; end if;
  if not exists (
    select 1 from public.usuarios_empresas ue
    where ue.empresa_id=v_empresa and ue.usuario_id=v_uid
      and lower(ue.perfil) IN ('administrador','gerenciador')
  ) then raise exception 'Somente administrador pode configurar as variações.'; end if;
  if p_tipologia_principal_id is not null then
    if p_tipologia_principal_id=p_tipologia_id then
      raise exception 'Escolha a opção Tipologia independente para o cadastro principal.';
    end if;
    if p_quantidade_modulos is null then
      raise exception 'Informe a quantidade de módulos desta variação.';
    end if;
    select p.empresa_id,p.tipologia_principal_id,p.fabricante
      into v_principal_empresa,v_principal_pai,v_principal_fabricante
      from public.tipologias p where p.id=p_tipologia_principal_id for update;
    if v_principal_empresa is distinct from v_empresa then
      raise exception 'A tipologia principal deve pertencer à mesma empresa.';
    end if;
    if v_principal_pai is not null then
      raise exception 'A tipologia principal não pode ser uma variação de outra.';
    end if;
    if v_fabricante is distinct from v_principal_fabricante then
      raise exception 'Tipologia e variação precisam ter o mesmo fabricante.';
    end if;
    if exists (select 1 from public.tipologias f where f.tipologia_principal_id=p_tipologia_id) then
      raise exception 'Este cadastro já é principal de outras variações; não pode virar variação.';
    end if;
  end if;
  update public.tipologias set
    tipologia_principal_id=p_tipologia_principal_id,
    quantidade_modulos=p_quantidade_modulos
    where id=p_tipologia_id;
  return jsonb_build_object('tipologia_id',p_tipologia_id,'principal_id',p_tipologia_principal_id,
    'quantidade_modulos',p_quantidade_modulos,'historico_preservado',true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.corrigir_identificacao_tipologia_admin(p_tipologia_id uuid, p_tipologia_principal_id uuid, p_principal_anterior_id uuid, p_confirmar_divergencia boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_origem public.tipologias%rowtype;
 v_destino public.tipologias%rowtype;
 v_codigo_anterior text;
 v_codigo_novo text;
 v_num_antes integer;
 v_num_depois integer;
 v_codigo_sufixo_antes text;
 v_codigo_sufixo_depois text;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null then raise exception 'Entre no EWGEST.'; end if;
 if p_tipologia_id is null then raise exception 'Selecione a tipologia que precisa ser corrigida.'; end if;
 if p_confirmar_divergencia is null then raise exception 'Confirme ou recuse a divergencia de descricao.'; end if;
 select * into v_origem from public.tipologias where id=p_tipologia_id for update;
 if not found then raise exception 'Tipologia original nao encontrada.'; end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  where ue.usuario_id=v_uid and ue.empresa_id=v_origem.empresa_id
  and lower(ue.perfil) IN ('administrador','gerenciador')
 ) then raise exception 'Somente administrador pode corrigir a identificacao.'; end if;
 if v_origem.tipologia_principal_id is distinct from p_principal_anterior_id then
  raise exception 'A identificacao foi alterada por outro usuario. Atualize o catalogo.';
 end if;
 if p_tipologia_principal_id is not null then
  if p_tipologia_principal_id=p_tipologia_id then
    raise exception 'Um cadastro nao pode apontar para si mesmo.';
  end if;
  select * into v_destino from public.tipologias
    where id=p_tipologia_principal_id for update;
  if not found or v_destino.empresa_id is distinct from v_origem.empresa_id then
    raise exception 'Tipologia destino nao encontrada na mesma empresa.';
  end if;
  if v_destino.tipologia_principal_id is not null then
    raise exception 'A identificacao correta deve ser uma tipologia principal, nao outra associacao.';
  end if;
  if upper(btrim(coalesce(v_destino.fabricante,'')))
    is distinct from upper(btrim(coalesce(v_origem.fabricante,''))) then
    raise exception 'Fabricantes divergentes. Confira antes de vincular.';
  end if;
  if upper(pg_catalog.regexp_replace(btrim(v_origem.descricao),'[[:space:]]+',' ','g'))
    is distinct from upper(pg_catalog.regexp_replace(btrim(v_destino.descricao),'[[:space:]]+',' ','g'))
    and not p_confirmar_divergencia then
    raise exception 'Descricoes diferentes. Confirme expressamente a divergencia.';
  end if;
 end if;
 if exists(select 1 from public.tipologias v where v.tipologia_principal_id=v_origem.id) then
   raise exception 'Este cadastro ja possui registros dependentes e nao pode ser vinculado.';
 end if;
 -- Apenas modulacoes pertencentes ao proprio cadastro podem acompanhar a correcao.
 if exists (
   select 1 from public.tipologias_modulacoes m
   where m.tipologia_principal_id=v_origem.id
     and m.tipologia_legada_id is distinct from v_origem.id
 ) then
   raise exception 'Este cadastro possui outras configuracoes associadas; revise-as antes de mudar a identificacao.';
 end if;
 if exists (
   select 1 from public.tipologias_modulacoes m
   where m.tipologia_legada_id=v_origem.id
     and m.tipologia_principal_id is distinct from coalesce(v_origem.tipologia_principal_id,v_origem.id)
 ) then
   raise exception 'Modulacao historica pertence a outra familia; revise a vinculacao.';
 end if;
 if v_origem.tipologia_principal_id is not distinct from p_tipologia_principal_id then
   raise exception 'Este cadastro ja utiliza a identificacao selecionada.';
 end if;
 select codigo into v_codigo_anterior from public.tipologias
   where id=v_origem.tipologia_principal_id;
 v_codigo_anterior:=coalesce(v_codigo_anterior,v_origem.codigo);
 v_codigo_novo:=coalesce(v_destino.codigo,v_origem.codigo);
 select m.numero_variacao into v_num_antes
   from public.tipologias_modulacoes m
   where m.tipologia_legada_id=v_origem.id order by m.codigo_interno limit 1;
 v_codigo_sufixo_antes:=case when v_num_antes is null then null
   else v_codigo_anterior||'-'||lpad(v_num_antes::text,2,'0') end;
 update public.tipologias
   set tipologia_principal_id=p_tipologia_principal_id
   where id=v_origem.id;
 -- Mantem os IDs MOD e os croquis historicos; recebe sufixo livre na nova familia.
 update public.tipologias_modulacoes m
   set tipologia_principal_id=coalesce(p_tipologia_principal_id,v_origem.id)
   where m.tipologia_legada_id=v_origem.id
     and m.tipologia_principal_id is distinct from coalesce(p_tipologia_principal_id,v_origem.id);
 select m.numero_variacao into v_num_depois
   from public.tipologias_modulacoes m
   where m.tipologia_legada_id=v_origem.id order by m.codigo_interno limit 1;
 v_codigo_sufixo_depois:=case when v_num_depois is null then null
   else v_codigo_novo||'-'||lpad(v_num_depois::text,2,'0') end;
 insert into public.tipologias_identificacoes_historico(
   empresa_id,tipologia_id,principal_anterior_id,principal_nova_id,
   codigo_cadastro_original,codigo_tecnico_anterior,codigo_tecnico_novo,usuario_id,
   codigo_variacao_anterior,codigo_variacao_novo
 ) values (
   v_origem.empresa_id,v_origem.id,v_origem.tipologia_principal_id,
   p_tipologia_principal_id,v_origem.codigo,v_codigo_anterior,v_codigo_novo,v_uid,
   v_codigo_sufixo_antes,v_codigo_sufixo_depois
 );
 return jsonb_build_object(
   'codigo_original_preservado',v_origem.codigo,
   'codigo_tecnico',v_codigo_novo,
   'codigo_variacao',v_codigo_sufixo_depois,
   'origem_id',v_origem.id,
   'principal_id',p_tipologia_principal_id,
   'historico_registrado',true,
   'croqui_e_esquadrias_preservados',true
 );
end;
$function$;

CREATE OR REPLACE FUNCTION public.editar_tipologia_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_manter_vinculo_origem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_reg public.tipologias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_origens integer;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'É necessário entrar na EWGEST.';
  END IF;
  IF p_tipologia_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000 THEN
    RAISE EXCEPTION 'Informe código, descrição e opção de vínculo válidos.';
  END IF;

  SELECT * INTO v_reg FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipologia não encontrada.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_reg.empresa_id
      AND ue.usuario_id=v_uid
      AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN
    RAISE EXCEPTION 'Somente o administrador desta empresa pode alterar tipologias.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.tipologias t
    WHERE t.empresa_id=v_reg.empresa_id AND t.id<>v_reg.id
      AND upper(btrim(t.codigo))=upper(v_codigo)
  ) THEN
    RAISE EXCEPTION 'Este código já pertence a outra tipologia. Não foi alterado nem unido automaticamente.';
  END IF;

  UPDATE public.tipologias
  SET codigo=v_codigo, descricao=v_descricao, provisoria=false
  WHERE id=v_reg.id;

  UPDATE public.tipologias_origens
  SET ativo=p_manter_vinculo_origem,alterado_em=now()
  WHERE tipologia_id=v_reg.id AND empresa_id=v_reg.empresa_id;
  GET DIAGNOSTICS v_origens=ROW_COUNT;

  INSERT INTO public.tipologias_edicoes
    (empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,descricao_depois,
     era_provisoria,manter_vinculo_origem,usuario_id)
  VALUES
    (v_reg.empresa_id,v_reg.id,v_reg.codigo,v_reg.descricao,v_codigo,v_descricao,
     v_reg.provisoria,p_manter_vinculo_origem,v_uid);

  RETURN jsonb_build_object(
    'tipologia_id',v_reg.id,'codigo',v_codigo,'mantido_historico',true,
    'reconhecer_origem_em_importacoes_futuras',p_manter_vinculo_origem,
    'regras_de_origem_atualizadas',v_origens
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.editar_tipologia_com_fabricante_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_fabricante text, p_manter_vinculo_origem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_reg public.tipologias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_fabricante text:=nullif(upper(btrim(p_fabricante)),'');
  v_origens integer;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'É necessário entrar na EWGEST.';
  END IF;
  IF p_tipologia_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000
    OR (v_fabricante IS NOT NULL AND (length(v_fabricante)<2 OR length(v_fabricante)>80))
  THEN
    RAISE EXCEPTION 'Informe código, descrição, fabricante e opção de vínculo válidos.';
  END IF;

  SELECT * INTO v_reg FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipologia não encontrada.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_reg.empresa_id
      AND ue.usuario_id=v_uid
      AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN
    RAISE EXCEPTION 'Somente o administrador desta empresa pode alterar tipologias.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.tipologias t
    WHERE t.empresa_id=v_reg.empresa_id AND t.id<>v_reg.id
      AND upper(btrim(t.codigo))=upper(v_codigo)
  ) THEN
    RAISE EXCEPTION 'Este código já pertence a outra tipologia. Nenhuma unificação foi feita.';
  END IF;

  UPDATE public.tipologias
  SET codigo=v_codigo, descricao=v_descricao, fabricante=v_fabricante,
      provisoria=false
  WHERE id=v_reg.id;

  UPDATE public.tipologias_origens
  SET ativo=p_manter_vinculo_origem,alterado_em=now()
  WHERE tipologia_id=v_reg.id AND empresa_id=v_reg.empresa_id;
  GET DIAGNOSTICS v_origens=ROW_COUNT;

  INSERT INTO public.tipologias_edicoes
    (empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,descricao_depois,
     era_provisoria,manter_vinculo_origem,usuario_id,fabricante_antes,fabricante_depois)
  VALUES
    (v_reg.empresa_id,v_reg.id,v_reg.codigo,v_reg.descricao,v_codigo,v_descricao,
     v_reg.provisoria,p_manter_vinculo_origem,v_uid,v_reg.fabricante,v_fabricante);

  RETURN jsonb_build_object(
    'tipologia_id',v_reg.id,'codigo',v_codigo,'fabricante',v_fabricante,
    'mantido_historico',true,
    'reconhecer_origem_em_importacoes_futuras',p_manter_vinculo_origem,
    'regras_de_origem_atualizadas',v_origens
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.editar_tipologia_fabricante_catalogo_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_fabricante text, p_manter_vinculo_origem boolean, p_criar_fabricante boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_empresa uuid;
  v_nome text:=nullif(upper(btrim(p_fabricante)),'');
  v_criado boolean:=false;
  v_count integer:=0;
  v_resultado jsonb;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_tipologia_id IS NULL OR p_criar_fabricante IS NULL THEN
    RAISE EXCEPTION 'Cadastro ou autorização inválidos.';
  END IF;
  SELECT empresa_id INTO v_empresa
    FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Tipologia não encontrada.'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue WHERE ue.empresa_id=v_empresa
      AND ue.usuario_id=v_uid AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN RAISE EXCEPTION 'Somente o administrador pode editar este cadastro.'; END IF;
  IF v_nome IS NOT NULL THEN
    IF length(v_nome) NOT BETWEEN 2 AND 80 THEN
      RAISE EXCEPTION 'Nome de fabricante inválido.';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.fabricantes
                  WHERE empresa_id=v_empresa AND nome=v_nome) THEN
      IF NOT p_criar_fabricante THEN
        RAISE EXCEPTION 'Fabricante % ainda não cadastrado. Confirme a inclusão no cadastro de fabricantes.',v_nome;
      END IF;
      INSERT INTO public.fabricantes(empresa_id,nome,criado_por)
      VALUES(v_empresa,v_nome,v_uid)
      ON CONFLICT (empresa_id,nome) DO NOTHING;
      GET DIAGNOSTICS v_count=ROW_COUNT;
      v_criado:=v_count>0;
    END IF;
  END IF;
  -- Quando a descrição terminar com um fabricante já cadastrado, os campos
  -- precisam concordar. Sem coincidência, o campo estruturado prevalece.
  IF EXISTS(
    SELECT 1 FROM public.fabricantes f
    WHERE f.empresa_id=v_empresa AND f.nome IS DISTINCT FROM v_nome
      AND upper(btrim(p_descricao)) LIKE '% - '||f.nome
  ) THEN
    RAISE EXCEPTION 'A descrição termina com outro fabricante. Corrija a descrição ou o campo Fabricante.';
  END IF;
  v_resultado:=public.editar_tipologia_com_fabricante_admin(
    p_tipologia_id,p_codigo,p_descricao,v_nome,p_manter_vinculo_origem
  );
  RETURN v_resultado || jsonb_build_object('fabricante_cadastrado_nesta_edicao',v_criado);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_arquivar_obra_reconciliada(p_obra_id uuid, p_confirmacao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_ver jsonb;
 v_record public.ew_obras_exclusoes_historico%rowtype;v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 IF NOT public.ew_pode((select empresa_id from public.obras where id=p_obra_id),'obras.estornar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.estornar'; END IF;
 PERFORM public.ew_exigir_permissao('obras.estornar');
 perform public.ew_exigir_sessao_atual();
 if p_obra_id is null or p_operacao_id is null then raise exception 'Obra e operação obrigatórias.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_record from public.ew_obras_exclusoes_historico where operacao_id=p_operacao_id;
 if found then
  if v_record.obra_excluida_id<>p_obra_id or v_record.excluido_por<>v_uid
   then raise exception 'Identificador já usado em outra operação.';end if;
  return jsonb_build_object('excluida',true,'repetida',true,'nome',v_record.obra_nome);
 end if;
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra já arquivada ou não encontrada.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 v_ver:=public.ew_inspecionar_reversao_obra(p_obra_id);
 if not (v_ver->>'permitido')::boolean then raise exception
  'ARQUIVAMENTO_BLOQUEADO: %',
  array_to_string(array(select jsonb_array_elements_text(v_ver->'motivos')),' ');
 end if;
 if upper(btrim(coalesce(p_confirmacao,'')))<>upper(coalesce(nullif(btrim(v_ob.codigo),''),v_ob.nome))
 then raise exception 'Confirmação incorreta. Digite o código da obra.';end if;
 update public.obras set arquivada_em=now(),arquivada_por=v_uid,motivo_arquivamento=v_motivo
 where id=p_obra_id and arquivada_em is null;
 insert into public.ew_obras_exclusoes_historico
  (operacao_id,empresa_id,obra_excluida_id,obra_nome,obra_codigo,motivo,resumo,excluido_por)
 values(p_operacao_id,v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,
  left(v_motivo,300),v_ver->'resumo',v_uid);
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ARQUIVAR_OBRA',
  p_operacao_id,v_motivo,jsonb_build_object(
   'resumo',v_ver->'resumo','cadastros_gerais_preservados',true,
   'historico_operacional_preservado',true));
 return jsonb_build_object('excluida',true,'repetida',false,
  'nome',v_ob.nome,'codigo',v_ob.codigo,'historico_preservado',true);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_cadastrar_comprimento_comercial(p_empresa_id uuid, p_comprimento_mm integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_id uuid;
BEGIN
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(
 SELECT 1 FROM public.usuarios_empresas u WHERE u.usuario_id=v_uid
   AND u.empresa_id=p_empresa_id AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode cadastrar comprimentos comerciais.';END IF;
 IF p_comprimento_mm IS NULL OR p_comprimento_mm NOT BETWEEN 100 AND 20000
 THEN RAISE EXCEPTION 'Informe um comprimento em mm, entre 100 e 20000.';END IF;
 INSERT INTO public.ew_comprimentos_comerciais(empresa_id,comprimento_mm,criado_por)
 VALUES(p_empresa_id,p_comprimento_mm,v_uid)
 ON CONFLICT (empresa_id,comprimento_mm) DO NOTHING
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN SELECT id INTO v_id FROM public.ew_comprimentos_comerciais
 WHERE empresa_id=p_empresa_id AND comprimento_mm=p_comprimento_mm; END IF;
 RETURN jsonb_build_object('id',v_id,'comprimento_mm',p_comprimento_mm);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_compras_cancelar_pedido(p_pedido_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_p public.ew_compras_pedidos%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 IF NOT public.ew_pode((select empresa_id from public.ew_compras_pedidos where id=p_pedido_id),'compras.pedir') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: compras.pedir'; END IF;
 IF NOT public.ew_pode((select empresa_id from public.ew_compras_pedidos where id=p_pedido_id),'compras.aprovar_pedido') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: compras.aprovar_pedido'; END IF;
 IF NOT public.ew_pode((select empresa_id from public.ew_compras_pedidos where id=p_pedido_id),'compras.consultar_valores') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: compras.consultar_valores'; END IF;
 perform public.ew_exigir_sessao_atual();
 if auth.uid() is null or p_pedido_id is null or p_operacao_id is null
    or char_length(v_motivo) not between 5 and 400
 then raise exception 'Pedido, identificador e motivo de 5 a 400 caracteres são obrigatórios.';end if;
 select * into v_p from public.ew_compras_pedidos where id=p_pedido_id for update;
 if not found then raise exception 'Pedido não localizado.';end if;
 if not public.ew_pode(v_p.empresa_id,'compras.pedir')
 then raise exception 'Sem permissão para cancelar pedido.';end if;
 if v_p.status='CANCELADO' then
  if v_p.cancelamento_operacao_id=p_operacao_id and v_p.cancelamento_motivo=v_motivo then
   return jsonb_build_object('id',v_p.id,'cancelado',true,'repetida',true);
  end if;
  raise exception 'Pedido já cancelado.';end if;
 if v_p.status<>'ABERTO' then
  raise exception 'Pedido já iniciou recebimento ou foi concluído. Cancelamento comercial direto bloqueado.';end if;
 -- Histórico estornado é preservado, mas não constitui uma obrigação ativa.
 if exists(select 1 from public.ew_compras_recebimentos r where r.pedido_id=v_p.id and r.empresa_id=v_p.empresa_id and r.estornado_em is null)
 then raise exception 'Estorne todos os recebimentos ativos antes de cancelar o pedido.';end if;
 if exists(select 1 from public.ew_compras_nfe_conciliacoes c where c.pedido_id=v_p.id and c.empresa_id=v_p.empresa_id and c.desvinculado_em is null)
  or exists(select 1 from public.ew_compras_notas_empresa n where n.pedido_id=v_p.id and n.empresa_id=v_p.empresa_id and n.status<>'CANCELADA')
 then raise exception 'Regularize as notas fiscais e conciliações ativas antes de cancelar o pedido.';end if;
 update public.ew_compras_pedidos set status='CANCELADO',cancelado_em=now(),
  cancelado_por=auth.uid(),cancelamento_motivo=v_motivo,
  cancelamento_operacao_id=p_operacao_id where id=v_p.id;
 -- A solicitação segue PEDIDO_GERADO para não originar outro pedido acidentalmente.
 return jsonb_build_object('id',v_p.id,'cancelado',true,'repetida',false,
   'estoque_alterado',false,'solicitacao_preservada',true);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_confirmar_entrega_producao(p_empresa_id uuid, p_obra_id uuid, p_tipo text, p_referencia_id uuid, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_plano public.ew_planos_liberados%rowtype;v_lote public.ew_liberacoes_lotes%rowtype;
 v_materiais jsonb;v_item jsonb;
 v_var uuid;v_length integer;v_unit text;v_qty numeric;v_local text;
 v_stock numeric;v_tp text;v_n integer:=0;v_liberacao uuid;v_lote_id uuid;
begin
 IF NOT public.ew_pode(p_empresa_id,'estoque.baixar') OR NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: entrega à produção exige baixa e consulta de estoque.'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_referencia_id is null
  or p_operacao_id is null or p_tipo not in ('PLANO','LOTE')
  or not exists(select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
   and u.empresa_id=p_empresa_id and public.ew_pode(p_empresa_id,'estoque.baixar'))
 then raise exception 'Sem permissão para baixar materiais da produção.';end if;
 if not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
   and o.arquivada_em is null)
 then raise exception 'Obra não encontrada ou arquivada.';end if;
 if not exists(select 1 from public.ew_estoques_locais l where l.empresa_id=p_empresa_id
   and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Estoque desta obra não está ativo.';end if;
 -- Bloqueio estável entre tentativas simultâneas de entrega do mesmo relatório.
 perform pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(p_tipo||'|'||p_referencia_id::text,773428));
 if p_tipo='PLANO' then
  select * into v_plano from public.ew_planos_liberados p
   where p.empresa_id=p_empresa_id and p.obra_id=p_obra_id
    and p.id=p_referencia_id for update;
  if not found or not exists(select 1 from public.liberacoes_corte l
    where l.id=v_plano.liberacao_id and l.cancelado_em is null)
  then raise exception 'Liberação não encontrada ou cancelada.';end if;
  if v_plano.entregue_em is not null then
   if v_plano.entrega_operacao_id=p_operacao_id then
    return jsonb_build_object('repetida',true,'referencia_id',p_referencia_id);end if;
   raise exception 'Este relatório já teve baixa física. Não duplique a entrega.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.liberacao_id=v_plano.liberacao_id and m.origem='PLANO_CORTE')
   then raise exception 'Liberação antiga já movimentou estoque. Não executar nova baixa.';end if;
  v_materiais:=v_plano.materiais_confirmados;
  v_liberacao:=v_plano.liberacao_id;
 else
  select * into v_lote from public.ew_liberacoes_lotes l
   where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id
    and l.id=p_referencia_id for update;
  if not found or v_lote.cancelado_em is not null
   then raise exception 'Lote de liberação não encontrado ou cancelado.';end if;
  if v_lote.entregue_em is not null then
   if v_lote.entrega_operacao_id=p_operacao_id then
    return jsonb_build_object('repetida',true,'referencia_id',p_referencia_id);end if;
   raise exception 'Este lote já teve baixa física. Não repita a entrega.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.lote_id=v_lote.id and m.origem='PLANO_CORTE_LOTE')
   then raise exception 'Lote antigo já movimentou estoque. Não executar nova baixa.';end if;
  v_materiais:=v_lote.materiais_confirmados;v_lote_id:=v_lote.id;
 end if;
 if jsonb_typeof(v_materiais) is distinct from 'array'
   or jsonb_array_length(v_materiais) not between 1 and 250
 then raise exception 'Relatório não possui materiais pendentes de entrega.';end if;
 -- Locks no MESMO escopo das rotinas atuais, sempre em ordem, evitando concorrência
 -- com transferências, estorno de NF e baixas de outras liberações.
 for v_item in select value from jsonb_array_elements(v_materiais)
  order by value->>'variacao_id',value->>'comprimento_mm',value->>'unidade' loop
   if jsonb_typeof(v_item)<>'object' then raise exception 'Linha inválida do relatório.';end if;
   v_var:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';
   v_local:=upper(btrim(coalesce(v_item->>'local_estoque','')));
   v_qty:=(v_item->>'quantidade')::numeric;
   select tipo into v_tp from public.ew_materiais_variacoes v
    where v.id=v_var and v.empresa_id=p_empresa_id;
   if v_tp is null or v_qty is null or v_qty<=0 or v_qty>1000000
      or (v_tp='perfil' and (v_unit<>'BARRA' or v_length not between 100 and 20000
          or v_qty<>trunc(v_qty)))
      or (v_tp='acessorio' and (v_length is not null
          or v_unit not in ('PC','PR','CJ','MT','KG','UN')
          or v_qty<>round(v_qty,3)))
   then raise exception 'Material ou quantidade inválidos no relatório de liberação.';end if;
   if not exists(select 1 from public.ew_locais_fisicos f
     where f.empresa_id=p_empresa_id and f.nome=v_local and f.ativo)
   then raise exception 'Galpão original do relatório está inativo. Concilie antes da entrega.';end if;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_obra_id::text||'|'||v_var::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit,34777));
   select coalesce(sum(m.quantidade_delta),0) into v_stock
    from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.variacao_id=v_var and m.comprimento_mm is not distinct from v_length
     and m.unidade=v_unit and m.local_estoque=v_local;
   if v_stock<v_qty then raise exception
    'Entrega bloqueada: saldo insuficiente de % no galpão %. Disponível % %, necessário % %.',
    v_var,v_local,v_stock,v_unit,v_qty,v_unit;end if;
 end loop;
 -- Todos os saldos foram validados. A transação inteira reverte se qualquer
 -- linha de movimentação falhar; nunca entrega pela metade.
 for v_item in select value from jsonb_array_elements(v_materiais) loop
   v_var:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';v_local:=upper(btrim(v_item->>'local_estoque'));
   v_qty:=(v_item->>'quantidade')::numeric;
   insert into public.ew_estoque_obras_movimentos
    (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
     origem,liberacao_id,lote_id,operacao_id,observacao,usuario_id,local_estoque)
   values(p_empresa_id,p_obra_id,v_var,v_length,v_unit,-v_qty,
    case when p_tipo='PLANO' then 'PLANO_CORTE' else 'PLANO_CORTE_LOTE' end,
    v_liberacao,v_lote_id,gen_random_uuid(),
    'Material entregue pelo almoxarife à produção — liberação '||p_referencia_id::text,
    v_uid,v_local);
   v_n:=v_n+1;
 end loop;
 if p_tipo='PLANO' then
   update public.ew_planos_liberados
   set entregue_em=now(),entregue_por=v_uid,entrega_operacao_id=p_operacao_id
   where id=p_referencia_id and empresa_id=p_empresa_id;
 else
   update public.ew_liberacoes_lotes
   set entregue_em=now(),entregue_por=v_uid,entrega_operacao_id=p_operacao_id
   where id=p_referencia_id and empresa_id=p_empresa_id;
 end if;
 return jsonb_build_object('repetida',false,'linhas_baixadas',v_n,
  'obra_id',p_obra_id,'tipo',p_tipo,'referencia_id',p_referencia_id);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_entregas_pendentes_producao(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 IF NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.consultar'; END IF;
 IF NOT public.ew_pode(p_empresa_id,'estoque.baixar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.baixar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.usuario_id=v_uid and u.empresa_id=p_empresa_id
  and u.perfil in ('administrador','almoxarife'))
 then raise exception 'Sem permissão para consultar entregas à produção.';end if;
 if not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
   and o.arquivada_em is null)
 then raise exception 'Obra não encontrada ou arquivada.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'tipo',x.tipo,'id',x.id,'data',x.data_liberacao,'fabrica',x.fabrica,
  'codigo',x.codigo,'arquivo',x.arquivo_nome,'materiais',x.materiais
 ) order by x.data_liberacao desc,x.id),'[]'::jsonb) into v_result
 from (
  select 'PLANO'::text tipo,p.id,p.data_liberacao,l.fabrica,
   e.codigo,p.arquivo_nome,p.materiais_confirmados materiais
  from public.ew_planos_liberados p
   join public.liberacoes_corte l on l.id=p.liberacao_id and l.cancelado_em is null
   join public.esquadrias e on e.id=p.esquadria_id
  where p.empresa_id=p_empresa_id and p.obra_id=p_obra_id and p.entregue_em is null
   and jsonb_typeof(p.materiais_confirmados)='array'
   and jsonb_array_length(p.materiais_confirmados)>0
   and not exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.liberacao_id=p.liberacao_id and m.origem='PLANO_CORTE')
  union all
  select 'LOTE'::text tipo,l.id,l.data_liberacao,l.fabrica,
   'LOTE CEM'::text codigo,l.arquivo_nome,l.materiais_confirmados materiais
  from public.ew_liberacoes_lotes l
  where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id and l.cancelado_em is null
   and l.entregue_em is null and jsonb_typeof(l.materiais_confirmados)='array'
   and jsonb_array_length(l.materiais_confirmados)>0
   and not exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.lote_id=l.id and m.origem='PLANO_CORTE_LOTE')
 ) x;
 return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;v_conciliadas int:=0;v_chave record;
begin
 IF NOT public.ew_pode((select empresa_id from public.obras where id=p_obra_id),'estoque.estornar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.estornar'; END IF;
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 -- Sincronizar a reversão total com as travas por material de transferências,
 -- entradas NF-e e estornos individuais. Ordem estável para evitar deadlock.
 FOR v_chave IN
  SELECT DISTINCT m.variacao_id::text||'|'||
    coalesce(m.comprimento_mm::text,'-')||'|'||m.unidade AS chave
  FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=p_obra_id
  ORDER BY chave
 LOOP
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_obra_id::text||'|'||v_chave.chave,34777));
 END LOOP;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
    or coalesce(v_audit.detalhes->>'modo','') IN ('individual','transferencia_entre_obras')
   then raise exception 'Identificador de operação já utilizado em outro tipo de estorno.';end if;
  return jsonb_build_object('repetida',true,'estornados',
    v_audit.detalhes->'movimentos_estornados',
    'conciliados',coalesce((v_audit.detalhes->>'transferencias_conciliadas')::int,0),
    'historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 -- Se as NF-e foram totalmente estornadas E somente restam pares de
 -- transferências internas equilibradas, NÃO gerar novos movimentos inversos:
 -- isso recriaria saldo negativo na origem/positivo no destino.
 v_conciliadas:=public.ew_transferencias_nfe_conciliadas(p_obra_id);
 IF v_conciliadas=0 THEN
  v_conciliadas:=public.ew_transferencias_internas_conciliadas(p_obra_id);
 END IF;
 IF v_conciliadas>0 THEN
  IF NOT (v_status->>'permitido')::boolean
    OR (v_status->'resumo'->>'transferencias_conciliadas')::int<>v_conciliadas
    OR (v_status->'resumo'->>'movimentos_pendentes')::int<>0
    OR (v_status->'resumo'->>'saldos_nao_zerados')::int<>0 THEN
   RAISE EXCEPTION 'Transferências não estão totalmente conciliadas. Verifique saldos e pendências.';
  END IF;
  INSERT INTO public.ew_auditoria_operacoes
   (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
  VALUES(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
   p_operacao_id,v_motivo,jsonb_build_object(
    'modo','CONCILIAR_TRANSFERENCIAS_HISTORICAS',
    'movimentos_estornados',0,
    'transferencias_conciliadas',v_conciliadas,
    'saldo_zerado_sem_novos_lancamentos',true));
  RETURN jsonb_build_object('repetida',false,'estornados',0,
   'conciliados',v_conciliadas,'saldos_zerados',true,
   'historico_preservado',true);
 END IF;
 -- Reverter estoque inteiro com NF vinculada pode desfazer uma devolução
 -- física sem atualizar o histórico da nota. Exigir fluxo específico.
 if exists(select 1 from public.ew_nfe_recebimentos n where n.obra_id=p_obra_id) then
  raise exception 'A obra contém recebimentos de NF-e. Use o estorno por recebimento; não zere o estoque inteiro.';
 end if;
 -- Uma transferência ENTRE OBRAS não pode ser revertida em apenas uma
 -- das obras. Ela deve ser estornada atomicamente nas duas pontas.
 IF EXISTS (
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.origem='TRANSFERENCIA'
    AND m.transferencia_id IS NOT NULL
    AND EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos outra
     WHERE outra.transferencia_id=m.transferencia_id
       AND outra.origem='TRANSFERENCIA' AND outra.obra_id<>m.obra_id
    )
    AND NOT EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id
    )
 ) THEN
  RAISE EXCEPTION 'Há transferência ativa entre obras. Estorne as duas pontas pelo histórico de movimentações antes de estornar o estoque inteiro.';
 END IF;
 perform 1 from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id order by m.id for update;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
   group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
   having sum(m.quantidade_delta)<0) then
  raise exception 'Saldo negativo em galpão. Concilie o estoque antes do estorno.';end if;
 -- Nunca inverter transferências ou baixas sem desfazer primeiro suas
 -- dependências. O estorno em lote é reservado a entradas independentes.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.origem<>'ESTORNO'
   AND m.estorno_de_id IS NULL
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e WHERE e.estorno_de_id=m.id)
   AND (m.quantidade_delta<=0 OR
     m.origem NOT IN ('ABERTURA','IMPORTACAO_CEM','COMPRA','AJUSTE'))
 ) THEN
  RAISE EXCEPTION 'Há transferências, consumo ou saídas ainda ativos. Estorne primeiro as dependências de cada material.';
 END IF;
 -- Registra em detalhes cada movimento que será revertido.
 select count(*),
  coalesce(jsonb_agg(jsonb_build_object('id',m.id,'origem',m.origem,
   'quantidade',m.quantidade_delta,'local',m.local_estoque,
   'unidade',m.unidade,'comprimento_mm',m.comprimento_mm,
   'variacao_id',m.variacao_id,'criado_em',m.criado_em,'usuario_original',m.usuario_id)),
   '[]'::jsonb)
 into v_n,v_originais from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.origem<>'ESTORNO' and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if v_n=0 then
  if (v_status->'resumo'->>'saldos_nao_zerados')::int>0 then
   raise exception 'Não existem movimentos pendentes, mas há saldos diferentes de zero.';end if;
  return jsonb_build_object('repetida',false,'estornados',0,'historico_preservado',true);
 end if;
 insert into public.ew_estoque_obras_movimentos (
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
 select m.empresa_id,m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,
  -m.quantidade_delta,'ESTORNO',gen_random_uuid(),left('Estorno para reimportação: '||v_motivo,500),
  v_uid,m.local_estoque,m.id
 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.origem<>'ESTORNO' and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if exists(select 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
 group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
 having sum(m.quantidade_delta)<>0) then
  raise exception 'A operação não zerou todos os saldos. Nenhum estorno foi confirmado.';end if;
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_operacao_id,v_motivo,jsonb_build_object('movimentos_estornados',v_n,
   'movimentos_originais',v_originais));
 return jsonb_build_object('repetida',false,'estornados',v_n,'historico_preservado',true);
end;$function$;

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

CREATE OR REPLACE FUNCTION public.ew_insumos_cancelar_nota(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_despesa public.ew_obra_despesas%rowtype;
 v_linha public.ew_insumos_movimentos%rowtype;v_saldo numeric;v_op uuid:=gen_random_uuid();
 v_count integer:=0;
begin
 IF NOT public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: financeiro.cancelar_despesas'; END IF;
 IF NOT public.ew_pode(p_empresa_id,'estoque.estornar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.estornar'; END IF;
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode cancelar nota.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400
 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_despesa from public.ew_obra_despesas d
  where d.id=p_despesa_id and d.empresa_id=p_empresa_id for update;
 if not found or v_despesa.status<>'aprovada' then
  raise exception 'Nota inexistente ou já cancelada.';end if;
 for v_linha in select m.* from public.ew_insumos_movimentos m
  join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
  where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id and m.origem='RECEBIMENTO'
  order by m.obra_id,m.insumo_id,m.local_estoque,m.id
 loop
  v_count:=v_count+1;
  if exists(select 1 from public.ew_insumos_movimentos x where x.estorno_de_id=v_linha.id)
  then raise exception 'Este recebimento já possui estorno de estoque.';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|'||v_linha.obra_id::text||'|'||
    v_linha.insumo_id::text||'|'||v_linha.local_estoque,9012));
  select coalesce(sum(x.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos x
    where x.empresa_id=p_empresa_id and x.obra_id=v_linha.obra_id
     and x.insumo_id=v_linha.insumo_id and x.local_estoque=v_linha.local_estoque;
  if v_saldo<v_linha.quantidade_delta then
   raise exception 'Não é possível cancelar: o saldo recebido foi transferido/utilizado. Estorne primeiro os movimentos.';
  end if;
  insert into public.ew_insumos_movimentos(
    empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
    operacao_id,estorno_de_id,observacao,usuario_id
  ) values(p_empresa_id,v_linha.obra_id,v_linha.insumo_id,v_linha.local_estoque,
    -v_linha.quantidade_delta,'ESTORNO',v_op,v_linha.id,btrim(p_motivo),v_uid);
 end loop;
 if v_count=0 then
  -- Nota da v45.1, que registrava apenas custos. Não inventar um estorno físico.
  return public.ew_cancelar_despesa_financeira(p_empresa_id,p_despesa_id,p_motivo);
 end if;
 update public.ew_obra_despesas set status='cancelada',cancelado_por=v_uid,
  cancelado_em=now(),observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 where empresa_id=p_empresa_id and id=p_despesa_id;
 return jsonb_build_object('cancelada',true,'itens_estornados',v_count,'operacao_estorno',v_op);
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
   and u.usuario_id=v_uid and u.perfil in ('administrador','almoxarife')
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
 IF NOT public.ew_pode(p_empresa_id,'estoque.estornar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.estornar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
   where u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
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

CREATE OR REPLACE FUNCTION public.ew_quantidades_recebidas_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
 IF NOT public.ew_pode(p_empresa_id,'estoque.receber') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estoque.receber'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
    and u.empresa_id=p_empresa_id and u.perfil in ('almoxarife','administrador')
 ) or not exists (
  select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
 ) then
  raise exception 'Acesso não autorizado ao recebimento.';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'variacao_id',r.variacao_id,'comprimento_mm',r.comprimento_mm,
   'unidade',r.unidade,'quantidade',r.quantidade
 )), '[]'::jsonb)
 into v_result from (
  select n.variacao_id,n.comprimento_mm,n.unidade,sum(n.quantidade) quantidade
  from public.ew_nfe_recebimentos n
  join public.ew_obra_despesas_itens i on i.id=n.despesa_item_id and i.empresa_id=n.empresa_id
  join public.ew_obra_despesas d on d.id=i.despesa_id and d.empresa_id=n.empresa_id
  where n.empresa_id=p_empresa_id and n.obra_id=p_obra_id and d.status='aprovada' and n.estornado_em is null
  group by n.variacao_id,n.comprimento_mm,n.unidade
 ) r;
 return coalesce(v_result,'[]'::jsonb);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_romaneio_transferencia_emitir(p_empresa_id uuid, p_documento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_doc public.ew_romaneios_transferencia%rowtype;
begin
 IF NOT public.ew_pode(p_empresa_id,'romaneios.transferir') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: romaneios.transferir'; END IF;
 PERFORM public.ew_exigir_permissao('romaneios.transferir');
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
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_romaneio_transferencia_salvar(p_empresa_id uuid, p_documento_id uuid, p_data date, p_motorista text, p_placa text, p_observacoes text, p_avulsos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_doc public.ew_romaneios_transferencia%rowtype;
 v_item jsonb;v_qtd numeric;v_antigos jsonb;
begin
 IF NOT public.ew_pode(p_empresa_id,'romaneios.transferir') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: romaneios.transferir'; END IF;
 PERFORM public.ew_exigir_permissao('romaneios.transferir');
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
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_romaneios_transferencia_listar(p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not public.ew_pode(p_empresa_id,'romaneios.consultar') then raise exception 'PERMISSAO_NEGADA: romaneios.consultar';end if;
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
 from public.ew_romaneios_transferencia d where d.empresa_id=p_empresa_id and exists(select 1 from public.obras o where o.id=d.obra_id and o.empresa_id=d.empresa_id and o.arquivada_em is null);
 return coalesce(v_result,'[]'::jsonb);
end;$function$;

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
end;$function$;

CREATE OR REPLACE FUNCTION public.registrar_saida_producao(p_registro_id uuid, p_esquadria_id uuid, p_tipo text, p_quantidade integer, p_data_saida date, p_folhas_por_unidade integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_folhas integer;
  v_marcos_liberados bigint;
  v_folhas_liberadas bigint;
  v_completas_enviadas bigint;
  v_marcos_enviados bigint;
  v_folhas_enviadas bigint;
  v_marcos_novos bigint;
  v_folhas_novas bigint;
  v_existente public.saidas_producao%ROWTYPE;
  v_primeira_liberacao date;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.esquadrias where id=p_esquadria_id),'romaneios.emitir') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: romaneios.emitir'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Entre na EWGEST para registrar uma saída.';
  END IF;
  IF p_registro_id IS NULL OR p_esquadria_id IS NULL THEN
    RAISE EXCEPTION 'Identificador do registro ou da esquadria ausente.';
  END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('completo','marco','folha') THEN
    RAISE EXCEPTION 'Escolha completo, marco ou folha.';
  END IF;
  IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Informe quantidade inteira e positiva.';
  END IF;
  IF p_data_saida IS NULL OR p_data_saida < DATE '2000-01-01' OR p_data_saida > current_date THEN
    RAISE EXCEPTION 'Informe uma data de saída válida e não futura.';
  END IF;
  -- Conjunto completo não precisa informar a composição física das folhas.
  -- Ela será confirmada quando houver saída desmembrada, se ainda não existir no cadastro.
  IF p_folhas_por_unidade IS NOT NULL AND p_folhas_por_unidade NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Quantidade de folhas por esquadria inválida (1 a 12).';
  END IF;
  IF p_tipo IN ('marco','folha') AND p_folhas_por_unidade IS NULL THEN
    RAISE EXCEPTION 'Informe a composição de folhas para expedição desmembrada.';
  END IF;

  -- Serializa lançamentos do mesmo item e garante que não superem o liberado.
  SELECT * INTO v_item FROM public.esquadrias
  WHERE id=p_esquadria_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esquadria não encontrada.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_item.empresa_id
      AND ue.usuario_id=v_usuario
      AND (
        ue.perfil IN ('administrador','gerenciador','supervisor')
        OR (
          ue.perfil='almoxarife'
          AND EXISTS(
            SELECT 1 FROM public.usuarios_login ul
            WHERE ul.usuario_id=v_usuario AND ul.empresa_id=ue.empresa_id
              AND ul.perfil='almoxarife' AND ul.ativo
          )
          AND EXISTS(
            SELECT 1 FROM public.romaneios r
            WHERE r.id::text=pg_catalog.current_setting('ewgest.romaneio_emissao_id',true)
              AND r.criado_por=v_usuario AND r.empresa_id=v_item.empresa_id
              AND r.obra_id=v_item.obra_id AND r.status='emitido'
              AND r.criado_em=pg_catalog.transaction_timestamp()
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'Sem permissão para registrar saídas desta empresa.';
  END IF;
  -- MAXIM-AR sai sempre como conjunto completo, sem opção de marco ou folha separados.
  IF v_item.descricao ~* 'MAXIM[[:space:]-]*AR' AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'MAXIM-AR só pode ser expedido como esquadria completa.';
  END IF;
  IF COALESCE(v_item.qtd_liberada,0) <= 0 THEN
    RAISE EXCEPTION 'Este código ainda não possui unidades liberadas para corte.';
  END IF;

  SELECT * INTO v_existente FROM public.saidas_producao WHERE id=p_registro_id;
  IF FOUND THEN
    IF v_existente.cancelado_em IS NOT NULL THEN
      RAISE EXCEPTION 'Saída já cancelada; não é possível reativar este identificador.';
    END IF;
    IF v_existente.esquadria_id<>p_esquadria_id
      OR v_existente.tipo<>p_tipo
      OR v_existente.quantidade<>p_quantidade
      OR v_existente.data_saida<>p_data_saida THEN
      RAISE EXCEPTION 'Identificador de operação já utilizado para outro lançamento.';
    END IF;
    RETURN jsonb_build_object('registro_id',v_existente.id,'repetido',true);
  END IF;

  PERFORM 1 FROM public.tipologias WHERE id=v_item.tipologia_id AND empresa_id=v_item.empresa_id FOR SHARE;
  IF ew_expedicao_interna.estado_item(v_item.id) IS NOT NULL THEN
    RAISE EXCEPTION 'Esta tipologia tem composição configurada. Emita pelo romaneio atualizado.';
  END IF;
  SELECT folhas_por_unidade INTO v_folhas
    FROM public.esquadrias_saida_config
    WHERE esquadria_id=p_esquadria_id;
  IF v_folhas IS NULL AND p_folhas_por_unidade IS NOT NULL THEN
    INSERT INTO public.esquadrias_saida_config
      (esquadria_id,folhas_por_unidade,configurado_por)
    VALUES (p_esquadria_id,p_folhas_por_unidade,v_usuario);
    v_folhas:=p_folhas_por_unidade;
  ELSIF v_folhas IS NOT NULL AND p_folhas_por_unidade IS NOT NULL
    AND v_folhas<>p_folhas_por_unidade THEN
    RAISE EXCEPTION 'Composição já cadastrada: % folha(s) por esquadria. Não foi alterada.', v_folhas;
  END IF;
  IF v_folhas IS NULL AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'Antes de desmembrar, confirme a quantidade de folhas por esquadria.';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN tipo IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo='completo' THEN quantidade*v_folhas
                           WHEN tipo='folha' THEN quantidade ELSE 0 END),0)
    INTO v_marcos_enviados,v_folhas_enviadas
    FROM public.saidas_producao
    WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;

  v_marcos_novos:=CASE WHEN p_tipo IN ('completo','marco') THEN p_quantidade ELSE 0 END;
  v_folhas_novas:=CASE WHEN p_tipo='completo' THEN p_quantidade*v_folhas
                       WHEN p_tipo='folha' THEN p_quantidade ELSE 0 END;

  -- A autorização de saída exige que a PARTE também tenha sido liberada.
  SELECT COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','folhas') THEN quantidade ELSE 0 END),0)
    INTO v_marcos_liberados,v_folhas_liberadas
    FROM public.liberacoes_corte
   WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;
  IF v_marcos_enviados+v_marcos_novos>v_marcos_liberados THEN
    RAISE EXCEPTION 'Marcos sem liberação suficiente. Disponíveis: %.',v_marcos_liberados-v_marcos_enviados;
  END IF;
  IF v_folhas IS NOT NULL AND v_folhas_enviadas+v_folhas_novas>v_folhas_liberadas*v_folhas THEN
    RAISE EXCEPTION 'Folhas sem liberação suficiente. Conjuntos liberados: %.',v_folhas_liberadas;
  END IF;
  IF p_tipo='completo' AND v_folhas IS NULL THEN
    SELECT COALESCE(SUM(quantidade),0) INTO v_completas_enviadas
    FROM public.saidas_producao WHERE esquadria_id=p_esquadria_id
      AND tipo='completo' AND cancelado_em IS NULL;
    IF v_completas_enviadas+p_quantidade>v_folhas_liberadas THEN
      RAISE EXCEPTION 'Não há conjuntos de folhas liberados para essa saída completa.';
    END IF;
  END IF;

  -- Bloqueia datas de saída anteriores à primeira liberação registrada do item.
  SELECT MIN(data_liberacao) INTO v_primeira_liberacao
  FROM public.liberacoes_corte WHERE esquadria_id=p_esquadria_id;
  IF v_primeira_liberacao IS NOT NULL AND p_data_saida<v_primeira_liberacao THEN
    RAISE EXCEPTION 'A saída não pode anteceder a primeira liberação (%).',
      v_primeira_liberacao;
  END IF;

  INSERT INTO public.saidas_producao
    (id,esquadria_id,tipo,quantidade,data_saida,usuario_id)
  VALUES (p_registro_id,p_esquadria_id,p_tipo,p_quantidade,p_data_saida,v_usuario);

  RETURN jsonb_build_object(
    'registro_id',p_registro_id,
    'repetido',false,
    'marcos_enviados',v_marcos_enviados+v_marcos_novos,
    'folhas_enviadas',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_enviadas+v_folhas_novas END,
    'marcos_possiveis',v_marcos_liberados,
    'folhas_possiveis',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_liberadas*v_folhas END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolver_modulacao_pendente_admin(p_esquadria_id uuid, p_tipologia_id uuid, p_modulacao_id uuid, p_criar_modulacao boolean, p_descricao_modulacao text, p_quantidade_modulos integer, p_confirmar_divergencia boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_item public.esquadrias%rowtype;
  v_tip public.tipologias%rowtype;
  v_mod public.tipologias_modulacoes%rowtype;
  v_principal uuid;
  v_principal_atual uuid;
  v_codigo_origem text;
  v_desc_origem text;
  v_desc_mod text;
  v_qtd integer;
  v_diferente boolean;
  v_criou boolean := false;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.esquadrias where id=p_esquadria_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  if v_uid is null then raise exception 'Entre no EWGEST.'; end if;
  if p_esquadria_id is null or p_tipologia_id is null
     or p_criar_modulacao is null or p_confirmar_divergencia is null then
    raise exception 'Informe a pendencia, a tipologia e a confirmacao.';
  end if;
  select * into v_item from public.esquadrias e where e.id=p_esquadria_id for update;
  if not found then raise exception 'Esquadria nao encontrada.'; end if;
  if not exists (
    select 1 from public.usuarios_empresas ue
    where ue.usuario_id=v_uid and ue.empresa_id=v_item.empresa_id
      and lower(ue.perfil) IN ('administrador','gerenciador')
  ) then raise exception 'Somente o administrador pode resolver pendencias.'; end if;
  if v_item.modulacao_id is not null then
    raise exception 'A modulacao desta esquadria ja foi definida; atualize a tela.';
  end if;
  select * into v_tip from public.tipologias t
   where t.id=p_tipologia_id and t.empresa_id=v_item.empresa_id;
  if not found then raise exception 'Tipologia de outra empresa ou inexistente.'; end if;
  v_principal:=coalesce(v_tip.tipologia_principal_id,v_tip.id);
  if v_item.tipologia_id is not null then
    select coalesce(t.tipologia_principal_id,t.id) into v_principal_atual
      from public.tipologias t
      where t.id=v_item.tipologia_id and t.empresa_id=v_item.empresa_id;
    if v_principal_atual is distinct from v_principal then
      raise exception 'Esta esquadria pertence a outra familia tecnica. Corrija a identificacao antes de escolher a modulacao.';
    end if;
  end if;
  v_codigo_origem:=coalesce(nullif(btrim(v_item.rotulo_tipologia_relatorio),''),btrim(v_item.codigo));
  v_desc_origem:=nullif(btrim(v_item.descricao),'');
  if v_desc_origem is null then raise exception 'Descricao de origem vazia; revise o relatorio.'; end if;
  if p_criar_modulacao then
    if p_modulacao_id is not null then raise exception 'Escolha criar OU vincular uma modulacao.'; end if;
    v_desc_mod:=nullif(btrim(p_descricao_modulacao),'');
    if v_desc_mod is null or length(v_desc_mod) not between 5 and 1000 then
      raise exception 'Informe uma descricao valida para a nova modulacao.';
    end if;
    if p_quantidade_modulos is not null and p_quantidade_modulos not between 1 and 100 then
      raise exception 'Quantidade de modulos fora do intervalo permitido.';
    end if;
    v_diferente:=upper(pg_catalog.regexp_replace(v_desc_origem,'[[:space:]]+',' ','g')) <>
      upper(pg_catalog.regexp_replace(v_desc_mod,'[[:space:]]+',' ','g'));
  else
    if p_modulacao_id is null then raise exception 'Selecione uma modulacao existente.'; end if;
    if p_quantidade_modulos is not null then
      raise exception 'Modifique o numero de modulos em um cadastro especifico, nao nesta associacao.';
    end if;
    select * into v_mod from public.tipologias_modulacoes m
      where m.id=p_modulacao_id
        and m.empresa_id=v_item.empresa_id
        and m.tipologia_principal_id=v_principal
      for update;
    if not found then raise exception 'Esta modulacao nao pertence a tipologia selecionada.'; end if;
    v_desc_mod:=v_mod.descricao;
    v_diferente:=upper(pg_catalog.regexp_replace(v_desc_origem,'[[:space:]]+',' ','g')) <>
      upper(pg_catalog.regexp_replace(v_desc_mod,'[[:space:]]+',' ','g'));
  end if;
  if v_diferente and not p_confirmar_divergencia then
    raise exception 'Descricoes diferentes: confirme a divergencia antes de associar.';
  end if;
  -- Inclui a OBRA na chave, nao permitindo que EA14_1 de outra obra seja associado.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_item.empresa_id::text||'|'||
      v_item.obra_id::text||'|'||v_codigo_origem||'|'||v_desc_origem)
  );
  if exists(select 1 from public.esquadrias e
    where e.id=p_esquadria_id and e.modulacao_id is not null
  ) then raise exception 'Modulacao ja resolvida; atualize a lista.'; end if;

  if p_criar_modulacao then
    if exists(select 1 from public.tipologias_modulacoes m
       where m.empresa_id=v_item.empresa_id
       and m.tipologia_principal_id=v_principal
       and upper(btrim(m.descricao))=upper(v_desc_mod)) then
      raise exception 'Modulacao desta descricao ja cadastrada: escolha vincular a existente.';
    end if;
    insert into public.tipologias_modulacoes(
      empresa_id,tipologia_principal_id,descricao,quantidade_modulos,tipologia_legada_id,criado_por
    ) values (
      v_item.empresa_id,v_principal,v_desc_mod,p_quantidade_modulos,
      case when v_tip.tipologia_principal_id is not null then v_tip.id else null end,
      v_uid
    ) returning * into v_mod;
    v_criou:=true;
  end if;

  update public.esquadrias e
    set tipologia_id=coalesce(e.tipologia_id,v_mod.tipologia_legada_id,v_tip.id),
        modulacao_id=v_mod.id
    where e.empresa_id=v_item.empresa_id
      and e.obra_id=v_item.obra_id
      and e.tipologia_id is not distinct from v_item.tipologia_id
      and e.modulacao_id is null
      and coalesce(nullif(btrim(e.rotulo_tipologia_relatorio),''),btrim(e.codigo))=v_codigo_origem
      and btrim(e.descricao)=v_desc_origem;
  get diagnostics v_qtd=row_count;
  if v_qtd<1 then raise exception 'Nenhuma pendencia foi classificada.'; end if;

  insert into public.classificacoes_tipologias_auditoria(
    empresa_id,obra_id,esquadria_referencia_id,tipologia_id,
    modulacao_id,codigo_origem,descricao_origem,registros_vinculados,
    confirmou_divergencia,confirmado_por
  ) values (
    v_item.empresa_id,v_item.obra_id,v_item.id,
    coalesce(v_item.tipologia_id,v_mod.tipologia_legada_id,v_tip.id),v_mod.id,
    v_codigo_origem,v_desc_origem,v_qtd,
    (v_diferente and p_confirmar_divergencia),v_uid
  );
  -- Nao salva regra global em tipologias_origens.
  return jsonb_build_object(
    'tipologia_principal_id',v_principal,'modulacao_id',v_mod.id,
    'codigo_interno',v_mod.codigo_interno,'numero_variacao',v_mod.numero_variacao,
    'nova_modulacao',v_criou,
    'esquadrias_classificadas',v_qtd,'alterou_outras_obras',false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.revisar_descricao_configuracao_admin(p_esquadria_id uuid, p_acao text, p_modulacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_item public.esquadrias%rowtype;
 v_mod public.tipologias_modulacoes%rowtype;
 v_principal uuid;
 v_codigo text;
 v_qtd integer;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.esquadrias where id=p_esquadria_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null then raise exception 'Entre no EWGEST.'; end if;
 if p_esquadria_id is null or p_acao not in ('corrigir','adiar') or p_acao is null then
   raise exception 'Selecione a esquadria e uma decisao valida.';
 end if;
 select * into v_item from public.esquadrias where id=p_esquadria_id for update;
 if not found then raise exception 'Esquadria nao encontrada.'; end if;
 if not exists(select 1 from public.usuarios_empresas ue
    where ue.usuario_id=v_uid and ue.empresa_id=v_item.empresa_id
      and lower(ue.perfil) IN ('administrador','gerenciador')) then
   raise exception 'Apenas ADM pode revisar descricoes.';
 end if;
 if v_item.tipologia_id is null or v_item.modulacao_id is not null then
   raise exception 'Esta esquadria nao tem uma pendencia de configuracao; atualize a tela.';
 end if;
 v_codigo:=coalesce(nullif(btrim(v_item.rotulo_tipologia_relatorio),''),btrim(v_item.codigo));
 select coalesce(t.tipologia_principal_id,t.id) into v_principal
 from public.tipologias t
 where t.id=v_item.tipologia_id and t.empresa_id=v_item.empresa_id;
 if v_principal is null then raise exception 'Familia tecnica inexistente.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtext(v_item.empresa_id::text||'|'||v_item.obra_id::text||
     '|'||v_codigo||'|'||v_item.descricao)
 );
 if p_acao='corrigir' then
   if p_modulacao_id is null then raise exception 'Selecione a configuracao que descreve a esquadria.'; end if;
   select * into v_mod from public.tipologias_modulacoes m
   where m.id=p_modulacao_id and m.empresa_id=v_item.empresa_id
     and m.tipologia_principal_id=v_principal
   for update;
   if not found then raise exception 'Configuracao de outra familia ou inexistente.'; end if;
   -- Apenas itens da mesma obra, origem, descricao e identidade tecnica.
   update public.esquadrias e
     set descricao=v_mod.descricao,
         modulacao_id=v_mod.id
   where e.empresa_id=v_item.empresa_id
     and e.obra_id=v_item.obra_id
     and e.tipologia_id=v_item.tipologia_id
     and e.modulacao_id is null
     and coalesce(nullif(btrim(e.rotulo_tipologia_relatorio),''),btrim(e.codigo))=v_codigo
     and btrim(e.descricao)=btrim(v_item.descricao);
   get diagnostics v_qtd=row_count;
   if v_qtd<1 then raise exception 'Pendencia alterada por outro usuario; atualize a tela.'; end if;
 else
   if p_modulacao_id is not null then
      raise exception 'Ao adiar nao se deve confirmar configuracao.';
   end if;
   select count(*) into v_qtd from public.esquadrias e
   where e.empresa_id=v_item.empresa_id
     and e.obra_id=v_item.obra_id
     and e.tipologia_id=v_item.tipologia_id
     and e.modulacao_id is null
     and coalesce(nullif(btrim(e.rotulo_tipologia_relatorio),''),btrim(e.codigo))=v_codigo
     and btrim(e.descricao)=btrim(v_item.descricao);
   if v_qtd<1 then raise exception 'Pendencia atualizada; recarregue a tela.'; end if;
 end if;
 insert into public.esquadrias_descricoes_revisoes(
   empresa_id,obra_id,esquadria_referencia_id,tipologia_id,modulacao_id,
   acao,descricao_original,descricao_resultante,esquadrias_afetadas,confirmado_por
 ) values (
   v_item.empresa_id,v_item.obra_id,v_item.id,v_item.tipologia_id,
   case when p_acao='corrigir' then v_mod.id else null end,
   p_acao,v_item.descricao,
   case when p_acao='corrigir' then v_mod.descricao else v_item.descricao end,
   v_qtd,v_uid
 );
 return jsonb_build_object('acao',p_acao,'esquadrias_afetadas',v_qtd,
  'modulacao_id',case when p_acao='corrigir' then v_mod.id else null end,
  'codigo_interno',case when p_acao='corrigir' then v_mod.codigo_interno else null end,
  'numero_variacao',case when p_acao='corrigir' then v_mod.numero_variacao else null end,
  'descricao_original_preservada',true,'obra_bloqueada',false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.salvar_abreviacao_tipologia(p_tipologia_id uuid, p_descricao_base text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_tip public.tipologias%ROWTYPE;
 v_previous text; v_next text;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_tipologia_id IS NULL THEN
  RAISE EXCEPTION 'Entre no EWGEST e selecione a tipologia.';
 END IF;
 SELECT * INTO v_tip FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Tipologia inexistente.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
   JOIN public.usuarios_login ul ON ul.usuario_id=ue.usuario_id AND ul.empresa_id=ue.empresa_id
   WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_tip.empresa_id
     AND ue.perfil IN ('administrador','gerenciador') AND ul.perfil IN ('administrador','gerenciador') AND ul.ativo) THEN
   RAISE EXCEPTION 'Somente ADM pode cadastrar ou editar abreviações.';
 END IF;
 v_next:=NULLIF(btrim(coalesce(p_descricao_base,'')),'');
 IF v_next IS NOT NULL AND (length(v_next)<2 OR length(v_next)>300) THEN
   RAISE EXCEPTION 'Informe uma abreviação entre 2 e 300 caracteres.';
 END IF;
 SELECT descricao_base INTO v_previous
   FROM public.tipologias_abreviacoes WHERE tipologia_id=p_tipologia_id FOR UPDATE;
 IF v_previous IS NOT DISTINCT FROM v_next THEN
   RETURN pg_catalog.jsonb_build_object('tipologia_id',p_tipologia_id,'abreviacao',v_next,'alterado',false);
 END IF;
 IF v_next IS NULL THEN
  DELETE FROM public.tipologias_abreviacoes WHERE tipologia_id=p_tipologia_id;
 ELSE
  INSERT INTO public.tipologias_abreviacoes(tipologia_id,empresa_id,descricao_base,atualizado_por)
  VALUES(p_tipologia_id,v_tip.empresa_id,v_next,v_uid)
  ON CONFLICT(tipologia_id) DO UPDATE SET
    descricao_base=EXCLUDED.descricao_base,
    atualizado_em=now(),atualizado_por=v_uid;
 END IF;
 INSERT INTO public.tipologias_abreviacoes_historico
  (tipologia_id,empresa_id,descricao_anterior,descricao_nova,alterado_por)
 VALUES(p_tipologia_id,v_tip.empresa_id,v_previous,v_next,v_uid);
 RETURN pg_catalog.jsonb_build_object('tipologia_id',p_tipologia_id,'abreviacao',v_next,'alterado',true);
END;$function$;

CREATE OR REPLACE FUNCTION public.salvar_croqui_tipologia_admin(p_tipologia_id uuid, p_imagem_base64 text, p_origem text, p_codigo_esquadria_referencia text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_empresa uuid;
  v_bytes bytea;
  v_total integer;
  v_origem text:=left(coalesce(nullif(btrim(p_origem),''),'Cadastro manual'),255);
  v_codigo text:=left(nullif(btrim(p_codigo_esquadria_referencia),''),100);
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.tipologias where id=p_tipologia_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_tipologia_id IS NULL THEN RAISE EXCEPTION 'Tipologia nao informada.'; END IF;
  SELECT empresa_id INTO v_empresa FROM public.tipologias WHERE id=p_tipologia_id;
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Tipologia nao encontrada.'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_empresa
      AND ue.usuario_id=v_uid
      AND lower(ue.perfil) IN ('administrador','gerenciador')
  ) THEN RAISE EXCEPTION 'Apenas o administrador pode cadastrar croquis.'; END IF;
  IF p_imagem_base64 IS NULL OR length(p_imagem_base64)<40 OR length(p_imagem_base64)>200000
     OR p_imagem_base64 !~ '^[A-Za-z0-9+/]+={0,2}$'
  THEN RAISE EXCEPTION 'O croqui precisa ser uma imagem WebP valida de ate 150 KB.'; END IF;
  BEGIN
    v_bytes:=pg_catalog.decode(p_imagem_base64,'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Imagem base64 invalida.';
  END;
  v_total:=pg_catalog.octet_length(v_bytes);
  IF v_total<20 OR v_total>150000
    OR pg_catalog.encode(pg_catalog.substring(v_bytes,1,4),'hex')<>'52494646'
    OR pg_catalog.encode(pg_catalog.substring(v_bytes,9,4),'hex')<>'57454250'
  THEN
    RAISE EXCEPTION 'Apenas croquis em formato WebP (maximo 150 KB) sao aceitos.';
  END IF;

  INSERT INTO public.tipologias_croquis
    (tipologia_id,imagem_base64,mime_type,origem,codigo_esquadria_referencia,
     tamanho_bytes,atualizado_por)
  VALUES(p_tipologia_id,p_imagem_base64,'image/webp',v_origem,v_codigo,v_total,v_uid)
  ON CONFLICT (tipologia_id) DO UPDATE
  SET imagem_base64=EXCLUDED.imagem_base64,
      origem=EXCLUDED.origem,
      codigo_esquadria_referencia=EXCLUDED.codigo_esquadria_referencia,
      tamanho_bytes=EXCLUDED.tamanho_bytes,
      atualizado_por=EXCLUDED.atualizado_por,
      atualizado_em=now();
  RETURN jsonb_build_object('tipologia_id',p_tipologia_id,'tamanho_bytes',v_total,
    'salvo',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.vincular_tipologia_existente_admin(p_esquadria_id uuid, p_tipologia_id uuid, p_confirmar_divergencia boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_item public.esquadrias%rowtype;
  v_alvo public.tipologias%rowtype;
  v_codigo text;
  v_desc text;
  v_qtd integer;
  v_divergente boolean;
BEGIN
 IF NOT public.ew_pode((select empresa_id from public.esquadrias where id=p_esquadria_id),'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
  PERFORM public.ew_exigir_sessao_atual();
  if v_uid is null then raise exception 'Entre na EWGEST.'; end if;
  if p_esquadria_id is null or p_tipologia_id is null or p_confirmar_divergencia is null then
    raise exception 'Selecione a esquadria, a tipologia e a confirmacao.';
  end if;
  select * into v_item from public.esquadrias e
   where e.id=p_esquadria_id for update;
  if not found then raise exception 'Esquadria nao encontrada.'; end if;
  if not exists (
    select 1 from public.usuarios_empresas ue
    where ue.usuario_id=v_uid and ue.empresa_id=v_item.empresa_id
      and lower(ue.perfil) IN ('administrador','gerenciador')
  ) then raise exception 'Somente o administrador pode confirmar tipologias.'; end if;
  if v_item.tipologia_id is not null then
    raise exception 'Esta esquadria ja foi classificada. Atualize o painel.';
  end if;
  select * into v_alvo from public.tipologias t
    where t.id=p_tipologia_id and t.empresa_id=v_item.empresa_id;
  if not found then raise exception 'Tipologia nao encontrada nesta empresa.'; end if;
  v_codigo:=coalesce(nullif(btrim(v_item.rotulo_tipologia_relatorio),''),btrim(v_item.codigo));
  v_desc:=nullif(btrim(v_item.descricao),'');
  if v_desc is null then raise exception 'A origem nao possui descricao; revise o relatorio.'; end if;
  v_divergente:=(upper(pg_catalog.regexp_replace(v_desc,'[[:space:]]+',' ','g'))
    is distinct from upper(pg_catalog.regexp_replace(btrim(v_alvo.descricao),'[[:space:]]+',' ','g')));
  if v_divergente and not p_confirmar_divergencia then
    raise exception 'Descricao diferente da tipologia selecionada. Confirme expressamente a divergencia.';
  end if;

  -- A trava inclui a OBRA. Mesmo codigo de esquadria em obras diferentes nao e identidade.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_item.empresa_id::text||'|'||v_item.obra_id::text||'|'||v_codigo||'|'||v_desc));
  if exists (select 1 from public.esquadrias e where e.id=p_esquadria_id and e.tipologia_id is not null) then
    raise exception 'Este cadastro ja foi classificado; atualize a lista.';
  end if;
  update public.esquadrias e set tipologia_id=v_alvo.id
   where e.empresa_id=v_item.empresa_id
     and e.obra_id=v_item.obra_id
     and e.tipologia_id is null
     and coalesce(nullif(btrim(e.rotulo_tipologia_relatorio),''),btrim(e.codigo))=v_codigo
     and btrim(e.descricao)=v_desc;
  get diagnostics v_qtd=row_count;
  if v_qtd<1 then raise exception 'Nenhuma esquadria pendente foi vinculada.'; end if;

  insert into public.classificacoes_tipologias_auditoria(
    empresa_id,obra_id,esquadria_referencia_id,tipologia_id,
    codigo_origem,descricao_origem,registros_vinculados,confirmou_divergencia,confirmado_por
  ) values (
    v_item.empresa_id,v_item.obra_id,v_item.id,v_alvo.id,
    v_codigo,v_desc,v_qtd,(v_divergente and p_confirmar_divergencia),v_uid
  );
  -- NAO altera codigo da esquadria, tipologia cadastrada, croquis,
  -- outras obras ou regras globais de tipologias_origens.
  return jsonb_build_object(
   'tipologia_id',v_alvo.id,'codigo_tipologia',v_alvo.codigo,
   'obra_id',v_item.obra_id,'esquadrias_vinculadas',v_qtd,
   'confirmacao_explicita',true,'alterou_outras_obras',false
  );
end;
$function$;

-- Função de evento DDL não é uma RPC de usuário.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
