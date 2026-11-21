-- EWGEST #34: consulta restrita de transferências físicas para estorno pelo ADM.
create or replace function public.ew_insumos_transferencias_obra(
 p_empresa_id uuid,p_obra_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
   where u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode consultar os estornos de transferências.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'operacao_id',s.operacao_id,'material',s.descricao,'unidade',s.unidade,
  'quantidade',s.quantidade,'obra_origem',s.obra_origem,'galpao_origem',s.galpao_origem,
  'obra_destino',s.obra_destino,'galpao_destino',s.galpao_destino,
  'estornada',s.estornada,'criado_em',s.criado_em)
  order by s.criado_em desc),'[]'::jsonb) into v_result
 from (
  select m.operacao_id,c.descricao,c.unidade,-m.quantidade_delta quantidade,
   o1.nome obra_origem,m.local_estoque galpao_origem,
   o2.nome obra_destino,p.local_estoque galpao_destino,
   m.criado_em,
   exists(select 1 from public.ew_insumos_movimentos e
    where e.empresa_id=p_empresa_id and e.estorno_de_id in (m.id,p.id)) estornada
  from public.ew_insumos_movimentos m
   join public.ew_insumos_movimentos p on p.empresa_id=m.empresa_id
     and p.transferencia_id=m.transferencia_id and p.quantidade_delta>0
   join public.ew_insumos_catalogo c on c.empresa_id=m.empresa_id and c.id=m.insumo_id
   join public.obras o1 on o1.empresa_id=m.empresa_id and o1.id=m.obra_id
   join public.obras o2 on o2.empresa_id=p.empresa_id and o2.id=p.obra_id
  where m.empresa_id=p_empresa_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 and (m.obra_id=p_obra_id or p.obra_id=p_obra_id)
  order by m.criado_em desc limit 150
 ) s;
 return v_result;
end
$func$;
revoke all on function public.ew_insumos_transferencias_obra(uuid,uuid) from public;
revoke execute on function public.ew_insumos_transferencias_obra(uuid,uuid) from anon;
grant execute on function public.ew_insumos_transferencias_obra(uuid,uuid) to authenticated;
