-- EWGEST v46.20: guardas obrigatórias em RPCs de escrita (perfil legado não dá acesso sem flag).
BEGIN;
CREATE OR REPLACE FUNCTION public.cancelar_romaneio_com_estorno(p_romaneio_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_header public.romaneios%rowtype;
 v_expected integer;v_updated integer;v_materal record;v_movimento uuid;v_materiais integer:=0;
 v_motivo text:=btrim(coalesce(p_motivo,''));
BEGIN
 PERFORM public.ew_exigir_permissao('romaneios.cancelar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_romaneio_id IS NULL THEN RAISE EXCEPTION 'Entre no EWGEST e escolha um romaneio.'; END IF;
 IF length(v_motivo) NOT BETWEEN 10 AND 400 THEN
  RAISE EXCEPTION 'Informe um motivo de cancelamento com 10 a 400 caracteres.';
 END IF;
 SELECT * INTO v_header FROM public.romaneios WHERE id=p_romaneio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Romaneio não encontrado.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=v_header.empresa_id AND ue.usuario_id=v_uid AND public.ew_pode(v_header.empresa_id,'romaneios.cancelar')) THEN
   RAISE EXCEPTION 'Apenas um administrador pode cancelar romaneios.';
 END IF;
 IF v_header.status='cancelado' THEN RAISE EXCEPTION 'Este romaneio já foi cancelado.'; END IF;
 -- Mesmos bloqueios de esquadria usados pelo registrador de saídas.
 PERFORM 1 FROM public.esquadrias e
 JOIN public.romaneios_itens ri ON ri.esquadria_id=e.id
 WHERE ri.romaneio_id=p_romaneio_id
 ORDER BY e.id FOR UPDATE OF e;
 SELECT count(*) INTO v_expected FROM public.romaneios_itens ri
 WHERE ri.romaneio_id=p_romaneio_id AND ri.natureza='esquadria';
 IF EXISTS(
  SELECT 1 FROM public.romaneios_itens ri
  LEFT JOIN public.saidas_producao s ON s.id=ri.saida_producao_id
  WHERE ri.romaneio_id=p_romaneio_id AND ri.natureza='esquadria'
    AND (s.id IS NULL OR s.cancelado_em IS NOT NULL OR s.esquadria_id IS DISTINCT FROM ri.esquadria_id
      OR s.tipo IS DISTINCT FROM ri.tipo_saida OR s.quantidade IS DISTINCT FROM ri.quantidade)
 ) THEN RAISE EXCEPTION 'Os movimentos não coincidem com o romaneio. Solicite revisão técnica antes do estorno.'; END IF;
 UPDATE public.saidas_producao s
 SET cancelado_em=now(),cancelado_por=v_uid
 WHERE s.id IN (
  SELECT ri.saida_producao_id FROM public.romaneios_itens ri
  WHERE ri.romaneio_id=p_romaneio_id AND ri.natureza='esquadria'
 ) AND s.cancelado_em IS NULL;
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>v_expected THEN RAISE EXCEPTION 'Estorno incompleto. Nenhum registro foi alterado.'; END IF;
 -- A devolução física deve ser confirmada na interface antes de cancelar.
 -- O estoque é recomposto com um movimento de ESTORNO rastreável, não com DELETE.
 FOR v_materal IN
   SELECT x.id AS vinculo_id,m.id AS mov_id,m.empresa_id,m.obra_id,m.variacao_id,
    m.comprimento_mm,m.unidade,m.quantidade_delta,m.local_estoque,m.origem,x.estorno_movimento_id
   FROM public.ew_romaneios_materiais_saidas x
   JOIN public.ew_estoque_obras_movimentos m ON m.id=x.movimento_id
   WHERE x.romaneio_id=p_romaneio_id ORDER BY x.id FOR UPDATE OF x
 LOOP
   IF v_materal.origem<>'SAIDA_OBRA' OR v_materal.quantidade_delta>=0
     OR v_materal.estorno_movimento_id IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
       WHERE m.estorno_de_id=v_materal.mov_id)
     THEN RAISE EXCEPTION 'Material do romaneio já estornado ou inconsistente. Cancelamento suspenso.';END IF;
   PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_materal.obra_id::text||'|'||v_materal.variacao_id::text||'|'||
    coalesce(v_materal.comprimento_mm::text,'-')||'|'||v_materal.unidade,34777));
   INSERT INTO public.ew_estoque_obras_movimentos
     (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
      origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
   VALUES(v_materal.empresa_id,v_materal.obra_id,v_materal.variacao_id,
      v_materal.comprimento_mm,v_materal.unidade,-v_materal.quantidade_delta,
      'ESTORNO',gen_random_uuid(),'Devolução física confirmada no cancelamento de romaneio '||
      v_header.numero||'. Motivo: '||v_motivo,v_uid,v_materal.local_estoque,v_materal.mov_id)
   RETURNING id INTO v_movimento;
   UPDATE public.ew_romaneios_materiais_saidas
     SET estorno_movimento_id=v_movimento WHERE id=v_materal.vinculo_id;
   v_materiais:=v_materiais+1;
 END LOOP;
 UPDATE public.romaneios SET status='cancelado',cancelado_em=now(),
  cancelado_por=v_uid,motivo_cancelamento=v_motivo WHERE id=p_romaneio_id;
 RETURN pg_catalog.jsonb_build_object('id',p_romaneio_id,'numero',v_header.numero,
  'status','cancelado','saidas_estornadas',v_updated,'materiais_devolvidos',v_materiais,
  'historico_preservado',true);
END;$function$;

CREATE OR REPLACE FUNCTION public.emitir_romaneio_com_saidas(p_chave_operacao uuid, p_obra_id uuid, p_data_saida date, p_motorista text, p_placa text, p_observacoes text, p_itens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid(); v_work public.obras%rowtype; v_rom public.romaneios%rowtype;
 v_item public.esquadrias%rowtype; v_line jsonb; v_num integer:=0;
 v_id uuid; v_ship uuid; v_qty integer; v_per integer; v_kind text;
 v_previous integer; v_factory text; v_mean numeric(8,2); v_tipo_saida text;
 v_total integer:=0; v_area numeric(14,3); v_desc text; v_code text;
 v_location text; v_measure text; v_unit text; v_desc_definida boolean;
 v_var uuid;v_length integer;v_local text;v_available numeric;v_material_tipo text;
 v_cor text;v_perfil_peso numeric;v_ri_id uuid;v_movimento_id uuid;v_peso_total numeric;
BEGIN
 PERFORM public.ew_exigir_permissao('romaneios.emitir');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_chave_operacao IS NULL OR p_obra_id IS NULL THEN
  RAISE EXCEPTION 'Faça login e informe a obra e a operação.';
 END IF;
 SELECT * INTO v_work FROM public.obras WHERE id=p_obra_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Obra inexistente.'; END IF;
 IF v_work.arquivada_em IS NOT NULL THEN RAISE EXCEPTION 'Obra arquivada não pode emitir romaneio.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
    AND ue.empresa_id=v_work.empresa_id AND public.ew_pode(v_work.empresa_id,'romaneios.emitir')
    AND EXISTS(SELECT 1 FROM public.usuarios_login ul
      WHERE ul.usuario_id=v_uid AND ul.empresa_id=ue.empresa_id
      AND ul.ativo AND ul.perfil=ue.perfil)) THEN
   RAISE EXCEPTION 'Sem permissão para emitir romaneios desta obra.';
 END IF;
 IF p_data_saida IS NULL OR p_data_saida<'2000-01-01'::date OR p_data_saida>current_date THEN
   RAISE EXCEPTION 'Data do romaneio inválida ou futura.';
 END IF;
 IF length(btrim(coalesce(p_motorista,''))) NOT BETWEEN 2 AND 140
    OR length(btrim(coalesce(p_placa,''))) NOT BETWEEN 5 AND 12 THEN
   RAISE EXCEPTION 'Informe motorista e placa válidos.';
 END IF;
 IF length(coalesce(p_observacoes,''))>1000 THEN RAISE EXCEPTION 'Observações muito extensas.'; END IF;
 IF p_itens IS NULL OR jsonb_typeof(p_itens)<>'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 60 THEN
   RAISE EXCEPTION 'Informe de 1 a 60 itens para o romaneio.';
 END IF;
 -- Idempotência da emissão inteira, incluindo todas as saídas.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_chave_operacao::text));
 SELECT * INTO v_rom FROM public.romaneios WHERE chave_operacao=p_chave_operacao;
 IF FOUND THEN
  IF v_rom.empresa_id<>v_work.empresa_id OR v_rom.obra_id<>p_obra_id THEN
    RAISE EXCEPTION 'Chave de emissão já usada em outra obra.';
  END IF;
  RETURN pg_catalog.jsonb_build_object('id',v_rom.id,'numero',v_rom.numero,'repetido',true);
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(7730058);
 INSERT INTO public.romaneios(empresa_id,obra_id,chave_operacao,data_saida,motorista,placa,observacoes,criado_por)
 VALUES(v_work.empresa_id,p_obra_id,p_chave_operacao,p_data_saida,btrim(p_motorista),upper(btrim(p_placa)),
   coalesce(p_observacoes,''),v_uid)
 RETURNING * INTO v_rom;
 -- Contexto transacional emitido apenas após validar empresa, papel e itens.
 PERFORM pg_catalog.set_config('ewgest.romaneio_emissao_id',v_rom.id::text,true);
 FOR v_line IN SELECT value FROM pg_catalog.jsonb_array_elements(p_itens) LOOP
   v_num:=v_num+1;
   IF pg_catalog.jsonb_typeof(v_line)<>'object' THEN RAISE EXCEPTION 'Item % inválido.',v_num; END IF;
   v_kind:=v_line->>'natureza';
   IF v_kind NOT IN ('esquadria','material') OR v_kind IS NULL THEN
    RAISE EXCEPTION 'Item % precisa ser esquadria ou material.',v_num;
   END IF;
   BEGIN v_qty:=(v_line->>'quantidade')::integer;
   EXCEPTION WHEN others THEN RAISE EXCEPTION 'Quantidade do item % inválida.',v_num; END;
   IF v_qty NOT BETWEEN 1 AND 100000 THEN RAISE EXCEPTION 'Quantidade inválida no item %.',v_num; END IF;
   v_desc:=btrim(coalesce(v_line->>'descricao',''));
   v_code:=btrim(coalesce(v_line->>'codigo',''));
   v_location:=btrim(coalesce(v_line->>'localizacao',''));
   v_measure:=btrim(coalesce(v_line->>'medida',''));
   v_unit:=upper(btrim(coalesce(v_line->>'unidade','UNID.')));
   IF length(v_unit) NOT BETWEEN 1 AND 12 OR length(v_desc)>350 OR length(v_code)>60
      OR length(v_location)>120 OR length(v_measure)>100 THEN
     RAISE EXCEPTION 'Dados extensos ou unidade inválida no item %.',v_num;
   END IF;
   v_factory:=NULL;v_mean:=NULL;v_id:=NULL;v_ship:=NULL;v_desc_definida:=false;
   IF v_kind='esquadria' THEN
     v_tipo_saida:=coalesce(nullif(v_line->>'tipo_saida',''),'completo');
     IF v_tipo_saida NOT IN ('completo','marco','folha') THEN
       RAISE EXCEPTION 'Tipo de saída inválido no item %.',v_num;
     END IF;
     IF NULLIF(v_line->>'esquadria_id','') IS NULL THEN
       RAISE EXCEPTION 'Selecione a esquadria no item %.',v_num;
     END IF;
     v_id:=(v_line->>'esquadria_id')::uuid;
     IF EXISTS(SELECT 1 FROM public.romaneios_itens
       WHERE romaneio_id=v_rom.id AND esquadria_id=v_id AND tipo_saida=v_tipo_saida) THEN
       RAISE EXCEPTION 'Componente da esquadria repetido neste romaneio (item %).',v_num;
     END IF;
     SELECT * INTO v_item FROM public.esquadrias WHERE id=v_id FOR UPDATE;
     IF NOT FOUND OR v_item.obra_id<>p_obra_id OR v_item.empresa_id<>v_work.empresa_id THEN
       RAISE EXCEPTION 'Esquadria do item % não pertence a esta obra.',v_num;
     END IF;
     BEGIN v_per:=(v_line->>'folhas_por_unidade')::integer;
     EXCEPTION WHEN others THEN RAISE EXCEPTION 'Confirme as folhas por unidade do item %.',v_num; END;
     -- Esquadria completa não precisa de folhas por unidade.
     -- O registrador resolve eventual composição já cadastrada.
     IF (v_per IS NOT NULL AND v_per NOT BETWEEN 1 AND 12)
       OR (v_tipo_saida<>'completo' AND v_per IS NULL) THEN
       RAISE EXCEPTION 'Confirme folhas por unidade somente para saída de marco/folha (item %).',v_num;
     END IF;
     v_ship:=gen_random_uuid();
     PERFORM public.registrar_saida_producao(v_ship,v_id,v_tipo_saida,v_qty,p_data_saida,v_per);
     v_code:=v_item.codigo;
     v_location:=coalesce(v_item.localizacao,'');
     v_desc:=case v_tipo_saida when 'marco' then 'MARCO — '
             when 'folha' then 'FOLHA — ' else '' end ||
             coalesce(v_item.descricao,'Esquadria '||v_item.codigo);
     IF v_line ? 'descricao_romaneio' THEN
       IF jsonb_typeof(v_line->'descricao_romaneio')<>'string' THEN
         RAISE EXCEPTION 'Descrição do romaneio deve ser texto no item %.',v_num;
       END IF;
       v_desc:=btrim(v_line->>'descricao_romaneio');
       IF length(v_desc) NOT BETWEEN 2 AND 350 THEN
         RAISE EXCEPTION 'Descrição do romaneio precisa ter entre 2 e 350 caracteres (item %).',v_num;
       END IF;
       v_desc_definida:=true;
     END IF;
     v_measure:=to_char(v_item.largura_mm,'FM99999990D00')||' x '||
                  to_char(v_item.altura_mm,'FM99999990D00')||' mm';
     v_unit:='UNID.';
     SELECT CASE WHEN count(*)=count(fabrica) AND count(DISTINCT fabrica)=1
         THEN min(fabrica) ELSE NULL END INTO v_factory
       FROM public.liberacoes_corte WHERE esquadria_id=v_id;
     IF v_tipo_saida='completo' AND v_factory IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM public.saidas_producao h
       WHERE h.esquadria_id=v_id AND h.tipo IN ('marco','folha')
     ) THEN
       SELECT coalesce(sum(s.quantidade),0)::integer INTO v_previous
       FROM public.saidas_producao s WHERE s.esquadria_id=v_id
         AND s.tipo='completo' AND s.cancelado_em IS NULL AND s.id<>v_ship;
       WITH lotes AS (
         SELECT data_liberacao,quantidade,
          (sum(quantidade) OVER(ORDER BY data_liberacao,id)-quantidade)::integer AS inicio,
          (sum(quantidade) OVER(ORDER BY data_liberacao,id))::integer AS fim
         FROM public.liberacoes_corte WHERE esquadria_id=v_id
       ), partes AS (
        SELECT greatest(0,least(fim,v_previous+v_qty)-greatest(inicio,v_previous)) as qtd,
        p_data_saida-data_liberacao as dias FROM lotes
       )
       SELECT CASE WHEN sum(qtd)=v_qty AND min(dias)>=0
         THEN round(sum(qtd*dias)::numeric/v_qty,2) ELSE NULL END
       INTO v_mean FROM partes WHERE qtd>0;
     END IF;
     v_area:=case v_tipo_saida
       when 'completo' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/1000000.0)::numeric,3)
       when 'marco' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/2000000.0)::numeric,3)
       when 'folha' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/(2000000.0*v_per))::numeric,3)
       else null end;
   ELSE
     -- A baixa de material é atribuição do almoxarife ou ADM.
     IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
       JOIN public.usuarios_login ul ON ul.empresa_id=ue.empresa_id AND ul.usuario_id=ue.usuario_id
       WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_work.empresa_id
         AND public.ew_pode(v_work.empresa_id,'estoque.baixar')
         AND ul.perfil=ue.perfil AND ul.ativo AND ul.excluido_em IS NULL)
       THEN RAISE EXCEPTION 'Somente ADM ou almoxarife pode expedir materiais físicos do estoque.';END IF;
     -- Material avulso NÃO é texto livre: exige estoque real identificado.
     v_tipo_saida:=NULL;
     IF v_line->>'variacao_id' IS NULL OR v_line->>'local_estoque' IS NULL
       THEN RAISE EXCEPTION 'Material % deve ser escolhido do estoque da obra.',v_num; END IF;
     v_var:=(v_line->>'variacao_id')::uuid;
     v_length:=nullif(v_line->>'comprimento_mm','')::integer;
     v_local:=upper(btrim(v_line->>'local_estoque'));
     SELECT v.tipo,coalesce(p.codigo,a.codigo),coalesce(p.descricao,a.descricao),
       coalesce(nullif(v.cor,''),nullif(v.acabamento,''),''),p.peso_kg_m
       INTO v_material_tipo,v_code,v_desc,v_cor,v_perfil_peso
     FROM public.ew_materiais_variacoes v
      LEFT JOIN public.ew_perfis p ON p.id=v.perfil_id
      LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id
     WHERE v.id=v_var AND v.empresa_id=v_work.empresa_id AND v.ativo;
     IF v_material_tipo IS NULL OR v_code IS NULL OR v_desc IS NULL THEN
       RAISE EXCEPTION 'Item % não está cadastrado como material ativo da empresa.',v_num;END IF;
     IF (v_material_tipo='perfil' AND (v_unit<>'BARRA' OR v_length NOT BETWEEN 100 AND 20000))
       OR (v_material_tipo='acessorio' AND (v_length IS NOT NULL OR v_unit NOT IN
        ('PC','PR','CJ','MT','KG','UN'))) OR v_material_tipo NOT IN ('perfil','acessorio')
       THEN RAISE EXCEPTION 'Unidade e comprimento incompatíveis com o material %.',v_num;END IF;
     IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais l WHERE l.empresa_id=v_work.empresa_id
       AND l.obra_id=p_obra_id AND l.excluido_em IS NULL)
       THEN RAISE EXCEPTION 'Estoque da obra inativo. Não é possível expedir material.';END IF;
     IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos l WHERE l.empresa_id=v_work.empresa_id
       AND l.nome=v_local AND l.ativo)
       THEN RAISE EXCEPTION 'Galpão de origem do material % não está ativo.',v_num;END IF;
     PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
       p_obra_id::text||'|'||v_var::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit,34777));
     SELECT coalesce(sum(m.quantidade_delta),0) INTO v_available
     FROM public.ew_estoque_obras_movimentos m
     WHERE m.empresa_id=v_work.empresa_id AND m.obra_id=p_obra_id
      AND m.variacao_id=v_var AND m.comprimento_mm IS NOT DISTINCT FROM v_length
      AND m.unidade=v_unit AND m.local_estoque=v_local;
     IF v_available<v_qty THEN
       RAISE EXCEPTION 'Item % sem saldo no galpão %. Disponível: % %, solicitado: % %.',
         v_num,v_local,v_available,v_unit,v_qty,v_unit;END IF;
     v_location:=v_local;
     v_measure:=CASE WHEN v_length IS NULL THEN '' ELSE v_length::text||' mm' END;
     v_desc:=v_desc||CASE WHEN v_cor<>'' THEN ' · '||v_cor ELSE '' END;
     v_area:=NULL;
   END IF;
   INSERT INTO public.romaneios_itens(romaneio_id,sequencia,natureza,esquadria_id,saida_producao_id,
    codigo,localizacao,descricao,medida,quantidade,unidade,area_m2,fabrica,prazo_liberacao_saida_dias,tipo_saida,descricao_impressao_definida)
   VALUES(v_rom.id,v_num,v_kind,v_id,v_ship,v_code,v_location,v_desc,v_measure,v_qty,v_unit,v_area,v_factory,v_mean,v_tipo_saida,v_desc_definida)
   RETURNING id INTO v_ri_id;
   IF v_kind='material' THEN
     INSERT INTO public.ew_estoque_obras_movimentos
      (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
       operacao_id,observacao,usuario_id,local_estoque)
     VALUES(v_work.empresa_id,p_obra_id,v_var,v_length,v_unit,-v_qty,'SAIDA_OBRA',
       gen_random_uuid(),'Saída direta para obra no romaneio '||v_rom.numero,v_uid,v_local)
     RETURNING id INTO v_movimento_id;
     v_peso_total:=CASE WHEN v_material_tipo='perfil' AND v_perfil_peso>0
      THEN round(v_qty*v_length/1000.0*v_perfil_peso,6) ELSE NULL END;
     INSERT INTO public.ew_romaneios_materiais_saidas
      (empresa_id,obra_id,romaneio_id,romaneio_item_id,movimento_id,variacao_id,
       comprimento_mm,unidade,quantidade,local_estoque,peso_kg,criado_por)
     VALUES(v_work.empresa_id,p_obra_id,v_rom.id,v_ri_id,v_movimento_id,v_var,
       v_length,v_unit,v_qty,v_local,v_peso_total,v_uid);
   END IF;
   v_total:=v_total+v_qty;
 END LOOP;
 RETURN pg_catalog.jsonb_build_object('id',v_rom.id,'numero',v_rom.numero,
    'repetido',false,'itens',v_num,'quantidade_total',v_total);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_arquivar_obra_reconciliada(p_obra_id uuid, p_confirmacao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_ver jsonb;
 v_record public.ew_obras_exclusoes_historico%rowtype;v_motivo text:=btrim(coalesce(p_motivo,''));
begin
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

CREATE OR REPLACE FUNCTION public.ew_cadastrar_material_manual_estoque(p_empresa_id uuid, p_obra_id uuid, p_tipo text, p_codigo text, p_descricao text, p_fabricante text, p_acabamento text, p_cor text, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_mat uuid;v_var uuid;v_mov jsonb;
 v_cod text:=upper(btrim(coalesce(p_codigo,'')));
 v_fab text:=upper(btrim(coalesce(p_fabricante,'')));
 v_desc text:=btrim(coalesce(p_descricao,''));
 v_finish text:=upper(btrim(coalesce(nullif(p_acabamento,''),'NÃO INFORMADO')));
 v_color text:=upper(btrim(coalesce(nullif(p_cor,''),'NÃO INFORMADA')));
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.receber');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
   WHERE ue.empresa_id=p_empresa_id AND ue.usuario_id=v_uid AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode cadastrar material manualmente.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
   WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id AND usuario_id=v_uid)
 THEN RETURN jsonb_build_object('repetida',true);END IF;
 IF p_tipo NOT IN ('perfil','acessorio') OR length(v_cod) NOT BETWEEN 1 AND 90
  OR length(v_fab) NOT BETWEEN 1 AND 150 OR length(v_desc) NOT BETWEEN 2 AND 500
  OR length(v_finish)>150 OR length(v_color)>150
 THEN RAISE EXCEPTION 'Informe tipo, código, descrição, fabricante e acabamento válidos.';END IF;
 IF p_tipo='perfil' AND (p_comprimento_mm NOT BETWEEN 100 AND 20000 OR p_unidade<>'BARRA')
 THEN RAISE EXCEPTION 'Informe o comprimento da barra inteira.';END IF;
 IF p_tipo='acessorio' AND (p_comprimento_mm IS NOT NULL OR p_unidade NOT IN('PC','PR','CJ','MT','KG','UN'))
 THEN RAISE EXCEPTION 'Unidade do acessório inválida.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_perfis WHERE p_tipo='perfil' AND empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fab AND upper(btrim(codigo))=v_cod)
 OR EXISTS(SELECT 1 FROM public.ew_acessorios WHERE p_tipo='acessorio' AND empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fab AND upper(btrim(codigo))=v_cod)
 THEN RAISE EXCEPTION 'Material já cadastrado. Selecione-o na lista em vez de criar duplicado.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_materiais_alias WHERE empresa_id=p_empresa_id AND tipo=p_tipo
  AND upper(btrim(fabricante))=v_fab AND upper(btrim(codigo_alternativo))=v_cod)
 THEN RAISE EXCEPTION 'Este código já está relacionado a outro material como código alternativo.';END IF;
 IF p_tipo='perfil' THEN
  INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante,comprimento_comercial_mm,criado_por,atualizado_por)
  VALUES(p_empresa_id,v_cod,v_desc,v_fab,p_comprimento_mm,v_uid,v_uid) RETURNING id INTO v_mat;
 ELSE
  INSERT INTO public.ew_acessorios(empresa_id,codigo,descricao,fabricante,unidade_item,criado_por,atualizado_por)
  VALUES(p_empresa_id,v_cod,v_desc,v_fab,p_unidade,v_uid,v_uid) RETURNING id INTO v_mat;
 END IF;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,acessorio_id,acabamento,cor,criado_por,atualizado_por)
 VALUES(p_empresa_id,p_tipo,
   CASE WHEN p_tipo='perfil' THEN v_mat ELSE NULL END,
   CASE WHEN p_tipo='acessorio' THEN v_mat ELSE NULL END,
   v_finish,v_color,v_uid,v_uid) RETURNING id INTO v_var;
 v_mov:=public.ew_movimentar_estoque_obra(p_empresa_id,p_obra_id,v_var,p_comprimento_mm,
   p_unidade,p_quantidade,p_origem,p_observacao,p_operacao_id);
 RETURN v_mov||jsonb_build_object('material_id',v_mat,'variacao_id',v_var,'novo',true);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_cadastrar_material_manual_estoque_local(p_empresa_id uuid, p_obra_id uuid, p_tipo text, p_codigo text, p_descricao text, p_fabricante text, p_acabamento text, p_cor text, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid, p_local_estoque text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_result jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.receber');
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas ue where
 ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ue.perfil IN ('administrador','gerenciador'))
 then raise exception 'Somente ADM pode cadastrar materiais.';end if;
 if not exists(select 1 from public.ew_locais_fisicos where empresa_id=p_empresa_id and nome=v_local and ativo)
 then raise exception 'Local de estoque inválido.';end if;
 v_result:=public.ew_cadastrar_material_manual_estoque(p_empresa_id,p_obra_id,p_tipo,p_codigo,
  p_descricao,p_fabricante,p_acabamento,p_cor,p_comprimento_mm,p_unidade,p_quantidade,
  p_origem,p_observacao,p_operacao_id);
 if not coalesce((v_result->>'repetida')::boolean,false) then
  update public.ew_estoque_obras_movimentos set local_estoque=v_local
  where empresa_id=p_empresa_id and operacao_id=p_operacao_id and usuario_id=v_uid;
 end if;
 return v_result||jsonb_build_object('local_estoque',v_local);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas'))
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada'
 THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r
    JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
    WHERE i.despesa_id=p_despesa_id AND r.empresa_id=p_empresa_id AND r.estornado_em is null)
 THEN RAISE EXCEPTION 'Esta nota possui materiais recebidos. Estorne as entradas de estoque antes de cancelar a despesa.';END IF;
 IF EXISTS(
    select 1 from public.ew_insumos_movimentos m
    join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
    where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id
     and m.origem='RECEBIMENTO'
 ) THEN RAISE EXCEPTION 'Nota com vidros/outros no estoque: use o cancelamento com estorno físico.';END IF;
 UPDATE public.ew_obra_despesas
 SET status='cancelada',cancelado_por=v_uid,cancelado_em=now(),
 observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status','cancelada');
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_cancelar_faturamento_financeiro(p_empresa_id uuid, p_faturamento_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_faturamento');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
  ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.cancelar_faturamento'))
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar faturamento.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe motivo de cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_faturamentos
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'emitido' THEN RAISE EXCEPTION 'Faturamento não pode ser cancelado.';END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado',cancelado_por=v_uid,
  cancelado_em=now(),observacoes=observacoes||' | Cancelado: '||btrim(p_motivo)
 WHERE id=p_faturamento_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_faturamento_id,'status','cancelado');
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_cancelar_liberacoes_obra(p_obra_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_e record;
 v_qtd integer;v_ativas integer;v_lotes integer;v_motivo text:=btrim(coalesce(p_motivo,''));v_liberacoes jsonb;
begin
 PERFORM public.ew_exigir_permissao('liberacoes.cancelar');
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe o motivo, de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u join public.usuarios_login ul
   on ul.usuario_id=u.usuario_id and ul.empresa_id=u.empresa_id
  where u.usuario_id=v_uid and u.empresa_id=v_ob.empresa_id
   and u.perfil in ('administrador','gerenciador') and ul.perfil=u.perfil and ul.ativo
   and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem cancelar liberações.';end if;
 perform 1 from public.esquadrias where obra_id=p_obra_id order by id for update;
 if exists (select 1 from public.romaneios where obra_id=p_obra_id and status<>'cancelado')
  then raise exception 'Cancele os romaneios emitidos antes das liberações.';end if;
 if exists(select 1 from public.saidas_producao s join public.esquadrias e
    on e.id=s.esquadria_id where e.obra_id=p_obra_id and s.cancelado_em is null)
  then raise exception 'Existem saídas de produção ativas. Estorne-as primeiro.';end if;
 if exists(select 1 from public.esquadrias where obra_id=p_obra_id and qtd_fabricada<>0)
  then raise exception 'Existem quantidades fabricadas que precisam ser conciliadas.';end if;
 -- Confere consistência acumulada ANTES de qualquer alteração.
 for v_e in
  select e.id,e.codigo,e.qtd_liberada,greatest(
      coalesce(sum(CASE WHEN l.tipo_componente IN ('completo','marco')
          AND l.cancelado_em IS NULL THEN l.quantidade ELSE 0 END),0),
      coalesce(sum(CASE WHEN l.tipo_componente IN ('completo','folhas')
          AND l.cancelado_em IS NULL THEN l.quantidade ELSE 0 END),0)
    )::integer as ativos
  from public.esquadrias e left join public.liberacoes_corte l on l.esquadria_id=e.id
  where e.obra_id=p_obra_id group by e.id,e.codigo,e.qtd_liberada
 loop
  if v_e.qtd_liberada<>v_e.ativos then
   raise exception 'Saldo de liberação inconsistente para %. Solicite conferência técnica.',v_e.codigo;
  end if;
 end loop;
 select count(*) into v_ativas
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 select coalesce(sum(e.qtd_liberada),0) into v_qtd
 from public.esquadrias e where e.obra_id=p_obra_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'esquadria',e.codigo,
  'quantidade',l.quantidade,'liberado_em',l.registrada_em,'liberado_por',l.usuario_id)),
  '[]'::jsonb) into v_liberacoes
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 update public.liberacoes_corte l set cancelado_em=now(),cancelado_por=v_uid,motivo_cancelamento=v_motivo
 from public.esquadrias e where l.esquadria_id=e.id and e.obra_id=p_obra_id
 and l.cancelado_em is null;
 update public.esquadrias set qtd_liberada=0 where obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
  where obra_id=p_obra_id and cancelado_em is null;
 update public.ew_liberacoes_lotes set cancelado_em=now(),cancelado_por=v_uid,
  motivo_cancelamento=v_motivo where obra_id=p_obra_id and cancelado_em is null;
 if v_ativas>0 or v_lotes>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_LIBERACOES',v_motivo,
   jsonb_build_object('registros',v_ativas,'quantidade',v_qtd,'lotes',v_lotes,
    'liberacoes_originais',v_liberacoes,
    'estoque','Baixas de materiais ainda precisam de estorno separado'));
 end if;
 return jsonb_build_object('canceladas',v_ativas,'unidades',v_qtd,'lotes',v_lotes,
  'estoque_pendente',true,'historico_preservado',true);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_cancelar_saidas_avulsas_obra(p_obra_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_total int;v_details jsonb;
begin
 PERFORM public.ew_exigir_permissao('romaneios.cancelar');
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 5 and 400 then raise exception 'Motivo obrigatório de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_ob.empresa_id
  and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
  and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Sem permissão para cancelar saídas avulsas.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 if exists(select 1 from public.romaneios r where r.obra_id=p_obra_id and r.status<>'cancelado')
 then raise exception 'Cancele os romaneios antes de estornar saídas avulsas.';end if;
 -- Não permitir operação aqui sobre saída ligada a qualquer romaneio.
 if exists(select 1 from public.saidas_producao s
  join public.esquadrias e on e.id=s.esquadria_id
  where e.obra_id=p_obra_id and s.cancelado_em is null
  and exists(select 1 from public.romaneios_itens ri where ri.saida_producao_id=s.id))
 then raise exception 'Existem saídas vinculadas a romaneios com estorno pendente. Solicite conferência técnica.';end if;
 select count(*),coalesce(jsonb_agg(jsonb_build_object('id',s.id,'esquadria_id',s.esquadria_id,
  'tipo',s.tipo,'quantidade',s.quantidade,'data_saida',s.data_saida,
  'registrada_em',s.registrada_em,'usuario_original',s.usuario_id)),'[]'::jsonb)
 into v_total,v_details
 from public.saidas_producao s join public.esquadrias e on e.id=s.esquadria_id
 where e.obra_id=p_obra_id and s.cancelado_em is null;
 update public.saidas_producao s set cancelado_em=now(),cancelado_por=v_uid
 from public.esquadrias e
 where s.esquadria_id=e.id and e.obra_id=p_obra_id and s.cancelado_em is null;
 if v_total>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_SAIDAS_AVULSAS',
   v_motivo,jsonb_build_object('saidas_canceladas',v_total,'saidas_originais',v_details));
 end if;
 return jsonb_build_object('canceladas',v_total,'historico_preservado',true);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_conciliar_codigo_cem(p_empresa_id uuid, p_tipo text, p_material_id uuid, p_codigo_cem text, p_usar_codigo_cem boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_codigo_antigo text;v_fabricante text;v_codigo text;
 v_outro uuid;v_alias uuid;v_id uuid;
BEGIN
 PERFORM public.ew_exigir_permissao('cadastros.editar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
  AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode conciliar códigos de materiais.';END IF;
 v_codigo:=upper(btrim(coalesce(p_codigo_cem,'')));
 IF p_tipo NOT IN ('perfil','acessorio') OR p_usar_codigo_cem IS NULL
   OR length(v_codigo) NOT BETWEEN 1 AND 90 THEN
   RAISE EXCEPTION 'Decisão de conciliação inválida.';END IF;
 IF p_tipo='perfil' THEN
  SELECT codigo,fabricante INTO v_codigo_antigo,v_fabricante FROM public.ew_perfis
   WHERE id=p_material_id AND empresa_id=p_empresa_id FOR UPDATE;
 ELSE
  SELECT codigo,fabricante INTO v_codigo_antigo,v_fabricante FROM public.ew_acessorios
   WHERE id=p_material_id AND empresa_id=p_empresa_id FOR UPDATE;
 END IF;
 IF v_codigo_antigo IS NULL THEN RAISE EXCEPTION 'Cadastro manual não encontrado.';END IF;
 v_fabricante:=upper(btrim(v_fabricante));v_codigo_antigo:=upper(btrim(v_codigo_antigo));
 IF v_codigo=v_codigo_antigo THEN
  RETURN jsonb_build_object('codigo_principal',v_codigo,'codigo_alternativo',null);
 END IF;
 IF p_tipo='perfil' THEN
  SELECT id INTO v_outro FROM public.ew_perfis WHERE empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fabricante AND upper(btrim(codigo))=v_codigo
    AND id<>p_material_id;
 ELSE
  SELECT id INTO v_outro FROM public.ew_acessorios WHERE empresa_id=p_empresa_id
    AND upper(btrim(fabricante))=v_fabricante AND upper(btrim(codigo))=v_codigo
    AND id<>p_material_id;
 END IF;
 IF v_outro IS NOT NULL THEN RAISE EXCEPTION 'Já existe outro material com este código CEM. Revise os cadastros.'; END IF;
 SELECT id,CASE WHEN p_tipo='perfil' THEN perfil_id ELSE acessorio_id END
 INTO v_alias,v_id FROM public.ew_materiais_alias
 WHERE empresa_id=p_empresa_id AND tipo=p_tipo AND fabricante=v_fabricante AND codigo_alternativo=v_codigo;
 IF v_alias IS NOT NULL AND v_id<>p_material_id THEN
  RAISE EXCEPTION 'Código CEM já vinculado a outro material.';END IF;
 IF p_usar_codigo_cem THEN
  IF NOT EXISTS (SELECT 1 FROM public.ew_materiais_alias WHERE empresa_id=p_empresa_id
    AND tipo=p_tipo AND fabricante=v_fabricante AND codigo_alternativo=v_codigo_antigo) THEN
   INSERT INTO public.ew_materiais_alias
   (empresa_id,tipo,perfil_id,acessorio_id,fabricante,codigo_alternativo,criado_por)
   VALUES(p_empresa_id,p_tipo,
      CASE WHEN p_tipo='perfil' THEN p_material_id ELSE NULL END,
      CASE WHEN p_tipo='acessorio' THEN p_material_id ELSE NULL END,
      v_fabricante,v_codigo_antigo,v_uid);
  END IF;
  IF p_tipo='perfil' THEN UPDATE public.ew_perfis SET codigo=v_codigo,atualizado_em=now(),atualizado_por=v_uid WHERE id=p_material_id;
  ELSE UPDATE public.ew_acessorios SET codigo=v_codigo,atualizado_em=now(),atualizado_por=v_uid WHERE id=p_material_id;END IF;
  -- Se o CEM já era um alias do mesmo material, pode permanecer para reconhecimento.
 ELSE
  IF v_alias IS NULL THEN
   INSERT INTO public.ew_materiais_alias
    (empresa_id,tipo,perfil_id,acessorio_id,fabricante,codigo_alternativo,criado_por)
   VALUES(p_empresa_id,p_tipo,
     CASE WHEN p_tipo='perfil' THEN p_material_id ELSE NULL END,
     CASE WHEN p_tipo='acessorio' THEN p_material_id ELSE NULL END,
     v_fabricante,v_codigo,v_uid);
  END IF;
 END IF;
 RETURN jsonb_build_object('material_id',p_material_id,
  'codigo_principal',CASE WHEN p_usar_codigo_cem THEN v_codigo ELSE v_codigo_antigo END,
  'codigo_alternativo',CASE WHEN p_usar_codigo_cem THEN v_codigo_antigo ELSE v_codigo END);
END;$function$;

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
 PERFORM public.ew_exigir_permissao('liberacoes.criar');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_referencia_id is null
  or p_operacao_id is null or p_tipo not in ('PLANO','LOTE')
  or not exists(select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
   and u.empresa_id=p_empresa_id and u.perfil in ('administrador','almoxarife'))
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

CREATE OR REPLACE FUNCTION public.ew_criar_obra_estoque(p_empresa_id uuid, p_nome text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_obra uuid:=gen_random_uuid();v_codigo text;v_nome text;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
   WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode criar obras para o estoque.';END IF;
 v_nome:=btrim(coalesce(p_nome,''));
 v_codigo:=upper(btrim(coalesce(p_codigo,'')));
 IF length(v_nome) NOT BETWEEN 3 AND 180 OR length(v_codigo)>80
 THEN RAISE EXCEPTION 'Nome ou código de obra inválido.';END IF;
 IF v_codigo='' THEN v_codigo:='MAN-'||upper(left(replace(v_obra::text,'-',''),10));END IF;
 IF EXISTS(SELECT 1 FROM public.obras WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND
   (upper(btrim(nome))=upper(v_nome) OR upper(btrim(codigo))=v_codigo))
 THEN RAISE EXCEPTION 'Já existe uma obra com este nome ou código. Selecione-a na lista.';END IF;
 INSERT INTO public.obras(id,empresa_id,codigo,nome,cliente,situacao)
 VALUES(v_obra,p_empresa_id,v_codigo,v_nome,NULL,'Em andamento');
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(p_empresa_id,v_obra,v_uid);
 RETURN jsonb_build_object('id',v_obra,'codigo',v_codigo,'nome',v_nome);
END;$function$;

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

CREATE OR REPLACE FUNCTION public.ew_estornar_movimento_obra(p_obra_id uuid, p_movimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid := auth.uid();
 v_obra public.obras%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_audit public.ew_auditoria_operacoes%rowtype;
 v_ver jsonb;
 v_mov public.ew_estoque_obras_movimentos%rowtype;
 v_motivo text := btrim(coalesce(p_motivo,''));
 v_saldo numeric;
 v_n integer := 0;
 v_par integer;
 v_soma numeric;
 v_materials integer;
 v_locais integer;
 v_local_retirada text;
 v_total_disponivel numeric;
 v_local_alocacao record;
 v_falta numeric;
 v_parcela numeric;
 v_estorno_id uuid;
 v_primeiro boolean:=true;
 v_parcelas jsonb:='[]'::jsonb;
 v_originais jsonb := '[]'::jsonb;
begin
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_movimento_id is null or p_operacao_id is null then
  raise exception 'Obra, movimento, operação e usuário são obrigatórios.';
 end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo com 5 a 400 caracteres.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found or v_obra.arquivada_em is not null then
  raise exception 'Obra não encontrada ou já arquivada.';
 end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
   and ue.perfil in ('administrador','gerenciador')
   and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem realizar estornos.'; end if;
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao <> 'ESTORNAR_ESTOQUE'
   or v_audit.obra_id is distinct from p_obra_id or v_audit.usuario_id <> v_uid
   or v_audit.referencia_id is distinct from p_movimento_id
   or v_audit.detalhes->>'modo' IS DISTINCT FROM 'individual' then
   raise exception 'Identificador de operação já usado em outro estorno.';
  end if;
  return jsonb_build_object('repetida',true,
   'estornados',v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 select * into v_original from public.ew_estoque_obras_movimentos
 where id=p_movimento_id and obra_id=p_obra_id for update;
 if not found then raise exception 'Movimentação não encontrada nesta obra.'; end if;
 if v_original.origem='SAIDA_OBRA' then
   raise exception 'Saída direta de material vinculada a romaneio. Cancele o romaneio e confirme a devolução física; não faça estorno isolado.';
  end if;
 if v_original.origem='ESTORNO' then
  raise exception 'Contrapartida de estorno é somente histórico. Nunca estorne outra vez o mesmo lançamento; revise a origem.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n where n.movimento_id=v_original.id) then
  raise exception 'Movimento vinculado à NF-e: use Estornar recebimento na tela Recebimento.';
 end if;
 if v_original.estorno_de_id is not null then
  raise exception 'Uma contrapartida de estorno não pode ser cancelada novamente.';
 end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos e
  where e.estorno_de_id=p_movimento_id) then
  raise exception 'Esta movimentação já foi estornada.';
 end if;
 v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
 if exists (
  select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
  where x.motivo not like 'Estorne as movimentações do estoque%'
 ) then
  raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
 end if;
 -- Transferência entre galpões é uma operação única de duas pernas.
 if v_original.transferencia_id is not null then
  if v_original.origem<>'TRANSFERENCIA' then
   raise exception 'Movimento de transferência possui origem inconsistente.';
  end if;
  select count(*),coalesce(sum(m.quantidade_delta),0),
   count(distinct (m.variacao_id::text||'|'||coalesce(m.comprimento_mm::text,'')||'|'||m.unidade)),
   count(distinct m.local_estoque)
  into v_par,v_soma,v_materials,v_locais
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.transferencia_id=v_original.transferencia_id;
  if v_par<>2 or v_soma<>0 or v_materials<>1 or v_locais<>2 then
   raise exception 'Transferência incompleta ou inconsistente. Não é seguro estornar uma perna isoladamente.';
  end if;
 end if;
 -- O lock por material/obra é o mesmo usado por transferências e NF-e,
 -- impedindo alteração de saldo enquanto as parcelas são planejadas.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||v_original.variacao_id::text||'|'||
  coalesce(v_original.comprimento_mm::text,'-')||'|'||v_original.unidade,34777));
 -- Transferência ENTRE GALPÕES: o estorno deve respeitar a cadeia das
 -- movimentações e nunca fingir que o material voltou fisicamente de galpão.
 -- Saldo recomposto por compra posterior não prova que o lote não foi usado.
 IF v_original.transferencia_id IS NOT NULL THEN
  SELECT * INTO v_mov FROM public.ew_estoque_obras_movimentos
  WHERE obra_id=p_obra_id AND transferencia_id=v_original.transferencia_id
    AND origem='TRANSFERENCIA' AND quantidade_delta>0
  LIMIT 1;
  IF v_mov.id IS NULL THEN
   RAISE EXCEPTION 'Crédito da transferência entre galpões não localizado.';
  END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_mov.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_mov.comprimento_mm
    AND m.unidade=v_mov.unidade AND m.criado_em>v_mov.criado_em
    AND m.quantidade_delta<0
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE','SAIDA_OBRA')
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id)
  ) THEN
   RAISE EXCEPTION 'Material utilizado após transferência entre galpões. Cancele o romaneio/saída e estorne a baixa de fabricação antes de desfazer a transferência.';
  END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_mov.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_mov.comprimento_mm
    AND m.unidade=v_mov.unidade AND m.criado_em>v_mov.criado_em
    AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
    AND m.transferencia_id IS DISTINCT FROM v_original.transferencia_id
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id)
  ) THEN
   RAISE EXCEPTION 'Transferência posterior do mesmo material ainda ativa. Estorne primeiro a transferência mais recente, seja para outro galpão ou outra obra.';
  END IF;
 END IF;
 -- Cancelar entrada não vinculada a NF-e: a localização física é irrelevante,
 -- mas material consumido ou transferido a outra obra continua indisponível.
 IF v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0 THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE','SAIDA_OBRA')
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material consumido na fabricação. Cancele primeiro romaneios, saídas e baixas.';END IF;
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
    AND EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
      WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
       AND other.obra_id<>m.obra_id)
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material transferido a outra obra. Devolva-o antes de estornar a entrada.';END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade
   GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<0
  ) THEN
   RAISE EXCEPTION 'Saldo negativo em galpão da obra: concilie antes do estorno.';
  END IF;
  SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_total_disponivel
  FROM(SELECT sum(m.quantidade_delta) saldo FROM public.ew_estoque_obras_movimentos m
    WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
     AND m.variacao_id=v_original.variacao_id
     AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
     AND m.unidade=v_original.unidade GROUP BY m.local_estoque) t;
  IF v_total_disponivel<v_original.quantidade_delta THEN
   RAISE EXCEPTION 'Saldo insuficiente na obra. Devolva material transferido ou usado antes do estorno.';
  END IF;
 END IF;
 -- Toda a obra é serializada pelo mesmo bloqueio da reversão total.
 perform 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
  and (m.id=p_movimento_id or
   (v_original.transferencia_id is not null
    and m.transferencia_id=v_original.transferencia_id))
 order by m.id for update;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  if v_mov.estorno_de_id is not null or exists(
   select 1 from public.ew_estoque_obras_movimentos s where s.estorno_de_id=v_mov.id
  ) then raise exception 'Uma das movimentações já foi estornada. Recarregue o histórico.'; end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.variacao_id=v_mov.variacao_id
   and m.comprimento_mm is not distinct from v_mov.comprimento_mm
   and m.unidade=v_mov.unidade and m.local_estoque=v_mov.local_estoque;
  if v_original.transferencia_id IS NOT NULL AND v_saldo-v_mov.quantidade_delta<0 then
   raise exception 'Estorno individual deixaria saldo negativo em % (% %). Desfaça antes as movimentações posteriores dependentes.',
    v_mov.local_estoque,v_saldo,v_mov.unidade;
  end if;
 end loop;
 IF v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0 THEN
  v_falta:=v_original.quantidade_delta;
  v_originais:=jsonb_build_array(jsonb_build_object(
   'movimento_id',v_original.id,'origem',v_original.origem,
   'quantidade',v_original.quantidade_delta,
   'variacao_id',v_original.variacao_id,
   'comprimento_mm',v_original.comprimento_mm,'unidade',v_original.unidade,
   'galpao_original',v_original.local_estoque,
   'usuario_original',v_original.usuario_id,'registrado_em',v_original.criado_em));
  FOR v_local_alocacao IN
   SELECT m.local_estoque,sum(m.quantidade_delta) saldo
   FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade
   GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)>0
   ORDER BY (m.local_estoque=v_original.local_estoque) DESC,m.local_estoque
  LOOP
   EXIT WHEN v_falta<=0;
   v_parcela:=least(v_falta,v_local_alocacao.saldo);
   INSERT INTO public.ew_estoque_obras_movimentos
   (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
   VALUES(v_original.empresa_id,v_original.obra_id,v_original.variacao_id,
    v_original.comprimento_mm,v_original.unidade,-v_parcela,'ESTORNO',
    pg_catalog.gen_random_uuid(),left('Estorno individual: '||v_motivo,500),
    v_uid,v_local_alocacao.local_estoque,
    CASE WHEN v_primeiro THEN v_original.id ELSE NULL END)
   RETURNING id INTO v_estorno_id;
   INSERT INTO public.ew_estornos_parcelas
    (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
     local_estoque,quantidade)
   VALUES(v_original.empresa_id,v_original.obra_id,p_operacao_id,
    v_original.id,v_estorno_id,v_local_alocacao.local_estoque,v_parcela);
   v_primeiro:=false;
   v_n:=v_n+1;
   v_falta:=v_falta-v_parcela;
   v_parcelas:=v_parcelas||jsonb_build_array(jsonb_build_object(
    'galpao',v_local_alocacao.local_estoque,'quantidade',v_parcela,
    'movimento_estorno_id',v_estorno_id,'movimento_original_id',v_original.id));
  END LOOP;
  IF v_falta<>0 THEN
   RAISE EXCEPTION 'Não foi possível alocar todas as parcelas. Operação cancelada.';
  END IF;
 ELSE
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  insert into public.ew_estoque_obras_movimentos (
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id
  ) values (
   v_mov.empresa_id,v_mov.obra_id,v_mov.variacao_id,v_mov.comprimento_mm,
   v_mov.unidade,-v_mov.quantidade_delta,'ESTORNO',pg_catalog.gen_random_uuid(),
   left('Estorno individual: '||v_motivo,500),v_uid,
   CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id,
   'galpao_do_estorno',CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END
  ));
 end loop;
 END IF;
 insert into public.ew_auditoria_operacoes (
  empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
  referencia_id,operacao_id,motivo,detalhes
 ) values (
  v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_movimento_id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','individual','movimentos_estornados',v_n,
   'movimentos_originais',v_originais,
   'parcelas',v_parcelas)
 );
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.ew_estornar_recebimento_nfe(p_empresa_id uuid, p_recebimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid();
 v_rec public.ew_nfe_recebimentos%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_obra public.obras%rowtype;
 v_local record;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_disponivel numeric:=0;
 v_restante numeric;
 v_baixas integer;
 v_abatido numeric;
 v_mov uuid;
 v_locais jsonb:='[]'::jsonb;
 v_primeiro boolean:=true;
begin
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 perform public.ew_exigir_sessao_atual();
 if v_user is null or p_empresa_id is null or p_recebimento_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas ue
    join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
    where ue.usuario_id=v_user and ue.empresa_id=p_empresa_id
      and ue.perfil='administrador' and ul.perfil='administrador'
      and ul.ativo and ul.excluido_em is null)
 then raise exception 'Somente o ADM pode estornar recebimentos de NF-e.';end if;
 if char_length(v_motivo) not between 5 and 400 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_recebimento_id::text,912425));
 select * into v_rec from public.ew_nfe_recebimentos n
  where n.id=p_recebimento_id and n.empresa_id=p_empresa_id for update;
 if not found then raise exception 'Recebimento não encontrado na empresa.';end if;
 if v_rec.estornado_em is not null then
   if v_rec.estorno_operacao_id=p_operacao_id then
     return jsonb_build_object('ja_estornado',true,'recebimento_id',v_rec.id,
       'locais',coalesce(v_rec.estorno_detalhes,'[]'::jsonb));
   end if;
   raise exception 'Recebimento já estornado anteriormente. Consulte o histórico.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n
  where n.estorno_operacao_id=p_operacao_id and n.id<>p_recebimento_id)
 then raise exception 'Identificador usado em outro estorno.';end if;
 select * into v_obra from public.obras o where o.id=v_rec.obra_id
  and o.empresa_id=p_empresa_id and o.arquivada_em is null for update;
 if not found then raise exception 'Obra não encontrada ou arquivada.';end if;
 select * into v_original from public.ew_estoque_obras_movimentos m
  where m.id=v_rec.movimento_id and m.empresa_id=p_empresa_id
   and m.obra_id=v_rec.obra_id for update;
 if not found or v_original.quantidade_delta<>v_rec.quantidade
    or v_original.variacao_id<>v_rec.variacao_id
    or v_original.comprimento_mm is distinct from v_rec.comprimento_mm
    or v_original.unidade<>v_rec.unidade
    or v_original.origem<>'COMPRA'
 then raise exception 'O recebimento original não confere com a movimentação de compra.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.estorno_de_id=v_original.id)
 then raise exception 'Movimento original já possui estorno associado. Revisão manual necessária.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   v_rec.obra_id::text||'|'||v_rec.variacao_id::text||'|'||
   coalesce(v_rec.comprimento_mm::text,'-')||'|'||v_rec.unidade,34777));
 -- Sem identificação de lote por NF, qualquer baixa de consumo posterior da MESMA
 -- variação/medida/unidade impede declarar o lote recebido como ainda não utilizado.
 -- Transferência de galpão não é consumo.
 select count(*) into v_baixas from public.ew_estoque_obras_movimentos m
 where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
   and m.variacao_id=v_rec.variacao_id
   and m.comprimento_mm is not distinct from v_rec.comprimento_mm
   and m.unidade=v_rec.unidade and m.quantidade_delta<0
   and m.criado_em>=v_rec.criado_em
   and m.origem in ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE');
 if v_baixas>0 then raise exception
  'Estorno bloqueado: há baixa de produção/consumo após esta NF. O estoque não rastreia lote por nota; confira a entrega e faça reconciliação autorizada.';end if;
 select coalesce(sum(q.saldo),0) into v_disponivel from (
   select sum(m.quantidade_delta) saldo from public.ew_estoque_obras_movimentos m
   where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
    and m.variacao_id=v_rec.variacao_id
    and m.comprimento_mm is not distinct from v_rec.comprimento_mm
    and m.unidade=v_rec.unidade
   group by m.local_estoque having sum(m.quantidade_delta)>0
 ) q;
 if v_disponivel<v_rec.quantidade then
  raise exception 'Saldo disponível na obra insuficiente (% %). Se transferido para outra obra, devolva antes do estorno.',
   v_disponivel,v_rec.unidade;end if;
 v_restante:=v_rec.quantidade;
 for v_local in
  select m.local_estoque,sum(m.quantidade_delta) as saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
   and m.variacao_id=v_rec.variacao_id
   and m.comprimento_mm is not distinct from v_rec.comprimento_mm
   and m.unidade=v_rec.unidade
  group by m.local_estoque having sum(m.quantidade_delta)>0
  order by (m.local_estoque=v_rec.local_estoque) desc,m.local_estoque
 loop
  exit when v_restante<=0;
  v_abatido:=least(v_local.saldo,v_restante);
  insert into public.ew_estoque_obras_movimentos
   (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(p_empresa_id,v_rec.obra_id,v_rec.variacao_id,v_rec.comprimento_mm,
    v_rec.unidade,-v_abatido,'ESTORNO',gen_random_uuid(),
    left('Estorno do recebimento NF (sem cancelar a despesa): '||v_motivo,500),
    v_user,v_local.local_estoque,case when v_primeiro then v_original.id else null end)
  returning id into v_mov;
  v_primeiro:=false;
  v_locais:=v_locais||jsonb_build_array(jsonb_build_object(
    'galpao',v_local.local_estoque,'quantidade',v_abatido,'movimento_id',v_mov));
  v_restante:=v_restante-v_abatido;
 end loop;
 if v_restante<>0 then raise exception 'Não foi possível completar o estorno físico.';end if;
 update public.ew_nfe_recebimentos
 set estornado_em=now(),estornado_por=v_user,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id,estorno_detalhes=v_locais
 where id=v_rec.id and empresa_id=p_empresa_id and estornado_em is null;
 return jsonb_build_object('ja_estornado',false,'recebimento_id',v_rec.id,
  'quantidade_estornada',v_rec.quantidade,'unidade',v_rec.unidade,
  'locais',v_locais,'despesa_preservada',true);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras(p_empresa_id uuid, p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_debito public.ew_estoque_obras_movimentos%rowtype;
 v_credito public.ew_estoque_obras_movimentos%rowtype;
 v_n integer;
 v_saldo numeric;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_status jsonb;
 v_key_a text;
 v_key_b text;
 v_local_disponivel text;
 v_saldo_total numeric;
 v_alocacao record;
 v_falta numeric;
 v_parcela numeric;
 v_estorno_id uuid;
 v_primeiro boolean:=true;
 v_locais jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 PERFORM public.ew_exigir_sessao_atual();
 IF p_empresa_id IS NULL OR p_transferencia_id IS NULL OR p_operacao_id IS NULL
 OR v_uid IS NULL OR NOT EXISTS (
  SELECT 1 FROM public.usuarios_empresas u
  JOIN public.usuarios_login ul
   ON ul.empresa_id=u.empresa_id AND ul.usuario_id=u.usuario_id
  WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_uid
   AND u.perfil IN ('administrador','gerenciador')
   AND ul.perfil=u.perfil AND ul.ativo AND ul.excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Somente ADM pode estornar transferências entre obras.'; END IF;
 IF char_length(v_motivo) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe motivo de 5 a 350 caracteres.'; END IF;

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'ESTORNO_TRANSF_OBRAS|'||p_operacao_id::text,62841));
 -- Operação repetida só pode corresponder à mesma transferência, empresa
 -- e a TODAS as parcelas: o primeiro estorno está no campo estorno_de_id
 -- (UNIQUE), as demais são ligadas pela tabela interna ew_estornos_parcelas.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE transferencia_id=p_operacao_id AND origem='ESTORNO') THEN
  SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos m
  WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO';
  IF v_n>=2 AND
   (SELECT count(*) FROM public.ew_estornos_parcelas ep
    WHERE ep.operacao_id=p_operacao_id AND ep.empresa_id=p_empresa_id)=v_n
   AND NOT EXISTS(
    SELECT 1 FROM public.ew_estoque_obras_movimentos m
    LEFT JOIN public.ew_estornos_parcelas ep
     ON ep.movimento_estorno_id=m.id AND ep.operacao_id=p_operacao_id
    LEFT JOIN public.ew_estoque_obras_movimentos original
     ON original.id=ep.movimento_original_id
    WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO'
    AND (ep.id IS NULL OR ep.empresa_id<>p_empresa_id
     OR original.transferencia_id IS DISTINCT FROM p_transferencia_id
     OR m.empresa_id<>p_empresa_id
     OR ep.quantidade<>abs(m.quantidade_delta)
     OR ep.local_estoque<>m.local_estoque)
   )
  THEN RETURN jsonb_build_object('repetida',true,'estornados',v_n); END IF;
  RAISE EXCEPTION 'Identificador já utilizado ou estorno parcial inconsistente.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estornos_parcelas
   WHERE operacao_id=p_operacao_id) THEN
   RAISE EXCEPTION 'Identificador de estorno já utilizado.';
 END IF;

 SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id AND origem='TRANSFERENCIA';
 IF v_n<>2 THEN RAISE EXCEPTION 'Transferência entre obras não localizada ou incompleta.';END IF;
 SELECT * INTO v_debito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta<0;
 SELECT * INTO v_credito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta>0;
 IF v_debito.id IS NULL OR v_credito.id IS NULL OR
  v_debito.obra_id=v_credito.obra_id OR
  v_debito.variacao_id IS DISTINCT FROM v_credito.variacao_id OR
  v_debito.comprimento_mm IS DISTINCT FROM v_credito.comprimento_mm OR
  v_debito.unidade IS DISTINCT FROM v_credito.unidade OR
  v_debito.quantidade_delta<>-v_credito.quantidade_delta
 THEN RAISE EXCEPTION 'Movimentos da transferência não formam um par íntegro.'; END IF;

 v_key_a:=v_debito.obra_id::text;
 v_key_b:=v_credito.obra_id::text;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),977124));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),977124));
 IF NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_debito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_credito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_debito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_credito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL)
 THEN RAISE EXCEPTION 'Uma das obras ou estoques está arquivada.'; END IF;

 v_status:=public.ew_inspecionar_reversao_obra(v_debito.obra_id);
 IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements_text(v_status->'motivos') AS motivo(texto)
  WHERE motivo.texto NOT LIKE 'Estorne as movimentações do estoque%')
 THEN RAISE EXCEPTION 'Existem liberações ou outras pendências na obra de origem. Concilie antes.';END IF;
 v_status:=public.ew_inspecionar_reversao_obra(v_credito.obra_id);
 IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements_text(v_status->'motivos') AS motivo(texto)
  WHERE motivo.texto NOT LIKE 'Estorne as movimentações do estoque%')
 THEN RAISE EXCEPTION 'Existem liberações ou outras pendências na obra de destino. Concilie antes.';END IF;

 -- Mesmo lock do estoque normal; origem e destino em ordem estável.
 v_key_a:=v_debito.obra_id::text||'|'||v_debito.variacao_id::text||'|'||
  coalesce(v_debito.comprimento_mm::text,'-')||'|'||v_debito.unidade;
 v_key_b:=v_credito.obra_id::text||'|'||v_credito.variacao_id::text||'|'||
  coalesce(v_credito.comprimento_mm::text,'-')||'|'||v_credito.unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),34777));

 IF EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos
  WHERE estorno_de_id IN (v_debito.id,v_credito.id))
 THEN RAISE EXCEPTION 'Uma das pernas já foi estornada. Recarregue o histórico.';END IF;
 -- O saldo disponível não prova que o lote transferido não foi utilizado:
 -- sem lote individual, bloquear consumos posteriores ainda não estornados.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0
   AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE')
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Estorno bloqueado: material consumido na obra de destino. Cancele o romaneio, reverta a saída e estorne a baixa primeiro.';END IF;
 -- Transferências posteriores para OUTRAS obras devem ser desfeitas em ordem inversa.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
   AND m.transferencia_id IS DISTINCT FROM p_transferencia_id
   AND EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
    WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
     AND other.obra_id<>m.obra_id)
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
    WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Material enviado posteriormente para outra obra. Devolva-o primeiro à obra de destino antes de estornar esta transferência.'; END IF;
 -- Não cancelar um material enquanto algum galpão da obra apresenta
 -- saldo negativo para a mesma combinação de variação, unidade e medida.
 IF EXISTS(
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<0
 ) THEN RAISE EXCEPTION 'Saldo negativo na obra destino. Concilie antes de devolver.'; END IF;
 SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_saldo_total
 FROM (SELECT sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
    AND m.variacao_id=v_credito.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
    AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque) t;
 IF v_saldo_total<v_credito.quantidade_delta THEN
  RAISE EXCEPTION 'Saldo insuficiente na obra destino: disponível % de % %.',
    v_saldo_total,v_credito.quantidade_delta,v_credito.unidade;
 END IF;
 v_falta:=v_credito.quantidade_delta;
 v_n:=0;
 -- Descontar exatamente a quantidade que está em cada galpão, sem transferir
 -- o material de volta ao galpão histórico antes de cancelar a operação.
 FOR v_alocacao IN
  SELECT m.local_estoque,sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)>0
  ORDER BY (m.local_estoque=v_credito.local_estoque) DESC,m.local_estoque
 LOOP
  EXIT WHEN v_falta<=0;
  v_parcela:=least(v_falta,v_alocacao.saldo);
  INSERT INTO public.ew_estoque_obras_movimentos
  (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
  VALUES (p_empresa_id,v_credito.obra_id,v_credito.variacao_id,
   v_credito.comprimento_mm,v_credito.unidade,-v_parcela,'ESTORNO',
   gen_random_uuid(),left('Estorno transferência entre obras: '||v_motivo,500),
   v_uid,v_alocacao.local_estoque,p_operacao_id,
   CASE WHEN v_primeiro THEN v_credito.id ELSE NULL END)
  RETURNING id INTO v_estorno_id;
  INSERT INTO public.ew_estornos_parcelas
   (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
    local_estoque,quantidade)
  VALUES(p_empresa_id,v_credito.obra_id,p_operacao_id,v_credito.id,v_estorno_id,
   v_alocacao.local_estoque,v_parcela);
  IF v_primeiro THEN v_local_disponivel:=v_alocacao.local_estoque; END IF;
  v_primeiro:=false;
  v_falta:=v_falta-v_parcela;
  v_n:=v_n+1;
  v_locais:=v_locais||jsonb_build_array(jsonb_build_object(
   'obra_id',v_credito.obra_id,'galpao',v_alocacao.local_estoque,
   'quantidade',v_parcela,'movimento_estorno_id',v_estorno_id,
   'movimento_original_id',v_credito.id));
 END LOOP;
 IF v_falta<>0 THEN
  RAISE EXCEPTION 'Alocação física inconsistente: faltam % %. Operação revertida.',v_falta,v_credito.unidade;
 END IF;
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
 VALUES (p_empresa_id,v_debito.obra_id,v_debito.variacao_id,v_debito.comprimento_mm,
  v_debito.unidade,-v_debito.quantidade_delta,'ESTORNO',gen_random_uuid(),
  left('Devolução para obra de origem: '||v_motivo,500),v_uid,
  v_debito.local_estoque,p_operacao_id,v_debito.id)
 RETURNING id INTO v_estorno_id;
 INSERT INTO public.ew_estornos_parcelas
  (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
   local_estoque,quantidade)
 VALUES (p_empresa_id,v_debito.obra_id,p_operacao_id,v_debito.id,v_estorno_id,
  v_debito.local_estoque,-v_debito.quantidade_delta);
 v_n:=v_n+1;
 INSERT INTO public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
   referencia_id,operacao_id,motivo,detalhes)
 VALUES (p_empresa_id,v_debito.obra_id,
  (SELECT nome FROM public.obras WHERE id=v_debito.obra_id),
  (SELECT codigo FROM public.obras WHERE id=v_debito.obra_id),
  v_uid,'ESTORNAR_ESTOQUE',v_debito.id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','transferencia_entre_obras',
   'transferencia_original_id',p_transferencia_id,
   'obra_origem_id',v_debito.obra_id,'obra_destino_id',v_credito.obra_id,
   'galpao_devolucao_origem',v_debito.local_estoque,
   'parcelas_destino',v_locais,'movimentos_estornados',v_n));
 RETURN jsonb_build_object('repetida',false,'estornados',v_n,
  'origem_obra_id',v_debito.obra_id,'destino_obra_id',v_credito.obra_id,
  'galpao_da_retirada',v_local_disponivel,'parcelas',v_locais,
  'historico_preservado',true);
END;
$function$;

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
 PERFORM public.ew_exigir_permissao('cadastros.editar');
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
$function$;

CREATE OR REPLACE FUNCTION public.ew_gerenciar_cadastro_auxiliar(p_empresa_id uuid, p_tipo text, p_id uuid, p_acao text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_antigo text;v_novo text;v_em_uso boolean;
begin
 PERFORM public.ew_exigir_permissao('cadastros.editar');
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

CREATE OR REPLACE FUNCTION public.ew_importar_cem_conciliado(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_d jsonb;v_tipo text;v_codigo text;v_fabricante text;v_id uuid;v_usar boolean;
 v_row jsonb;v_encontrado boolean;v_result jsonb;v_seen text[]:=ARRAY[]::text[];v_key text;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode realizar importação conciliada.';END IF;
 IF jsonb_typeof(p_decisoes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_decisoes)>400
 THEN RAISE EXCEPTION 'Lista de conciliações inválida.';END IF;
 -- Se operação foi anteriormente concluída, não repetir os efeitos de conciliação.
 SELECT resumo INTO v_result FROM public.ew_cem_importacoes_materiais
 WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF FOUND THEN RETURN v_result;END IF;
 FOR v_d IN SELECT value FROM jsonb_array_elements(p_decisoes) LOOP
   v_tipo:=v_d->>'tipo';v_codigo:=upper(btrim(v_d->>'codigo_cem'));
   v_fabricante:=upper(btrim(v_d->>'fabricante'));
   v_id:=(v_d->>'material_id')::uuid;
   v_usar:=(v_d->>'usar_codigo_cem')::boolean;
   v_key:=v_tipo||'|'||v_fabricante||'|'||v_codigo;
   IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'Decisão repetida para código CEM %.',v_codigo;END IF;
   v_seen:=array_append(v_seen,v_key);
   v_encontrado:=false;
   FOR v_row IN SELECT value FROM jsonb_array_elements(CASE WHEN v_tipo='perfil' THEN p_perfis ELSE p_acessorios END) LOOP
      IF upper(btrim(coalesce(v_row->>'codigo','')))=v_codigo AND upper(btrim(coalesce(v_row->>'fabricante','')))=v_fabricante
      THEN v_encontrado:=true;EXIT; END IF;
   END LOOP;
   IF NOT v_encontrado THEN RAISE EXCEPTION 'A conciliação não corresponde ao arquivo CEM: %.',v_codigo;END IF;
   PERFORM public.ew_conciliar_codigo_cem(p_empresa_id,v_tipo,v_id,v_codigo,v_usar);
 END LOOP;
 RETURN public.importar_materiais_cem(p_empresa_id,p_codigo_obra,p_perfis,p_acessorios,p_operacao_id);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_codigo text:=upper(btrim(coalesce(p_codigo_obra,'')));
  v_nome text:=btrim(coalesce(p_nome_obra,''));
  v_cliente text:=btrim(coalesce(p_cliente,''));
  v_obra_id uuid;
  v_obra_result jsonb;
  v_material_result jsonb:='{}'::jsonb;
  v_row jsonb;
  v_codigo_esq text;
  v_descricao text;
  v_localizacao text;
  v_rotulo text;
  v_qtd numeric;
  v_largura numeric;
  v_altura numeric;
  v_modulos integer;
  v_geradas integer:=0;
  v_esquadria_id uuid;
  v_esquadrias_ids jsonb:='[]'::jsonb;
  v_materials_selected boolean;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
  PERFORM public.ew_exigir_sessao_atual();
  IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
     NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
       WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
  THEN RAISE EXCEPTION 'Somente um ADM autenticado pode importar uma obra do CEM.'; END IF;
  IF length(v_codigo) NOT BETWEEN 1 AND 80 OR length(v_nome) NOT BETWEEN 3 AND 180 OR
     length(v_cliente)>250
  THEN RAISE EXCEPTION 'Confira código (1–80), nome (3–180) e cliente (até 250 caracteres) da obra.'; END IF;
  IF jsonb_typeof(p_esquadrias) IS DISTINCT FROM 'array' OR
     jsonb_array_length(p_esquadrias) NOT BETWEEN 1 AND 1500 OR
     jsonb_typeof(p_perfis) IS DISTINCT FROM 'array' OR
     jsonb_typeof(p_acessorios) IS DISTINCT FROM 'array' OR
     jsonb_typeof(p_decisoes) IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'Os dados de esquadrias e materiais são inválidos.'; END IF;
  IF jsonb_array_length(p_perfis)>800 OR jsonb_array_length(p_acessorios)>1200 OR
     jsonb_array_length(p_decisoes)>400 THEN
    RAISE EXCEPTION 'Arquivo CEM acima do limite de importação segura.'; END IF;
  v_materials_selected:=jsonb_array_length(p_perfis)+jsonb_array_length(p_acessorios)>0;
  IF NOT v_materials_selected AND jsonb_array_length(p_decisoes)>0
  THEN RAISE EXCEPTION 'Há conciliações sem materiais selecionados.'; END IF;
  -- Serializa tentativas simultâneas de importação do mesmo código/empresa.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_empresa_id::text||'|'||v_codigo,0));
  IF EXISTS (SELECT 1 FROM public.obras
     WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL
       AND upper(btrim(codigo))=v_codigo)
  THEN RAISE EXCEPTION 'Esta obra já está cadastrada no EWGEST (%). Nenhum item foi duplicado.',v_codigo;
  END IF;
  -- Reutiliza o cadastro protegido existente, que também configura o local de estoque.
  v_obra_result:=public.ew_criar_obra_estoque(p_empresa_id,v_nome,v_codigo);
  v_obra_id:=(v_obra_result->>'id')::uuid;
  IF v_obra_id IS NULL THEN RAISE EXCEPTION 'Não foi possível confirmar o cadastro da obra.';END IF;
  UPDATE public.obras SET cliente=nullif(v_cliente,'') WHERE id=v_obra_id AND empresa_id=p_empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Não foi possível atualizar o cliente da obra.'; END IF;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_esquadrias) LOOP
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR
       jsonb_typeof(v_row->'quantidade') IS DISTINCT FROM 'number' OR
       jsonb_typeof(v_row->'largura_mm') IS DISTINCT FROM 'number' OR
       jsonb_typeof(v_row->'altura_mm') IS DISTINCT FROM 'number'
    THEN RAISE EXCEPTION 'Esquadria incompleta no ZIP.'; END IF;
    v_codigo_esq:=btrim(coalesce(v_row->>'codigo',''));
    v_descricao:=btrim(coalesce(v_row->>'descricao',''));
    v_localizacao:=btrim(coalesce(v_row->>'localizacao',''));
    v_rotulo:=btrim(coalesce(v_row->>'referencia_tipologia',''));
    v_qtd:=(v_row->>'quantidade')::numeric;
    v_largura:=(v_row->>'largura_mm')::numeric;
    v_altura:=(v_row->>'altura_mm')::numeric;
    IF length(v_codigo_esq) NOT BETWEEN 1 AND 100 OR length(v_descricao)>1000 OR
       length(v_localizacao)>500 OR length(v_rotulo)>150 OR
       v_qtd<>trunc(v_qtd) OR v_qtd NOT BETWEEN 1 AND 100000 OR
       v_largura<=0 OR v_largura>100000 OR v_altura<=0 OR v_altura>100000
    THEN RAISE EXCEPTION 'Dados inválidos da esquadria %: confira medidas e quantidade.',v_codigo_esq; END IF;
    v_modulos:=NULL;
    IF jsonb_typeof(v_row->'quantidade_modulos')='number' AND
       (v_row->>'quantidade_modulos')::numeric BETWEEN 1 AND 100 AND
       (v_row->>'quantidade_modulos')::numeric=trunc((v_row->>'quantidade_modulos')::numeric)
    THEN v_modulos:=(v_row->>'quantidade_modulos')::integer;END IF;
    INSERT INTO public.esquadrias(
      empresa_id,obra_id,codigo,descricao,localizacao,largura_mm,altura_mm,quantidade,
      qtd_liberada,qtd_fabricada,rotulo_tipologia_relatorio,quantidade_modulos)
    VALUES(p_empresa_id,v_obra_id,v_codigo_esq,nullif(v_descricao,''),nullif(v_localizacao,''),
      v_largura,v_altura,v_qtd::integer,0,0,
      nullif(v_rotulo,''),v_modulos) RETURNING id INTO v_esquadria_id;
    v_esquadrias_ids:=v_esquadrias_ids||jsonb_build_array(v_esquadria_id);
    v_geradas:=v_geradas+1;
  END LOOP;
  IF v_materials_selected THEN
    -- Chamada transacional: erro em qualquer material desfaz TUDO, inclusive obra e esquadrias.
    v_material_result:=public.ew_importar_cem_conciliado(
      p_empresa_id,v_codigo,p_perfis,p_acessorios,p_operacao_id,p_decisoes);
    IF (v_material_result->>'esquadrias_alteradas')::integer<>0 OR
       (v_material_result->>'estoque_fisico_alterado')::boolean IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'A importação de materiais não garantiu a preservação do estoque.';END IF;
  END IF;
  RETURN jsonb_build_object(
    'obra_criada',true,'obra_id',v_obra_id,'codigo_obra',v_codigo,
    'nome_obra',v_nome,'cliente',nullif(v_cliente,''),
    'esquadrias_novas',v_geradas,'esquadrias_ids',v_esquadrias_ids,
    'perfis_novos',coalesce((v_material_result->>'perfis_novos')::integer,0),
    'perfis_existentes',coalesce((v_material_result->>'perfis_existentes')::integer,0),
    'acessorios_novos',coalesce((v_material_result->>'acessorios_novos')::integer,0),
    'acessorios_existentes',coalesce((v_material_result->>'acessorios_existentes')::integer,0),
    'variacoes_novas',coalesce((v_material_result->>'variacoes_novas')::integer,0),
    'vinculos_por_obra',coalesce((v_material_result->>'vinculos_por_obra')::integer,0),
    'estoque_fisico_alterado',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_financeiro(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb, p_orcamento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_result jsonb;
 v_valor numeric(14,2);
 v_aluminio numeric(14,2):=0;
 v_acessorios numeric(14,2):=0;
 v_vidros numeric(14,2):=0;
 v_outros numeric(14,2):=0;
 v_fabricacao numeric(14,2):=0;
 v_instalacao numeric(14,2):=0;
 v_soma numeric(14,2):=0;
 v_work_id uuid;
 v_nome text;
 v_linha jsonb;
 v_nivel text;
 v_empresa_faturamento text;
 v_base text;
 v_valor_linha numeric(14,2);
 v_faturar boolean;
 v_nivel_id uuid;
 v_faturadora_id uuid;
 v_existente_base text;
 v_indice integer:=0;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR p_empresa_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=auth.uid() AND ue.empresa_id=p_empresa_id
    AND ue.perfil='administrador'
 ) THEN RAISE EXCEPTION 'Somente ADM pode importar obra com orçamento.'; END IF;
 IF jsonb_typeof(p_orcamento) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'Informe o orçamento antes de importar.'; END IF;
 IF jsonb_typeof(p_orcamento->'valor_total') IS DISTINCT FROM 'number' OR
   (p_orcamento->>'valor_total')::numeric<=0 OR
   (p_orcamento->>'valor_total')::numeric>999999999999.99 OR
   (p_orcamento->>'valor_total')::numeric<>round((p_orcamento->>'valor_total')::numeric,2)
 THEN RAISE EXCEPTION 'Valor total do orçamento inválido.'; END IF;
 v_valor:=(p_orcamento->>'valor_total')::numeric;

 IF jsonb_typeof(p_orcamento->'niveis')='array' THEN
  IF jsonb_array_length(p_orcamento->'niveis') NOT BETWEEN 1 AND 100 THEN
   RAISE EXCEPTION 'Cadastre de 1 a 100 níveis para a obra.'; END IF;
  FOR v_linha IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
   v_indice:=v_indice+1;
   v_nivel:=upper(btrim(coalesce(v_linha->>'nivel','')));
   v_empresa_faturamento:=upper(btrim(coalesce(v_linha->>'empresa_faturamento','')));
   v_base:=v_linha->>'categoria_base';
   IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
      char_length(v_nivel) NOT BETWEEN 2 AND 120 OR
      char_length(v_empresa_faturamento) NOT BETWEEN 2 AND 120 OR
      v_base IS NULL OR v_base NOT IN ('aluminio','acessorios','vidros','outros','fabricacao','instalacao') OR
      jsonb_typeof(v_linha->'valor') IS DISTINCT FROM 'number' OR
      jsonb_typeof(v_linha->'faturar') IS DISTINCT FROM 'boolean'
   THEN RAISE EXCEPTION 'Nível ou empresa inválidos na linha %.',v_indice; END IF;
   v_valor_linha:=(v_linha->>'valor')::numeric;
   IF v_valor_linha<0 OR v_valor_linha>999999999999.99 OR
      v_valor_linha<>round(v_valor_linha,2)
   THEN RAISE EXCEPTION 'Valor inválido na linha %.',v_indice; END IF;
   v_faturar:=(v_linha->>'faturar')::boolean;
   v_soma:=v_soma+v_valor_linha;
   CASE v_base
    WHEN 'aluminio' THEN v_aluminio:=v_aluminio+v_valor_linha;
    WHEN 'acessorios' THEN v_acessorios:=v_acessorios+v_valor_linha;
    WHEN 'vidros' THEN v_vidros:=v_vidros+v_valor_linha;
    WHEN 'outros' THEN v_outros:=v_outros+v_valor_linha;
    WHEN 'fabricacao' THEN v_fabricacao:=v_fabricacao+v_valor_linha;
    WHEN 'instalacao' THEN v_instalacao:=v_instalacao+v_valor_linha;
   END CASE;
  END LOOP;
  IF v_soma<>v_valor THEN
   RAISE EXCEPTION 'A soma dos níveis (%) deve corresponder ao valor total da obra.',v_soma;
  END IF;
 ELSE
  -- Compatibilidade com versões anteriores da interface.
  FOREACH v_nome IN ARRAY ARRAY['aluminio','acessorios','vidros','outros','fabricacao','instalacao'] LOOP
   IF jsonb_typeof(p_orcamento->v_nome) IS DISTINCT FROM 'number' OR
      (p_orcamento->>v_nome)::numeric<0 OR
      (p_orcamento->>v_nome)::numeric>999999999999.99 OR
      (p_orcamento->>v_nome)::numeric<>round((p_orcamento->>v_nome)::numeric,2)
   THEN RAISE EXCEPTION 'Orçamento inválido: %.',v_nome; END IF;
  END LOOP;
  v_aluminio:=(p_orcamento->>'aluminio')::numeric;
  v_acessorios:=(p_orcamento->>'acessorios')::numeric;
  v_vidros:=(p_orcamento->>'vidros')::numeric;
  v_outros:=(p_orcamento->>'outros')::numeric;
  v_fabricacao:=(p_orcamento->>'fabricacao')::numeric;
  v_instalacao:=(p_orcamento->>'instalacao')::numeric;
  IF v_valor<>v_aluminio+v_acessorios+v_vidros+v_outros+v_fabricacao+v_instalacao THEN
   RAISE EXCEPTION 'Soma das categorias inválida.'; END IF;
 END IF;

 v_result:=public.ew_importar_obra_cem(
   p_empresa_id,p_codigo_obra,p_nome_obra,p_cliente,p_esquadrias,
   p_perfis,p_acessorios,p_operacao_id,p_decisoes);
 v_work_id:=(v_result->>'obra_id')::uuid;
 IF v_work_id IS NULL OR v_result->>'obra_criada'<>'true' THEN
  RAISE EXCEPTION 'A importação não confirmou obra nova.'; END IF;

 INSERT INTO public.ew_obra_orcamento(
   empresa_id,obra_id,valor_total,aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por)
 VALUES (p_empresa_id,v_work_id,v_valor,v_aluminio,v_acessorios,v_vidros,
   v_outros,v_fabricacao,v_instalacao,auth.uid());

 IF jsonb_typeof(p_orcamento->'niveis')='array' THEN
  v_indice:=0;
  FOR v_linha IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
   v_indice:=v_indice+1;
   v_nivel:=upper(btrim(v_linha->>'nivel'));
   v_empresa_faturamento:=upper(btrim(v_linha->>'empresa_faturamento'));
   v_base:=v_linha->>'categoria_base';
   v_valor_linha:=(v_linha->>'valor')::numeric;
   v_faturar:=(v_linha->>'faturar')::boolean;
   INSERT INTO public.ew_niveis_orcamento_catalogo(empresa_id,nome,categoria_base)
    VALUES(p_empresa_id,v_nivel,v_base)
    ON CONFLICT (empresa_id,nome) DO NOTHING;
   SELECT id,categoria_base INTO v_nivel_id,v_existente_base
    FROM public.ew_niveis_orcamento_catalogo
    WHERE empresa_id=p_empresa_id AND nome=v_nivel;
   IF v_nivel_id IS NULL OR v_existente_base IS DISTINCT FROM v_base THEN
    RAISE EXCEPTION 'O nível % já existe com outro grupo financeiro.',v_nivel;
   END IF;
   INSERT INTO public.ew_empresas_faturamento_catalogo(empresa_id,nome)
    VALUES(p_empresa_id,v_empresa_faturamento)
    ON CONFLICT (empresa_id,nome) DO NOTHING;
   SELECT id INTO v_faturadora_id
    FROM public.ew_empresas_faturamento_catalogo
    WHERE empresa_id=p_empresa_id AND nome=v_empresa_faturamento;
   IF v_faturadora_id IS NULL THEN
    RAISE EXCEPTION 'Empresa de faturamento não encontrada: %.',v_empresa_faturamento;
   END IF;
   INSERT INTO public.ew_obra_orcamento_niveis(
     empresa_id,obra_id,linha,nivel_id,empresa_faturamento_id,
     nivel_nome,empresa_faturamento_nome,categoria_base,valor,percentual,faturar)
    VALUES(p_empresa_id,v_work_id,v_indice,v_nivel_id,v_faturadora_id,
      v_nivel,v_empresa_faturamento,v_base,v_valor_linha,
      round(v_valor_linha/v_valor*100,5),v_faturar);
  END LOOP;
 END IF;
 RETURN v_result||jsonb_build_object(
    'orcamento_gravado',true,'valor_total',v_valor,'niveis_gravados',v_indice);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_importar_obra_cem_precificacao(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb, p_orcamento jsonb, p_precificacao jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_fab_origem bigint:=0;
 v_inst_origem bigint:=0;
 v_fab_atual bigint;
 v_inst_atual bigint;
 v_comb bigint;
 v_pcent integer;
 v_exp_fab bigint;
 v_exp_inst bigint;
 v_calc_fab bigint;
 v_calc_inst bigint;
 v_count integer;
 v_idx integer;
 v_soma_pesos numeric;
 v_sum_fab bigint;
 v_sum_inst bigint;
 v_total_area numeric;
 v_cat jsonb;
 v_item jsonb;
 v_origem jsonb;
 v_nome text;
 v_local text;
 v_categoria_uuid uuid;
 v_cat_map jsonb:='{}'::jsonb;
 v_result jsonb;
 v_obra_id uuid;
 v_revisao_id uuid;
 v_codigo_existente text;
 v_valor_orcado numeric;
 v_hash_existente text;
 v_request_hash text;
 v_ids jsonb;
 v_esquadria_id uuid;
 v_tipo_id uuid;
 v_categoria_nome text;
 v_categoria_base int;
 v_categoria_fab bigint;
 v_categoria_inst bigint;
 v_categoria_area numeric;
 v_valor_linha numeric;
 v_peso numeric;
 v_expected_errs integer;
 v_linha_categoria jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
    AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador'
 ) THEN RAISE EXCEPTION 'Somente ADM autenticado pode aprovar importação e precificação.'; END IF;
 v_request_hash:=md5(jsonb_build_object(
  'empresa_id',p_empresa_id,'codigo_obra',upper(btrim(coalesce(p_codigo_obra,''))),
  'nome_obra',btrim(coalesce(p_nome_obra,'')),'cliente',btrim(coalesce(p_cliente,'')),
  'esquadrias',p_esquadrias,'perfis',p_perfis,'acessorios',p_acessorios,
  'decisoes',p_decisoes,'orcamento',p_orcamento,'precificacao',p_precificacao
 )::text);
 -- A chave de operação é permanente na revisão aprovada; o retry devolve
 -- a mesma obra e a mesma revisão, sem inserir mais nenhuma linha.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|preco-cem|'||p_operacao_id::text,0));
 SELECT r.obra_id,r.id,o.codigo,orc.valor_total,r.operacao_hash
  INTO v_obra_id,v_revisao_id,v_codigo_existente,v_valor_orcado,v_hash_existente
  FROM public.ew_precificacao_revisoes r
  JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=r.empresa_id
  JOIN public.ew_obra_orcamento orc ON orc.obra_id=r.obra_id AND orc.empresa_id=r.empresa_id
 WHERE r.empresa_id=p_empresa_id AND r.operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v_hash_existente IS DISTINCT FROM v_request_hash THEN
   RAISE EXCEPTION 'O identificador da importação já foi usado com outros dados. Refaça a conferência sem reutilizar esta operação.'; END IF;
  IF upper(btrim(v_codigo_existente))<>upper(btrim(coalesce(p_codigo_obra,''))) THEN
   RAISE EXCEPTION 'Operação de importação já vinculada a outra obra.'; END IF;
  IF EXISTS(SELECT 1 FROM public.ew_precificacao_revisoes r
    WHERE r.id=v_revisao_id AND r.estado<>'aprovada')
  THEN RAISE EXCEPTION 'A operação existe com histórico ainda não aprovado.';END IF;
  RETURN jsonb_build_object('obra_criada',true,'obra_id',v_obra_id,
     'orcamento_gravado',true,'valor_total',v_valor_orcado,
     'estoque_fisico_alterado',false,'ja_importado',true,
     'esquadrias_novas',(SELECT count(*) FROM public.esquadrias e
       WHERE e.empresa_id=p_empresa_id AND e.obra_id=v_obra_id),
     'precificacao_gravada',true,'precificacao_revisao_id',v_revisao_id);
 END IF;
 IF jsonb_typeof(p_orcamento->'niveis') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_precificacao) IS DISTINCT FROM 'object' OR
    jsonb_typeof(p_precificacao->'categorias') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_precificacao->'itens') IS DISTINCT FROM 'array' OR
    jsonb_typeof(p_esquadrias) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Orçamento ou precificação incompletos.'; END IF;
 v_count:=jsonb_array_length(p_esquadrias);
 IF v_count NOT BETWEEN 1 AND 1500 OR
    jsonb_array_length(p_precificacao->'itens')<>v_count OR
    jsonb_array_length(p_precificacao->'categorias') NOT BETWEEN 1 AND 150
 THEN RAISE EXCEPTION 'Quantidade de itens/categorias não corresponde à obra.'; END IF;
 IF p_precificacao->>'versao' IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'Versão de precificação não reconhecida.'; END IF;

 -- Percentuais e totais originais são derivados do próprio orçamento, não do
 -- JSON de precificação. Valores inteiros enviados são centavos, nunca reais.
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_orcamento->'niveis') LOOP
  IF jsonb_typeof(v_item->'valor') IS DISTINCT FROM 'number' THEN
   RAISE EXCEPTION 'Nível sem valor monetário válido.'; END IF;
  v_valor_linha:=(v_item->>'valor')::numeric;
  IF v_valor_linha<0 OR v_valor_linha>999999999999.99 OR
     v_valor_linha<>round(v_valor_linha,2) THEN
   RAISE EXCEPTION 'Nível financeiro fora da precisão em reais.'; END IF;
  IF v_item->>'categoria_base' IN ('fabricacao','instalacao') AND v_valor_linha>0 AND
    (jsonb_typeof(v_item->'faturar') IS DISTINCT FROM 'boolean' OR
     (v_item->>'faturar')::boolean IS DISTINCT FROM true)
  THEN RAISE EXCEPTION 'Níveis de fabricação e instalação precisam ser faturáveis.'; END IF;
  IF v_item->>'categoria_base'='fabricacao' THEN
   v_fab_origem:=v_fab_origem+(v_valor_linha*100)::bigint;
  ELSIF v_item->>'categoria_base'='instalacao' THEN
   v_inst_origem:=v_inst_origem+(v_valor_linha*100)::bigint;
  END IF;
 END LOOP;
 v_comb:=v_fab_origem+v_inst_origem;
 IF v_comb<=0 OR v_comb>100000000000000 THEN
  RAISE EXCEPTION 'O orçamento não possui fabricação/instalação válidos.'; END IF;
 IF jsonb_typeof(p_precificacao->'fabricacao_original_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'instalacao_original_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'fabricacao_distribuida_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'instalacao_distribuida_centavos') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'percentual_fabricacao_bp') IS DISTINCT FROM 'number' OR
    jsonb_typeof(p_precificacao->'percentual_ajustado') IS DISTINCT FROM 'boolean'
 THEN RAISE EXCEPTION 'Distribuição sem os campos obrigatórios.'; END IF;
 IF (p_precificacao->>'fabricacao_original_centavos')::numeric<>v_fab_origem OR
    (p_precificacao->>'instalacao_original_centavos')::numeric<>v_inst_origem
 THEN RAISE EXCEPTION 'Valores originais divergentes do orçamento informado.'; END IF;
 v_pcent:=(p_precificacao->>'percentual_fabricacao_bp')::integer;
 IF v_pcent NOT BETWEEN 0 AND 10000 OR
    (p_precificacao->>'percentual_fabricacao_bp')::numeric<>v_pcent
 THEN RAISE EXCEPTION 'Percentual de fabricação inválido.'; END IF;
 v_fab_atual:=(p_precificacao->>'fabricacao_distribuida_centavos')::bigint;
 v_inst_atual:=(p_precificacao->>'instalacao_distribuida_centavos')::bigint;
 IF v_fab_atual<0 OR v_inst_atual<0 OR v_fab_atual+v_inst_atual<>v_comb OR
    (p_precificacao->>'fabricacao_distribuida_centavos')::numeric<>v_fab_atual OR
    (p_precificacao->>'instalacao_distribuida_centavos')::numeric<>v_inst_atual
 THEN RAISE EXCEPTION 'Distribuição não fecha o total contratado.'; END IF;
 IF (p_precificacao->>'percentual_ajustado')::boolean THEN
  IF v_fab_atual<>floor((v_comb::numeric*v_pcent+5000)/10000)::bigint THEN
   RAISE EXCEPTION 'Percentual alterado não corresponde à nova fabricação.'; END IF;
 ELSE
  IF v_fab_atual<>v_fab_origem OR v_inst_atual<>v_inst_origem OR
     v_pcent<>round(v_fab_origem::numeric/v_comb*10000)::integer
  THEN RAISE EXCEPTION 'Percentual sugerido difere do orçamento.'; END IF;
 END IF;

 -- Validar catálogo de categorias em memória, antes de criar a obra.
 IF EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') AS c
  WHERE jsonb_typeof(c) IS DISTINCT FROM 'object' OR
        jsonb_typeof(c->'preco_base_m2_centavos') IS DISTINCT FROM 'number' OR
        jsonb_typeof(c->'fabricacao_centavos') IS DISTINCT FROM 'number' OR
        jsonb_typeof(c->'instalacao_centavos') IS DISTINCT FROM 'number' OR
        char_length(btrim(c->>'nome')) NOT BETWEEN 2 AND 120 OR
        char_length(btrim(c->>'id_local')) NOT BETWEEN 1 AND 100
 ) THEN RAISE EXCEPTION 'Categoria sem nome ou valores válidos.'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p_precificacao->'categorias'))<>
    (SELECT count(DISTINCT lower(btrim(c->>'nome'))) FROM jsonb_array_elements(p_precificacao->'categorias') c) OR
    (SELECT count(*) FROM jsonb_array_elements(p_precificacao->'categorias'))<>
    (SELECT count(DISTINCT c->>'id_local') FROM jsonb_array_elements(p_precificacao->'categorias') c)
 THEN RAISE EXCEPTION 'Categorias repetidas.'; END IF;
 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  IF (v_cat->>'preco_base_m2_centavos')::numeric<>trunc((v_cat->>'preco_base_m2_centavos')::numeric) OR
     (v_cat->>'preco_base_m2_centavos')::numeric NOT BETWEEN 0 AND 100000000000 OR
     (v_cat->>'fabricacao_centavos')::numeric<>trunc((v_cat->>'fabricacao_centavos')::numeric) OR
     (v_cat->>'instalacao_centavos')::numeric<>trunc((v_cat->>'instalacao_centavos')::numeric) OR
     (v_cat->>'fabricacao_centavos')::numeric<0 OR
     (v_cat->>'instalacao_centavos')::numeric<0
  THEN RAISE EXCEPTION 'Preço/valor inválido na categoria %.',v_cat->>'nome'; END IF;
 END LOOP;

 -- Cada índice representa a posição do item no CEM, independentemente de
 -- códigos EA duplicados. Isso evita associação incorreta de preços futuros.
 v_idx:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_precificacao->'itens') LOOP
  v_origem:=p_esquadrias->v_idx;
  IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
     (v_item->>'indice_importacao')::integer IS DISTINCT FROM v_idx OR
     v_item->>'codigo' IS DISTINCT FROM v_origem->>'codigo' OR
     v_item->>'descricao' IS DISTINCT FROM v_origem->>'descricao' OR
     v_item->>'referencia_tipologia' IS DISTINCT FROM coalesce(v_origem->>'referencia_tipologia','') OR
     (v_item->>'largura_mm')::numeric<>(v_origem->>'largura_mm')::numeric OR
     (v_item->>'altura_mm')::numeric<>(v_origem->>'altura_mm')::numeric OR
     (v_item->>'quantidade')::integer<>(v_origem->>'quantidade')::integer OR
     NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') c
          WHERE c->>'id_local'=v_item->>'categoria_id_local')
  THEN RAISE EXCEPTION 'Item % diverge do CEM ou da categoria selecionada.',v_idx+1; END IF;
  IF jsonb_typeof(v_item->'definir_padrao_tipologia') IS DISTINCT FROM 'boolean'
  THEN RAISE EXCEPTION 'Definição de categoria padrão inválida no item %.',v_idx+1; END IF;
  IF jsonb_typeof(v_item->'fabricacao_centavos') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'instalacao_centavos') IS DISTINCT FROM 'number' OR
     (v_item->>'fabricacao_centavos')::numeric<0 OR
     (v_item->>'instalacao_centavos')::numeric<0 OR
     (v_item->>'fabricacao_centavos')::numeric<>trunc((v_item->>'fabricacao_centavos')::numeric) OR
     (v_item->>'instalacao_centavos')::numeric<>trunc((v_item->>'instalacao_centavos')::numeric)
  THEN RAISE EXCEPTION 'Valores fracionários ou negativos no item %.',v_idx+1; END IF;
  IF round((v_origem->>'largura_mm')::numeric*(v_origem->>'altura_mm')::numeric*
           (v_origem->>'quantidade')::numeric/1000000,6) <>
     round((v_item->>'area_m2')::numeric,6)
  THEN RAISE EXCEPTION 'Área do item % não confere com largura/altura/quantidade.',v_idx+1; END IF;
  v_idx:=v_idx+1;
 END LOOP;

 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_precificacao->'categorias') c
              WHERE (c->>'preco_base_m2_centavos')::numeric>0) OR
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_precificacao->'itens') p
      JOIN jsonb_array_elements(p_precificacao->'categorias') c
       ON c->>'id_local'=p->>'categoria_id_local'
      WHERE (c->>'preco_base_m2_centavos')::numeric<=0
    ) THEN RAISE EXCEPTION 'Todas as categorias em uso exigem preço-base positivo.'; END IF;

 -- O rateio é recalculado no servidor por maior resto e índice do CEM;
 -- não basta o cliente enviar somatórios aparentemente corretos.
 WITH entrada AS (
  SELECT p.ord::integer-1 idx,p.item,
   (o.item->>'largura_mm')::numeric*(o.item->>'altura_mm')::numeric*
   (o.item->>'quantidade')::numeric AS area,
   (c.item->>'preco_base_m2_centavos')::numeric AS preco
  FROM jsonb_array_elements(p_precificacao->'itens') WITH ORDINALITY p(item,ord)
  JOIN jsonb_array_elements(p_esquadrias) WITH ORDINALITY o(item,ord) USING(ord)
  JOIN jsonb_array_elements(p_precificacao->'categorias') c(item)
   ON c.item->>'id_local'=p.item->>'categoria_id_local'
 ), pesos AS (
  SELECT idx,item,area,area*preco AS peso FROM entrada
 ), total AS (
  SELECT sum(peso) AS todo FROM pesos
 ), primeira AS (
  SELECT p.*,
   floor(v_fab_atual::numeric*p.peso/t.todo)::bigint AS f0,
   mod(v_fab_atual::numeric*p.peso,t.todo) AS fr,
   floor(v_inst_atual::numeric*p.peso/t.todo)::bigint AS i0,
   mod(v_inst_atual::numeric*p.peso,t.todo) AS ir
  FROM pesos p CROSS JOIN total t
 ), ordenada AS (
  SELECT p.*,
   row_number() OVER(ORDER BY fr DESC,idx ASC) AS rank_f,
   row_number() OVER(ORDER BY ir DESC,idx ASC) AS rank_i,
   v_fab_atual-sum(f0) OVER() AS sob_f,
   v_inst_atual-sum(i0) OVER() AS sob_i
  FROM primeira p
 )
 SELECT count(*) FILTER(WHERE
  (item->>'fabricacao_centavos')::bigint<>(f0+CASE WHEN rank_f<=sob_f THEN 1 ELSE 0 END)
  OR (item->>'instalacao_centavos')::bigint<>(i0+CASE WHEN rank_i<=sob_i THEN 1 ELSE 0 END)
  ) INTO v_expected_errs FROM ordenada;
 IF v_expected_errs IS NULL OR v_expected_errs<>0 THEN
  RAISE EXCEPTION 'Valores dos itens não conferem com o rateio aprovado.'; END IF;


 -- Validar também os totais fornecidos por categoria.
 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  SELECT coalesce(sum((it->>'fabricacao_centavos')::bigint),0),
         coalesce(sum((it->>'instalacao_centavos')::bigint),0),
         coalesce(sum((it->>'area_m2')::numeric),0)
    INTO v_categoria_fab,v_categoria_inst,v_categoria_area
    FROM jsonb_array_elements(p_precificacao->'itens') it
    WHERE it->>'categoria_id_local'=v_cat->>'id_local';
  IF v_categoria_fab<>(v_cat->>'fabricacao_centavos')::bigint OR
     v_categoria_inst<>(v_cat->>'instalacao_centavos')::bigint OR
     round(v_categoria_area,6)<>round((v_cat->>'area_m2')::numeric,6)
  THEN RAISE EXCEPTION 'Total divergente da categoria %.',v_cat->>'nome'; END IF;
 END LOOP;

 -- Somente a partir daqui executar operações que criam obra/dados.
 -- A chamada continua na MESMA transação de PostgreSQL.
 v_result:=public.ew_importar_obra_cem_financeiro(
  p_empresa_id,p_codigo_obra,p_nome_obra,p_cliente,p_esquadrias,
  p_perfis,p_acessorios,p_operacao_id,p_decisoes,p_orcamento);
 v_obra_id:=(v_result->>'obra_id')::uuid;
 v_ids:=v_result->'esquadrias_ids';
 IF v_obra_id IS NULL OR v_result->>'obra_criada'<>'true' OR
    jsonb_typeof(v_ids) IS DISTINCT FROM 'array' OR
    jsonb_array_length(v_ids)<>v_count
 THEN RAISE EXCEPTION 'IDs das esquadrias não foram retornados pelo importador.'; END IF;

 INSERT INTO public.ew_precificacao_revisoes(
  empresa_id,obra_id,versao,operacao_id,operacao_hash,fabricacao_original_centavos,instalacao_original_centavos,
  fabricacao_distribuida_centavos,instalacao_distribuida_centavos,
  percentual_fabricacao_bp,area_total_m2,motivo,aprovado_por)
 VALUES(
  p_empresa_id,v_obra_id,1,p_operacao_id,v_request_hash,v_fab_origem,v_inst_origem,v_fab_atual,v_inst_atual,
  v_pcent,
  (SELECT round(sum((v_area.item->>'area_m2')::numeric),6)
   FROM jsonb_array_elements(p_precificacao->'itens') AS v_area(item)),
  'Precificação aprovada na importação do CEM',v_uid)
 RETURNING id INTO v_revisao_id;

 FOR v_cat IN SELECT value FROM jsonb_array_elements(p_precificacao->'categorias') LOOP
  v_nome:=upper(btrim(v_cat->>'nome'));
  INSERT INTO public.ew_precificacao_categorias(empresa_id,nome,criado_por)
   VALUES(p_empresa_id,v_nome,v_uid)
   ON CONFLICT DO NOTHING;
  SELECT id INTO v_categoria_uuid FROM public.ew_precificacao_categorias
   WHERE empresa_id=p_empresa_id AND lower(btrim(nome))=lower(v_nome);
  IF v_categoria_uuid IS NULL THEN
   RAISE EXCEPTION 'Categoria não encontrada após cadastro: %.',v_nome; END IF;
  v_cat_map:=v_cat_map||jsonb_build_object(v_cat->>'id_local',v_categoria_uuid);
  INSERT INTO public.ew_precificacao_revisoes_categorias(
   empresa_id,obra_id,revisao_id,categoria_id,categoria_nome_snapshot,
   preco_base_m2_centavos,area_m2,fabricacao_centavos,instalacao_centavos)
  VALUES(
   p_empresa_id,v_obra_id,v_revisao_id,v_categoria_uuid,v_nome,
   (v_cat->>'preco_base_m2_centavos')::bigint,
   round((v_cat->>'area_m2')::numeric,6),
   (v_cat->>'fabricacao_centavos')::bigint,(v_cat->>'instalacao_centavos')::bigint
  );
 END LOOP;

 v_idx:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_precificacao->'itens') LOOP
  v_origem:=p_esquadrias->v_idx;
  v_esquadria_id:=(v_ids->>v_idx)::uuid;
  v_categoria_uuid:=(v_cat_map->>(v_item->>'categoria_id_local'))::uuid;
  -- Vínculo por código técnico somente se houver exatamente uma tipologia
  -- correspondente da mesma empresa. Nunca escolher arbitrariamente.
  SELECT CASE WHEN count(*)=1 THEN (array_agg(t.id))[1] ELSE NULL END
   INTO v_tipo_id FROM public.tipologias t
   WHERE t.empresa_id=p_empresa_id AND
    upper(btrim(t.codigo))=upper(btrim(coalesce(v_origem->>'referencia_tipologia','')));
  SELECT c->>'nome' INTO v_categoria_nome FROM jsonb_array_elements(p_precificacao->'categorias') c
    WHERE c->>'id_local'=v_item->>'categoria_id_local';
  INSERT INTO public.ew_precificacao_revisoes_itens(
   empresa_id,obra_id,revisao_id,indice_importacao,
   esquadria_id,tipologia_id,categoria_id,categoria_nome_snapshot,
   codigo_snapshot,descricao_snapshot,referencia_tipologia_snapshot,linha_snapshot,
   largura_mm,altura_mm,quantidade,area_m2,
   fabricacao_centavos,instalacao_centavos)
  VALUES(
   p_empresa_id,v_obra_id,v_revisao_id,v_idx,
   v_esquadria_id,v_tipo_id,v_categoria_uuid,upper(btrim(v_categoria_nome)),
   v_item->>'codigo',coalesce(v_item->>'descricao',''),
   coalesce(v_item->>'referencia_tipologia',''),NULL,
   (v_item->>'largura_mm')::numeric,(v_item->>'altura_mm')::numeric,
   (v_item->>'quantidade')::integer,round((v_item->>'area_m2')::numeric,6),
   (v_item->>'fabricacao_centavos')::bigint,(v_item->>'instalacao_centavos')::bigint
  );
  IF (v_item->>'definir_padrao_tipologia')::boolean THEN
   IF v_tipo_id IS NULL THEN
    RAISE EXCEPTION 'Só é possível salvar categoria padrão para tipologia cadastrada e identificada sem ambiguidades (%).',v_item->>'referencia_tipologia';
   END IF;
   IF EXISTS(
    SELECT 1 FROM jsonb_array_elements(p_precificacao->'itens') outro
    WHERE upper(btrim(coalesce(outro->>'referencia_tipologia','')))=
          upper(btrim(coalesce(v_item->>'referencia_tipologia','')))
      AND outro->>'categoria_id_local' IS DISTINCT FROM v_item->>'categoria_id_local'
      AND (outro->>'definir_padrao_tipologia')::boolean IS TRUE
   ) THEN RAISE EXCEPTION 'A mesma tipologia não pode ter duas categorias padrão diferentes na importação.';END IF;
   INSERT INTO public.ew_precificacao_tipologias_padrao(
    empresa_id,tipologia_id,categoria_id,alterado_por)
   VALUES(p_empresa_id,v_tipo_id,v_categoria_uuid,v_uid)
   ON CONFLICT (empresa_id,tipologia_id) DO UPDATE
    SET categoria_id=EXCLUDED.categoria_id,
        alterado_por=EXCLUDED.alterado_por,
        atualizado_em=now();
  END IF;
  v_idx:=v_idx+1;
 END LOOP;

 -- Verificação final independente, travada ao concluir a transação.
 IF (SELECT coalesce(sum(fabricacao_centavos),0) FROM public.ew_precificacao_revisoes_itens
     WHERE revisao_id=v_revisao_id)<>v_fab_atual OR
    (SELECT coalesce(sum(instalacao_centavos),0) FROM public.ew_precificacao_revisoes_itens
     WHERE revisao_id=v_revisao_id)<>v_inst_atual
 THEN RAISE EXCEPTION 'A gravação do histórico não conciliou os valores.'; END IF;

 RETURN v_result||jsonb_build_object('precificacao_gravada',true,
  'precificacao_revisao_id',v_revisao_id,
  'precificacao_itens',v_count,
  'precificacao_categorias',jsonb_array_length(p_precificacao->'categorias'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_importar_saldo_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_nome_arquivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_usuario uuid:=auth.uid();v_obra_id uuid;v_obra_count integer;
 v_tipo text;v_row jsonb;v_codigo text;v_cor text;v_qtd numeric;v_comp integer;
 v_variacao uuid;v_matches uuid[];v_unidade text;v_existente integer;
 v_novos integer:=0;v_ja_existiam integer:=0;v_linhas integer:=0;
 v_barras numeric:=0;v_acessorios numeric:=0;
 v_pendencias jsonb:='[]'::jsonb;v_result jsonb;v_id uuid;
 v_chave text;v_vistas text[]:=ARRAY[]::text[];
BEGIN
 PERFORM public.ew_exigir_permissao('obras.importar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
     WHERE ue.usuario_id=v_usuario AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode importar o estoque calculado do CEM.';END IF;
 IF length(coalesce(p_nome_arquivo,''))>240 OR length(coalesce(p_codigo_obra,''))>100
 OR jsonb_typeof(p_perfis) IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_acessorios) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Arquivo ou dados de importação inválidos.';END IF;
 IF jsonb_array_length(p_perfis)>500 OR jsonb_array_length(p_acessorios)>1500 OR
  jsonb_array_length(p_perfis)+jsonb_array_length(p_acessorios)=0
 THEN RAISE EXCEPTION 'Quantidade de registros do CEM inválida.';END IF;
 SELECT count(*),(array_agg(id))[1] INTO v_obra_count,v_obra_id FROM public.obras
 WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND upper(btrim(codigo))=upper(btrim(p_codigo_obra));
 IF v_obra_count<>1 THEN
  RAISE EXCEPTION 'A obra do arquivo (%) não foi encontrada unicamente no EWGEST.',p_codigo_obra;
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|'||v_obra_id::text||'|CEM',74421));
 SELECT resumo INTO v_result FROM public.ew_estoque_importacoes_cem
 WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN RETURN v_result||jsonb_build_object('repetida',true);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais
  WHERE obra_id=v_obra_id AND empresa_id=p_empresa_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Este estoque não existe ou está arquivado. Restaure-o primeiro.';END IF;
 FOR v_tipo IN SELECT unnest(ARRAY['perfil','acessorio']) LOOP
  FOR v_row IN SELECT value FROM jsonb_array_elements(
    CASE WHEN v_tipo='perfil' THEN p_perfis ELSE p_acessorios END) LOOP
   IF jsonb_typeof(v_row)<>'object' THEN RAISE EXCEPTION 'Registro CEM inválido.';END IF;
   v_codigo:=upper(btrim(coalesce(v_row->>'codigo','')));
   v_cor:=upper(btrim(coalesce(v_row->>'cor','')));
   IF v_tipo='acessorio' AND v_cor IN ('','-') THEN v_cor:='NÃO INFORMADA';END IF;
   v_qtd:=(v_row->>'quantidade')::numeric;
   v_comp:=CASE WHEN v_tipo='perfil' THEN (v_row->>'comprimento_mm')::integer ELSE NULL END;
   IF length(v_codigo) NOT BETWEEN 1 AND 90 OR
    length(v_cor) NOT BETWEEN 1 AND 150 OR
    v_qtd IS NULL OR v_qtd<=0 OR v_qtd>10000000 OR v_qtd<>trunc(v_qtd,3) OR
    (v_tipo='perfil' AND (v_comp NOT BETWEEN 100 AND 20000 OR v_qtd<>trunc(v_qtd)))
   THEN RAISE EXCEPTION 'Código, comprimento ou quantidade incorretos: %.',v_codigo;END IF;
   v_chave:=v_tipo||'|'||v_codigo||'|'||v_cor||'|'||coalesce(v_comp::text,'-');
   IF v_chave=ANY(v_vistas) THEN
    RAISE EXCEPTION 'Registro do CEM repetido para %; agrupe as quantidades.',v_codigo;END IF;
   v_vistas:=array_append(v_vistas,v_chave);
   v_linhas:=v_linhas+1;
   v_variacao:=NULL;v_unidade:='';
   IF v_tipo='perfil' THEN
    SELECT array_agg(v.id) INTO v_matches FROM public.ew_perfis m
     JOIN public.ew_materiais_variacoes v ON v.perfil_id=m.id
     WHERE m.empresa_id=p_empresa_id AND v.empresa_id=p_empresa_id
      AND upper(btrim(m.codigo))=v_codigo AND
         (upper(btrim(v.cor))=v_cor OR upper(btrim(v.codigo_cor))=v_cor);
    v_unidade:='BARRA';
   ELSE
    SELECT array_agg(v.id) INTO v_matches FROM public.ew_acessorios m
     JOIN public.ew_materiais_variacoes v ON v.acessorio_id=m.id
     WHERE m.empresa_id=p_empresa_id AND v.empresa_id=p_empresa_id
      AND upper(btrim(m.codigo))=v_codigo AND upper(btrim(v.cor))=v_cor;
    SELECT upper(btrim(m.unidade_item)) INTO v_unidade FROM public.ew_acessorios m
     WHERE m.empresa_id=p_empresa_id AND upper(btrim(m.codigo))=v_codigo;
    v_unidade:=CASE v_unidade WHEN 'M' THEN 'MT' WHEN 'PÇ' THEN 'PC'
      WHEN 'PEÇA' THEN 'PC' WHEN 'PAR' THEN 'PR' WHEN 'CONJUNTO' THEN 'CJ'
      ELSE v_unidade END;
   END IF;
   IF coalesce(array_length(v_matches,1),0)=0 THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Sem cadastro correspondente'));
     CONTINUE;
   END IF;
   IF array_length(v_matches,1)>1 THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Mais de uma variação correspondente'));
     CONTINUE;
   END IF;
   IF v_tipo='acessorio' AND v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') THEN
     v_pendencias:=v_pendencias||jsonb_build_array(jsonb_build_object(
      'tipo',v_tipo,'codigo',v_codigo,'cor',v_cor,'motivo','Unidade de acessório precisa de revisão'));
     CONTINUE;
   END IF;
   v_variacao:=v_matches[1];
   SELECT count(*) INTO v_existente FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND obra_id=v_obra_id AND variacao_id=v_variacao
      AND comprimento_mm IS NOT DISTINCT FROM v_comp AND unidade=v_unidade;
   IF v_existente>0 THEN v_ja_existiam:=v_ja_existiam+1;CONTINUE;END IF;
   INSERT INTO public.ew_estoque_obras_movimentos
     (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
      origem,operacao_id,observacao,usuario_id)
   VALUES(p_empresa_id,v_obra_id,v_variacao,v_comp,v_unidade,v_qtd,
     'IMPORTACAO_CEM',pg_catalog.gen_random_uuid(),
     'Saldo inicial calculado pelo CEM · '||left(coalesce(p_nome_arquivo,'arquivo'),240),v_usuario);
   v_novos:=v_novos+1;
   IF v_tipo='perfil' THEN v_barras:=v_barras+v_qtd; ELSE v_acessorios:=v_acessorios+v_qtd;END IF;
  END LOOP;
 END LOOP;
 v_result:=jsonb_build_object('obra_id',v_obra_id,'codigo_obra',p_codigo_obra,
  'linhas_lidas',v_linhas,'linhas_importadas',v_novos,'linhas_preservadas',v_ja_existiam,
  'barras_importadas',v_barras,'quantidade_acessorios_importada',v_acessorios,
  'pendencias',v_pendencias,'repetida',false);
 INSERT INTO public.ew_estoque_importacoes_cem
   (empresa_id,obra_id,operacao_id,nome_arquivo,resumo,usuario_id)
 VALUES(p_empresa_id,v_obra_id,p_operacao_id,p_nome_arquivo,v_result,v_usuario);
 RETURN v_result;
END;$function$;

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

CREATE OR REPLACE FUNCTION public.ew_liberar_lote_cem(p_obra_id uuid, p_data_liberacao date, p_fabrica text, p_itens jsonb, p_materiais jsonb, p_arquivo_nome text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_empresa uuid;v_lote uuid;v_item jsonb;v_esq public.esquadrias%rowtype;
 v_variacao uuid;v_tipo text;v_length integer;v_unit text;v_qty numeric;v_local text;
 v_key text;v_keys text[]:=array[]::text[];v_seen uuid[]:=array[]::uuid[];v_saldo numeric;
 v_reply jsonb;v_release_id uuid;v_items int:=0;v_total int:=0;v_mat_count int;
BEGIN
 PERFORM public.ew_exigir_permissao('liberacoes.criar');
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null or p_operacao_id is null then raise exception 'Sessão ou operação inválida.';end if;
 select id into v_lote from public.ew_liberacoes_lotes where operacao_id=p_operacao_id;
 if found then return jsonb_build_object('repetida',true,'lote_id',v_lote);end if;
 select empresa_id into v_empresa from public.obras where id=p_obra_id;
 if v_empresa is null then raise exception 'Obra não encontrada.';end if;
 if not exists(select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
  and u.empresa_id=v_empresa and u.perfil in ('administrador','gerenciador','supervisor'))
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
 -- Materiais ficam pendentes para entrega física, sem debitar estoque na liberação.
 return jsonb_build_object('repetida',false,'lote_id',v_lote,'itens_liberados',v_items,
   'unidades_liberadas',v_total,'linhas_baixadas',0,'linhas_pendentes_entrega',v_mat_count);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_liberar_plano_corte_componente(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_materiais jsonb, p_fonte text, p_arquivo_nome text, p_operacao_id uuid, p_componente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_usuario uuid:=auth.uid();v_item public.esquadrias%ROWTYPE;v_op uuid;
 v_result jsonb;v_liberacao uuid;v_entrada jsonb;v_variacao uuid;v_tipo text;
 v_length integer;v_unidade text;v_quantidade numeric;v_saldo numeric;v_local text;
 v_materiais_count integer;v_seen text[]:=ARRAY[]::text[];v_key text;
BEGIN
 PERFORM public.ew_exigir_permissao('liberacoes.criar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_operacao_id IS NULL THEN RAISE EXCEPTION 'Sessão ou operação inválida.';END IF;
 SELECT id INTO v_op FROM public.ew_planos_liberados WHERE operacao_id=p_operacao_id;
 IF FOUND THEN RETURN jsonb_build_object('plano_id',v_op,'repetida',true);END IF;
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria não encontrada.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_usuario
     AND ue.empresa_id=v_item.empresa_id AND ue.perfil IN ('administrador','gerenciador','supervisor'))
 THEN RAISE EXCEPTION 'Usuário não autorizado para esta liberação.';END IF;
 IF jsonb_typeof(p_materiais) IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'Lista de materiais inválida.';END IF;
 v_materiais_count:=jsonb_array_length(p_materiais);
 IF v_materiais_count>150 THEN RAISE EXCEPTION 'Limite de 150 linhas de materiais por liberação.'; END IF;
 IF p_fonte NOT IN ('MANUAL','CEM_CONFERIDO','SEM_BAIXA') THEN RAISE EXCEPTION 'Origem inválida.';END IF;
 IF v_materiais_count=0 AND p_fonte<>'SEM_BAIXA' THEN RAISE EXCEPTION 'Confirme sem baixa ou informe os materiais.';END IF;
 IF v_materiais_count>0 AND p_fonte='SEM_BAIXA' THEN RAISE EXCEPTION 'Informe a origem dos materiais.';END IF;
 IF v_materiais_count>0 AND NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais l
   WHERE l.empresa_id=v_item.empresa_id AND l.obra_id=v_item.obra_id AND l.excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque da obra não existe ou está arquivado. Nenhuma baixa foi feita.'; END IF;
 IF length(coalesce(p_arquivo_nome,''))>240 THEN RAISE EXCEPTION 'Nome de arquivo inválido.';END IF;
 -- Valida todos os materiais antes de criar a liberação.
 FOR v_entrada IN SELECT value FROM jsonb_array_elements(p_materiais) LOOP
   IF jsonb_typeof(v_entrada)<>'object' THEN RAISE EXCEPTION 'Linha de material inválida.';END IF;
   v_variacao:=(v_entrada->>'variacao_id')::uuid;
   v_length:=nullif(v_entrada->>'comprimento_mm','')::integer;
   v_unidade:=v_entrada->>'unidade';
   v_local:=upper(btrim(coalesce(nullif(v_entrada->>'local_estoque',''),'IMBIRIBEIRA')));
   if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=v_item.empresa_id and l.nome=v_local and l.ativo) then raise exception 'Local físico inválido para material.';end if;
   v_quantidade:=(v_entrada->>'quantidade')::numeric;
   SELECT tipo INTO v_tipo FROM public.ew_materiais_variacoes
     WHERE id=v_variacao AND empresa_id=v_item.empresa_id AND ativo=true;
   IF v_tipo IS NULL THEN RAISE EXCEPTION 'Material não encontrado nesta empresa.';END IF;
   IF v_quantidade IS NULL OR v_quantidade<=0 OR v_quantidade>1000000
     OR (v_tipo='perfil' AND (v_unidade<>'BARRA' OR v_length NOT BETWEEN 100 AND 20000
         OR v_quantidade<>trunc(v_quantidade)))
     OR (v_tipo='acessorio' AND (v_length IS NOT NULL OR v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN')))
   THEN RAISE EXCEPTION 'Quantidade, unidade ou comprimento de material inválido.';END IF;
   v_key:=v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unidade||'|'||v_local;
   IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'O mesmo material/comprimento foi repetido no espelho.';END IF;
   v_seen:=array_append(v_seen,v_key);
 END LOOP;
 -- O próprio registro original respeita saldo pendente e fábrica.
 v_result:=public.ew_registrar_liberacao_componente(p_esquadria_id,p_quantidade,p_data_liberacao,p_fabrica,p_componente);
 v_liberacao:=(v_result->>'registro_id')::uuid;
 INSERT INTO public.ew_planos_liberados
 (operacao_id,empresa_id,obra_id,esquadria_id,liberacao_id,fonte,arquivo_nome,
  materiais_confirmados,data_liberacao,usuario_id)
 VALUES(p_operacao_id,v_item.empresa_id,v_item.obra_id,v_item.id,v_liberacao,p_fonte,
  nullif(btrim(coalesce(p_arquivo_nome,'')),''),p_materiais,p_data_liberacao,v_usuario)
 RETURNING id INTO v_op;
 -- A liberação registra o plano impresso. Só o almoxarife entrega/baixa depois.
 RETURN v_result||jsonb_build_object('plano_id',v_op,'tipo_componente',p_componente,'linhas_baixadas',0,'linhas_pendentes_entrega',v_materiais_count,'repetida',false);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_liberar_plano_corte_revisado(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_materiais jsonb, p_fonte text, p_arquivo_nome text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_usuario uuid:=auth.uid();v_item public.esquadrias%ROWTYPE;v_op uuid;
 v_result jsonb;v_liberacao uuid;v_entrada jsonb;v_variacao uuid;v_tipo text;
 v_length integer;v_unidade text;v_quantidade numeric;v_saldo numeric;v_local text;
 v_materiais_count integer;v_seen text[]:=ARRAY[]::text[];v_key text;
BEGIN
 PERFORM public.ew_exigir_permissao('liberacoes.criar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_operacao_id IS NULL THEN RAISE EXCEPTION 'Sessão ou operação inválida.';END IF;
 SELECT id INTO v_op FROM public.ew_planos_liberados WHERE operacao_id=p_operacao_id;
 IF FOUND THEN RETURN jsonb_build_object('plano_id',v_op,'repetida',true);END IF;
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria não encontrada.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_usuario
     AND ue.empresa_id=v_item.empresa_id AND ue.perfil IN ('administrador','gerenciador','supervisor'))
 THEN RAISE EXCEPTION 'Usuário não autorizado para esta liberação.';END IF;
 IF jsonb_typeof(p_materiais) IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'Lista de materiais inválida.';END IF;
 v_materiais_count:=jsonb_array_length(p_materiais);
 IF v_materiais_count>150 THEN RAISE EXCEPTION 'Limite de 150 linhas de materiais por liberação.'; END IF;
 IF p_fonte NOT IN ('MANUAL','CEM_CONFERIDO','SEM_BAIXA') THEN RAISE EXCEPTION 'Origem inválida.';END IF;
 IF v_materiais_count=0 AND p_fonte<>'SEM_BAIXA' THEN RAISE EXCEPTION 'Confirme sem baixa ou informe os materiais.';END IF;
 IF v_materiais_count>0 AND p_fonte='SEM_BAIXA' THEN RAISE EXCEPTION 'Informe a origem dos materiais.';END IF;
 IF v_materiais_count>0 AND NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais l
   WHERE l.empresa_id=v_item.empresa_id AND l.obra_id=v_item.obra_id AND l.excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque da obra não existe ou está arquivado. Nenhuma baixa foi feita.'; END IF;
 IF length(coalesce(p_arquivo_nome,''))>240 THEN RAISE EXCEPTION 'Nome de arquivo inválido.';END IF;
 -- Valida todos os materiais antes de criar a liberação.
 FOR v_entrada IN SELECT value FROM jsonb_array_elements(p_materiais) LOOP
   IF jsonb_typeof(v_entrada)<>'object' THEN RAISE EXCEPTION 'Linha de material inválida.';END IF;
   v_variacao:=(v_entrada->>'variacao_id')::uuid;
   v_length:=nullif(v_entrada->>'comprimento_mm','')::integer;
   v_unidade:=v_entrada->>'unidade';
   v_local:=upper(btrim(coalesce(nullif(v_entrada->>'local_estoque',''),'IMBIRIBEIRA')));
   if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=v_item.empresa_id and l.nome=v_local and l.ativo) then raise exception 'Local físico inválido para material.';end if;
   v_quantidade:=(v_entrada->>'quantidade')::numeric;
   SELECT tipo INTO v_tipo FROM public.ew_materiais_variacoes
     WHERE id=v_variacao AND empresa_id=v_item.empresa_id AND ativo=true;
   IF v_tipo IS NULL THEN RAISE EXCEPTION 'Material não encontrado nesta empresa.';END IF;
   IF v_quantidade IS NULL OR v_quantidade<=0 OR v_quantidade>1000000
     OR (v_tipo='perfil' AND (v_unidade<>'BARRA' OR v_length NOT BETWEEN 100 AND 20000
         OR v_quantidade<>trunc(v_quantidade)))
     OR (v_tipo='acessorio' AND (v_length IS NOT NULL OR v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN')))
   THEN RAISE EXCEPTION 'Quantidade, unidade ou comprimento de material inválido.';END IF;
   v_key:=v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unidade||'|'||v_local;
   IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'O mesmo material/comprimento foi repetido no espelho.';END IF;
   v_seen:=array_append(v_seen,v_key);
 END LOOP;
 -- O próprio registro original respeita saldo pendente e fábrica.
 v_result:=public.registrar_liberacao_corte_fabrica(p_esquadria_id,p_quantidade,p_data_liberacao,p_fabrica);
 v_liberacao:=(v_result->>'registro_id')::uuid;
 INSERT INTO public.ew_planos_liberados
 (operacao_id,empresa_id,obra_id,esquadria_id,liberacao_id,fonte,arquivo_nome,
  materiais_confirmados,data_liberacao,usuario_id)
 VALUES(p_operacao_id,v_item.empresa_id,v_item.obra_id,v_item.id,v_liberacao,p_fonte,
  nullif(btrim(coalesce(p_arquivo_nome,'')),''),p_materiais,p_data_liberacao,v_usuario)
 RETURNING id INTO v_op;
 -- A liberação registra o plano impresso. Só o almoxarife entrega/baixa depois.
 RETURN v_result||jsonb_build_object('plano_id',v_op,'linhas_baixadas',0,'linhas_pendentes_entrega',v_materiais_count,'repetida',false);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_movimentar_estoque_obra(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_usuario uuid:=auth.uid();v_tipo text;v_unidade_item text;v_saldo numeric;v_total numeric;v_id uuid;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.baixar');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL
  OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_usuario
     AND ue.empresa_id=p_empresa_id AND ue.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode movimentar o estoque da obra.'; END IF;
 SELECT id INTO v_id FROM public.ew_estoque_obras_movimentos
  WHERE operacao_id=p_operacao_id AND empresa_id=p_empresa_id AND usuario_id=v_usuario;
 IF FOUND THEN RETURN jsonb_build_object('id',v_id,'repetida',true); END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE obra_id=p_obra_id AND empresa_id=p_empresa_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque desta obra não existe ou está arquivado.';END IF;
 SELECT tipo INTO v_tipo FROM public.ew_materiais_variacoes
   WHERE id=p_variacao_id AND empresa_id=p_empresa_id AND ativo=true;
 IF v_tipo IS NULL THEN RAISE EXCEPTION 'Material ou cor não encontrado.';END IF;
 IF v_tipo='acessorio' THEN
  SELECT upper(btrim(a.unidade_item)) INTO v_unidade_item
  FROM public.ew_materiais_variacoes v JOIN public.ew_acessorios a ON a.id=v.acessorio_id
  WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id AND a.empresa_id=p_empresa_id;
 END IF;
 IF (v_tipo='perfil' AND (p_unidade<>'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000
     OR p_quantidade<>trunc(p_quantidade)))
 OR (v_tipo='acessorio' AND (p_comprimento_mm IS NOT NULL OR (p_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') AND p_unidade IS DISTINCT FROM v_unidade_item)))
 THEN RAISE EXCEPTION 'Tipo, comprimento ou unidade incompatível com o material.';END IF;
 IF p_origem NOT IN ('ABERTURA','COMPRA','SAIDA_MANUAL','AJUSTE')
    OR p_quantidade IS NULL OR p_quantidade=0 OR abs(p_quantidade)>1000000
 THEN RAISE EXCEPTION 'Tipo ou quantidade inválida.';END IF;
 IF (p_origem IN ('ABERTURA','COMPRA') AND p_quantidade<0)
 OR (p_origem='SAIDA_MANUAL' AND p_quantidade>0)
 THEN RAISE EXCEPTION 'Sinal de quantidade incompatível com a movimentação.';END IF;
 IF length(coalesce(p_observacao,''))>500 OR
   (p_origem IN ('AJUSTE','SAIDA_MANUAL') AND length(btrim(coalesce(p_observacao,'')))<5)
 THEN RAISE EXCEPTION 'Informe uma justificativa de 5 a 500 caracteres nos ajustes e saídas.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo
  FROM public.ew_estoque_obras_movimentos
  WHERE obra_id=p_obra_id AND empresa_id=p_empresa_id AND variacao_id=p_variacao_id
    AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm AND unidade=p_unidade;
 v_total:=v_saldo+p_quantidade;
 IF v_total<0 THEN RAISE EXCEPTION 'Saldo insuficiente na obra (% %).',v_saldo,p_unidade;END IF;
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,observacao,usuario_id)
 VALUES (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
   p_quantidade,p_origem,p_operacao_id,
   coalesce(nullif(btrim(coalesce(p_observacao,'')),''),
    CASE WHEN p_origem='ABERTURA' THEN 'Cadastro manual do estoque da obra'
      ELSE 'Entrada manual na obra' END),v_usuario) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'saldo',v_total,'unidade',p_unidade,'repetida',false);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_movimentar_estoque_obra_local(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid, p_local_estoque text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_saldo numeric;v_result jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.baixar');
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where
   u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil IN ('administrador','gerenciador'))
 then raise exception 'Somente o ADM pode movimentar estoque.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=p_empresa_id
   and l.nome=v_local and l.ativo)
 then raise exception 'Selecione um local de estoque válido.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.usuario_id=v_uid)
 then return jsonb_build_object('repetida',true);end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 if p_quantidade<0 then
   select coalesce(sum(quantidade_delta),0) into v_saldo
   from public.ew_estoque_obras_movimentos where empresa_id=p_empresa_id and obra_id=p_obra_id
   and variacao_id=p_variacao_id and comprimento_mm is not distinct from p_comprimento_mm
   and unidade=p_unidade and local_estoque=v_local;
   if v_saldo+p_quantidade<0 then
     raise exception 'Saldo insuficiente em %: disponível % %.',v_local,v_saldo,p_unidade;
   end if;
 end if;
 v_result:=public.ew_movimentar_estoque_obra(p_empresa_id,p_obra_id,p_variacao_id,
   p_comprimento_mm,p_unidade,p_quantidade,p_origem,p_observacao,p_operacao_id);
 if not coalesce((v_result->>'repetida')::boolean,false) then
   update public.ew_estoque_obras_movimentos set local_estoque=v_local
   where id=(v_result->>'id')::uuid;
 end if;
 return v_result||jsonb_build_object('local_estoque',v_local);
end;$function$;

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
 PERFORM public.ew_exigir_permissao('estoque.receber');
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

CREATE OR REPLACE FUNCTION public.ew_receber_item_nfe(p_empresa_id uuid, p_despesa_item_id uuid, p_variacao_id uuid, p_quantidade numeric, p_unidade text, p_comprimento_mm integer, p_local_estoque text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();v_despesa public.ew_obra_despesas%ROWTYPE;
 v_item public.ew_obra_despesas_itens%ROWTYPE;
 v_variacao public.ew_materiais_variacoes%ROWTYPE;
 v_recebido uuid;v_mov jsonb;v_id uuid;v_unidade text:=upper(btrim(coalesce(p_unidade,'')));
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_unidade_cadastro text;v_unidade_embalagem text;v_fator_embalagem numeric;
 v_unidade_nf text;v_limite_fisico numeric;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.receber');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
     ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM confirma entradas físicas provenientes de NF-e.';END IF;
 IF p_despesa_item_id IS NULL OR p_variacao_id IS NULL OR
   p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
   p_quantidade<>round(p_quantidade,3)
 THEN RAISE EXCEPTION 'Item ou quantidade de recebimento inválidos.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(p_despesa_item_id::text,912423));
 SELECT id INTO v_recebido FROM public.ew_nfe_recebimentos WHERE despesa_item_id=p_despesa_item_id AND estornado_em IS NULL;
 IF v_recebido IS NOT NULL THEN RETURN jsonb_build_object('id',v_recebido,'ja_recebido',true);END IF;
 SELECT * INTO v_item FROM public.ew_obra_despesas_itens
 WHERE id=p_despesa_item_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Item de nota não encontrado nesta empresa.';END IF;
 SELECT * INTO v_despesa FROM public.ew_obra_despesas
 WHERE id=v_item.despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_despesa.status<>'aprovada' OR v_despesa.categoria NOT IN ('aluminio','acessorios') OR
   v_despesa.origem<>'nfe_xml' OR v_despesa.chave_nfe IS NULL
 THEN RAISE EXCEPTION 'A NF-e deve estar aprovada e classificada como alumínio ou acessórios.';END IF;
 SELECT * INTO v_variacao FROM public.ew_materiais_variacoes
 WHERE id=p_variacao_id AND empresa_id=p_empresa_id;
 IF NOT FOUND OR
   (v_despesa.categoria='aluminio' AND
     (v_variacao.tipo<>'perfil' OR v_item.perfil_id IS DISTINCT FROM v_variacao.perfil_id)) OR
   (v_despesa.categoria='acessorios' AND
     (v_variacao.tipo<>'acessorio' OR v_item.acessorio_id IS DISTINCT FROM v_variacao.acessorio_id))
 THEN RAISE EXCEPTION 'Variação incompatível com o item da NF-e. Vincule o material correto antes de receber.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais WHERE
   empresa_id=p_empresa_id AND obra_id=v_despesa.obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque da obra inexistente ou arquivado.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos WHERE
   empresa_id=p_empresa_id AND nome=v_local AND ativo)
 THEN RAISE EXCEPTION 'Selecione um galpão válido.';END IF;
 v_unidade_nf:=upper(btrim(coalesce(v_item.unidade,'')));
 IF v_variacao.tipo='perfil' THEN
   IF v_unidade<>'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000 OR
      p_quantidade<>trunc(p_quantidade)
   THEN RAISE EXCEPTION 'Perfis exigem quantidade inteira em BARRA e comprimento comercial em mm.';END IF;
   IF v_unidade_nf IN ('BARRA','BR') AND p_quantidade>v_item.quantidade
   THEN RAISE EXCEPTION 'Quantidade recebida maior que o número de barras da NF-e.';END IF;
   IF v_unidade_nf IN ('MT','M') AND p_quantidade*p_comprimento_mm/1000>v_item.quantidade+0.0001
   THEN RAISE EXCEPTION 'Metros em barras ultrapassam os metros registrados na NF-e.';END IF;
 ELSE
   SELECT upper(btrim(unidade_item)),upper(btrim(unidade_embalagem)),quantidade_por_embalagem
   INTO v_unidade_cadastro,v_unidade_embalagem,v_fator_embalagem
   FROM public.ew_acessorios
   WHERE id=v_variacao.acessorio_id AND empresa_id=p_empresa_id;
   IF v_unidade_cadastro IN ('PEÇA','PECA','PÇ','PÇS') THEN v_unidade_cadastro:='PC';END IF;
   IF v_unidade_cadastro IN ('PAR','PARES') THEN v_unidade_cadastro:='PR';END IF;
   IF v_unidade_cadastro IN ('METRO','M') THEN v_unidade_cadastro:='MT';END IF;
   IF v_unidade_cadastro='UNIDADE' THEN v_unidade_cadastro:='UN';END IF;
   IF p_comprimento_mm IS NOT NULL OR v_unidade<>v_unidade_cadastro
   THEN RAISE EXCEPTION 'Unidade do recebimento deve ser a unidade do item (%). Converta embalagens antes.',v_unidade_cadastro;END IF;
   IF v_unidade_nf=v_unidade_cadastro THEN v_limite_fisico:=v_item.quantidade;
   ELSIF v_unidade_nf=v_unidade_embalagem AND coalesce(v_fator_embalagem,0)>0
   THEN v_limite_fisico:=v_item.quantidade*v_fator_embalagem;
   ELSIF v_unidade_nf='UN' AND v_unidade_cadastro='PC'
   THEN v_limite_fisico:=v_item.quantidade;
   ELSE RAISE EXCEPTION 'Unidade da NF-e (%) não é compatível com a unidade do item (%) nem tem conversão cadastrada.',
     v_unidade_nf,v_unidade_cadastro;
   END IF;
   IF p_quantidade>v_limite_fisico+0.001
   THEN RAISE EXCEPTION 'Recebimento excede a quantidade da NF-e convertida: % %.',v_limite_fisico,v_unidade_cadastro;END IF;
 END IF;
 -- A movimentação e o vínculo à NF-e são atômicos: erro reverte as duas inserções.
 v_mov:=public.ew_movimentar_estoque_obra_local(
   p_empresa_id,v_despesa.obra_id,p_variacao_id,p_comprimento_mm,v_unidade,
   p_quantidade,'COMPRA','Recebimento confirmado da NF-e '||left(v_despesa.numero_documento,75),
   p_operacao_id,v_local);
 IF coalesce((v_mov->>'repetida')::boolean,false) OR (v_mov->>'id') IS NULL
 THEN RAISE EXCEPTION 'Operação de estoque já utilizada; confira o histórico antes de repetir.';END IF;
 INSERT INTO public.ew_nfe_recebimentos(
   empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,
   unidade,quantidade,local_estoque,movimento_id,usuario_id)
 VALUES(p_empresa_id,v_despesa.obra_id,p_despesa_item_id,p_variacao_id,p_comprimento_mm,
   v_unidade,p_quantidade,v_local,(v_mov->>'id')::uuid,v_uid) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'obra_id',v_despesa.obra_id,'movimento_id',v_mov->>'id',
   'quantidade',p_quantidade,'unidade',v_unidade,'ja_recebido',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_receber_materiais_almox(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_local_estoque text, p_itens jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_previous public.ew_obra_despesas%rowtype;
 v_despesa_id uuid;v_item_id uuid;v_mov_id uuid;
 v_row jsonb;v_var public.ew_materiais_variacoes%rowtype;
 v_codigo text;v_descricao text;v_unidade text;v_length integer;
 v_qty numeric;v_subtotal numeric;v_sum numeric:=0;v_count integer:=0;
begin
 PERFORM public.ew_exigir_permissao('estoque.receber');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas u
   where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and public.ew_pode(p_empresa_id,'estoque.receber'))
 then raise exception 'Acesso não autorizado ao recebimento.';end if;
 if p_categoria not in ('aluminio','acessorios') or p_valor is null
    or p_valor<=0 or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
    or p_data_documento is null
    or char_length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
    or length(coalesce(p_observacoes,''))>1000
    or jsonb_typeof(p_itens) is distinct from 'array'
    or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Nota ou itens recebidos inválidos.';end if;
 if not exists(select 1 from public.ew_fornecedores f where f.empresa_id=p_empresa_id
    and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione fornecedor cadastrado e ativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=p_empresa_id
    and l.nome=v_local and l.ativo)
 then raise exception 'Selecione galpão de destino ativo.';end if;
 if not exists(select 1 from public.ew_obra_orcamento o
    where o.empresa_id=p_empresa_id and o.obra_id=p_obra_id)
  or not exists(select 1 from public.ew_estoques_locais l where l.empresa_id=p_empresa_id
    and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Obra sem orçamento ou estoque ativo.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 -- Serializar por número da nota, fornecedor e categoria além do UUID da operação:
 -- duas sessões usando UUIDs diferentes não devem duplicar a mesma NF.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(coalesce(p_fornecedor,'')))||'|'||lower(btrim(p_numero_documento)),541890));
 select * into v_previous from public.ew_obra_despesas d
  where d.empresa_id=p_empresa_id and d.operacao_id=p_operacao_id;
 if found then
   if v_previous.obra_id<>p_obra_id or v_previous.categoria<>p_categoria
      or v_previous.valor<>p_valor or v_previous.status<>'aprovada'
   then raise exception 'Identificador já utilizado para outro lançamento.';end if;
   select count(*) into v_count
    from public.ew_nfe_recebimentos n
    join public.ew_obra_despesas_itens i on i.id=n.despesa_item_id
    where i.despesa_id=v_previous.id and n.empresa_id=p_empresa_id;
   if v_count<>jsonb_array_length(p_itens) then
    raise exception 'Operação anterior incompleta; confira antes de repetir.';end if;
   return jsonb_build_object('id',v_previous.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
   and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
   and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
   and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Já existe nota com este número, fornecedor e categoria nesta obra.';end if;

 -- Primeiro valida todas as linhas sem gravar saldos.
 for v_row in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_row) is distinct from 'object' or
     jsonb_typeof(v_row->'quantidade') is distinct from 'number' or
     jsonb_typeof(v_row->'valor_total') is distinct from 'number' or
     jsonb_typeof(v_row->'variacao_id') is distinct from 'string'
   then raise exception 'Linha de material incompleta.';end if;
   v_qty:=(v_row->>'quantidade')::numeric;
   v_subtotal:=(v_row->>'valor_total')::numeric;
   if v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,3)
      or v_subtotal<0 or v_subtotal>999999999999.99 or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Quantidade ou valor do material inválido.';end if;
   select * into v_var from public.ew_materiais_variacoes v
    where v.id=(v_row->>'variacao_id')::uuid and v.empresa_id=p_empresa_id and v.ativo;
   if not found or (p_categoria='aluminio' and v_var.tipo<>'perfil')
     or (p_categoria='acessorios' and v_var.tipo<>'acessorio')
   then raise exception 'Material ou cor incompatível com a categoria.';end if;
   if not exists(select 1 from public.ew_cem_obras_materiais m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=v_var.id)
   then raise exception 'O material não está previsto nesta obra.';end if;
   if v_var.tipo='perfil' then
    if jsonb_typeof(v_row->'comprimento_mm') is distinct from 'number'
    then raise exception 'Informe o comprimento da barra.';end if;
    v_length:=(v_row->>'comprimento_mm')::integer;
    if v_length not between 100 and 20000 or v_qty<>trunc(v_qty)
    then raise exception 'Perfis exigem barras inteiras e comprimento válido.';end if;
   elsif v_row->>'comprimento_mm' is not null
   then raise exception 'Acessórios não possuem comprimento de barra.';end if;
   v_count:=v_count+1;v_sum:=v_sum+v_subtotal;
 end loop;
 if v_sum<>p_valor then raise exception 'A soma dos itens não confere com a nota.';end if;

 insert into public.ew_obra_despesas
 (empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
  data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 values(p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,btrim(p_numero_documento),
  p_data_documento,'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id)
 returning id into v_despesa_id;
 for v_row in select value from jsonb_array_elements(p_itens) loop
  select * into v_var from public.ew_materiais_variacoes v
   where v.id=(v_row->>'variacao_id')::uuid and v.empresa_id=p_empresa_id and v.ativo;
  v_qty:=(v_row->>'quantidade')::numeric;
  v_subtotal:=(v_row->>'valor_total')::numeric;
  if v_var.tipo='perfil' then
   select p.codigo,p.descricao into v_codigo,v_descricao from public.ew_perfis p
    where p.id=v_var.perfil_id and p.empresa_id=p_empresa_id;
   v_unidade:='BARRA';v_length:=(v_row->>'comprimento_mm')::integer;
  else
   select a.codigo,a.descricao,
    case when upper(btrim(a.unidade_item)) in ('PEÇA','PECA','PÇ','PÇS') then 'PC'
     when upper(btrim(a.unidade_item)) in ('PAR','PARES') then 'PR'
     when upper(btrim(a.unidade_item)) in ('METRO','M') then 'MT'
     when upper(btrim(a.unidade_item))='UNIDADE' then 'UN'
     else upper(btrim(a.unidade_item)) end
   into v_codigo,v_descricao,v_unidade
   from public.ew_acessorios a
   where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id;
   v_length:=null;
   if v_unidade not in ('PC','PR','CJ','MT','KG','UN')
   then raise exception 'Unidade do acessório não suportada.';end if;
  end if;
  if v_codigo is null then raise exception 'Material sem cadastro.';end if;
  if v_unidade in ('PC','UN','PR','CJ','CX') and v_qty<>trunc(v_qty) then
   raise exception 'Acessorios em % exigem quantidade inteira (1, 2, 3...).',v_unidade;
  end if;
  insert into public.ew_obra_despesas_itens
  (despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
    valor_unitario,valor_total,perfil_id,acessorio_id)
  values(v_despesa_id,p_empresa_id,left(v_codigo,120),left(v_descricao,500),
    v_unidade,v_qty,round(v_subtotal/v_qty,6),v_subtotal,v_var.perfil_id,v_var.acessorio_id)
  returning id into v_item_id;
  -- Entrada física somente depois da nota validada. Mesmo commit/transação.
  insert into public.ew_estoque_obras_movimentos
  (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_obra_id,v_var.id,v_length,v_unidade,v_qty,
   'COMPRA',gen_random_uuid(),'Recebimento NF '||left(p_numero_documento,75),
   v_uid,v_local)
  returning id into v_mov_id;
  insert into public.ew_nfe_recebimentos
  (empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
   quantidade,local_estoque,movimento_id,usuario_id)
  values(p_empresa_id,p_obra_id,v_item_id,v_var.id,v_length,v_unidade,
   v_qty,v_local,v_mov_id,v_uid);
 end loop;
 return jsonb_build_object('id',v_despesa_id,'ja_registrado',false,
   'itens_recebidos',v_count,'obra_id',p_obra_id);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_registrar_despesa_financeira(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_origem text, p_chave_nfe text, p_itens jsonb, p_observacoes text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();v_id uuid;v_linha jsonb;v_perfil uuid;v_acessorio uuid;
 v_qtd numeric;v_preco numeric;v_total numeric;
 v_chave text:=nullif(btrim(coalesce(p_chave_nfe,'')),'');
 v_antigo uuid;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.despesas');
 PERFORM public.ew_exigir_sessao_atual();
 IF p_origem='manual' AND p_categoria IN ('vidros','outros') THEN
   RAISE EXCEPTION 'Vidros e outros insumos: registre a nota pelo Recebimento físico da versão atualizada.';
 END IF;
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.despesas'))
 THEN RAISE EXCEPTION 'Somente ADM registra despesas financeiras.';END IF;
 IF p_operacao_id IS NULL OR p_obra_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.ew_obra_orcamento
   WHERE obra_id=p_obra_id AND empresa_id=p_empresa_id)
 THEN RAISE EXCEPTION 'Selecione uma obra com orçamento registrado.';END IF;
 IF p_categoria NOT IN ('aluminio','acessorios','vidros','outros') OR
    p_valor IS NULL OR p_valor<=0 OR p_valor>999999999999.99 OR
    p_valor<>round(p_valor,2) OR p_origem NOT IN ('manual','nfe_xml') OR
    length(coalesce(p_fornecedor,''))>240 OR length(coalesce(p_numero_documento,''))>100 OR
    length(coalesce(p_observacoes,''))>1000 THEN
  RAISE EXCEPTION 'Dados financeiros da despesa inválidos.';END IF;
 IF v_chave IS NOT NULL AND v_chave !~ '^[0-9]{44}$' THEN RAISE EXCEPTION 'Chave da NF-e inválida (44 dígitos).';END IF;
 IF p_origem='nfe_xml' AND v_chave IS NULL THEN RAISE EXCEPTION 'XML sem chave NF-e identificada.';END IF;
 IF jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens)>500
 THEN RAISE EXCEPTION 'Itens da despesa inválidos.';END IF;
 SELECT id INTO v_antigo FROM public.ew_obra_despesas WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF v_antigo IS NOT NULL THEN RETURN jsonb_build_object('id',v_antigo,'ja_registrado',true);END IF;
 INSERT INTO public.ew_obra_despesas(
 empresa_id,obra_id,categoria,valor,fornecedor,numero_documento,data_documento,
 origem,chave_nfe,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 VALUES(p_empresa_id,p_obra_id,p_categoria,p_valor,coalesce(p_fornecedor,''),
 coalesce(p_numero_documento,''),p_data_documento,p_origem,v_chave,
 'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id)
 RETURNING id INTO v_id;
 FOR v_linha IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_linha->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_linha->'valor_unitario') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_linha->'valor_total') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Item incompleto na nota.';END IF;
  v_qtd:=(v_linha->>'quantidade')::numeric;
  v_preco:=(v_linha->>'valor_unitario')::numeric;
  v_total:=(v_linha->>'valor_total')::numeric;
  IF v_qtd<=0 OR v_qtd>1e9 OR v_preco<0 OR v_preco>1e9 OR v_total<0 OR v_total>1e11
  THEN RAISE EXCEPTION 'Quantidade ou preço inválido no XML.'; END IF;
  v_perfil:=nullif(v_linha->>'perfil_id','')::uuid;
  v_acessorio:=nullif(v_linha->>'acessorio_id','')::uuid;
  IF v_perfil IS NOT NULL AND v_acessorio IS NOT NULL
  THEN RAISE EXCEPTION 'Item com duas classificações.';END IF;
  IF v_perfil IS NOT NULL AND (p_categoria<>'aluminio' OR NOT EXISTS(
    SELECT 1 FROM public.ew_perfis WHERE id=v_perfil AND empresa_id=p_empresa_id))
  THEN RAISE EXCEPTION 'Perfil não encontrado no catálogo da empresa.';END IF;
  IF v_acessorio IS NOT NULL AND (p_categoria<>'acessorios' OR NOT EXISTS(
    SELECT 1 FROM public.ew_acessorios WHERE id=v_acessorio AND empresa_id=p_empresa_id))
  THEN RAISE EXCEPTION 'Acessório não encontrado no catálogo da empresa.';END IF;
  INSERT INTO public.ew_obra_despesas_itens(
   despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,valor_total,perfil_id,acessorio_id)
  VALUES(v_id,p_empresa_id,left(coalesce(v_linha->>'codigo',''),120),
   left(coalesce(v_linha->>'descricao',''),500),
   left(coalesce(v_linha->>'unidade',''),30),v_qtd,v_preco,v_total,v_perfil,v_acessorio);
 END LOOP;
 RETURN jsonb_build_object('id',v_id,'ja_registrado',false,'valor',p_valor,'itens',jsonb_array_length(p_itens));
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_registrar_faturamento_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_data_faturamento date, p_numero_documento text, p_observacoes text, p_itens jsonb, p_operacao_id uuid, p_instalacao_confirmada boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_budget numeric;
 v_faturado numeric;
 v_id uuid;
 v_antigo uuid;
 v_item jsonb;
 v_esquadria public.esquadrias%ROWTYPE;
 v_quantidade numeric;
 v_unit numeric;
 v_line numeric;
 v_total numeric:=0;
 v_total_invoiced numeric;
 v_count int:=0;
 v_shipped numeric;
 v_seen uuid[]:=ARRAY[]::uuid[];
 v_precificacao_revisao_id uuid;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.faturar');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND public.ew_pode(p_empresa_id,'financeiro.faturar'))
 THEN RAISE EXCEPTION 'Somente ADM pode registrar faturamentos.';END IF;
 IF p_categoria NOT IN ('fabricacao','instalacao') OR p_operacao_id IS NULL OR p_obra_id IS NULL OR
   p_data_faturamento IS NULL OR length(btrim(coalesce(p_numero_documento,''))) NOT BETWEEN 1 AND 120 OR
   length(coalesce(p_observacoes,''))>1000 OR
   jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 200
 THEN RAISE EXCEPTION 'Informe tipo, data, número do documento e ao menos uma esquadria.';END IF;
 IF p_categoria='instalacao' AND p_instalacao_confirmada IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Confirme a instalação dos itens antes de faturar instalação.';END IF;
 -- Serializa invoices simultâneas da mesma obra/categoria.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria,0));
 SELECT id INTO v_antigo FROM public.ew_obra_faturamentos
  WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF v_antigo IS NOT NULL THEN RETURN jsonb_build_object('id',v_antigo,'ja_registrado',true);END IF;
 -- Sempre bloquear o orçamento contratual original e preservar o registro.
 SELECT CASE p_categoria WHEN 'fabricacao' THEN fabricacao ELSE instalacao END
 INTO v_budget FROM public.ew_obra_orcamento
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento financeiro da obra não encontrado.';END IF;
 -- Nas obras precificadas, usar a DISTRIBUIÇÃO aprovada, não os valores
 -- originais 70/30. Obras antigas continuam usando orçamento legado.
 SELECT id,CASE p_categoria
   WHEN 'fabricacao' THEN fabricacao_distribuida_centavos::numeric/100
   ELSE instalacao_distribuida_centavos::numeric/100 END
 INTO v_precificacao_revisao_id,v_budget
 FROM public.ew_precificacao_revisoes
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND estado='aprovada'
 ORDER BY versao DESC LIMIT 1;
 IF NOT FOUND THEN
  SELECT CASE p_categoria WHEN 'fabricacao' THEN fabricacao ELSE instalacao END
  INTO v_budget FROM public.ew_obra_orcamento
  WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id;
 END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_item->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'valor_unitario') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Esquadria ou valor de faturamento incompleto.';END IF;
  IF (v_item->>'esquadria_id')::uuid=ANY(v_seen) THEN
   RAISE EXCEPTION 'Esquadria repetida no mesmo documento. Agrupe quantidades de cada código.';
  END IF;
  v_seen:=array_append(v_seen,(v_item->>'esquadria_id')::uuid);
  SELECT * INTO v_esquadria FROM public.esquadrias WHERE id=(v_item->>'esquadria_id')::uuid
    AND empresa_id=p_empresa_id AND obra_id=p_obra_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria do faturamento não pertence à obra.';END IF;
  -- Segurança no servidor: em obras precificadas, nenhum documento pode
  -- contornar o cadastro individual aprovado, ainda que o cliente REST seja
  -- invocado diretamente sem passar pela interface.
  IF v_precificacao_revisao_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.ew_precificacao_revisoes_itens pi
   WHERE pi.revisao_id=v_precificacao_revisao_id
    AND pi.empresa_id=p_empresa_id AND pi.obra_id=p_obra_id
    AND pi.esquadria_id=v_esquadria.id
    AND pi.quantidade=v_esquadria.quantidade
  ) THEN
   RAISE EXCEPTION 'Esquadria sem precificação individual aprovada ou com quantidade divergente: %.',v_esquadria.codigo;
  END IF;
  v_quantidade:=(v_item->>'quantidade')::numeric;
  v_unit:=(v_item->>'valor_unitario')::numeric;
  IF v_quantidade<=0 OR v_quantidade>v_esquadria.quantidade OR v_quantidade<>round(v_quantidade,6) OR
     v_unit<=0 OR v_unit>100000000 OR v_unit<>round(v_unit,4)
  THEN RAISE EXCEPTION 'Quantidade ou preço unitário inválido para %.',v_esquadria.codigo; END IF;
  SELECT coalesce(sum(fi.quantidade),0) INTO v_total_invoiced
  FROM public.ew_obra_faturamentos_itens fi
  JOIN public.ew_obra_faturamentos fh ON fh.id=fi.faturamento_id
  WHERE fi.esquadria_id=v_esquadria.id AND fh.empresa_id=p_empresa_id
  AND fh.obra_id=p_obra_id AND fh.categoria=p_categoria AND fh.status='emitido';
  -- Equivalente expedido: completa 100%, marco 50%, folha física 50%/folhas.
  -- Romaneios cancelados não autorizam faturamento.
  IF EXISTS (
   SELECT 1 FROM public.romaneios_itens ri
   JOIN public.romaneios rr ON rr.id=ri.romaneio_id
   LEFT JOIN public.esquadrias_saida_config cfg ON cfg.esquadria_id=ri.esquadria_id
   WHERE ri.esquadria_id=v_esquadria.id AND rr.empresa_id=p_empresa_id
    AND rr.obra_id=p_obra_id AND rr.status='emitido' AND rr.cancelado_em IS NULL
    AND ri.natureza='esquadria' AND ri.tipo_saida='folha'
    AND (cfg.folhas_por_unidade IS NULL OR cfg.folhas_por_unidade NOT BETWEEN 1 AND 12)
  ) THEN
   RAISE EXCEPTION 'Composição física das folhas não cadastrada para %.',v_esquadria.codigo;
  END IF;
  SELECT coalesce(sum(
    CASE ri.tipo_saida
     WHEN 'completo' THEN ri.quantidade::numeric
     WHEN 'marco' THEN ri.quantidade::numeric/2
     WHEN 'folha' THEN ri.quantidade::numeric/(2*cfg.folhas_por_unidade)
     ELSE 0 END
  ),0) INTO v_shipped
  FROM public.romaneios_itens ri
  JOIN public.romaneios rr ON rr.id=ri.romaneio_id
  LEFT JOIN public.esquadrias_saida_config cfg ON cfg.esquadria_id=ri.esquadria_id
  WHERE ri.esquadria_id=v_esquadria.id AND rr.empresa_id=p_empresa_id
   AND rr.obra_id=p_obra_id AND rr.status='emitido' AND rr.cancelado_em IS NULL
   AND ri.natureza='esquadria';
  IF v_total_invoiced+v_quantidade>v_esquadria.quantidade OR
     v_total_invoiced+v_quantidade>v_shipped THEN
    RAISE EXCEPTION 'Quantidade equivalente não faturável de %: confira saídas ativas e histórico de %.',
      v_esquadria.codigo,p_categoria;
  END IF;
  v_line:=round(v_quantidade*v_unit,2);
  IF v_line<=0 THEN RAISE EXCEPTION 'Valor de faturamento arredondado para zero.';END IF;
  v_total:=v_total+v_line;
  v_count:=v_count+1;
 END LOOP;
 SELECT coalesce(sum(valor_total),0) INTO v_faturado FROM public.ew_obra_faturamentos
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido';
 IF v_faturado+v_total>v_budget
 THEN RAISE EXCEPTION 'Faturamento supera o valor contratado para %. Previsto %, já faturado %, novo %.',
 p_categoria,v_budget,v_faturado,v_total;END IF;
 INSERT INTO public.ew_obra_faturamentos(
  empresa_id,obra_id,categoria,data_faturamento,numero_documento,observacoes,valor_total,criado_por,operacao_id)
 VALUES(p_empresa_id,p_obra_id,p_categoria,p_data_faturamento,
 btrim(p_numero_documento),coalesce(p_observacoes,''),v_total,v_uid,p_operacao_id)
 RETURNING id INTO v_id;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  v_quantidade:=(v_item->>'quantidade')::numeric;
  v_unit:=(v_item->>'valor_unitario')::numeric;
  INSERT INTO public.ew_obra_faturamentos_itens(
   faturamento_id,empresa_id,esquadria_id,quantidade,valor_unitario,valor_total)
  VALUES(v_id,p_empresa_id,(v_item->>'esquadria_id')::uuid,
   v_quantidade,v_unit,round(v_quantidade*v_unit,2));
 END LOOP;
 RETURN jsonb_build_object('id',v_id,'categoria',p_categoria,'valor_total',v_total,'itens',v_count,'ja_registrado',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_registrar_liberacao_componente(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_componente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_e public.esquadrias%rowtype;
 v_tipo text:=lower(btrim(coalesce(p_componente,'')));
 v_fabrica text:=upper(btrim(coalesce(p_fabrica,'')));
 v_c integer;v_m integer;v_f integer;v_frame integer;v_folhas integer;
 v_id uuid;
begin
 PERFORM public.ew_exigir_permissao('liberacoes.criar');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null then raise exception 'Entre no sistema para registrar uma liberação.';end if;
 if p_quantidade is null or p_quantidade<1 or p_quantidade>100000
 then raise exception 'Informe quantidade inteira e positiva.';end if;
 if p_data_liberacao is null or p_data_liberacao>current_date or p_data_liberacao<date '2000-01-01'
 then raise exception 'Data de liberação inválida.';end if;
 if v_tipo not in ('completo','marco','folhas')
 then raise exception 'Selecione completo, somente marco ou conjunto das folhas.';end if;
 if v_fabrica<>'' and v_fabrica not in ('AFOGADOS','IMBIRIBEIRA')
 then raise exception 'Fábrica inválida.';end if;
 select * into v_e from public.esquadrias where id=p_esquadria_id for update;
 if not found then raise exception 'Esquadria não encontrada.';end if;
 if not exists(select 1 from public.usuarios_empresas ue where ue.usuario_id=v_uid
   and ue.empresa_id=v_e.empresa_id and ue.perfil in ('administrador','gerenciador','supervisor'))
 then raise exception 'Usuário não autorizado para liberar esta esquadria.';end if;
 if v_tipo<>'completo' and
    (v_e.descricao !~* '[0-9]{1,2}[[:space:]-]*FOLHA' or
     v_e.descricao ~* 'MAXIM[[:space:]-]*AR')
 then raise exception 'Esta esquadria deve ser liberada como conjunto completo.';end if;
 select coalesce(sum(quantidade) filter(where tipo_componente='completo'),0)::integer,
        coalesce(sum(quantidade) filter(where tipo_componente='marco'),0)::integer,
        coalesce(sum(quantidade) filter(where tipo_componente='folhas'),0)::integer
   into v_c,v_m,v_f from public.liberacoes_corte
  where esquadria_id=p_esquadria_id and cancelado_em is null;
 v_frame:=v_c+v_m+(case when v_tipo in ('completo','marco') then p_quantidade else 0 end);
 v_folhas:=v_c+v_f+(case when v_tipo in ('completo','folhas') then p_quantidade else 0 end);
 if v_frame>v_e.quantidade or v_folhas>v_e.quantidade then
   raise exception 'Quantidade excede o saldo desta parte. Marcos disponíveis: %, conjuntos de folhas disponíveis: %.',
   v_e.quantidade-v_c-v_m,v_e.quantidade-v_c-v_f;
 end if;
 insert into public.liberacoes_corte
  (esquadria_id,quantidade,data_liberacao,usuario_id,fabrica,tipo_componente)
 values(p_esquadria_id,p_quantidade,p_data_liberacao,v_uid,
        nullif(v_fabrica,''),v_tipo)
 returning id into v_id;
 -- qtd_liberada permanece inteira: conta unidades com pelo menos uma parte liberada.
 -- Para a AREA liberada usa-se 100% completo, 50% marco e 50% folhas.
 update public.esquadrias set qtd_liberada=greatest(v_frame,v_folhas)
 where id=p_esquadria_id;
 return jsonb_build_object('registro_id',v_id,'quantidade_liberada',p_quantidade,
  'tipo_componente',v_tipo,'fabrica',nullif(v_fabrica,''),
  'marcos_liberados',v_frame,'conjuntos_folhas_liberados',v_folhas,
  'saldo_marcos',v_e.quantidade-v_frame,'saldo_folhas',v_e.quantidade-v_folhas);
end;
$function$;

CREATE OR REPLACE FUNCTION public.ew_registrar_recebimento_manual_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_local_estoque text, p_itens jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_op_anterior public.ew_obra_despesas%ROWTYPE;
 v_despesa jsonb;v_despesa_id uuid;v_row jsonb;
 v_var public.ew_materiais_variacoes%ROWTYPE;
 v_codigo text;v_descricao text;v_unidade text;
 v_quantidade numeric;v_item_valor numeric;v_soma numeric:=0;
 v_comprimento integer;v_recebimento uuid;v_mov jsonb;v_item_id uuid;
 v_count integer:=0;v_total_itens integer;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.receber');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_obra_id IS NULL OR p_operacao_id IS NULL OR
    NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
      WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode registrar entrada de material e nota fiscal.';END IF;
 IF p_categoria NOT IN ('aluminio','acessorios') OR p_valor IS NULL OR
   p_valor<=0 OR p_valor>999999999999.99 OR p_valor<>round(p_valor,2)
 THEN RAISE EXCEPTION 'Categoria ou valor total da nota inválidos.';END IF;
 IF jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR
   jsonb_array_length(p_itens) NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Selecione de 1 a 100 materiais recebidos.';END IF;
 v_total_itens:=jsonb_array_length(p_itens);
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'O estoque da obra não existe ou está arquivado.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_local AND ativo)
 THEN RAISE EXCEPTION 'Informe um galpão ativo cadastrado.';END IF;
 IF length(btrim(coalesce(p_numero_documento,''))) NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Informe o número da nota/documento.';END IF;
 IF length(coalesce(p_fornecedor,''))>240 OR length(coalesce(p_observacoes,''))>1000
 THEN RAISE EXCEPTION 'Fornecedor ou observação muito extensos.';END IF;
 -- Impede tentativas simultâneas com a mesma operação e repetições após falha de rede.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 SELECT * INTO v_op_anterior FROM public.ew_obra_despesas
 WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v_op_anterior.obra_id<>p_obra_id OR v_op_anterior.categoria<>p_categoria
    OR v_op_anterior.valor<>p_valor OR v_op_anterior.status<>'aprovada'
  THEN RAISE EXCEPTION 'Identificador de operação já utilizado para outro lançamento.'; END IF;
  SELECT count(*) INTO v_count FROM public.ew_nfe_recebimentos n
   JOIN public.ew_obra_despesas_itens i ON i.id=n.despesa_item_id
   WHERE i.despesa_id=v_op_anterior.id AND n.empresa_id=p_empresa_id;
  IF v_count<>v_total_itens THEN
   RAISE EXCEPTION 'Operação existente não possui todos os recebimentos. Confira o histórico.';END IF;
  RETURN jsonb_build_object('id',v_op_anterior.id,'ja_registrado',true,'itens_recebidos',v_count);
 END IF;

 -- Valida tudo antes da primeira gravação. Cada linha requer valor para preservar custo unitário.
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_row->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_row->'valor_total') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Informe quantidade e subtotal de cada material.';END IF;
  v_quantidade:=(v_row->>'quantidade')::numeric;
  v_item_valor:=(v_row->>'valor_total')::numeric;
  IF v_quantidade<=0 OR v_quantidade>1000000 OR v_quantidade<>round(v_quantidade,3)
     OR v_item_valor<0 OR v_item_valor>999999999999.99 OR v_item_valor<>round(v_item_valor,2)
  THEN RAISE EXCEPTION 'Quantidade ou subtotal do material inválidos.';END IF;
  IF jsonb_typeof(v_row->'variacao_id') IS DISTINCT FROM 'string'
  THEN RAISE EXCEPTION 'Informe a cor/variação de cada material.';END IF;
  SELECT * INTO v_var FROM public.ew_materiais_variacoes
   WHERE id=(v_row->>'variacao_id')::uuid AND empresa_id=p_empresa_id AND ativo;
  IF NOT FOUND OR
    (p_categoria='aluminio' AND v_var.tipo<>'perfil') OR
    (p_categoria='acessorios' AND v_var.tipo<>'acessorio')
  THEN RAISE EXCEPTION 'Material ou variação incompatível com a categoria.'; END IF;
  IF v_var.tipo='perfil' THEN
   IF jsonb_typeof(v_row->'comprimento_mm') IS DISTINCT FROM 'number'
   THEN RAISE EXCEPTION 'Informe o comprimento das barras em mm.';END IF;
   v_comprimento:=(v_row->>'comprimento_mm')::integer;
   IF v_comprimento NOT BETWEEN 100 AND 20000 OR v_quantidade<>trunc(v_quantidade)
   THEN RAISE EXCEPTION 'Perfis exigem barras inteiras e comprimento comercial válido.';END IF;
  ELSE
   IF v_row ? 'comprimento_mm' AND v_row->>'comprimento_mm' IS NOT NULL
   THEN RAISE EXCEPTION 'Acessórios não devem informar comprimento de barra.';END IF;
  END IF;
  v_soma:=v_soma+v_item_valor; v_count:=v_count+1;
 END LOOP;
 IF v_soma<>p_valor
 THEN RAISE EXCEPTION 'A soma dos subtotais dos itens deve ser igual ao valor total da nota.';END IF;

 v_despesa:=public.ew_registrar_despesa_financeira(p_empresa_id,p_obra_id,p_categoria,
  p_valor,p_fornecedor,p_numero_documento,p_data_documento,'manual',NULL,
  '[]'::jsonb,p_observacoes,p_operacao_id);
 IF coalesce((v_despesa->>'ja_registrado')::boolean,false) OR (v_despesa->>'id') IS NULL
 THEN RAISE EXCEPTION 'Documento já registrado; confira o histórico antes de repetir.'; END IF;
 v_despesa_id:=(v_despesa->>'id')::uuid;

 FOR v_row IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  SELECT * INTO v_var FROM public.ew_materiais_variacoes
   WHERE id=(v_row->>'variacao_id')::uuid AND empresa_id=p_empresa_id AND ativo;
  v_quantidade:=(v_row->>'quantidade')::numeric;
  v_item_valor:=(v_row->>'valor_total')::numeric;
  IF v_var.tipo='perfil' THEN
   SELECT p.codigo,p.descricao INTO v_codigo,v_descricao
   FROM public.ew_perfis p WHERE p.id=v_var.perfil_id AND p.empresa_id=p_empresa_id;
   v_unidade:='BARRA';v_comprimento:=(v_row->>'comprimento_mm')::integer;
  ELSE
   SELECT a.codigo,a.descricao,
     CASE
       WHEN upper(btrim(a.unidade_item)) IN ('PEÇA','PECA','PÇ','PÇS') THEN 'PC'
       WHEN upper(btrim(a.unidade_item)) IN ('PAR','PARES') THEN 'PR'
       WHEN upper(btrim(a.unidade_item)) IN ('METRO','M') THEN 'MT'
       WHEN upper(btrim(a.unidade_item))='UNIDADE' THEN 'UN'
       ELSE upper(btrim(a.unidade_item))
     END INTO v_codigo,v_descricao,v_unidade
   FROM public.ew_acessorios a WHERE a.id=v_var.acessorio_id AND a.empresa_id=p_empresa_id;
   v_comprimento:=NULL;
   IF v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN')
   THEN RAISE EXCEPTION 'Unidade do acessório não suportada para estoque físico (%).',v_unidade;END IF;
  END IF;
  IF v_codigo IS NULL THEN RAISE EXCEPTION 'Material sem cadastro válido.';END IF;
  IF v_unidade IN ('PC','UN','PR','CJ','CX') AND v_quantidade<>trunc(v_quantidade) THEN
   RAISE EXCEPTION 'Acessorios em % exigem quantidade inteira (1, 2, 3...).',v_unidade;
  END IF;
  INSERT INTO public.ew_obra_despesas_itens
   (despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,
    quantidade,valor_unitario,valor_total,perfil_id,acessorio_id)
  VALUES(v_despesa_id,p_empresa_id,left(v_codigo,120),left(v_descricao,500),
    v_unidade,v_quantidade,round(v_item_valor/v_quantidade,6),v_item_valor,
    v_var.perfil_id,v_var.acessorio_id)
  RETURNING id INTO v_item_id;
  v_mov:=public.ew_movimentar_estoque_obra_local(p_empresa_id,p_obra_id,v_var.id,
    v_comprimento,v_unidade,v_quantidade,'COMPRA',
    'Entrada manual NF '||left(p_numero_documento,75),gen_random_uuid(),v_local);
  IF coalesce((v_mov->>'repetida')::boolean,false) OR (v_mov->>'id') IS NULL
  THEN RAISE EXCEPTION 'Falha ao vincular movimento ao estoque da obra.';END IF;
  INSERT INTO public.ew_nfe_recebimentos
   (empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
    quantidade,local_estoque,movimento_id,usuario_id)
  VALUES(p_empresa_id,p_obra_id,v_item_id,v_var.id,v_comprimento,v_unidade,
    v_quantidade,v_local,(v_mov->>'id')::uuid,v_uid) RETURNING id INTO v_recebimento;
 END LOOP;
 RETURN jsonb_build_object('id',v_despesa_id,'obra_id',p_obra_id,
  'itens_recebidos',v_count,'valor',p_valor,'local_estoque',v_local,'ja_registrado',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_renomear_fabricante_sem_vinculo(p_empresa_id uuid, p_id uuid, p_novo_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_nome text;v_novo text:=upper(btrim(coalesce(p_novo_nome,'')));
begin
 PERFORM public.ew_exigir_permissao('cadastros.editar');
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
$function$;

CREATE OR REPLACE FUNCTION public.ew_revisar_nfe_almox(p_empresa_id uuid, p_despesa_id uuid, p_acao text, p_justificativa text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode aprovar ou rejeitar notas.';END IF;
 IF p_acao NOT IN ('aprovar','rejeitar') OR length(coalesce(p_justificativa,''))>400
 THEN RAISE EXCEPTION 'Ação ou justificativa inválida.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'pendente' THEN RAISE EXCEPTION 'A nota não está pendente de aprovação.';END IF;
 IF p_acao='rejeitar' AND length(btrim(coalesce(p_justificativa,'')))<5
 THEN RAISE EXCEPTION 'Informe motivo da rejeição com pelo menos 5 caracteres.';END IF;
 UPDATE public.ew_obra_despesas SET
  status=CASE WHEN p_acao='aprovar' THEN 'aprovada' ELSE 'cancelada' END,
  aprovado_por=CASE WHEN p_acao='aprovar' THEN v_uid ELSE NULL END,
  aprovado_em=CASE WHEN p_acao='aprovar' THEN now() ELSE NULL END,
  cancelado_por=CASE WHEN p_acao='rejeitar' THEN v_uid ELSE NULL END,
  cancelado_em=CASE WHEN p_acao='rejeitar' THEN now() ELSE NULL END,
  observacoes=coalesce(observacoes,'')||CASE WHEN p_acao='rejeitar' THEN ' | Rejeição: '||btrim(p_justificativa) ELSE '' END
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status',CASE WHEN p_acao='aprovar' THEN 'aprovada' ELSE 'cancelada' END);
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_romaneio_transferencia_emitir(p_empresa_id uuid, p_documento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_doc public.ew_romaneios_transferencia%rowtype;
begin
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

CREATE OR REPLACE FUNCTION public.ew_romaneios_transferencia_juntar(p_empresa_id uuid, p_principal_id uuid, p_outros uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_master public.ew_romaneios_transferencia%rowtype;
 v_doc public.ew_romaneios_transferencia%rowtype;v_id uuid;v_count integer:=0;
begin
 PERFORM public.ew_exigir_permissao('romaneios.transferir');
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
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_submeter_nfe_almox(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_chave_nfe text, p_itens jsonb, p_observacoes text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_id uuid;v_antigo uuid;v_item jsonb;
v_q numeric;v_unit numeric;v_total numeric;v_chave text;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.receber');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
   WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='almoxarife')
 THEN RAISE EXCEPTION 'Somente almoxarife autorizado pode enviar NF-e.';END IF;
 IF p_operacao_id IS NULL OR p_obra_id IS NULL OR
  NOT EXISTS(SELECT 1 FROM public.ew_obra_orcamento b WHERE b.empresa_id=p_empresa_id AND b.obra_id=p_obra_id)
 THEN RAISE EXCEPTION 'Obra sem orçamento financeiro identificado.';END IF;
 v_chave:=nullif(btrim(coalesce(p_chave_nfe,'')),'');
 IF v_chave IS NULL OR v_chave !~ '^[0-9]{44}$' OR
   p_categoria NOT IN ('aluminio','acessorios','vidros','outros') OR
   p_valor IS NULL OR p_valor<=0 OR p_valor>999999999999.99 OR p_valor<>round(p_valor,2) OR
   length(btrim(coalesce(p_fornecedor,''))) NOT BETWEEN 1 AND 240 OR
   length(btrim(coalesce(p_numero_documento,''))) NOT BETWEEN 1 AND 100 OR
   p_data_documento IS NULL OR length(coalesce(p_observacoes,''))>1000 OR
   jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 500
 THEN RAISE EXCEPTION 'Nota fiscal incompleta ou inválida.';END IF;
 SELECT id INTO v_antigo FROM public.ew_obra_despesas WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF v_antigo IS NOT NULL THEN RETURN jsonb_build_object('id',v_antigo,'ja_registrado',true);END IF;
 INSERT INTO public.ew_obra_despesas(
 empresa_id,obra_id,categoria,valor,fornecedor,numero_documento,data_documento,origem,
 chave_nfe,status,observacoes,criado_por,operacao_id)
 VALUES(p_empresa_id,p_obra_id,p_categoria,p_valor,btrim(p_fornecedor),
 btrim(p_numero_documento),p_data_documento,'nfe_xml',v_chave,'pendente',coalesce(p_observacoes,''),v_uid,p_operacao_id)
 RETURNING id INTO v_id;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_item->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'valor_unitario') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_item->'valor_total') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Item da NF-e inválido.';END IF;
  v_q:=(v_item->>'quantidade')::numeric;
  v_unit:=(v_item->>'valor_unitario')::numeric;
  v_total:=(v_item->>'valor_total')::numeric;
  IF v_q<=0 OR v_q>1e9 OR v_unit<0 OR v_unit>1e9 OR v_total<0 OR v_total>1e11
  THEN RAISE EXCEPTION 'Quantidade ou preço da NF-e inválido.';END IF;
  INSERT INTO public.ew_obra_despesas_itens(
   despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,valor_total)
  VALUES(v_id,p_empresa_id,left(coalesce(v_item->>'codigo',''),120),
   left(coalesce(v_item->>'descricao',''),500),left(coalesce(v_item->>'unidade',''),30),
   v_q,v_unit,v_total);
 END LOOP;
 RETURN jsonb_build_object('id',v_id,'status','pendente','valor',p_valor,'itens',jsonb_array_length(p_itens));
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_usuario uuid:=auth.uid();
 v_origem_local text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino_local text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;
 v_unidade_acessorio text;
 v_saldo numeric;
 v_quantidade_movimentos integer;
 v_origem_codigo text;
 v_destino_codigo text;
 v_chave_origem text;
 v_chave_destino text;
 v_observacao text;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.transferir_obras');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
  NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
    WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_usuario
     AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode transferir estoque entre obras.'; END IF;

 IF p_origem_obra_id IS NULL OR p_destino_obra_id IS NULL OR
    p_origem_obra_id=p_destino_obra_id
 THEN RAISE EXCEPTION 'Selecione obras de origem e destino diferentes.'; END IF;

 SELECT codigo INTO v_origem_codigo FROM public.obras
 WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 SELECT codigo INTO v_destino_codigo FROM public.obras
 WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 IF NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_origem_obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_destino_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Obra ou estoque inexistente, de outra empresa ou arquivado.'; END IF;

 IF v_origem_local='' OR v_destino_local='' OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_origem_local AND ativo) OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_destino_local AND ativo)
 THEN RAISE EXCEPTION 'Galpão de origem ou destino inválido.'; END IF;

 SELECT v.tipo,upper(btrim(a.unidade_item))
 INTO v_tipo,v_unidade_acessorio
 FROM public.ew_materiais_variacoes v
 LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id AND a.empresa_id=p_empresa_id
 WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id AND v.ativo;
 IF v_tipo IS NULL OR p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
    (v_tipo='perfil' AND
      (p_unidade IS DISTINCT FROM 'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000
       OR p_comprimento_mm IS NULL OR p_quantidade<>trunc(p_quantidade))) OR
    (v_tipo='acessorio' AND
      (p_comprimento_mm IS NOT NULL OR
       p_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') OR
       p_unidade IS DISTINCT FROM v_unidade_acessorio OR
       p_quantidade<>round(p_quantidade,3)))
 THEN RAISE EXCEPTION 'Material, comprimento, unidade ou quantidade inválidos.'; END IF;
 IF char_length(btrim(coalesce(p_observacao,''))) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe um motivo de 5 a 350 caracteres.'; END IF;

 -- Uma mesma operação não pode ser executada em paralelo, nem reutilizada
 -- para mudar origem, destino, material ou quantidade.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'TRANSF_OBRAS|'||p_operacao_id::text,62841));
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
    WHERE m.transferencia_id=p_operacao_id AND m.empresa_id<>p_empresa_id)
 THEN RAISE EXCEPTION 'Identificador de transferência já utilizado.'; END IF;

 SELECT count(*) INTO v_quantidade_movimentos
 FROM public.ew_estoque_obras_movimentos
 WHERE transferencia_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF v_quantidade_movimentos>0 THEN
  IF v_quantidade_movimentos<>2 OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_origem_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_origem_local
      AND quantidade_delta=-p_quantidade AND origem='TRANSFERENCIA') OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_destino_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_destino_local
      AND quantidade_delta=p_quantidade AND origem='TRANSFERENCIA')
  THEN RAISE EXCEPTION 'Identificador já utilizado para outra transferência.'; END IF;
  RETURN jsonb_build_object('repetida',true,'quantidade',p_quantidade,
    'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id);
 END IF;

 -- Mesma chave de lock do estoque normal. Ordenação estável evita deadlock
 -- quando duas obras transferem materiais entre si ao mesmo tempo.
 v_chave_origem:=p_origem_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 v_chave_destino:=p_destino_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   least(v_chave_origem,v_chave_destino),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   greatest(v_chave_origem,v_chave_destino),34777));
 SELECT coalesce(sum(m.quantidade_delta),0) INTO v_saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_origem_obra_id
  AND m.variacao_id=p_variacao_id AND
  m.comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
  AND m.unidade=p_unidade AND m.local_estoque=v_origem_local;
 IF v_saldo<p_quantidade
 THEN RAISE EXCEPTION 'Saldo insuficiente na obra de origem. Disponível: % %.',v_saldo,p_unidade; END IF;

 v_observacao:='Remanejamento entre obras '||coalesce(v_origem_codigo,'—')||
  ' → '||coalesce(v_destino_codigo,'—')||' · '||btrim(p_observacao);
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 VALUES
 (p_empresa_id,p_origem_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  -p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_origem_local,p_operacao_id),
 (p_empresa_id,p_destino_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_destino_local,p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'quantidade',p_quantidade,
  'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id,
  'saldo_origem',v_saldo-p_quantidade,'comprimento_mm',p_comprimento_mm);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_obra(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;v_saldo numeric;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.transferir_galpoes');
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null or p_operacao_id is null or not exists(select 1 from public.usuarios_empresas ue
   where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and ue.perfil IN ('administrador','gerenciador'))
 then raise exception 'Somente ADM pode transferir estoque.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id and empresa_id=p_empresa_id)
 then return jsonb_build_object('repetida',true);end if;
 if v_origem=v_destino or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_origem and ativo)
   or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_destino and ativo)
 then raise exception 'Selecione galpões de origem e destino diferentes e válidos.';end if;
 if not exists(select 1 from public.ew_estoques_locais where empresa_id=p_empresa_id
   and obra_id=p_obra_id and excluido_em is null)
 then raise exception 'Estoque da obra arquivado ou inexistente.';end if;
 select tipo into v_tipo from public.ew_materiais_variacoes where id=p_variacao_id
   and empresa_id=p_empresa_id and ativo;
 if v_tipo is null or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
   or (v_tipo='perfil' and (p_unidade<>'BARRA' or p_comprimento_mm not between 100 and 20000
     or p_quantidade<>trunc(p_quantidade)))
   or (v_tipo='acessorio' and (p_comprimento_mm is not null or p_unidade not in ('PC','PR','CJ','MT','KG','UN')))
 then raise exception 'Material, comprimento ou quantidade inválidos.';end if;
 if char_length(btrim(coalesce(p_observacao,'')))<5 then raise exception 'Informe motivo da transferência.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_estoque_obras_movimentos where empresa_id=p_empresa_id and obra_id=p_obra_id
 and variacao_id=p_variacao_id and comprimento_mm is not distinct from p_comprimento_mm
 and unidade=p_unidade and local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente no galpão %. Disponível % %.',v_origem,v_saldo,p_unidade;end if;
 insert into public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
  operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 values
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,-p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_origem,p_operacao_id),
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_destino,p_operacao_id);
 return jsonb_build_object('repetida',false,'origem',v_origem,'destino',v_destino,'quantidade',p_quantidade);
end;$function$;
COMMIT;
