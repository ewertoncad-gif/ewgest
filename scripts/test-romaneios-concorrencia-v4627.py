#!/usr/bin/env python3
"""Exercise the exact numbering triggers in disposable CI PostgreSQL.
Minimal tables, not a substitute for full production-schema integration.
"""
import os, pathlib, subprocess, time
assert os.environ.get('EWGEST_CONCURRENCY_CI')=='1'
assert os.environ.get('PGHOST')=='127.0.0.1' and os.environ.get('PGDATABASE')=='ewgest_ci'
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'database/proposals/20261125_numeracao_romaneios_por_obra_v4627.sql').read_text()
core=source[source.index('CREATE SCHEMA ew_romnum_interna;'):source.index('INSERT INTO public.ew_permissoes_catalogo')]
core=core.replace('public.','ewgest_num_test.')
base=['psql','-X','-qAt','-v','ON_ERROR_STOP=1']
def sql(s):
 return subprocess.check_output(base+['-c',s],text=True,timeout=30).strip()
def run(s,app):
 return subprocess.Popen(base+['-c',s],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env={**os.environ,'PGAPPNAME':app})
def uid(n):
 return f'00000000-0000-4000-8000-{n:012d}'
sql(f"""
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon;END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated;END IF;
END $$;
CREATE SCHEMA ewgest_num_test;
CREATE TABLE ewgest_num_test.empresas(id uuid PRIMARY KEY);
CREATE TABLE ewgest_num_test.obras(id uuid PRIMARY KEY,empresa_id uuid NOT NULL,arquivada_em timestamptz);
CREATE TABLE ewgest_num_test.romaneios(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,obra_id uuid NOT NULL,numero text NOT NULL,status text NOT NULL DEFAULT 'emitido',criado_por uuid,CONSTRAINT romaneios_empresa_id_numero_key UNIQUE(empresa_id,numero));
CREATE TABLE ewgest_num_test.ew_romaneios_transferencia(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,obra_id uuid NOT NULL,numero text NOT NULL,status text NOT NULL DEFAULT 'RASCUNHO',criado_por uuid,CONSTRAINT ew_romaneios_transferencia_numero_key UNIQUE(numero));
INSERT INTO ewgest_num_test.empresas VALUES('{uid(1)}');
INSERT INTO ewgest_num_test.obras VALUES('{uid(2)}','{uid(1)}',NULL),('{uid(3)}','{uid(1)}',NULL);
{core}
""")
def insert(table,obra=2):
 return f"INSERT INTO ewgest_num_test.{table}(empresa_id,obra_id,criado_por) VALUES('{uid(1)}','{uid(obra)}','{uid(4)}') RETURNING numero;"
def esperar(app):
 end=time.monotonic()+8
 while time.monotonic()<end:
  if sql(f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event='PgSleep'")=='1':return
  time.sleep(.05)
 raise AssertionError('Primeira sessão não manteve a transação aberta')
def finish(p):
 out,err=p.communicate(timeout=25)
 assert p.returncode==0,err
 return out
first=run('BEGIN;'+insert('romaneios')+'SELECT pg_sleep(10); COMMIT;','num-first')
others=[]
try:
 esperar('num-first')
 others=[run(insert('ew_romaneios_transferencia' if i%2 else 'romaneios'),f'num-race-{i}') for i in range(4)]
 for p in others:
  _,err=p.communicate(timeout=8)
  assert p.returncode!=0 and 'Numeração desta obra em uso' in err,err
 assert sql(insert('ew_romaneios_transferencia',3))=='RM001'
 assert 'RM001' in finish(first)
 assert sql(insert('ew_romaneios_transferencia'))=='RM002'
 assert sql(insert('ew_romaneios_transferencia'))=='RM003'
 assert sql(insert('ew_romaneios_transferencia'))=='RM004'
 print('PASS cinco sessões: quatro disputas bloqueadas, outra obra independente, sequência retomada sem lacunas',flush=True)
finally:
 for p in [first,*others]:
  if p.poll() is None:p.kill();p.communicate()
first=run(f"BEGIN; UPDATE ewgest_num_test.ew_romaneios_transferencia SET status='AGRUPADO' WHERE obra_id='{uid(2)}' AND numero IN ('RM003','RM004'); SELECT pg_sleep(8); COMMIT;",'num-group')
other=None
try:
 esperar('num-group')
 other=run(insert('romaneios'),'num-group-race')
 _,err=other.communicate(timeout=6)
 assert other.returncode!=0 and 'Numeração desta obra em uso' in err,err
 finish(first)
 assert sql(insert('romaneios'))=='RM003'
 assert sql(f"SELECT count(*) FROM ew_romnum_interna.eventos WHERE obra_id='{uid(2)}' AND evento='NUMERO_REUTILIZADO' AND numero='RM003'")=='1'
 assert sql(f"SELECT count(*) FROM ewgest_num_test.ew_romaneios_transferencia WHERE obra_id='{uid(2)}' AND status='AGRUPADO'")=='2'
 print('PASS agrupamento concorrente: número só reutilizado após commit, evento e rascunhos preservados',flush=True)
finally:
 for p in [first,other]:
  if p is not None and p.poll() is None:p.kill();p.communicate()
