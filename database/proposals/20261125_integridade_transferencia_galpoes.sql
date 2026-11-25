-- Transferência entre galpões: serialização por operação e validação da repetição.
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
 return jsonb_build_object('repetida',false,'origem',v_origem,'destino',v_destino,'quantidade',p_quantidade);
end;$function$;
