import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const core=readFileSync(new URL('../assets/precificacao-core.js',import.meta.url),'utf8');
const ui=readFileSync(new URL('../assets/precificacao-importacao.js',import.meta.url),'utf8');

const nos=new Map(),handlers=new Map();
function node(id){
 if(!nos.has(id))nos.set(id,{id,value:'',textContent:'',innerHTML:'',disabled:false,
 classList:{add(){},remove(){}},setAttribute(){},querySelector(){return null;},
 addEventListener(e,fn){handlers.set(this.id+':'+e,fn);}});
 return nos.get(id);
}
const doc={getElementById:node,createElement:()=>node('wrapper'),body:{appendChild(){}}};
const w={confirm:()=>true};
const obra={nomeObra:'Teste',codigo:'M2',esquadriasPayload:[
 {codigo:'EA',descricao:'JANELA',largura_mm:10000,altura_mm:3610,quantidade:1},
 {codigo:'GC',descricao:'GUARDA CORPO',largura_mm:10000,altura_mm:5159,quantidade:1},
 {codigo:'FC',descricao:'FACHADA',largura_mm:10000,altura_mm:3525,quantidade:1}]};
new Function('window',core)(w);
new Function('window','document','currentCompany','ensureSession','apiGet','cemParsed',ui)(w,doc,{id:'empresa-teste'},async()=>{},async()=>[],obra);
let gravado=null;
await w.ewPrecificacaoImportacao.abrir(obra,{niveis:[{categoria_base:'fabricacao',valor:9835.2,faturar:true},{categoria_base:'instalacao',valor:2458.8,faturar:true}]},async d=>{gravado=d;obra.jaImportado=true});
const html=()=>node('ewPriceCategorias').innerHTML;
const evento=(id,value)=>handlers.get('ewPriceCategorias:change')({target:{dataset:{price:id},value}});
const clicar=(id)=>handlers.get('ewPriceCategorias:click')({target:{closest(sel){return sel==='[data-lock]'?{dataset:{lock:id}}:null;}}});
const restaurar=()=>handlers.get('ewPriceRestore:click')();
assert.ok(html().includes('100,00')&&!node('ewPriceConfirmar').disabled);
evento('categoria-0','130,00');
assert.ok(html().includes('130,00')&&html().includes('87,53')&&html().includes('aria-pressed="true"'));
evento('categoria-1','90,00');
assert.ok(html().includes('130,00')&&html().includes('90,00'));
evento('categoria-0','999999,00');
assert.ok(node('ewPriceConfirmar').disabled);
assert.ok(node('ewPriceFechamento').textContent.includes('esgotam'));
restaurar();
assert.ok(!node('ewPriceConfirmar').disabled&&html().includes('100,00')&&!html().includes('aria-pressed="true"'));
clicar('categoria-0');
assert.ok(html().includes('aria-pressed="true"'));
clicar('categoria-0');
assert.ok(!html().includes('aria-pressed="true"'));
evento('categoria-0','130,00');
node('ewPricePercent').value='60';
handlers.get('ewPricePercent:input')();
assert.ok(!node('ewPriceConfirmar').disabled);
await handlers.get('ewPriceConfirmar:click')();
assert.equal(gravado.fabricacao_distribuida_centavos,737640);
assert.equal(gravado.instalacao_distribuida_centavos,491760);
assert.equal(gravado.categorias.find(c=>c.id_local==='categoria-0').preco_base_m2_centavos,13000);
assert.equal(gravado.itens.reduce((s,x)=>s+x.fabricacao_centavos+x.instalacao_centavos,0),1229400);
console.log('OK: tela de importação — preço automático, edição, cadeados, bloqueio, restauração e payload com centavos exatos.');
