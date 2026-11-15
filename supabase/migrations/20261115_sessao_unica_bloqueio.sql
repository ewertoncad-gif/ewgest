-- Aplicar após implantação da interface v42.7 e da Edge Function.
-- Restrição efetiva em leituras RLS e em todas as RPCs privilegiadas.
alter policy "Consultar meus vinculos" on public.usuarios_empresas
 using (usuario_id=(select auth.uid()) and (select public.ew_sessao_eh_atual()));
create policy "Apenas sessao unica consulta cadastro" on public.usuarios_login
 as restrictive for select to authenticated
 using ((select public.ew_sessao_eh_atual()));

do $enforce$
declare r record; v_def text;v_new text;v_total int:=0;
begin
 for r in
  select p.oid,p.proname,pg_get_functiondef(p.oid) def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_language lang on lang.oid=p.prolang
  where n.nspname='public' and p.prosecdef and lang.lanname='plpgsql'
    and p.prorettype <> 'event_trigger'::regtype
    and p.proname not in ('ew_controlar_sessao_unica','ew_exigir_sessao_atual')
    and has_function_privilege('authenticated',p.oid,'execute')
 loop
  if position('PERFORM public.ew_exigir_sessao_atual();' in r.def)>0 then continue;end if;
  v_def:=r.def;
  v_new:=regexp_replace(v_def,'\mBEGIN\M',
    E'BEGIN\n  PERFORM public.ew_exigir_sessao_atual();','i');
  if v_def=v_new then raise exception 'Não foi possível proteger a função %',r.proname;end if;
  execute v_new;
  v_total:=v_total+1;
 end loop;
 if v_total<25 then raise exception 'Cobertura incompleta: somente % funções protegidas.',v_total;end if;
 raise notice 'RPCs privilegiadas protegidas: %',v_total;
end;$enforce$;
