-- Apenas pares físicos completos, com identidade, empresa e quantidade verificadas.
-- Pares ausentes ou inconsistentes não autorizam apropriação. Não remove pendências.
CREATE OR REPLACE VIEW ew_compras_interna.transferencias_fisicas_custo WITH (security_invoker=true) AS
WITH movimentos AS (
 SELECT empresa_id,id,'OBRA'::text tipo,obra_id local_id,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,local_estoque galpao,quantidade_delta,origem,transferencia_id,estorno_de_id,criado_em
 FROM public.ew_estoque_obras_movimentos
 UNION ALL
 SELECT empresa_id,id,'EMPRESA',local_empresa_id,'TECNICO',variacao_id,comprimento_mm,unidade,galpao,quantidade_delta,origem,transferencia_id,estorno_de_id,criado_em
 FROM public.ew_compras_estoque_empresa
 UNION ALL
 SELECT m.empresa_id,m.id,'OBRA',m.obra_id,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.local_estoque,m.quantidade_delta,m.origem,m.transferencia_id,m.estorno_de_id,m.criado_em
 FROM public.ew_insumos_movimentos m JOIN public.ew_insumos_catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id
), pares AS (
 SELECT a.empresa_id,CASE a.tipo_material WHEN 'INSUMO' THEN 'INSUMOS' ELSE 'OBRAS' END fluxo,a.transferencia_id,a.id origem_movimento_id,b.id destino_movimento_id,
 NULL::boolean estornado_registro
 FROM movimentos a JOIN movimentos b ON b.empresa_id=a.empresa_id AND b.transferencia_id=a.transferencia_id
 AND b.tipo_material=a.tipo_material AND b.tipo='OBRA' AND (b.local_id,b.galpao)<>(a.local_id,a.galpao)
 AND b.origem='TRANSFERENCIA' AND b.quantidade_delta>0
 WHERE a.tipo='OBRA' AND a.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND a.transferencia_id IS NOT NULL
 AND (SELECT count(*) FROM movimentos k WHERE k.empresa_id=a.empresa_id AND k.transferencia_id=a.transferencia_id AND k.tipo_material=a.tipo_material AND k.tipo='OBRA' AND k.origem='TRANSFERENCIA')=2
 UNION ALL
 SELECT t.empresa_id,'LOCAIS',t.id,coalesce(t.movimento_origem_obra_id,t.movimento_origem_empresa_id),
 coalesce(t.movimento_destino_obra_id,t.movimento_destino_empresa_id),t.estornado_em IS NOT NULL
 FROM public.ew_compras_transferencias t WHERE t.origem_tipo='OBRA' OR t.destino_tipo='OBRA'
), verificadas AS (
 SELECT p.empresa_id,p.fluxo,p.transferencia_id,a.id origem_movimento_id,b.id destino_movimento_id,
 a.tipo origem_tipo,a.local_id origem_id,a.galpao origem_galpao,b.tipo destino_tipo,b.local_id destino_id,b.galpao destino_galpao,
 a.tipo_material,a.material_id,a.comprimento_mm,a.unidade,-a.quantidade_delta quantidade,a.criado_em,
 a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=a.empresa_id AND z.tipo=a.tipo AND z.tipo_material=a.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=a.id OR (a.tipo='OBRA' AND a.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=a.empresa_id AND ep.obra_id=a.local_id AND ep.movimento_original_id=a.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_origem,
 b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=b.empresa_id AND z.tipo=b.tipo AND z.tipo_material=b.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=b.id OR (b.tipo='OBRA' AND b.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=b.empresa_id AND ep.obra_id=b.local_id AND ep.movimento_original_id=b.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_destino,
 p.estornado_registro
 FROM pares p JOIN movimentos a ON a.empresa_id=p.empresa_id AND a.id=p.origem_movimento_id
 JOIN movimentos b ON b.empresa_id=p.empresa_id AND b.id=p.destino_movimento_id
 WHERE a.origem='TRANSFERENCIA' AND b.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND b.quantidade_delta=-a.quantidade_delta
 AND a.tipo_material=b.tipo_material AND a.material_id=b.material_id AND a.comprimento_mm IS NOT DISTINCT FROM b.comprimento_mm
 AND a.unidade=b.unidade AND (a.tipo,a.local_id,a.galpao)<>(b.tipo,b.local_id,b.galpao)
 AND (p.fluxo<>'LOCAIS' OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.empresa_id=p.empresa_id AND t.id=p.transferencia_id
 AND t.origem_tipo=a.tipo AND t.origem_id=a.local_id AND t.origem_galpao=a.galpao AND t.destino_tipo=b.tipo AND t.destino_id=b.local_id AND t.destino_galpao=b.galpao
 AND t.variacao_id=a.material_id AND t.comprimento_mm IS NOT DISTINCT FROM a.comprimento_mm AND t.unidade=a.unidade AND t.quantidade=-a.quantidade_delta))
)
SELECT v.*,CASE WHEN saldo_origem=-quantidade AND saldo_destino=quantidade AND estornado_registro IS DISTINCT FROM true THEN 'ATIVA'
 WHEN saldo_origem=0 AND saldo_destino=0 AND estornado_registro IS DISTINCT FROM false THEN 'ESTORNADA'
 ELSE 'INCONSISTENTE' END estado
FROM verificadas v;
REVOKE ALL ON ew_compras_interna.transferencias_fisicas_custo FROM PUBLIC,anon,authenticated;

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
 IF NOT (public.ew_pode(p_empresa_id,'estoque.estornar')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid)
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
 perform ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'INSUMOS',v_saida.transferencia_id,v_op);
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$function$;

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
 IF v_original.transferencia_id IS NOT NULL THEN
  PERFORM ew_compras_interna.custo_estornar_se_integrada(v_obra.empresa_id,'OBRAS',v_original.transferencia_id,p_operacao_id);
 END IF;
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
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
 IF NOT (public.ew_pode(p_empresa_id,case when p_origem_obra_id=p_destino_obra_id then 'estoque.transferir_galpoes' else 'estoque.transferir_obras' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
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
 perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'INSUMOS',v_transfer);
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$function$;

CREATE OR REPLACE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid, p_fluxo text, p_transferencia uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE t record; x record; ev record; l uuid; f uuid; al jsonb; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF NOT public.ew_pode(p_empresa,CASE WHEN (t.origem_tipo,t.origem_id)=(t.destino_tipo,t.destino_id) THEN 'estoque.transferir_galpoes' ELSE 'estoque.transferir_obras' END) THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 IF t.estado<>'ATIVA' THEN RAISE EXCEPTION 'Transferência física inválida'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
 IF al IS NULL THEN
  IF (t.origem_tipo,t.origem_id)=(t.destino_tipo,t.destino_id) THEN RETURN false; END IF;
  -- Legado: somente primeira transferência com origem inequívoca.
  SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
  l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
  al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
  IF al IS NULL THEN RAISE EXCEPTION 'Histórico de custo não conciliado'; END IF;
 END IF;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,al,uid);
 RETURN true;
END;$function$;

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
   where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and public.ew_pode(p_empresa_id,'estoque.transferir_galpoes'))
 then raise exception 'Somente ADM pode transferir estoque.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('TRANSF_OBRAS|'||p_operacao_id::text,62841));
 if exists(select 1 from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id) then
 if (select count(*) from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id)<>2
 or not exists(select 1 from public.ew_estoque_obras_movimentos m where m.transferencia_id=p_operacao_id and m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm and m.unidade=p_unidade and m.local_estoque=v_origem and m.quantidade_delta=-p_quantidade and m.origem='TRANSFERENCIA')
 or not exists(select 1 from public.ew_estoque_obras_movimentos m where m.transferencia_id=p_operacao_id and m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm and m.unidade=p_unidade and m.local_estoque=v_destino and m.quantidade_delta=p_quantidade and m.origem='TRANSFERENCIA')
 then raise exception 'Identificador já utilizado para outra transferência.';end if;
 return jsonb_build_object('repetida',true);end if;
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
 perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'OBRAS',p_operacao_id);
 return jsonb_build_object('repetida',false,'origem',v_origem,'destino',v_destino,'quantidade',p_quantidade);
end;$function$;
REVOKE ALL ON FUNCTION public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) TO authenticated;