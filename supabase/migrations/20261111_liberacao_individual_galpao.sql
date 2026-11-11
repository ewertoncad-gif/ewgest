-- Ajusta liberação individual para dar baixa no galpão explicitamente escolhido.
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
 IF v_usuario IS NULL OR p_operacao_id IS NULL THEN RAISE EXCEPTION 'Sessão ou operação inválida.';END IF;
 SELECT id INTO v_op FROM public.ew_planos_liberados WHERE operacao_id=p_operacao_id;
 IF FOUND THEN RETURN jsonb_build_object('plano_id',v_op,'repetida',true);END IF;
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria não encontrada.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_usuario
     AND ue.empresa_id=v_item.empresa_id AND ue.perfil IN ('administrador','supervisor'))
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
 FOR v_entrada IN SELECT value FROM jsonb_array_elements(p_materiais) LOOP
   v_variacao:=(v_entrada->>'variacao_id')::uuid;
   v_length:=nullif(v_entrada->>'comprimento_mm','')::integer;
   v_unidade:=v_entrada->>'unidade';
   v_local:=upper(btrim(coalesce(nullif(v_entrada->>'local_estoque',''),'IMBIRIBEIRA')));
   if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=v_item.empresa_id and l.nome=v_local and l.ativo) then raise exception 'Local físico inválido para material.';end if;
   v_quantidade:=(v_entrada->>'quantidade')::numeric;
   PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
     v_item.obra_id::text||'|'||v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unidade,34777));
   SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo
   FROM public.ew_estoque_obras_movimentos
   WHERE obra_id=v_item.obra_id AND empresa_id=v_item.empresa_id
     AND variacao_id=v_variacao AND comprimento_mm IS NOT DISTINCT FROM v_length
     AND unidade=v_unidade AND local_estoque=v_local;
   IF v_saldo<v_quantidade THEN RAISE EXCEPTION
     'Estoque insuficiente para material %. Disponível % %, solicitado % %.',
     v_variacao,v_saldo,v_unidade,v_quantidade,v_unidade;END IF;
   INSERT INTO public.ew_estoque_obras_movimentos
     (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
      origem,liberacao_id,operacao_id,observacao,usuario_id,local_estoque)
   VALUES(v_item.empresa_id,v_item.obra_id,v_variacao,v_length,v_unidade,-v_quantidade,
      'PLANO_CORTE',v_liberacao,pg_catalog.gen_random_uuid(),
      'Baixa confirmada na liberação '||v_liberacao::text,v_usuario,v_local);
 END LOOP;
 RETURN v_result||jsonb_build_object('plano_id',v_op,'linhas_baixadas',v_materiais_count,'repetida',false);
END;$function$
;
