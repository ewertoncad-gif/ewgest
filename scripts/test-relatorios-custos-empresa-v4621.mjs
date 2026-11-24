// EWGEST v46.21 — teste funcional de cálculo de relatório de custos da empresa.
// Executado em Node com simulação da API, sem usar o banco de produção.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const content=fs.readFileSync(new URL('../assets/relatorios-custos-empresa.js',import.meta.url),'utf8');
let allowed=true;
const localA='00000000-0000-4000-8000-000000000001';
const localB='00000000-0000-4000-8000-000000000002';
const supplierA='00000000-0000-4000-8000-000000000003';
const supplierB='00000000-0000-4000-8000-000000000004';
const docs=[
 {id:'n1',local_empresa_id:localA,pedido_id:'p1',fornecedor_id:supplierA,
  numero_documento:'NF 01',data_documento:'2026-11-01',valor_centavos:10001,status:'ATIVA',criado_em:'2026-11-02'},
 {id:'n2',local_empresa_id:localA,pedido_id:'p2',fornecedor_id:supplierA,
  numero_documento:'NF 02',data_documento:'2026-11-12',valor_centavos:20002,status:'ATIVA',criado_em:'2026-11-13'},
 {id:'n3',local_empresa_id:localA,pedido_id:'p3',fornecedor_id:supplierA,
  numero_documento:'NF cancelada',data_documento:'2026-11-14',valor_centavos:99999,status:'CANCELADA',criado_em:'2026-11-15'},
 {id:'n4',local_empresa_id:localB,pedido_id:'p4',fornecedor_id:supplierB,
  numero_documento:'NF 04',data_documento:'2026-11-25',valor_centavos:30003,status:'ATIVA',criado_em:'2026-11-26'}
];
const db={
 ew_compras_notas_empresa:docs,
 ew_compras_locais_empresa:[{id:localA,nome:'ESTOQUE GVG'},{id:localB,nome:'ESTOQUE REGIONAL'}],
 ew_fornecedores:[{id:supplierA,nome:'HIDRO'},{id:supplierB,nome:'VIDRAÇARIA'}]
};
const tables=[];
const context=vm.createContext({
 Intl,console,window:{},document:{getElementById(){return null}},
 temPermissao(key){return allowed&&['relatorios.financeiros','compras.consultar_valores','financeiro.consultar'].includes(key)},
 ensureSession:async()=>{},
 apiGet:async(table,params)=>{
  tables.push(table);
  assert.ok(db[table], 'Consulta não aprovada: '+table);
  assert.equal(params.empresa_id,'eq.tenant1','A consulta não filtrou pela empresa');
  return db[table].slice(Number(params.offset||0),Number(params.offset||0)+Number(params.limit||1000));
 }
});
vm.runInContext(content,context);
const report=context.window.ewCustosEmpresa;
assert.equal(typeof report?.gerar,'function');

const all=await report.gerar({empresaId:'tenant1'});
assert.equal(all.rows.length,3,'Notas canceladas não devem aparecer sem seleção');
assert.equal(all.notesCount,4,'Total de documentos do filtro inclui cancelados');
assert.equal(all.totalActiveCents,60006,'Cancelamento não integra soma ativa');
assert.match(all.summaryHtml,/R\$\s?600,06/);
assert.equal(all.summaryCsv.length,2);
assert.equal(all.summaryCsv[0][1],2);
assert.equal(all.summaryCsv[0][3],1);
assert.ok(all.rows.every(r=>r[5]==='ATIVA'));

const withCancelled=await report.gerar({empresaId:'tenant1',incluirCanceladas:true});
assert.equal(withCancelled.rows.length,4);
assert.equal(withCancelled.totalActiveCents,60006,'Mostrar cancelados não altera total ativo');
assert.equal(withCancelled.rows.filter(r=>r[5]==='CANCELADA').length,1);

const subset=await report.gerar({empresaId:'tenant1',localId:localA,
 fornecedorId:supplierA,inicio:'2026-11-10',fim:'2026-11-20'});
assert.equal(subset.totalActiveCents,20002,'Filtro de local, fornecedor e período');
assert.equal(subset.rows.length,1);
assert.equal(subset.rows[0][3],'NF 02');
assert.equal(subset.summaryCsv[0][1],1);

const separated=await report.gerar({empresaId:'tenant1',localId:localB});
assert.equal(separated.totalActiveCents,30003);
assert.equal(separated.rows[0][0],'ESTOQUE REGIONAL');

await assert.rejects(report.gerar({empresaId:'tenant1',inicio:'2026-11-30',
 fim:'2026-11-01'}),/Data inicial posterior/);
await assert.rejects(report.gerar({empresaId:'tenant1',localId:'wrong'}),/Local de estoque não encontrado/);

allowed=false;
await assert.rejects(report.gerar({empresaId:'tenant1'}),/Seu nível não permite/);
assert.deepEqual([...new Set(tables)].sort(),[
 'ew_compras_locais_empresa','ew_compras_notas_empresa','ew_fornecedores'].sort(),
 'O relatório de custos empresariais não deve puxar despesas ou faturamentos de obras.');

const appHtml=fs.readFileSync(new URL('../app.html',import.meta.url),'utf8');
const reportsJs=fs.readFileSync(new URL('../assets/relatorios-obras.js',import.meta.url),'utf8');
assert.match(appHtml,/value="custos_empresa"/);
assert.match(appHtml,/id="reportCompanyLocal"/);
assert.match(appHtml,/id="reportCompanySupplier"/);
assert.ok(appHtml.includes('relatorios-custos-empresa.js'));
assert.match(reportsJs,/window\.ewCustosEmpresa\.gerar/);
assert.match(reportsJs,/res\.summaryHtml/);
assert.match(reportsJs,/tipo==='custos_empresa'/);
assert.match(reportsJs,/incluirCanceladas:el\('reportCancelled'\)\.checked/);

console.log('PASS: relatório empresarial, cancelamentos, moeda em centavos, segregação, filtros e permissão.');
