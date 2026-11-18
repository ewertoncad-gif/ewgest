-- Revogação preventiva: TRUNCATE ignora RLS e não deve ser acessível
-- aos perfis públicos do aplicativo. Não altera SELECT/INSERT/UPDATE/DELETE.
do $rights$
declare r record;n int:=0;
begin
 for r in select distinct t.table_name
   from information_schema.role_table_grants g
   join information_schema.tables t on t.table_schema=g.table_schema and t.table_name=g.table_name
   where g.table_schema='public' and t.table_type='BASE TABLE'
    and g.grantee in ('anon','authenticated')
    and g.privilege_type in ('TRUNCATE','TRIGGER','REFERENCES')
 loop
   execute format('revoke truncate, trigger, references on table public.%I from anon, authenticated',r.table_name);
   n:=n+1;
 end loop;
 raise notice 'Tabelas com privilégios especiais restritos: %',n;
end;$rights$;
