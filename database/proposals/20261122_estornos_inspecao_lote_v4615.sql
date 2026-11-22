-- EWGEST v46.15: conferência coerente com contrapartidas e devoluções.
-- PROPOSTA para homologação, não aplicada em produção.
-- Hashes de referência no banco antes da alteração:
-- ew_inspecionar_reversao_obra = 38e1e982224ef7dd6aa0880991b884f1
-- ew_estornar_estoque_obra = 59b0beced1da8c1bd87b2fef8e1da630
BEGIN;
CREATE OR REPLACE FUNCTION public.ew_inspecionar_reversao_obra(p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_obra public.obras%rowtype;v_uid uuid:=auth.uid();
 v_n_esq int;v_lib int;v_lib_cancel int;v_lotes int;v_planos int;
 v_rom int;v_rom_cancel int;v_saida int;v_saida_cancel int;
 v_mov int;v_mov_abertos int;v_fabr int;v_liberadas int;v_refs int;
 v_saldos int;v_insumos_saldos int;v_conciliadas int:=0;v_conciliadas_nf int:=0;v_motivos text[]:=array[]::text[];
begin
 perform public.ew_exigir_sessao_atual();
 select * into v_obra from public.obras where id=p_obra_id;
 if not found then raise exception 'Obra não encontrada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.empresa_id=v_obra.empresa_id and ue.usuario_id=v_uid
   and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
   and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem conferir reversões.';end if;
 select count(*),coalesce(sum(e.qtd_liberada),0),coalesce(sum(e.qtd_fabricada),0)
 into v_n_esq,v_liberadas,v_fabr from public.esquadrias e where e.obra_id=p_obra_id;
 select count(*) filter(where l.cancelado_em is null),
 count(*) filter(where l.cancelado_em is not null)
 into v_lib,v_lib_cancel from public.liberacoes_corte l
 join public.esquadrias e on e.id=l.esquadria_id where e.obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
 where obra_id=p_obra_id and cancelado_em is null;
 select count(*) into v_planos from public.ew_planos_liberados p
 left join public.liberacoes_corte l on l.id=p.liberacao_id
 where p.obra_id=p_obra_id and (l.id is null or l.cancelado_em is null);
 select count(*) filter(where status<>'cancelado'),
 count(*) filter(where status='cancelado')
 into v_rom,v_rom_cancel from public.romaneios where obra_id=p_obra_id;
 select count(*) filter(where s.cancelado_em is null),
 count(*) filter(where s.cancelado_em is not null)
 into v_saida,v_saida_cancel from public.saidas_producao s
 join public.esquadrias e on e.id=s.esquadria_id where e.obra_id=p_obra_id;
 select count(*),
 count(*) filter(where m.origem<>'ESTORNO' and m.estorno_de_id is null
  and not exists(select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id))
 into v_mov,v_mov_abertos from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id;
 select count(*) into v_saldos from (
  select m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
  from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
  group by 1,2,3,4 having sum(m.quantidade_delta)<>0
 ) saldo;
 select count(*) into v_insumos_saldos from (
  select m.insumo_id,m.local_estoque from public.ew_insumos_movimentos m
  where m.empresa_id=v_obra.empresa_id and m.obra_id=p_obra_id
  group by m.insumo_id,m.local_estoque having sum(m.quantidade_delta)<>0
 ) x;
 select count(*) into v_refs from (
  select a.id from public.classificacoes_tipologias_auditoria a
   join public.esquadrias e on e.id=a.esquadria_referencia_id
   where e.obra_id=p_obra_id and a.obra_id<>p_obra_id
  union all
  select r.id from public.esquadrias_descricoes_revisoes r
   join public.esquadrias e on e.id=r.esquadria_referencia_id
   where e.obra_id=p_obra_id and r.obra_id<>p_obra_id
 ) xs;
 -- Transferências internas históricas ficam conciliadas quando todas as NF-e
 -- físicas foram estornadas e o saldo em cada galpão já é exatamente zero.
 v_conciliadas_nf:=public.ew_transferencias_nfe_conciliadas(p_obra_id);
 v_conciliadas:=v_conciliadas_nf;
 IF v_conciliadas=0 THEN
  v_conciliadas:=public.ew_transferencias_internas_conciliadas(p_obra_id);
 END IF;
 IF v_conciliadas>0 AND v_conciliadas=v_mov_abertos THEN
  v_mov_abertos:=0;
 ELSE
  v_conciliadas:=0;v_conciliadas_nf:=0;
 END IF;
 if v_rom>0 then v_motivos:=array_append(v_motivos,'Cancele todos os romaneios emitidos.');end if;
 if v_saida>0 then v_motivos:=array_append(v_motivos,'Estorne todas as saídas de produção ainda ativas.');end if;
 if v_lib>0 or v_lotes>0 or v_planos>0 or v_liberadas>0 then
  v_motivos:=array_append(v_motivos,'Cancele as liberações para corte e seus lotes.');end if;
 if v_fabr>0 then v_motivos:=array_append(v_motivos,'Existem quantidades fabricadas a conciliar.');end if;
 if v_mov_abertos>0 or v_saldos>0 then
  v_motivos:=array_append(v_motivos,'Estorne as movimentações do estoque e confira saldo zero por material e galpão.');end if;
 if v_insumos_saldos>0 then v_motivos:=array_append(v_motivos,
  'Estorne ou transfira todo o estoque de vidros e outros insumos antes de arquivar a obra.');end if;
 if v_refs>0 then v_motivos:=array_append(v_motivos,'Há referências vinculadas a outra obra.');end if;
 if v_obra.arquivada_em is not null then
  v_motivos:=array_append(v_motivos,'Esta obra já foi retirada do acompanhamento ativo.');end if;
 return jsonb_build_object(
 'obra_id',v_obra.id,'nome',v_obra.nome,'codigo',v_obra.codigo,'motivos',to_jsonb(v_motivos),
 'permitido',cardinality(v_motivos)=0,'arquivada_em',v_obra.arquivada_em,
 'resumo',jsonb_build_object(
  'esquadrias',v_n_esq,'liberacoes',v_lib,'liberacoes_canceladas',v_lib_cancel,
  'unidades_liberadas',v_liberadas,'fabricadas',v_fabr,'lotes_cem',v_lotes,
  'planos_liberados',v_planos,'romaneios',v_rom,'romaneios_cancelados',v_rom_cancel,
  'saidas_producao',v_saida,'saidas_canceladas',v_saida_cancel,
  'movimentos_estoque',v_mov,'movimentos_pendentes',v_mov_abertos,
  'transferencias_nfe_conciliadas',v_conciliadas_nf,
  'transferencias_conciliadas',v_conciliadas,
  'saldos_nao_zerados',v_saldos,'saldos_insumos_nao_zerados',v_insumos_saldos,
  'referencias_externas',v_refs));
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;v_conciliadas int:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
   then raise exception 'Identificador de operação já utilizado.';end if;
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
COMMIT;
