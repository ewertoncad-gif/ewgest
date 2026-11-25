-- Estorno de entradas independentes e transferências internas: dependência física do material.
BEGIN;
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
   and public.ew_pode(v_obra.empresa_id,'estoque.estornar')
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
 -- Fluxos vinculados devem reverter a operação completa, não apenas a perna física.
 if exists(select 1 from public.ew_compras_recebimentos_movimentos x where x.movimento_obra_id=v_original.id) then
  raise exception 'Movimento vinculado a pedido de compra. Estorne o recebimento do pedido.';
 end if;
 if exists(select 1 from public.ew_compras_transferencias t where t.movimento_origem_obra_id=v_original.id or t.movimento_destino_obra_id=v_original.id) then
  raise exception 'Movimento vinculado a transferência de local empresarial. Estorne a transferência completa.';
 end if;
 -- Entradas independentes e transferências internas dependem do material,
 -- não de liberações gerais. Baixas negativas avulsas preservam guardas antigos.
 if v_original.quantidade_delta<0 and v_original.transferencia_id is null then
  v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
  if exists (
   select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
   where x.motivo not like 'Estorne as movimentações do estoque%'
  ) then
   raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
  end if;
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
    AND (EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
      WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
       AND other.obra_id<>m.obra_id) OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.movimento_origem_obra_id=m.id AND t.estornado_em IS NULL))
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
COMMIT;
