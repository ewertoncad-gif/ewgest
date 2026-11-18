-- Perfil Gerenciador para operações da empresa, sem acesso à mutação de contas ADM.
alter table public.usuarios_login drop constraint if exists usuarios_login_perfil_check;
alter table public.usuarios_login add constraint usuarios_login_perfil_check
 check (perfil in ('administrador','gerenciador','supervisor','tecnico','consulta','almoxarife'));
alter table public.usuarios_empresas drop constraint if exists usuarios_empresas_perfil_check;
alter table public.usuarios_empresas add constraint usuarios_empresas_perfil_check
 check (perfil in ('administrador','gerenciador','supervisor','tecnico','consulta','almoxarife'));

do $policies$
declare p record;oldq text;oldw text;newq text;neww text;changed int:=0;
begin
 for p in select schemaname,tablename,policyname,cmd,qual,with_check
 from pg_policies where schemaname='public'
 and (coalesce(qual,'')||coalesce(with_check,'')) like '%administrador%'
 loop
  oldq:=p.qual;oldw:=p.with_check;newq:=oldq;neww:=oldw;
  if newq is not null then
   newq:=replace(newq,$a$ = 'administrador'::text$a$,$b$ = ANY (ARRAY['administrador'::text, 'gerenciador'::text])$b$);
   newq:=replace(newq,$a$ARRAY['administrador'::text, 'supervisor'::text$a$,$b$ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text$b$);
  end if;
  if neww is not null then
   neww:=replace(neww,$a$ = 'administrador'::text$a$,$b$ = ANY (ARRAY['administrador'::text, 'gerenciador'::text])$b$);
   neww:=replace(neww,$a$ARRAY['administrador'::text, 'supervisor'::text$a$,$b$ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text$b$);
  end if;
  if newq is not distinct from oldq and neww is not distinct from oldw then
    raise exception 'Política não adaptada: %.%',p.tablename,p.policyname;
  end if;
  if oldq is not null then execute format('alter policy %I on %I.%I using (%s)',p.policyname,p.schemaname,p.tablename,newq);end if;
  if oldw is not null then execute format('alter policy %I on %I.%I with check (%s)',p.policyname,p.schemaname,p.tablename,neww);end if;
  changed:=changed+1;
 end loop;
 if changed<24 then raise exception 'Cobertura RLS abaixo do esperado: %',changed;end if;
 raise notice 'Políticas atualizadas: %',changed;
end;$policies$;

do $rpcs$
declare p record;def text;outdef text;n integer:=0;
begin
 for p in
  select oid,proname,pg_get_functiondef(oid) as def
  from pg_proc where pronamespace='public'::regnamespace and prosecdef
   and has_function_privilege('authenticated',oid,'EXECUTE')
   and prosrc like '%administrador%'
 loop
  def:=p.def;
  outdef:=replace(def, $a$='administrador'$a$, $b$ IN ('administrador','gerenciador')$b$);
  outdef:=replace(outdef, $a$= 'administrador'$a$, $b$ IN ('administrador','gerenciador')$b$);
  outdef:=replace(outdef, $a$('administrador','supervisor'$a$, $b$('administrador','gerenciador','supervisor'$b$);
  outdef:=replace(outdef, $a$('administrador','almoxarife'$a$, $b$('administrador','gerenciador','almoxarife'$b$);
  if outdef=def then raise exception 'RPC administrativa não adaptada: %',p.proname;end if;
  execute outdef;n:=n+1;
 end loop;
 if n<32 then raise exception 'Cobertura de RPCs incompleta: %',n;end if;
 raise notice 'Funções privilegiadas adaptadas: %',n;
end;$rpcs$;
