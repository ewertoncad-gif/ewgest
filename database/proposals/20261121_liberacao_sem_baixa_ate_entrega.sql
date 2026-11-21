-- EWGEST #38 — a liberação técnica APENAS planeja/imprime; não consome estoque.
-- Somente a confirmação física do almoxarifado poderá debitar materiais.
-- Liberações históricas que já geraram baixa permanecem intocadas; a consulta
-- de pendentes da próxima migração as exclui para evitar baixa duplicada.
alter table public.ew_planos_liberados
 add column if not exists entregue_em timestamptz,
 add column if not exists entregue_por uuid references auth.users(id),
 add column if not exists entrega_operacao_id uuid;
alter table public.ew_liberacoes_lotes
 add column if not exists entregue_em timestamptz,
 add column if not exists entregue_por uuid references auth.users(id),
 add column if not exists entrega_operacao_id uuid;
create unique index if not exists ew_planos_entrega_op_unico on public.ew_planos_liberados(entrega_operacao_id) where entrega_operacao_id is not null;
create unique index if not exists ew_lotes_entrega_op_unico on public.ew_liberacoes_lotes(entrega_operacao_id) where entrega_operacao_id is not null;

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
end;$function$
;

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
END;$function$
;
