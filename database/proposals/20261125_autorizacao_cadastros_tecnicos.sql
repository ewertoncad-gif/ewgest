-- Autorização de cadastros técnicos vinculada à empresa-alvo.
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
      AND ue.usuario_id=v_uid
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
      AND ue.usuario_id=v_uid
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
   AND u.empresa_id=p_empresa_id)
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

CREATE OR REPLACE FUNCTION public.ew_excluir_cadastro_tecnico_sem_vinculo(p_empresa_id uuid, p_tipo text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_nome text;
begin
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_id is null
    or not exists(select 1 from public.usuarios_empresas u
       where u.empresa_id=p_empresa_id and u.usuario_id=v_uid)
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
    if exists(select 1 from public.ew_compras_solicitacoes s where s.empresa_id=p_empresa_id and s.itens @> jsonb_build_array(jsonb_build_object('variacao_id',p_id)))
    or exists(select 1 from public.ew_compras_cotacoes s where s.empresa_id=p_empresa_id and s.itens @> jsonb_build_array(jsonb_build_object('variacao_id',p_id)))
    or exists(select 1 from public.ew_compras_pedidos s where s.empresa_id=p_empresa_id and s.itens @> jsonb_build_array(jsonb_build_object('variacao_id',p_id)))
    or exists(select 1 from public.ew_compras_recebimentos s where s.empresa_id=p_empresa_id and s.itens @> jsonb_build_array(jsonb_build_object('variacao_id',p_id)))
    then raise exception 'Variação vinculada ao histórico de compras: exclusão bloqueada.';end if;
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
$function$;

CREATE OR REPLACE FUNCTION public.ew_renomear_fabricante_sem_vinculo(p_empresa_id uuid, p_id uuid, p_novo_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_nome text;v_novo text:=upper(btrim(coalesce(p_novo_nome,'')));
begin
 IF NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar'; END IF;
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
   where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
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
    where ue.usuario_id=v_uid and ue.empresa_id=v_item.empresa_id) then
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
   WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_tip.empresa_id AND ul.ativo) THEN
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

ALTER POLICY "ADM insere perfis" ON public.ew_perfis TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM atualiza perfis" ON public.ew_perfis TO authenticated USING (public.ew_pode(empresa_id,'cadastros.editar')) WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM insere acessórios" ON public.ew_acessorios TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM atualiza acessórios" ON public.ew_acessorios TO authenticated USING (public.ew_pode(empresa_id,'cadastros.editar')) WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM insere variações" ON public.ew_materiais_variacoes TO authenticated WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "ADM atualiza variações" ON public.ew_materiais_variacoes TO authenticated USING (public.ew_pode(empresa_id,'cadastros.editar')) WITH CHECK (public.ew_pode(empresa_id,'cadastros.editar'));
ALTER POLICY "Administrador consulta fabricantes da empresa" ON public.fabricantes TO authenticated USING (public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'obras.consultar'));
-- Impede reatribuição de identidade ou vínculo de uma variação por PATCH.
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_identidade_cadastro_tecnico() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF (NEW.id,NEW.empresa_id) IS DISTINCT FROM (OLD.id,OLD.empresa_id) THEN RAISE EXCEPTION 'Identidade e empresa do cadastro são imutáveis.';END IF;
 IF TG_TABLE_NAME='ew_materiais_variacoes' THEN
  IF (NEW.tipo,NEW.perfil_id,NEW.acessorio_id) IS DISTINCT FROM (OLD.tipo,OLD.perfil_id,OLD.acessorio_id) THEN RAISE EXCEPTION 'Vínculo do material da variação é imutável.';END IF;
 END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_identidade_cadastro_tecnico() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_identidade_tecnica_guard BEFORE UPDATE ON public.ew_perfis FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_identidade_cadastro_tecnico();
CREATE TRIGGER ew_identidade_tecnica_guard BEFORE UPDATE ON public.ew_acessorios FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_identidade_cadastro_tecnico();
CREATE TRIGGER ew_identidade_tecnica_guard BEFORE UPDATE ON public.ew_materiais_variacoes FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_identidade_cadastro_tecnico();
