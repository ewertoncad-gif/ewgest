import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../app.html',import.meta.url),'utf8');
const start=source.indexOf('function finRenderResumo(){');
const end=source.indexOf('\nfunction finRenderClassificacaoFiscal(',start);
assert.ok(start>=0&&end>start);
const render=new Function('finState','node','finMoney','finCategories','finRenderClassificacaoFiscal','escapeHTML',source.slice(start,end)+';finRenderResumo();');
function verificar(d,restante,total){
 const nodes={};
 const node=id=>nodes[id]??={innerHTML:'',insertAdjacentHTML(_,html){this.innerHTML+=html}};
 render({orcamento:{valor_total:1000,aluminio:1000,fabricacao:0,instalacao:0},compromissos:[d],faturas:[],orcamentoNiveis:[],precificacao:null},node,v=>Number(v).toFixed(2),[['aluminio','Alumínio','custo']],()=>{},String);
 assert.ok(nodes.finSummary.innerHTML.includes(restante),nodes.finSummary.innerHTML);
 assert.ok(nodes.finTotals.innerHTML.includes(total),nodes.finTotals.innerHTML);
}
const base={categoria:'aluminio',realizado_centavos:20000,comprometido_pendente_centavos:10000};
verificar({...base,ajuste_transferencias_centavos:5000},'650.00','250.00');
verificar({...base,ajuste_transferencias_centavos:-5000},'750.00','150.00');
verificar({...base,ajuste_transferencias_centavos:5000,transferencias_custo_pendentes:1},'Custo de transferência pendente','250.00');
verificar(base,'700.00','Não integrado');
console.log('4 cenários financeiros aprovados');
