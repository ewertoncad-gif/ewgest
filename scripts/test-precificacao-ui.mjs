// Simulação ponta a ponta do módulo visual sem navegador nem banco.
// Exercita os scripts REAIS por VM com catálogos sintéticos e ações do usuário.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
const read=p=>readFileSync(fileURLToPath(new URL(p,import.meta.url)),'utf8');
const elements=new Map();
const createElement=()=>({
 className:'',innerHTML:'',textContent:'',value:'',disabled:false,
 dataset:{},handlers:{},attributes:{},
 classList:{_state:new Set(),add(k){this._state.add(k)},remove(k){this._state.delete(k)},contains(k){return this._state.has(k)}},
 setAttribute(k,v){this.attributes[k]=v},
 addEventListener(k,fn){this.handlers[k]=fn},
 focus(){},select(){},
 querySelector(){return null}
});
const doc={
 body:{appendChild(){}},
 createElement,
 getElementById(id){if(!elements.has(id))elements.set(id,createElement());return elements.get(id)}
};
const uuid='a38fddaa-153e-4db7-ae11-8d9d17c88233';
const obra={nomeObra:'TESTE PRECO',codigo:'TST-PRECO-01',obraExistente:null,jaImportado:false,
 esquadriasPayload:[
  {codigo:'EA01',descricao:'JANELA CORRER',referencia_tipologia:'GOLD-JCR101',largura_mm:1200,altura_mm:1000,quantidade:2},
  {codigo:'GC01',descricao:'GUARDA CORPO',referencia_tipologia:'GC100',largura_mm:2500,altura_mm:1100,quantidade:1}
 ]};
const quote={valor_total:10000,niveis:[
 {nivel:'FABRICAÇÃO',categoria_base:'fabricacao',valor:7000,faturar:true},
 {nivel:'INSTALAÇÃO',categoria_base:'instalacao',valor:3000,faturar:true}
]};
let requested=[],pending=false,record=null,approve=()=>true;
const data={
 ew_precificacao_categorias:[{id:uuid,nome:'LINHA ESPECIAL',ativo:true}],
 tipologias:[{id:'9f32bbcd-58fb-4cd4-9529-407c4be21256',codigo:'GOLD-JCR101'}],
 ew_precificacao_tipologias_padrao:[{tipologia_id:'9f32bbcd-58fb-4cd4-9529-407c4be21256',categoria_id:uuid}]
};
const window={confirm:()=>approve()};
const context={window,document:doc,console,
 currentCompany:{id:'empresa-test'},cemParsed:obra,
 ensureSession:async()=>{},
 apiGet:async(table,filter)=>{requested.push(table);if(pending)throw Error('Falha na consulta');return data[table]||[];},
 Error,Map,Set,Number,Math,BigInt,Array,String,Object,JSON};
vm.runInNewContext(read('../assets/precificacao-core.js'),context,{filename:'precificacao-core.js'});
vm.runInNewContext(read('../assets/precificacao-importacao.js'),context,{filename:'precificacao-importacao.js'});
const ui=context.window.ewPrecificacaoImportacao;
const el=id=>doc.getElementById(id);
const change=(id,dataset,value)=>el(id).handlers.change({target:{dataset,value}});
let saved;
await ui.abrir(obra,quote,async draft=>{record=draft;obra.jaImportado=true;});
assert.deepEqual(requested,
 ['ew_precificacao_categorias','tipologias','ew_precificacao_tipologias_padrao']);
assert.match(el('ewPriceCategorias').innerHTML,/LINHA ESPECIAL/);
assert.match(el('ewPriceItens').innerHTML,/LINHA ESPECIAL/);
assert.equal(el('ewPriceConfirmar').disabled,true,'No preço = bloqueado');
change('ewPriceCategorias',{price:'catalogo-'+uuid},'R$ 1.500,00');
assert.equal(el('ewPriceConfirmar').disabled,true,'Falta preço de guarda-corpo');
change('ewPriceCategorias',{price:'categoria-1'},'1400');
assert.equal(el('ewPriceConfirmar').disabled,false,'Preços válidos liberam confirmação');
change('ewPricePercent',{},'60');
assert.match(el('ewPriceResumo').innerHTML,/R\$\s*6\.000,00/);
assert.match(el('ewPriceResumo').innerHTML,/R\$\s*4\.000,00/);
assert.match(el('ewPriceItens').innerHTML,/ewPriceGroupRow/);
const click=async()=>el('ewPriceConfirmar').handlers.click();
await click();
assert.equal(obra.jaImportado,true);
assert.equal(record.fabricacao_original_centavos,700000);
assert.equal(record.instalacao_original_centavos,300000);
assert.equal(record.fabricacao_distribuida_centavos,600000);
assert.equal(record.instalacao_distribuida_centavos,400000);
assert.equal(record.itens.length,2);
assert.equal(record.itens[0].referencia_tipologia,'GOLD-JCR101');
assert.equal(record.itens.reduce((s,x)=>s+x.fabricacao_centavos,0),600000);
assert.equal(record.itens.reduce((s,x)=>s+x.instalacao_centavos,0),400000);
assert.ok(record.categorias.some(x=>x.nome==='LINHA ESPECIAL'&&x.fabricacao_centavos>0));
assert.equal(el('ewPriceOverlay')?.classList._state.has('hidden'),true,'Modal fecha após commit');
const res2={...obra,codigo:'TST-PRECO-02',jaImportado:false};
context.cemParsed=res2;
pending=true;
await assert.rejects(ui.abrir(res2,quote,async()=>{}),/Falha na consulta/);
assert.equal(el('ewPriceOverlay')?.classList._state.has('hidden'),true,'Falha na consulta fecha modal');
pending=false;
const custoInvalido={...quote,niveis:[
 {nivel:'FABRICAÇÃO',categoria_base:'fabricacao',valor:7000,faturar:false},
 ...quote.niveis.slice(1)
]};
await assert.rejects(ui.abrir(res2,custoInvalido,async()=>{}),/marque os níveis/);
assert.equal(quote.niveis[0].valor,7000,'Orçamento original não alterado');
console.log('OK: UI v46.9 — catálogo por tipologia, categorias, preço R$, 60/40, totais por item, confirmação e falha segura.');
