import assert from 'node:assert/strict';
import {modelo,validarRetorno,exportarXlsx,parsePreco} from '../assets/compras-cotacao-xlsx.mjs';
const exp=modelo('sol','fornecedor',[{chave:'1',material:'Perfil P01 & natural',quantidade:4,unidade:'BARRA',comprimento_mm:6000},{chave:'2',material:'Acessório',quantidade:2,unidade:'PC'}]);
const good=structuredClone(exp);good[2][5]='125,00';good[3][5]=20.50;
assert.deepEqual(validarRetorno(exp,good),[{chave:'1',preco_unitario_centavos:12500},{chave:'2',preco_unitario_centavos:2050}]);
for(const change of [a=>a[0][2]='outro',a=>a[2][2]=5,a=>a[2][3]='KG',a=>a[2][4]=7000,a=>a[2][5]='',a=>a[2][5]='=1+1',a=>a[3][0]='1',a=>a.pop()]){const a=structuredClone(good);change(a);assert.throws(()=>validarRetorno(exp,a));}
const blob=exportarXlsx(exp),bytes=new Uint8Array(await blob.arrayBuffer());
assert.equal(new DataView(bytes.buffer).getUint32(0,true),0x04034b50);
console.log('PASS validação Excel: identificação, material, quantidade, unidade, preço e duplicidade.');

for(const [v,c] of [['55',5500],['55,5',5550],['55.56',5556],['R$ 1.250,75',125075],['0',0],['125,001',null],['-1',null],['',null],['abc',null]])assert.equal(parsePreco(v),c,'Preço '+v);
console.log('PASS formatação monetária brasileira e limites de preço.');
