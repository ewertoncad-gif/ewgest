BEGIN;
-- Proposta 2: saídas de componentes com revisão congelada; não alterar documentos históricos.
ALTER TABLE public.saidas_producao
 ADD COLUMN composicao_revisao_id uuid REFERENCES ew_expedicao_interna.revisoes(id),
 ADD COLUMN componente_id text,
 ADD COLUMN componente_nome text,
 ADD COLUMN equivalente_expedido numeric;
ALTER TABLE public.saidas_producao DROP CONSTRAINT saidas_producao_tipo_check;
ALTER TABLE public.saidas_producao ADD CONSTRAINT saidas_producao_tipo_check CHECK(tipo IN ('completo','marco','folha','componente'));
ALTER TABLE public.saidas_producao ADD CONSTRAINT ew_saida_composicao_coerente CHECK (
 (composicao_revisao_id IS NULL AND tipo<>'componente' AND componente_id IS NULL AND componente_nome IS NULL AND equivalente_expedido IS NULL)
 OR (composicao_revisao_id IS NOT NULL AND equivalente_expedido>0 AND componente_nome IS NOT NULL AND
 ((tipo='completo' AND componente_id IS NULL) OR (tipo='componente' AND componente_id IS NOT NULL))));
ALTER TABLE public.romaneios_itens
 ADD COLUMN composicao_revisao_id uuid REFERENCES ew_expedicao_interna.revisoes(id),
 ADD COLUMN componente_id text,
 ADD COLUMN componente_nome text,
 ADD COLUMN equivalente_expedido numeric;
ALTER TABLE public.romaneios_itens DROP CONSTRAINT romaneios_itens_tipo_saida_check;
ALTER TABLE public.romaneios_itens ADD CONSTRAINT romaneios_itens_tipo_saida_check CHECK (
 (natureza='esquadria' AND tipo_saida IN ('completo','marco','folha','componente')) OR (natureza='material' AND tipo_saida IS NULL));
ALTER TABLE public.romaneios_itens ADD CONSTRAINT ew_romaneio_composicao_coerente CHECK (
 (composicao_revisao_id IS NULL AND tipo_saida IS DISTINCT FROM 'componente' AND componente_id IS NULL AND componente_nome IS NULL AND equivalente_expedido IS NULL)
 OR (natureza='esquadria' AND composicao_revisao_id IS NOT NULL AND equivalente_expedido>0 AND componente_nome IS NOT NULL AND
 ((tipo_saida='completo' AND componente_id IS NULL) OR (tipo_saida='componente' AND componente_id IS NOT NULL))));

CREATE OR REPLACE FUNCTION ew_expedicao_interna.estado_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $f$
DECLARE e public.esquadrias%rowtype; rev ew_expedicao_interna.revisoes%rowtype; vid uuid; ativos int; legados int; nrevs int;
 nlib bigint; mlib bigint; flib bigint; p jsonb; pid text; pq integer; peso integer;
 enviados bigint; saldo bigint; total bigint; completas bigint:=NULL; completas_env bigint:=NULL; eq numeric:=0; partes jsonb:='[]'::jsonb;
BEGIN
 SELECT * INTO e FROM public.esquadrias WHERE id=p_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT count(*),count(*) FILTER(WHERE composicao_revisao_id IS NULL),count(DISTINCT composicao_revisao_id)
 INTO ativos,legados,nrevs FROM public.saidas_producao WHERE esquadria_id=e.id AND cancelado_em IS NULL;
 IF nrevs>1 OR (legados>0 AND nrevs>0) THEN RAISE EXCEPTION 'Histórico incompatível de composições na esquadria %.',e.codigo;END IF;
 IF legados>0 THEN RETURN NULL; END IF;
 IF nrevs=1 THEN
  SELECT composicao_revisao_id INTO vid FROM public.saidas_producao WHERE esquadria_id=e.id AND cancelado_em IS NULL LIMIT 1;
  SELECT * INTO rev FROM ew_expedicao_interna.revisoes WHERE id=vid AND empresa_id=e.empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revisão histórica indisponível.'; END IF;
 ELSE
  -- Não reinterpretar faturamentos antigos sem saídas ativas.
  IF EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens i JOIN public.ew_obra_faturamentos h ON h.id=i.faturamento_id
   WHERE i.esquadria_id=e.id AND h.status='emitido') THEN RETURN NULL;END IF;
  SELECT * INTO rev FROM ew_expedicao_interna.revisoes WHERE empresa_id=e.empresa_id AND tipologia_id=e.tipologia_id ORDER BY revisao DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL;END IF;
 END IF;
 SELECT coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','marco')),0),
        coalesce(sum(quantidade) FILTER(WHERE tipo_componente IN ('completo','folhas')),0)
 INTO mlib,flib FROM public.liberacoes_corte WHERE esquadria_id=e.id AND cancelado_em IS NULL;
 nlib:=least(mlib,flib,e.quantidade);
 FOR p IN SELECT value FROM jsonb_array_elements(rev.partes) LOOP
  pid:=p->>'id'; pq:=(p->>'quantidade')::integer;peso:=(p->>'peso')::integer;
  total:=nlib*pq;
  SELECT coalesce(sum(CASE WHEN tipo='completo' THEN quantidade::bigint*pq WHEN tipo='componente' AND componente_id=pid THEN quantidade ELSE 0 END),0)
   INTO enviados FROM public.saidas_producao WHERE esquadria_id=e.id AND cancelado_em IS NULL AND composicao_revisao_id=rev.id;
  IF enviados>total THEN RAISE EXCEPTION 'Saldo de componentes inconsistente na esquadria %.',e.codigo;END IF;
  saldo:=total-enviados;
  completas:=least(coalesce(completas,saldo/pq),saldo/pq);
  completas_env:=least(coalesce(completas_env,enviados/pq),enviados/pq);
  eq:=eq+enviados::numeric*peso/(10000::numeric*pq);
  partes:=partes||jsonb_build_array(p||jsonb_build_object('saldo',saldo,'enviado',enviados,'total',total));
 END LOOP;
 RETURN jsonb_build_object('esquadria_id',e.id,'revisao_id',rev.id,'revisao',rev.revisao,'partes',partes,'liberadas',nlib,
 'completas_disponiveis',completas,'completas_enviadas',completas_env,'equivalente_expedido',eq);
END;$f$;
REVOKE ALL ON FUNCTION ew_expedicao_interna.estado_item(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_composicoes_obra(p_empresa_id uuid,p_obra_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT (public.ew_pode(p_empresa_id,'obras.consultar') OR public.ew_pode(p_empresa_id,'romaneios.consultar') OR public.ew_pode(p_empresa_id,'romaneios.emitir') OR public.ew_pode(p_empresa_id,'financeiro.consultar')) THEN RAISE EXCEPTION 'Sem permissão de expedição.';END IF;
 IF p_obra_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Obra indisponível.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(x.estado),'[]'::jsonb) FROM (
 SELECT ew_expedicao_interna.estado_item(e.id) AS estado
 FROM public.esquadrias e JOIN public.obras o ON o.id=e.obra_id AND o.empresa_id=e.empresa_id
 WHERE e.empresa_id=p_empresa_id AND o.arquivada_em IS NULL AND (p_obra_id IS NULL OR e.obra_id=p_obra_id)
 AND (EXISTS(SELECT 1 FROM public.saidas_producao s WHERE s.esquadria_id=e.id AND s.cancelado_em IS NULL AND s.composicao_revisao_id IS NOT NULL)
 OR (p_obra_id IS NOT NULL AND EXISTS(SELECT 1 FROM ew_expedicao_interna.revisoes r WHERE r.empresa_id=e.empresa_id AND r.tipologia_id=e.tipologia_id)))
 ) x WHERE x.estado IS NOT NULL);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_composicoes_obra(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_composicoes_obra(uuid,uuid) TO authenticated;

-- Interno, acessível somente pelo emissor autenticado e validado.
CREATE OR REPLACE FUNCTION ew_expedicao_interna.registrar_saida(p_id uuid,p_esquadria uuid,p_tipo text,p_qtd integer,p_data date,p_revisao uuid,p_componente text)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $f$
DECLARE e public.esquadrias%rowtype; est jsonb; p jsonb; eq numeric; nome text; u uuid:=auth.uid();
BEGIN
 SELECT * INTO e FROM public.esquadrias WHERE id=p_esquadria FOR UPDATE;
 IF NOT FOUND OR u IS NULL OR NOT public.ew_pode(e.empresa_id,'romaneios.emitir') OR NOT EXISTS(
 SELECT 1 FROM public.romaneios h WHERE h.id::text=pg_catalog.current_setting('ewgest.romaneio_emissao_id',true)
 AND h.empresa_id=e.empresa_id AND h.obra_id=e.obra_id AND h.criado_por=u AND h.status='emitido'
 AND h.criado_em=pg_catalog.transaction_timestamp()) THEN RAISE EXCEPTION 'Saída deve pertencer ao romaneio em emissão.';END IF;
 IF p_id IS NULL OR p_qtd NOT BETWEEN 1 AND 100000 OR p_data IS NULL OR p_data<date '2000-01-01' OR p_data>current_date
 OR p_revisao IS NULL OR p_tipo NOT IN ('completo','componente') THEN RAISE EXCEPTION 'Saída inválida.';END IF;
 IF EXISTS(SELECT 1 FROM public.liberacoes_corte l WHERE l.esquadria_id=e.id AND l.cancelado_em IS NULL)
  AND p_data<(SELECT min(data_liberacao) FROM public.liberacoes_corte WHERE esquadria_id=e.id AND cancelado_em IS NULL)
 THEN RAISE EXCEPTION 'Data de saída anterior à liberação.';END IF;
 -- Evita que uma nova revisão seja salva entre conferência e emissão.
 PERFORM 1 FROM public.tipologias WHERE id=e.tipologia_id AND empresa_id=e.empresa_id FOR SHARE;
 est:=ew_expedicao_interna.estado_item(e.id);
 IF est IS NULL OR (est->>'revisao_id')::uuid IS DISTINCT FROM p_revisao THEN RAISE EXCEPTION 'Composição alterada ou incompatível. Atualize o romaneio.';END IF;
 IF p_tipo='completo' THEN
  IF p_componente IS NOT NULL OR p_qtd>(est->>'completas_disponiveis')::bigint THEN RAISE EXCEPTION 'Saldo insuficiente de esquadrias completas.'; END IF;
  eq:=p_qtd; nome:='Esquadria completa';
 ELSE
  SELECT value INTO p FROM jsonb_array_elements(est->'partes') WHERE value->>'id'=p_componente;
  IF p IS NULL OR p_qtd>(p->>'saldo')::bigint THEN RAISE EXCEPTION 'Componente inválido ou saldo insuficiente.';END IF;
  eq:=p_qtd::numeric*(p->>'peso')::integer/(10000::numeric*(p->>'quantidade')::integer);nome:=p->>'nome';
 END IF;
 INSERT INTO public.saidas_producao(id,esquadria_id,tipo,quantidade,data_saida,usuario_id,composicao_revisao_id,componente_id,componente_nome,equivalente_expedido)
 VALUES(p_id,e.id,p_tipo,p_qtd,p_data,u,p_revisao,p_componente,nome,eq);
 RETURN jsonb_build_object('equivalente',eq,'nome',nome);
END;$f$;
REVOKE ALL ON FUNCTION ew_expedicao_interna.registrar_saida(uuid,uuid,text,integer,date,uuid,text) FROM PUBLIC,anon,authenticated;

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
 v_rev uuid;v_comp text;v_comp_nome text;v_equiv numeric;v_comp_result jsonb;
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
   v_rev:=NULL;v_comp:=NULL;v_comp_nome:=NULL;v_equiv:=NULL;
   IF v_kind='esquadria' THEN
     v_tipo_saida:=coalesce(nullif(v_line->>'tipo_saida',''),'completo');
     v_rev:=nullif(v_line->>'composicao_revisao_id','')::uuid;
     v_comp:=nullif(v_line->>'componente_id','');
     IF v_tipo_saida NOT IN ('completo','marco','folha','componente') OR
        (v_tipo_saida='componente' AND (v_rev IS NULL OR v_comp IS NULL)) OR
        (v_rev IS NOT NULL AND v_tipo_saida NOT IN ('completo','componente')) OR
        (v_tipo_saida<>'componente' AND v_comp IS NOT NULL) THEN
       RAISE EXCEPTION 'Tipo de saída inválido no item %.',v_num;
     END IF;
     IF NULLIF(v_line->>'esquadria_id','') IS NULL THEN
       RAISE EXCEPTION 'Selecione a esquadria no item %.',v_num;
     END IF;
     v_id:=(v_line->>'esquadria_id')::uuid;
     IF EXISTS(SELECT 1 FROM public.romaneios_itens
       WHERE romaneio_id=v_rom.id AND esquadria_id=v_id AND tipo_saida=v_tipo_saida AND componente_id IS NOT DISTINCT FROM v_comp) THEN
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
     IF v_rev IS NULL AND ((v_per IS NOT NULL AND v_per NOT BETWEEN 1 AND 12)
       OR (v_tipo_saida<>'completo' AND v_per IS NULL)) THEN
       RAISE EXCEPTION 'Confirme folhas por unidade somente para saída de marco/folha (item %).',v_num;
     END IF;
     v_ship:=gen_random_uuid();
     IF v_rev IS NOT NULL THEN
       v_comp_result:=ew_expedicao_interna.registrar_saida(v_ship,v_id,v_tipo_saida,v_qty,p_data_saida,v_rev,v_comp);
       v_equiv:=(v_comp_result->>'equivalente')::numeric;v_comp_nome:=v_comp_result->>'nome';
     ELSE
       PERFORM public.registrar_saida_producao(v_ship,v_id,v_tipo_saida,v_qty,p_data_saida,v_per);
     END IF;
     v_code:=v_item.codigo;
     v_location:=coalesce(v_item.localizacao,'');
     v_desc:=case v_tipo_saida when 'marco' then 'MARCO — '
             when 'folha' then 'FOLHA — ' when 'componente' then v_comp_nome||' — ' else '' end ||
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
     IF v_tipo_saida='completo' AND v_rev IS NULL AND v_factory IS NOT NULL AND NOT EXISTS(
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
     v_area:=CASE WHEN v_rev IS NOT NULL THEN round(v_item.largura_mm::numeric*v_item.altura_mm::numeric*v_equiv/1000000,3)
       ELSE case v_tipo_saida
       when 'completo' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/1000000.0)::numeric,3)
       when 'marco' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/2000000.0)::numeric,3)
       when 'folha' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/(2000000.0*v_per))::numeric,3)
       else null end END;
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
    codigo,localizacao,descricao,medida,quantidade,unidade,area_m2,fabrica,prazo_liberacao_saida_dias,tipo_saida,descricao_impressao_definida,composicao_revisao_id,componente_id,componente_nome,equivalente_expedido)
   VALUES(v_rom.id,v_num,v_kind,v_id,v_ship,v_code,v_location,v_desc,v_measure,v_qty,v_unit,v_area,v_factory,v_mean,v_tipo_saida,v_desc_definida,v_rev,v_comp,v_comp_nome,v_equiv)
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
 -- A composição não pode perder lastro para faturamentos ativos.
 IF EXISTS(SELECT 1 FROM public.romaneios_itens ri JOIN public.ew_obra_faturamentos_itens fi ON fi.esquadria_id=ri.esquadria_id
 JOIN public.ew_obra_faturamentos f ON f.id=fi.faturamento_id
 WHERE ri.romaneio_id=p_romaneio_id AND ri.composicao_revisao_id IS NOT NULL AND f.status='emitido')
 THEN RAISE EXCEPTION 'Estorne os faturamentos ativos das esquadrias deste romaneio antes de cancelar a expedição por componentes.'; END IF;
 SELECT count(*) INTO v_expected FROM public.romaneios_itens ri
 WHERE ri.romaneio_id=p_romaneio_id AND ri.natureza='esquadria';
 IF EXISTS(
  SELECT 1 FROM public.romaneios_itens ri
  LEFT JOIN public.saidas_producao s ON s.id=ri.saida_producao_id
  WHERE ri.romaneio_id=p_romaneio_id AND ri.natureza='esquadria'
    AND (s.id IS NULL OR s.cancelado_em IS NOT NULL OR s.esquadria_id IS DISTINCT FROM ri.esquadria_id
      OR s.tipo IS DISTINCT FROM ri.tipo_saida OR s.quantidade IS DISTINCT FROM ri.quantidade
      OR s.composicao_revisao_id IS DISTINCT FROM ri.composicao_revisao_id OR s.componente_id IS DISTINCT FROM ri.componente_id OR s.equivalente_expedido IS DISTINCT FROM ri.equivalente_expedido)
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
COMMIT;
