-- Snapshot de produção PRÉ v46.17. Somente restaurar antes de criar movimentos diretos, ou após análise de compatibilidade.
CREATE OR REPLACE FUNCTION public.cancelar_romaneio_com_estorno(p_romaneio_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_header public.romaneios%rowtype;
 v_expected integer;v_updated integer;
 v_motivo text:=btrim(coalesce(p_motivo,''));
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_romaneio_id IS NULL THEN RAISE EXCEPTION 'Entre no EWGEST e escolha um romaneio.'; END IF;
 IF length(v_motivo) NOT BETWEEN 10 AND 400 THEN
  RAISE EXCEPTION 'Informe um motivo de cancelamento com 10 a 400 caracteres.';
 END IF;
 SELECT * INTO v_header FROM public.romaneios WHERE id=p_romaneio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Romaneio não encontrado.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=v_header.empresa_id AND ue.usuario_id=v_uid AND ue.perfil IN ('administrador','gerenciador')) THEN
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
 UPDATE public.romaneios SET status='cancelado',cancelado_em=now(),
  cancelado_por=v_uid,motivo_cancelamento=v_motivo WHERE id=p_romaneio_id;
 RETURN pg_catalog.jsonb_build_object('id',p_romaneio_id,'numero',v_header.numero,
  'status','cancelado','saidas_estornadas',v_updated,'historico_preservado',true);
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
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_chave_operacao IS NULL OR p_obra_id IS NULL THEN
  RAISE EXCEPTION 'Faça login e informe a obra e a operação.';
 END IF;
 SELECT * INTO v_work FROM public.obras WHERE id=p_obra_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Obra inexistente.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
    AND ue.empresa_id=v_work.empresa_id AND ue.perfil IN ('administrador','gerenciador','supervisor','almoxarife')
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
     v_tipo_saida:=NULL;
     IF length(v_desc) NOT BETWEEN 2 AND 350 THEN
       RAISE EXCEPTION 'Informe descrição do material no item %.',v_num;
     END IF;
     v_area:=NULL;
   END IF;
   INSERT INTO public.romaneios_itens(romaneio_id,sequencia,natureza,esquadria_id,saida_producao_id,
    codigo,localizacao,descricao,medida,quantidade,unidade,area_m2,fabrica,prazo_liberacao_saida_dias,tipo_saida,descricao_impressao_definida)
   VALUES(v_rom.id,v_num,v_kind,v_id,v_ship,v_code,v_location,v_desc,v_measure,v_qty,v_unit,v_area,v_factory,v_mean,v_tipo_saida,v_desc_definida);
   v_total:=v_total+v_qty;
 END LOOP;
 RETURN pg_catalog.jsonb_build_object('id',v_rom.id,'numero',v_rom.numero,
    'repetido',false,'itens',v_num,'quantidade_total',v_total);
END;$function$;
