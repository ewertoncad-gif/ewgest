import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const begin=html.indexOf('function stockReversalBalances(obraId){');
const mid=html.indexOf('function stockReverseFechar(){',begin);
const depBegin=html.indexOf('function stockReverseDependenciasMovimento(mov,lista){');
const hBegin=html.indexOf('function stockReverseHistoryRender(id){');
const hEnd=html.indexOf('async function stockReverseIndividual(movimentoId){',hBegin);
assert.ok(begin>0&&mid>begin&&depBegin>mid&&hBegin>depBegin&&hEnd>hBegin);
const countFn=html.slice(begin,mid);
const depFn=html.slice(depBegin,hBegin);
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
 works:[{id:own,codigo:'TREINAMENTO'}],
 node,stockReverseHistoryLimit:60,stockReverseConciliadas:0,
 stockReverseConciliadasNfe:0,stockReverseReady:true,
 stockReverseDescricaoMaterial:m=>({cabecalho:'TESTE MATERIAL',detalhes:m.local_estoque}),
 matFormat:(x)=>String(x),escapeHTML:x=>String(x),
 stockReverseIndividual:()=>{},
};
vm.createContext(ctx);
vm.runInContext(countFn+'\n'+depFn+'\n'+renderFn,ctx);
const balances=ctx.stockReversalBalances(own);
assert.equal(balances.movimentos,5);
assert.equal(balances.pendentes,2,'Parcela ESTORNO sem estorno_de_id nunca deve ser pendente');
assert.equal(balances.saldos.length,0,'Ambos os galpões estão zerados');

ctx.stockReverseHistoryRender(own);
assert.equal(node('stockReverseHistoryCount').textContent,
 'Exibindo 2 de 2 movimentação(ões) neste filtro.');
assert.doesNotMatch(node('stockReverseHistoryList').innerHTML,/Contrapartida de estorno/);

ctx.stockReverseConciliadas=2;
ctx.stockReverseHistoryRender(own);
assert.equal(node('stockReverseHistoryCount').textContent,
 'Exibindo 0 de 0 movimentação(ões) neste filtro.',
 'Transferência conciliada não pode continuar no filtro de pendências');
assert.doesNotMatch(node('stockReverseHistoryList').innerHTML,/Estornar lançamento/);

node('stockReverseHistoryFilter').value='todas';
ctx.stockReverseHistoryRender(own);
let total=node('stockReverseHistoryList').innerHTML;
assert.equal((total.match(/Contrapartida de estorno/g)||[]).length,2,
 'As duas parcelas devem existir no histórico, uma sem vínculo direto');
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

const transferencia={...entry,id:'tr-interno',origem:'TRANSFERENCIA',
 transferencia_id:'op-interna',quantidade_delta:2,
 criado_em:'2026-11-22T15:00:00.000Z'};
const remanejamento={...transferencia,id:'tr-posterior',quantidade_delta:-1,
 transferencia_id:'op-posterior',criado_em:'2026-11-22T15:30:00.000Z'};
const compra={...entry,id:'compra-posterior',origem:'COMPRA',quantidade_delta:1,
 criado_em:'2026-11-22T16:00:00.000Z'};
let dependencias=ctx.stockReverseDependenciasMovimento(
 transferencia,[transferencia,remanejamento,compra]);
assert.equal(dependencias.length,1,
 'Saldo recomposto por compra não remove a dependência da transferência');
assert.match(dependencias[0].descricao,/Transferência entre galpões/);
const baixa={...remanejamento,id:'baixa-posterior',origem:'PLANO_CORTE_LOTE',
 transferencia_id:null,criado_em:'2026-11-22T15:45:00.000Z'};
dependencias=ctx.stockReverseDependenciasMovimento(transferencia,
 [transferencia,baixa,compra]);
assert.equal(dependencias.length,1,'Baixa de corte ativa deve impedir reversão');
assert.match(dependencias[0].descricao,/Baixa\/consumo/);
const estorno={...baixa,id:'reversao-baixa',origem:'ESTORNO',quantidade_delta:1,
 estorno_de_id:'baixa-posterior',criado_em:'2026-11-22T16:30:00.000Z'};
assert.equal(ctx.stockReverseDependenciasMovimento(transferencia,
 [transferencia,baixa,compra,estorno]).length,0,
 'Baixa estornada não pode permanecer entre as dependências');
assert.match(html,/ESTORNO BLOQUEADO — primeiro desfaça as movimentações posteriores/,
 'Clique na movimentação deve mostrar a ordem correta, sem executar estorno');

console.log('OK v46.15: contrapartida parcial nunca vira pendência ou opção de estorno, histórico conciliado com saldo zero.');
