import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const begin=html.indexOf('function stockReversalBalances(obraId){');
const mid=html.indexOf('function stockReverseFechar(){',begin);
const hBegin=html.indexOf('function stockReverseHistoryRender(id){');
const hEnd=html.indexOf('async function stockReverseIndividual(movimentoId){',hBegin);
assert.ok(begin>0&&mid>begin&&hBegin>mid&&hEnd>hBegin);
const countFn=html.slice(begin,mid);
const renderFn=html.slice(hBegin,hEnd);

const own='obra-ficticia';
const id=(x)=>x;
const entry={
 id:id('entrada'),obra_id:own,variacao_id:'mat1',comprimento_mm:6000,
 unidade:'BARRA',local_estoque:'AFOGADOS',quantidade_delta:2,
 origem:'ABERTURA',estorno_de_id:null,criado_em:'2026-11-22T14:00:00.000Z',
};
const internalA={...entry,id:id('af->imb-A'),origem:'TRANSFERENCIA',
 quantidade_delta:-1,transferencia_id:'transfer-interna',
 criado_em:'2026-11-22T14:01:00.000Z'};
const internalB={...entry,id:id('af->imb-B'),origem:'TRANSFERENCIA',
 local_estoque:'IMBIRIBEIRA',quantidade_delta:1,
 transferencia_id:'transfer-interna',criado_em:'2026-11-22T14:01:01.000Z'};
const reversal1={...entry,id:id('estorno-af'),origem:'ESTORNO',
 quantidade_delta:-1,estorno_de_id:'entrada',criado_em:'2026-11-22T14:02:00.000Z'};
const reversal2={...entry,id:id('estorno-imb-parcela'),
 origem:'ESTORNO',quantidade_delta:-1,local_estoque:'IMBIRIBEIRA',
 estorno_de_id:null,criado_em:'2026-11-22T14:02:01.000Z'};
const records=[entry,internalA,internalB,reversal1,reversal2];

const els=new Map();
const node=key=>{
 if(!els.has(key))els.set(key,{
  value:'',textContent:'',innerHTML:'',
  classList:{toggle(){},add(){},remove(){}},
  querySelectorAll(){return []},
 });
 return els.get(key);
};
node('stockReverseHistoryFilter').value='pendentes';
const ctx={
 estoqueObraMovimentos:records,
 node,stockReverseHistoryLimit:60,stockReverseConciliadas:0,
 stockReverseConciliadasNfe:0,stockReverseReady:true,
 stockReverseDescricaoMaterial:m=>({cabecalho:'TESTE MATERIAL',detalhes:m.local_estoque}),
 matFormat:(x)=>String(x),escapeHTML:x=>String(x),
 stockReverseIndividual:()=>{},
};
vm.createContext(ctx);
vm.runInContext(countFn+'\n'+renderFn,ctx);
const balances=ctx.stockReversalBalances(own);
assert.equal(balances.movimentos,5);
assert.equal(balances.pendentes,2,'Parcela ESTORNO sem estorno_de_id nunca deve ser pendente');
assert.equal(balances.saldos.length,0,'Ambos os galpões estão zerados');

ctx.stockReverseHistoryRender(own);
assert.equal(node('stockReverseHistoryCount').textContent,
 'Exibindo 2 de 2 movimentação(ões) neste filtro.');
assert.doesNotMatch(node('stockReverseHistoryList').innerHTML,/estorno-imb-parcela/);

ctx.stockReverseConciliadas=2;
ctx.stockReverseHistoryRender(own);
assert.equal(node('stockReverseHistoryCount').textContent,
 'Exibindo 0 de 0 movimentação(ões) neste filtro.',
 'Transferência conciliada não pode continuar no filtro de pendências');
assert.doesNotMatch(node('stockReverseHistoryList').innerHTML,/Estornar lançamento/);

node('stockReverseHistoryFilter').value='todas';
ctx.stockReverseHistoryRender(own);
let total=node('stockReverseHistoryList').innerHTML;
assert.match(total,/estorno-imb-parcela/);
assert.match(total,/Contrapartida de estorno/);
assert.match(total,/Histórico conciliado \(saldo zero\)/);
assert.doesNotMatch(total,/data-stock-reverse-item=/,
 'Nenhuma contrapartida nem transferência conciliada deve oferecer botão');

ctx.stockReverseConciliadasNfe=2;
ctx.stockReverseHistoryRender(own);
total=node('stockReverseHistoryList').innerHTML;
assert.match(total,/Histórico conciliado pelo estorno da NF-e/);

assert.match(html,/mov\.origem==='ESTORNO'\|\|mov\.estorno_de_id/,
 'A RPC individual não pode ser disparada pela interface para contrapartidas');
assert.match(html,/transferencias_conciliadas\?\?ver\?\.resumo\?\.transferencias_nfe_conciliadas/,
 'A tela deve aceitar o resumo de conciliação interna e de NF-e');

console.log('OK v46.15: contrapartida parcial nunca vira pendência ou opção de estorno, histórico conciliado com saldo zero.');
