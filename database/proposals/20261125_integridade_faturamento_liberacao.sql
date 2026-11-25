-- Faturamento e liberação: somente rotinas validadas, sem alterar flags.
CREATE OR REPLACE FUNCTION public.ew_registrar_faturamento_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_data_faturamento date, p_numero_documento text, p_observacoes text, p_itens jsonb, p_operacao_id uuid, p_instalacao_confirmada boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
 v_area_unit numeric; v_area_m2 numeric; v_preco_m2 numeric; v_area_faturada numeric;
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
 IF NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=p_empresa_id AND o.arquivada_em IS NULL FOR SHARE) THEN RAISE EXCEPTION 'Obra não encontrada ou arquivada.';END IF;
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
 IF v_antigo IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM public.ew_obra_faturamentos WHERE id=v_antigo AND empresa_id=p_empresa_id AND obra_id=p_obra_id AND categoria=p_categoria AND status='emitido') THEN RAISE EXCEPTION 'Identificador de faturamento já utilizado ou cancelado.'; END IF;
 RETURN jsonb_build_object('id',v_antigo,'ja_registrado',true);END IF;
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
  v_area_unit:=v_esquadria.largura_mm::numeric*v_esquadria.altura_mm::numeric/1000000;
  SELECT coalesce(sum(fi.quantidade),0),coalesce(sum(coalesce(fi.area_m2,fi.quantidade*v_area_unit)),0) INTO v_total_invoiced,v_area_faturada
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
    AND ri.natureza='esquadria' AND ri.tipo_saida='folha' AND ri.composicao_revisao_id IS NULL
    AND (cfg.folhas_por_unidade IS NULL OR cfg.folhas_por_unidade NOT BETWEEN 1 AND 12)
  ) THEN
   RAISE EXCEPTION 'Composição física das folhas não cadastrada para %.',v_esquadria.codigo;
  END IF;
  SELECT coalesce(sum(
    CASE WHEN ri.composicao_revisao_id IS NOT NULL THEN ri.equivalente_expedido ELSE CASE ri.tipo_saida
     WHEN 'completo' THEN ri.quantidade::numeric
     WHEN 'marco' THEN ri.quantidade::numeric/2
     WHEN 'folha' THEN ri.quantidade::numeric/(2*cfg.folhas_por_unidade)
     ELSE 0 END END
  ),0) INTO v_shipped
  FROM public.romaneios_itens ri
  JOIN public.romaneios rr ON rr.id=ri.romaneio_id
  LEFT JOIN public.esquadrias_saida_config cfg ON cfg.esquadria_id=ri.esquadria_id
  WHERE ri.esquadria_id=v_esquadria.id AND rr.empresa_id=p_empresa_id
   AND rr.obra_id=p_obra_id AND rr.status='emitido' AND rr.cancelado_em IS NULL
   AND ri.natureza='esquadria';
  IF NOT (v_item ? 'area_m2' OR v_item ? 'preco_m2') AND
     (v_total_invoiced+v_quantidade>v_esquadria.quantidade OR v_total_invoiced+v_quantidade>v_shipped
      OR round(v_area_faturada+v_quantidade*v_area_unit,6)>round(least(v_shipped,v_esquadria.quantidade)*v_area_unit,6)) THEN
    RAISE EXCEPTION 'Quantidade equivalente não faturável de %: confira saídas ativas e histórico de %.',
      v_esquadria.codigo,p_categoria;
  END IF;
  IF v_item ? 'area_m2' OR v_item ? 'preco_m2' THEN
   IF jsonb_typeof(v_item->'area_m2') IS DISTINCT FROM 'number' OR jsonb_typeof(v_item->'preco_m2') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Informe área e preço por m².'; END IF;
   v_area_m2:=(v_item->>'area_m2')::numeric; v_preco_m2:=(v_item->>'preco_m2')::numeric;
   IF v_area_unit<=0 OR v_area_m2<=0 OR v_area_m2<>round(v_area_m2,6) OR v_preco_m2<=0 OR v_preco_m2>100000000 OR v_preco_m2<>round(v_preco_m2,4)
     OR abs(v_area_m2-v_quantidade*v_area_unit)>greatest(0.000001,v_area_unit*0.0000005)
     OR round(v_area_faturada+v_area_m2,6)>round(least(v_shipped,v_esquadria.quantidade)*v_area_unit,6)
     OR v_unit<>round(v_preco_m2*v_area_unit,4)
   THEN RAISE EXCEPTION 'Área ou preço por m² incompatível com as dimensões e saldo expedido de %.',v_esquadria.codigo; END IF;
   v_line:=round(v_area_m2*v_preco_m2,2);
  ELSE v_line:=round(v_quantidade*v_unit,2); END IF;
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
   faturamento_id,empresa_id,esquadria_id,quantidade,valor_unitario,valor_total,area_m2,preco_m2)
  VALUES(v_id,p_empresa_id,(v_item->>'esquadria_id')::uuid,
   v_quantidade,v_unit,CASE WHEN v_item ? 'area_m2' THEN round((v_item->>'area_m2')::numeric*(v_item->>'preco_m2')::numeric,2) ELSE round(v_quantidade*v_unit,2) END,
   (v_item->>'area_m2')::numeric,(v_item->>'preco_m2')::numeric);
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
 if v_tipo<>'completo'
 then raise exception 'A liberação deve ser da esquadria completa.';end if;
 if v_fabrica<>'' and v_fabrica not in ('AFOGADOS','IMBIRIBEIRA')
 then raise exception 'Fábrica inválida.';end if;
 select * into v_e from public.esquadrias where id=p_esquadria_id for update;
 if not found then raise exception 'Esquadria não encontrada.';end if;
 if not exists(select 1 from public.usuarios_empresas ue where ue.usuario_id=v_uid
   and ue.empresa_id=v_e.empresa_id and public.ew_pode(v_e.empresa_id,'liberacoes.criar'))
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

REVOKE INSERT,UPDATE,DELETE ON public.ew_obra_faturamentos,public.ew_obra_faturamentos_itens FROM authenticated,anon,PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ew_registrar_faturamento_financeiro(uuid,uuid,text,date,text,text,jsonb,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_registrar_faturamento_financeiro(uuid,uuid,text,date,text,text,jsonb,uuid,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_contadores_esquadria() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF current_user IN ('authenticated','anon') THEN
 IF TG_OP='INSERT' THEN
 IF coalesce(NEW.qtd_liberada,0)<>0 OR coalesce(NEW.qtd_fabricada,0)<>0 THEN RAISE EXCEPTION 'Contadores de produção somente por operações do sistema.';END IF;
 ELSE
 IF (NEW.qtd_liberada,NEW.qtd_fabricada) IS DISTINCT FROM (OLD.qtd_liberada,OLD.qtd_fabricada) THEN RAISE EXCEPTION 'Contadores de produção somente por operações do sistema.';END IF;
 END IF;
 END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_contadores_esquadria() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_contadores_producao_guard BEFORE INSERT OR UPDATE ON public.esquadrias FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_contadores_esquadria();
