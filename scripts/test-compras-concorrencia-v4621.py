#!/usr/bin/env python3
"""Real overlapping PostgreSQL connections; isolated CI service, synthetic schema.
The receipt RPC body is extracted from the proposal; legacy tables and authorization
are minimal test doubles, not a full Supabase integration test.
Never run against a persistent or production database.
"""
import json
import os
import pathlib
import subprocess
import time

assert os.environ.get("EWGEST_CONCURRENCY_CI") == "1", "Only disposable CI database"
assert os.environ.get("PGHOST") == "127.0.0.1" and os.environ.get("PGDATABASE") == "ewgest_ci"
schema = "ewgest_conc"
root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "database/proposals/20261123_compras_locais_estoque_v4621.sql").read_text()
start = source.index("create or replace function public.ew_compras_receber_pedido(")
end = source.index("end;$f$;", start) + len("end;$f$;")
rpc = source[start:end].replace("public.", schema + ".").replace("auth.uid()", schema + ".uid()")
base = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"]
def sql(statement, app="ewgest-controller"):
    return subprocess.check_output(base + ["-c", statement], text=True,
        env={**os.environ, "PGAPPNAME":app}, timeout=30).strip()
def uid(n):
    return f"00000000-0000-4000-8000-{n:012d}"
setup = f"""
CREATE SCHEMA {schema};
SET search_path={schema},pg_catalog;
CREATE TABLE ew_compras_pedidos(id uuid primary key,numero bigint,empresa_id uuid,fornecedor_id uuid,obra_id uuid,local_empresa_id uuid,itens jsonb,status text);
CREATE TABLE ew_compras_recebimentos(id uuid primary key default gen_random_uuid(),empresa_id uuid,pedido_id uuid,galpao text,operacao_id uuid unique,itens jsonb,criado_por uuid,estornado_em timestamptz);
CREATE TABLE ew_locais_fisicos(empresa_id uuid,nome text,ativo boolean);
CREATE TABLE ew_compras_locais_empresa(id uuid primary key,empresa_id uuid,ativo boolean);
CREATE TABLE obras(id uuid,empresa_id uuid,arquivada_em timestamptz);
CREATE TABLE ew_estoques_locais(empresa_id uuid,obra_id uuid,criado_por uuid,excluido_em timestamptz,unique(empresa_id,obra_id));
CREATE TABLE ew_nfe_recebimentos(empresa_id uuid,obra_id uuid,despesa_item_id uuid,estornado_em timestamptz,variacao_id uuid,comprimento_mm integer,unidade text);
CREATE TABLE ew_obra_despesas_itens(id uuid,despesa_id uuid);
CREATE TABLE ew_obra_despesas(id uuid,status text,fornecedor text);
CREATE TABLE ew_fornecedores(id uuid,nome text);
CREATE TABLE ew_estoque_obras_movimentos(id uuid primary key default gen_random_uuid(),empresa_id uuid,obra_id uuid,variacao_id uuid,comprimento_mm integer,unidade text,quantidade_delta numeric,origem text,operacao_id uuid,observacao text,usuario_id uuid,local_estoque text);
CREATE TABLE ew_compras_estoque_empresa(id uuid primary key default gen_random_uuid(),empresa_id uuid,local_empresa_id uuid,recebimento_id uuid,chave text,variacao_id uuid,galpao text,unidade text,comprimento_mm integer,quantidade_delta numeric);
CREATE TABLE ew_compras_recebimentos_movimentos(empresa_id uuid,recebimento_id uuid,chave text,movimento_obra_id uuid,movimento_empresa_id uuid,primary key(recebimento_id,chave));
CREATE FUNCTION uid() RETURNS uuid LANGUAGE sql AS $$select current_setting('ewgest.test_uid')::uuid$$;
CREATE FUNCTION ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$begin if {schema}.uid() is null then raise exception 'sem sessao';end if;end;$$;
CREATE FUNCTION ew_pode(uuid,text) RETURNS boolean LANGUAGE sql AS $$select true$$;
{rpc}
INSERT INTO ew_locais_fisicos VALUES('{uid(1)}','AFOGADOS',true);
INSERT INTO ew_compras_locais_empresa VALUES('{uid(2)}','{uid(1)}',true);
"""
sql(setup)
for n in (3,4,5):
    items=json.dumps([dict(chave="A",variacao_id=uid(9),quantidade=2,unidade="BARRA",comprimento_mm=6000)])
    sql(f"insert into {schema}.ew_compras_pedidos values ('{uid(n)}',{n},'{uid(1)}',null,null,'{uid(2)}','{items}','ABERTO')")
def receive(p,op,user,qty):
    items=json.dumps([dict(chave="A",quantidade=qty)])
    return f"set ewgest.test_uid='{uid(user)}'; select {schema}.ew_compras_receber_pedido('{uid(p)}','AFOGADOS','{items}','{uid(op)}');"
def process(statement, app):
    return subprocess.Popen(base+["-c",statement],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,
        env={**os.environ,"PGAPPNAME":app})
def wait_for(app,event_type,event=None):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        clause=f" and wait_event='{event}'" if event else ""
        if sql(f"select count(*) from pg_stat_activity where application_name='{app}' and wait_event_type='{event_type}'{clause}")=="1":
            return
        time.sleep(.05)
    raise AssertionError(f"Session {app} never reached {event_type}/{event}")
def run_case(p,op1,op2,q1,q2,kind):
    a=process("BEGIN; "+receive(p,op1,21,q1)+" select pg_sleep(12); COMMIT;","ewgest-race-a")
    b=None
    try:
        wait_for("ewgest-race-a","Timeout","PgSleep")
        b=process("BEGIN; "+receive(p,op2,21 if kind=="retry" else 22,q2)+" COMMIT;","ewgest-race-b")
        wait_for("ewgest-race-b","Lock")
        # This explicitly observes overlapping sessions and a real database lock.
        out_a,err_a=a.communicate(timeout=25)
        out_b,err_b=b.communicate(timeout=25)
        assert a.returncode==0,err_a
        first=json.loads(next(x for x in out_a.splitlines() if x.startswith("{")))
        if kind=="excess":
            assert b.returncode!=0 and "Pedido indisponível" in err_b,err_b
        else:
            assert b.returncode==0,err_b
            second=json.loads(next(x for x in out_b.splitlines() if x.startswith("{")))
            if kind=="retry":
                assert second["repetida"] is True and second["id"]==first["id"],second
            else:
                assert second["status"]=="CONCLUIDO" and second["id"]!=first["id"],second
        result=sql(f"select p.status||'|'||count(distinct r.id)||'|'||sum(m.quantidade_delta) from {schema}.ew_compras_pedidos p join {schema}.ew_compras_recebimentos r on r.pedido_id=p.id join {schema}.ew_compras_estoque_empresa m on m.recebimento_id=r.id where p.id='{uid(p)}' group by p.status")
        expected="CONCLUIDO|2|2" if kind=="partial" else "CONCLUIDO|1|2"
        assert result==expected,(result,expected)
        print(f"PASS {kind}: overlapping sessions, observed lock, {result}",flush=True)
    finally:
        for proc in (a,b):
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.communicate()
run_case(3,11,12,2,2,"excess")
run_case(4,13,13,2,2,"retry")
run_case(5,14,15,1,1,"partial")
