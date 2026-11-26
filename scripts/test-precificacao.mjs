import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const fonte=readFileSync(fileURLToPath(new URL('../assets/precificacao-core.js',import.meta.url)),'utf8');
const contexto={window:{}};
vm.runInNewContext(fonte,contexto,{filename:'precificacao-core.js',timeout:5000});
const {precificar,totaisComDistribuicao,sugerirCategoria}=contexto.window.ewPrecificacaoCore;
const p=({id,categoriaId,largura_mm=1200,altura_mm=1150,quantidade=1})=>
 ({id,codigo:id,categoriaId,largura_mm,altura_mm,quantidade});
const categorias=[
 {id:'esq',nome:'Esquadrias',precoBaseCentavosM2:160000},
 {id:'gc',nome:'Guarda-corpo',precoBaseCentavosM2:200000},
 {id:'gr',nome:'Gradil',precoBaseCentavosM2:120000}
];
const base={fabricacaoOriginalCentavos:7000000,instalacaoOriginalCentavos:3000000,
 categorias,itens:[p({id:'EA2',categoriaId:'esq'}),
 p({id:'GC1',categoriaId:'gc',largura_mm:2500,altura_mm:1100,quantidade:2}),
 p({id:'GR1',categoriaId:'gr',largura_mm:3000,altura_mm:900,quantidade:3})]};
function verificar(d){
 const resultado=precificar(d);
 const fab=resultado.itens.reduce((s,x)=>s+x.fabricacaoCentavos,0);
 const inst=resultado.itens.reduce((s,x)=>s+x.instalacaoCentavos,0);
 assert.equal(fab,resultado.totais.fabricacaoCentavos);
 assert.equal(inst,resultado.totais.instalacaoCentavos);
 assert.equal(fab+inst,resultado.totais.totalCentavos);
 assert.equal(resultado.fechamento.diferencaCentavos,0);
 assert.equal(resultado.categorias.reduce((s,x)=>s+x.fabricacaoCentavos,0),fab);
 assert.equal(resultado.categorias.reduce((s,x)=>s+x.instalacaoCentavos,0),inst);
 for(const x of resultado.itens){
  assert.ok(Number.isSafeInteger(x.fabricacaoCentavos)&&x.fabricacaoCentavos>=0);
  assert.ok(Number.isSafeInteger(x.instalacaoCentavos)&&x.instalacaoCentavos>=0);
  assert.equal(x.fabricacaoCentavos+x.instalacaoCentavos,x.valorTotalCentavos);
 }
 return resultado;
}
const primeiro=verificar(base);
assert.equal(primeiro.fechamento.valorTotalCentavos,10000000);
assert.equal(primeiro.totais.percentualSugeridoBp,7000);
assert.equal(primeiro.totais.percentualAjustadoBp,null);
assert.equal(primeiro.itens.find(x=>x.id==='EA2').areaM2,1.38);
const trocado=verificar({...base,percentualFabricacaoBp:5500});
assert.equal(trocado.totais.fabricacaoCentavos,5500000);
assert.equal(trocado.totais.instalacaoCentavos,4500000);
assert.notEqual(trocado.categorias[0].precoAjustadoFabricacaoM2,
 primeiro.categorias[0].precoAjustadoFabricacaoM2);
assert.equal(trocado.fechamento.valorTotalCentavos,primeiro.fechamento.valorTotalCentavos);
for(const pct of [0,1,500,1000,3000,5000,7000,9999,10000]){
 const r=verificar({...base,percentualFabricacaoBp:pct});
 assert.equal(r.totais.fabricacaoCentavos+r.totais.instalacaoCentavos,10000000);
}
const invertido=verificar({...base,itens:[...base.itens].reverse(),categorias:[...categorias].reverse()});
for(const linha of primeiro.itens){
 const inversa=invertido.itens.find(x=>x.id===linha.id);
 assert.equal(linha.fabricacaoCentavos,inversa.fabricacaoCentavos);
 assert.equal(linha.instalacaoCentavos,inversa.instalacaoCentavos);
}
const cents={...base,fabricacaoOriginalCentavos:1,instalacaoOriginalCentavos:2};
const min=verificar(cents);
assert.equal(min.itens.reduce((s,x)=>s+x.valorTotalCentavos,0),3);
const minReverso=verificar({...cents,itens:[...base.itens].reverse()});
for(const item of min.itens){
 const inversa=minReverso.itens.find(x=>x.id===item.id);
 assert.equal(item.fabricacaoCentavos,inversa.fabricacaoCentavos);
 assert.equal(item.instalacaoCentavos,inversa.instalacaoCentavos);
}
for(let rodada=1;rodada<=220;rodada++){
 const fabricacao=rodada*117,instalacao=rodada*89;
 const r=verificar({...base,fabricacaoOriginalCentavos:fabricacao,
  instalacaoOriginalCentavos:instalacao,percentualFabricacaoBp:rodada%10001});
 assert.equal(r.fechamento.valorTotalCentavos,fabricacao+instalacao);
}
assert.equal(sugerirCategoria('JANELA DE CORRER COM PEITORIL'),'ESQUADRIAS');
assert.equal(sugerirCategoria('SPLIT'),'GUARDA-CORPO');
assert.equal(sugerirCategoria('GUARDA CORPO'),'GUARDA-CORPO');
assert.equal(sugerirCategoria('GRADIL'),'GRADIL');
assert.equal(sugerirCategoria('FACHADA UNITIZADA'),'FACHADAS');
assert.equal(sugerirCategoria('TEXTO DESCONHECIDO'),'OUTROS');
assert.throws(()=>precificar({...base,itens:[...base.itens,base.itens[0]]}),/único/);
assert.throws(()=>precificar({...base,itens:[p({id:'N',categoriaId:'inexistente'})]}),/categoria/);
assert.throws(()=>precificar({...base,itens:[p({id:'N',categoriaId:'esq',largura_mm:0})]}),/Largura/);
assert.throws(()=>precificar({...base,percentualFabricacaoBp:10001}),/Percentual/);
assert.throws(()=>precificar({...base,categorias:categorias.map(x=>({...x,precoBaseCentavosM2:0}))}),/preço-base/);
assert.throws(()=>precificar({...base,categorias:categorias.map(x=>x.id==='esq'?{...x,precoBaseCentavosM2:0}:x)}),/preço por m²/);
assert.equal(totaisComDistribuicao(7000,3000).totalCentavos,10000);
console.log('OK: precificação por m² — 220 cenários, rateio determinístico, totais exatos, percentuais e validações.');

const {redistribuirPrecos}=contexto.window.ewPrecificacaoCore;
const exemploMedio={fabricacaoOriginalCentavos:983520,instalacaoOriginalCentavos:245880,
 categorias:['esq','gc','fach'].map(id=>({id,nome:id,precoBaseCentavosM2:0})),
 itens:[p({id:'EA',categoriaId:'esq',largura_mm:10000,altura_mm:3610}),
 p({id:'GC',categoriaId:'gc',largura_mm:10000,altura_mm:5159}),
 p({id:'FC',categoriaId:'fach',largura_mm:10000,altura_mm:3525})]};
const media=redistribuirPrecos(exemploMedio);
assert.ok(media.every(c=>c.precoBaseCentavosM2===10000),'Preço inicial de R$ 100,00/m²');
assert.ok(exemploMedio.categorias.every(c=>c.precoBaseCentavosM2===0),'Entrada imutável');
const editados=media.map(c=>c.id==='esq'?{...c,bloqueado:true,precoBaseCentavosM2:13000}:c);
const redistribuidos=redistribuirPrecos({...exemploMedio,categorias:editados});
assert.equal(redistribuidos.find(c=>c.id==='esq').precoBaseCentavosM2,13000);
assert.ok(redistribuidos.filter(c=>c.id!=='esq').every(c=>c.precoBaseCentavosM2===8753));
const calculado=verificar({...exemploMedio,categorias:redistribuidos});
assert.equal(calculado.fechamento.valorTotalCentavos,1229400);
assert.equal(calculado.totais.fabricacaoCentavos,983520);
assert.equal(calculado.totais.instalacaoCentavos,245880);
const doisCadeados=redistribuirPrecos({...exemploMedio,categorias:redistribuidos.map(c=>c.id==='gc'?{...c,bloqueado:true,precoBaseCentavosM2:9000}:c)});
assert.equal(doisCadeados.find(c=>c.id==='gc').precoBaseCentavosM2,9000);
assert.equal(doisCadeados.find(c=>c.id==='esq').precoBaseCentavosM2,13000);
assert.equal(verificar({...exemploMedio,categorias:doisCadeados,percentualFabricacaoBp:6000}).totais.fabricacaoCentavos,737640);
assert.throws(()=>redistribuirPrecos({...exemploMedio,categorias:editados.map(c=>c.id==='esq'?{...c,precoBaseCentavosM2:999999}:c)}),/esgotam/);
assert.throws(()=>redistribuirPrecos({...exemploMedio,categorias:editados.map(c=>({...c,bloqueado:true}))}),/não fecham/);
const travados=redistribuirPrecos({...exemploMedio,categorias:redistribuidos.map(c=>({...c,bloqueado:true}))});
assert.equal(travados[0].precoBaseCentavosM2,13000);
const restaurados=redistribuirPrecos({...exemploMedio,categorias:doisCadeados.map(c=>({...c,bloqueado:false,precoBaseCentavosM2:0}))});
assert.ok(restaurados.every(c=>c.precoBaseCentavosM2===10000&&!c.bloqueado));
const nova=[...redistribuidos,{id:'nova',nome:'Nova',precoBaseCentavosM2:0}];
const movidos=exemploMedio.itens.map(x=>x.id==='FC'?{...x,categoriaId:'nova'}:x);
assert.equal(verificar({...exemploMedio,itens:movidos,categorias:redistribuirPrecos({...exemploMedio,itens:movidos,categorias:nova})}).fechamento.valorTotalCentavos,1229400);
for(let i=1;i<=150;i++){
 const dados={...exemploMedio,fabricacaoOriginalCentavos:983520+i,instalacaoOriginalCentavos:245880+i*3};
 const cats=redistribuirPrecos(dados);
 cats[0]={...cats[0],bloqueado:true,precoBaseCentavosM2:10000+i};
 verificar({...dados,categorias:redistribuirPrecos({...dados,categorias:cats}),percentualFabricacaoBp:i*53%10001});
}
console.log('OK: preço médio automático, cadeados, redistribuição, restauração, mudanças de categorias e 150 cenários adicionais de fechamento.');

const livreNovamente=redistribuirPrecos({...exemploMedio,categorias:doisCadeados.map(c=>c.id==='esq'?{...c,bloqueado:false}:c)});
assert.equal(livreNovamente.find(c=>c.id==='esq').precoBaseCentavosM2,livreNovamente.find(c=>c.id==='fach').precoBaseCentavosM2);
assert.equal(livreNovamente.find(c=>c.id==='gc').precoBaseCentavosM2,9000);
const vazio=redistribuirPrecos({...exemploMedio,categorias:doisCadeados,itens:exemploMedio.itens.map(x=>x.categoriaId==='esq'?{...x,categoriaId:'fach'}:x)});
assert.equal(vazio[0].precoBaseCentavosM2,0);
assert.equal(vazio[0].bloqueado,false);
verificar({...exemploMedio,categorias:redistribuirPrecos({...exemploMedio,categorias:vazio})});
console.log('OK: categorias vazias não participam; desbloqueio restaura média comum.');
