-- EWGEST #34: guardas para os fluxos antigos, mantendo cadastros e obras auditáveis.
-- Não aplicar sem as tabelas ew_insumos_* e os testes de cancelamento.

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
 v_saldos int;v_insumos_saldos int;v_motivos text[]:=array[]::text[];
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
 count(*) filter(where m.estorno_de_id is null
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
  'saldos_nao_zerados',v_saldos,'saldos_insumos_nao_zerados',v_insumos_saldos,
  'referencias_externas',v_refs));
end;$function$


CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada'
 THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r
    JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
    WHERE i.despesa_id=p_despesa_id AND r.empresa_id=p_empresa_id)
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
END;$function$


CREATE OR REPLACE FUNCTION public.ew_gerenciar_cadastro_auxiliar(p_empresa_id uuid, p_tipo text, p_id uuid, p_acao text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_antigo text;v_novo text;v_em_uso boolean;
begin
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
