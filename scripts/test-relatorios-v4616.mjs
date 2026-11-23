import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const read=(relative)=>readFileSync(fileURLToPath(new URL(relative,import.meta.url)),'utf8');
const app=read('../app.html');
const transfer=read('../assets/romaneios-transferencia.js');
const reports=read('../assets/relatorios-obras.js');

assert.doesNotThrow(()=>new Function(transfer),'Romaneios de transferência devem compilar');
assert.doesNotThrow(()=>new Function(reports),'Relatórios devem compilar');
for(const key of [
 'id="navRelatorios"','id="relatorios"','id="reportType"',
 'id="reportWork"','id="reportStart"','id="reportEnd"',
 'id="reportCsv"','id="reportPrint"',
 'relatorios-obras.js?v=20261122c','romaneios-transferencia.js?v=20261122b']){
 assert.ok(app.includes(key),'Componente ausente: '+key);
}
assert.ok(app.includes("'navFinanceiro','navRelatorios'"),
 'Relatório deve seguir o mesmo controle administrativo do Financeiro');
assert.match(reports,/listarTudo\('ew_obra_faturamentos'/,
 'Faturamento deve usar a tabela de documentos emitidos');
assert.match(reports,/listarTudo\('ew_obra_faturamentos_itens'/,
 'Faturamento deve incluir itens para auditoria');
assert.match(reports,/listarTudo\('ew_estoque_obras_movimentos'/,
 'Relatório de estoque deve usar movimentos persistidos');
assert.match(reports,/usuarios_login/,
 'Responsáveis por movimentações devem vir do cadastro de usuários');
assert.match(reports,/transfers\.get\(m\.transferencia_id\)/,
 'Transferência entre obras deve identificar as duas pernas');
assert.match(reports,/m\.estorno_de_id/,
 'Estornos devem aparecer vinculados ao original');
assert.match(reports,/function csv\(\)/,
 'Relatórios exportáveis para planilha');
assert.doesNotMatch(reports,/\/rest\/v1\/rpc\/|method\s*:\s*'POST'|\.update\(|\.delete\(/,
 'Relatórios nunca devem chamar RPC de escrita nem modificar estoque');

const fixtures=[
 {id:'ativo',obra_id:'obra-ativa',numero:'RM100',status:'RASCUNHO',
  data:'2026-11-22',origem:'AFOGADOS',destino:'IMBIRIBEIRA',itens:[]},
 {id:'historico',obra_id:'obra-arquivada',numero:'RM101',status:'RASCUNHO',
  data:'2026-11-21',origem:'AFOGADOS',destino:'IMBIRIBEIRA',itens:[]}
];
const els=new Map();
function element(id){
 if(!els.has(id))els.set(id,{
  innerHTML:'',textContent:'',value:'',checked:false,
  addEventListener(){},querySelectorAll(){return []}
 });
 return els.get(id);
}
const win={}, ctx={
 document:{getElementById:element},window:win,
 works:[{id:'obra-ativa',nome:'Obra em andamento'}],
 currentCompany:{id:'empresa-ficticia'},
 Map,Number,String,Date,Array,Option:function(){},
};
vm.createContext(ctx);
const injection=transfer.replace('window.ewTransferRomaneiosReload=carregar;',
 'window.__testTransfer={setDocs:d=>docs=d,render};window.ewTransferRomaneiosReload=carregar;');
assert.ok(injection.includes('__testTransfer'));
vm.runInContext(injection,ctx);
win.__testTransfer.setDocs(fixtures);
win.__testTransfer.render();
assert.match(element('romTransfList').innerHTML,/RM100/);
assert.doesNotMatch(element('romTransfList').innerHTML,/RM101/,
 'Romaneio de obra arquivada não pode surgir na tela operacional');
assert.match(element('romTransfList').innerHTML,/data-t-edit="ativo"/);
// Nem uma simulação de filtro histórico deve fazer o romaneio arquivado voltar.
element('romTransfIncludeArchived').checked=true;
win.__testTransfer.render();
assert.doesNotMatch(element('romTransfList').innerHTML,/RM101/,
 'Romaneio de obra encerrada é definitivo: não existe consulta operacional');
assert.doesNotMatch(app,/id="romTransfIncludeArchived"/);
assert.match(reports,/arquivada_em:'is.null'/,
 'Relatório consulta somente obras ativas');
for(const filtro of ['ctx.ativas.has(f.obra_id)','ctx.ativas.has(m.obra_id)',
 'ctx.ativas.has(x.elemento.obra_id)','ctx.ativas.has(x.doc.obra_id)',
 'ctx.ativas.has(d.obra_id)']){
 assert.ok(reports.includes(filtro),'Relatório deve impedir soma de obra encerrada: '+filtro);
}
console.log('OK v46.20: obras encerradas fora de romaneios, seletores e totais operacionais; auditoria preservada.');
