-- EWGEST v46.0 — MT = metro inteiro em compras, estoque e entrega à produção.
-- Sem alteracao ou arredondamento de registros anteriores. Excecao apenas para
-- estornos reais (estorno_de_id presente) de movimentos antigos ja fracionados.
-- Metros quadrados (M2), quilos (KG) e litros (L) continuam fracionaveis.

create or replace function public.ew_validar_mt_despesa_item()
returns trigger language plpgsql set search_path='' as $function$
begin
 if upper(btrim(coalesce(new.unidade,''))) in ('MT','M','METRO','METROS')
    and new.quantidade is not null and new.quantidade<>trunc(new.quantidade)
 then
  raise exception 'Compras em MT devem ter metros inteiros (1, 2, 3...). Não é permitido comprar meio metro.';
 end if;
 return new;
end;
$function$;

drop trigger if exists ew_despesa_mt_inteiro on public.ew_obra_despesas_itens;
create trigger ew_despesa_mt_inteiro
 before insert or update of quantidade,unidade on public.ew_obra_despesas_itens
 for each row execute function public.ew_validar_mt_despesa_item();

create or replace function public.ew_validar_mt_movimento_material()
returns trigger language plpgsql set search_path='' as $function$
begin
 if new.estorno_de_id is null
    and upper(btrim(coalesce(new.unidade,''))) in ('MT','M','METRO','METROS')
    and new.quantidade_delta is not null
    and new.quantidade_delta<>trunc(new.quantidade_delta)
 then
  raise exception 'Movimentações em MT exigem metros inteiros (1, 2, 3...), inclusive transferências e entregas à produção.';
 end if;
 return new;
end;
$function$;

drop trigger if exists ew_movimento_material_mt_inteiro on public.ew_estoque_obras_movimentos;
create trigger ew_movimento_material_mt_inteiro
 before insert or update of unidade,quantidade_delta on public.ew_estoque_obras_movimentos
 for each row execute function public.ew_validar_mt_movimento_material();

create or replace function public.ew_validar_mt_movimento_insumo()
returns trigger language plpgsql set search_path='' as $function$
declare v_unidade text;
begin
 if new.estorno_de_id is not null then return new;end if;
 select c.unidade into v_unidade from public.ew_insumos_catalogo c
 where c.id=new.insumo_id and c.empresa_id=new.empresa_id;
 if upper(btrim(coalesce(v_unidade,''))) in ('MT','M','METRO','METROS')
    and new.quantidade_delta is not null
    and new.quantidade_delta<>trunc(new.quantidade_delta)
 then
  raise exception 'Estoque e transferências de insumos em MT exigem metros inteiros (1, 2, 3...).';
 end if;
 return new;
end;
$function$;

drop trigger if exists ew_movimento_insumo_mt_inteiro on public.ew_insumos_movimentos;
create trigger ew_movimento_insumo_mt_inteiro
 before insert or update of quantidade_delta,insumo_id on public.ew_insumos_movimentos
 for each row execute function public.ew_validar_mt_movimento_insumo();

revoke all on function public.ew_validar_mt_despesa_item() from public,anon,authenticated;
revoke all on function public.ew_validar_mt_movimento_material() from public,anon,authenticated;
revoke all on function public.ew_validar_mt_movimento_insumo() from public,anon,authenticated;
