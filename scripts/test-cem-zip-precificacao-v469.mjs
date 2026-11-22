// EWGEST v46.9 — fluxo real de extração e interpretação do ZIP técnico CEM.
// ZIP/XML e orçamento completamente sintéticos. Não acessa Supabase nem produção.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {deflateRawSync} from 'node:zlib';
import vm from 'node:vm';

const source=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const core=readFileSync(fileURLToPath(new URL('../assets/precificacao-core.js',import.meta.url)),'utf8');
const js=source.slice(source.indexOf('function cemSqlValues(value){'),source.indexOf('function cemEncontrarConciliacoes(r,perfis,acessorios){'));
assert.ok(js.includes('async function cemExtrairXML(zip)')&&
 js.includes('function cemMontarPayload(r)'), 'O parser e montador do CEM devem existir no aplicativo real');

// DOMParser mínimo para XML sintético de teste: testa o fluxo JS do aplicativo,
// não a implementação nativa de parse de XML de um navegador.
function xmlAttrs(text){
 const attrs=new Map([...text.matchAll(/([A-Za-z][A-Za-z0-9_]*)="([^"]*)"/g)]
   .map(m=>[m[1],m[2]]));
 return {getAttribute:(key)=>attrs.get(key)||null};
}
class SyntheticDOMParser {
 parseFromString(text){
  const root=text.match(/<ExportObras\b[^>]*>/);
  const obra=text.match(/<Obra\b[^>]*\/?>/);
  const sql=[...text.matchAll(/<SQL\b([^>]*?)\/>/g)].map(m=>xmlAttrs(m[1]));
  return {
   documentElement:{tagName:root?'ExportObras':'invalid'},
   querySelector(selector){
    if(selector==='parsererror')return null;
    if(selector==='ExportObras > Obra')return obra?xmlAttrs(obra[0]):null;
    throw new Error('Seletor XML inesperado: '+selector);
   },
   getElementsByTagName(tag){assert.equal(tag,'SQL');return sql;}
  };
 }
}
const sandbox={DOMParser:SyntheticDOMParser,Blob,Response,DecompressionStream,
 DataView,TextDecoder,Uint8Array,Map,Set,Number,Math,Array,Object,JSON,String,
 Error,console};
const pipeline=vm.runInNewContext(js+
 '\n({cemExtrairXML,cemLerObra,cemMontarEsquadrias,cemMontarPayload});',sandbox,
 {filename:'cem-pipeline-real.js',timeout:7000});
const context={window:{}};
vm.runInNewContext(core,context,{filename:'precificacao-core.js',timeout:7000});
const preco=context.window.ewPrecificacaoCore;

// Atributos Flds2 respeitam a codificação de strings SQL da exportação.
// O exemplo é propositalmente inventado, sem copiar documentos da empresa.
function record(table,fields){
 const names=Object.keys(fields).join(',');
 const values=Object.values(fields).map(v=>v===null?'NULL':
   "'"+String(v).replaceAll("'","''")+"'" ).join(',');
 return '<SQL Table="'+table+'" Flds1="'+names+'" Flds2="'+values+'" />';
}
function inventarXml(){
 return '<?xml version="1.0" encoding="UTF-8"?>\n'+
 '<ExportObras><Obra ID="12" Codigo="CEM-FICTICIO-001" />'+
 record('OBRA',{ID_OBRA:12,OBR_NOME:'OBRA TESTE TECNICO',ID_CLIENTE_OBRA:75})+
 record('CLIENTE',{ID_CLIENTE:75,CLI_NOME:'CLIENTE DE TESTE'})+
 record('OBITENS',{ITEMOBRA:1,TIPO:'EA05',CODESQD:'GOLD-JCR101',
   DESCRICAO:'JANELA DE CORRER',QTDE:2,L:1200,H:1000,LOCALIZ:'SALA',VARDEFS:''})+
 record('OBITENS',{ITEMOBRA:2,TIPO:'GC01',CODESQD:'GC100',
   DESCRICAO:'GUARDA CORPO',QTDE:1,L:2500,H:1100,LOCALIZ:'VARANDA',VARDEFS:''})+
 record('OBESQD',{ITEMOBRA:1})+record('OBESQD',{ITEMOBRA:2})+
 record('OBCALCP',{ITEMOBRA:1,CODPERF:'CG1016',CODTRATEXT:'PINTURA',
  QTDE:3,TAM:1650})+
 record('OBCALCA',{ITEMOBRA:2,CODACES:'AC001',PRENATA:'PRETO',
  QTDE:10,UNID:'PC'})+
 record('PERF',{CODPERF:'CG1016',REF:'HYDRO',DESCRICAO:'PERFIL PARA TESTE',
  LINHA:'GOLD SLIM',PESO:0.985,PRENATP:''})+
 record('ACES',{CODACES:'AC001',REF:'HYDRO',DESCRICAO:'FECHO PARA TESTE',
  LINHA:'GOLD SLIM',UNID:'PC',UNID_EMB:'CX'})+
 record('OBAPROV',{CODPERF:'CG1016',CODTRATEXT:'PINTURA',BARRA:6000,NUMBARRAS:2})+
 record('OBAPROV',{CODPERF:'CG1016',CODTRATEXT:'PINTURA',BARRA:6500,NUMBARRAS:3})+
 record('OBACES',{CODACES:'AC001',EMBALAGEM:10})+
 '</ExportObras>';
}
function crc32(bytes){
 let crc=0xffffffff;
 for(const b of bytes){
  crc^=b;
  for(let i=0;i<8;i++)crc=(crc&1)?((crc>>>1)^0xedb88320):(crc>>>1);
 }
 return (crc^0xffffffff)>>>0;
}
function zipEntry(name,content,method,offset){
 const filename=Buffer.from(name),raw=Buffer.from(content,'utf8');
 const compressed=method===8?deflateRawSync(raw):raw,crc=crc32(raw);
 const local=Buffer.alloc(30);
 local.writeUInt32LE(0x04034b50,0);local.writeUInt16LE(20,4);
 local.writeUInt16LE(method,8);local.writeUInt32LE(crc,14);
 local.writeUInt32LE(compressed.length,18);local.writeUInt32LE(raw.length,22);
 local.writeUInt16LE(filename.length,26);
 const dir=Buffer.alloc(46);
 dir.writeUInt32LE(0x02014b50,0);dir.writeUInt16LE(20,4);
 dir.writeUInt16LE(20,6);dir.writeUInt16LE(method,10);
 dir.writeUInt32LE(crc,16);dir.writeUInt32LE(compressed.length,20);
 dir.writeUInt32LE(raw.length,24);dir.writeUInt16LE(filename.length,28);
 dir.writeUInt32LE(offset,42);
 return {local:Buffer.concat([local,filename,compressed]),
  central:Buffer.concat([dir,filename])};
}
function gerarZip(files){
 const locals=[],centers=[];let offset=0;
 for(const [name,body,method] of files){
  const entry=zipEntry(name,body,method,offset);
  locals.push(entry.local);centers.push(entry.central);offset+=entry.local.length;
 }
 const central=Buffer.concat(centers),end=Buffer.alloc(22);
 end.writeUInt32LE(0x06054b50,0);end.writeUInt16LE(files.length,8);
 end.writeUInt16LE(files.length,10);end.writeUInt32LE(central.length,12);
 end.writeUInt32LE(offset,16);
 return new Blob([...locals,central,end]);
}
for(const method of [0,8]){
 const zip=gerarZip([['LEIA-ME.txt','outro arquivo',0],
  ['CEM/ExpObras.xml',inventarXml(),method]]);
 const xml=await pipeline.cemExtrairXML(zip);
 assert.match(xml,/CEM-FICTICIO-001/);
 const obra=pipeline.cemLerObra(xml);
 const esquadrias=pipeline.cemMontarEsquadrias(obra);
 const materiais=pipeline.cemMontarPayload(obra);
 assert.equal(obra.nomeObra,'OBRA TESTE TECNICO');
 assert.equal(obra.clienteObra,'CLIENTE DE TESTE');
 assert.equal(obra.codigo,'CEM-FICTICIO-001');
 assert.equal(esquadrias.length,2);
 assert.equal(esquadrias[0].codigo,'EA05');
 assert.equal(esquadrias[0].quantidade,2);
 assert.equal(esquadrias[0].largura_mm,1200);
 assert.equal(esquadrias[0].referencia_tipologia,'GOLD-JCR101');
 assert.equal(esquadrias[1].codigo,'GC01');
 assert.equal(materiais.perfis.length,1);
 assert.equal(materiais.acessorios.length,1);
 assert.equal(materiais.perfis[0].variacoes[0].linhas_calculo,1);
 assert.equal(materiais.perfis[0].variacoes[0].quantidade_prevista,3);
 assert.equal(materiais.perfis[0].variacoes[0].comprimento_total_m,4.95);
 const barras=materiais.perfis[0].variacoes[0].barras_planejadas;
 assert.equal(barras.length,2);
 assert.equal(barras[0].comprimento_mm,6000);
 assert.equal(barras[0].quantidade,2);
 assert.equal(barras[1].comprimento_mm,6500);
 assert.equal(barras[1].quantidade,3);
 assert.equal(materiais.acessorios[0].variacoes[0].quantidade_prevista,10);
 assert.equal(materiais.acessorios[0].quantidade_por_embalagem,10);
 // Do XML real interpretado para m² + distribuição financeira.
 const result=preco.precificar({
  fabricacaoOriginalCentavos:700000,instalacaoOriginalCentavos:300000,
  percentualFabricacaoBp:6000,
  categorias:[{id:'jan',nome:'ESQUADRIAS',precoBaseCentavosM2:10000},
    {id:'gc',nome:'GUARDA-CORPO',precoBaseCentavosM2:10000}],
  itens:esquadrias.map((x,i)=>({...x,id:'linha-'+i,
    categoriaId:i===0?'jan':'gc'}))
 });
 assert.equal(result.totais.fabricacaoCentavos,600000);
 assert.equal(result.totais.instalacaoCentavos,400000);
 assert.equal(result.itens.length,2);
 assert.equal(result.itens[0].areaM2,2.4);
 assert.equal(result.itens[1].areaM2,2.75);
 assert.equal(result.fechamento.diferencaCentavos,0);
 assert.equal(result.fechamento.valorTotalCentavos,1000000);
}
await assert.rejects(pipeline.cemExtrairXML(new Blob(['arquivo sem ZIP'])),/diretório ZIP válido/);
await assert.rejects(pipeline.cemExtrairXML(
 gerarZip([['outro.xml','sem ExpObras.xml',0]])),/ExpObras.xml não encontrado/);
assert.throws(()=>pipeline.cemLerObra('<Outro></Outro>'),/XML de exportação inválido/);
console.log('OK: ZIP CEM fictício método armazenado e deflate, leitura XML, esquadrias, barras, acessórios e distribuição 60/40.');

// Volume representativo da estrutura encontrada no ZIP técnico (apenas dados
// inventados): 70 linhas calculadas, 103 códigos de perfis, 132 de acessórios,
// 105 registros de barras. O arquivo original da GVG NUNCA entra no GitHub.
function inventarXmlVolume(){
 const linhas=['<ExportObras><Obra ID="99" Codigo="HOMOLOG-70-ITENS" />',
  record('OBRA',{ID_OBRA:99,OBR_NOME:'OBRA ARTIFICIAL DE VOLUME',ID_CLIENTE_OBRA:101}),
  record('CLIENTE',{ID_CLIENTE:101,CLI_NOME:'CLIENTE INEXISTENTE'})];
 for(let i=1;i<=70;i++){
  linhas.push(record('OBITENS',{ITEMOBRA:i,TIPO:'EA'+String(i).padStart(3,'0'),
   CODESQD:i%2?'GOLD-JCR101':'GC100',DESCRICAO:i%2?'JANELA DE CORRER':'GUARDA CORPO',
   QTDE:1+i%3,L:900+i*11,H:1100+i*7,LOCALIZ:'LOCAL FICTICIO',VARDEFS:''}));
  linhas.push(record('OBESQD',{ITEMOBRA:i}));
 }
 // Os 24 itens não calculados não entram nas áreas nem no orçamento.
 for(let i=71;i<=94;i++)linhas.push(record('OBITENS',{
  ITEMOBRA:i,TIPO:'OUT'+i,CODESQD:'SEM-CALCULO',DESCRICAO:'ITEM EXCLUIDO',
  QTDE:1,L:100,H:100,LOCALIZ:'',VARDEFS:''}));
 for(let i=1;i<=103;i++){
  const codigo='CP'+String(i).padStart(3,'0');
  linhas.push(record('PERF',{CODPERF:codigo,REF:'FABRICANTE FICTICIO',
   DESCRICAO:'PERFIL PARA TESTE '+i,LINHA:'LINHA TESTE',PESO:'1.5',PRENATP:''}));
  // Distribuir referência por 70 itens, sem inventar histórico de obra real.
  linhas.push(record('OBCALCP',{ITEMOBRA:1+((i-1)%70),CODPERF:codigo,
   CODTRATEXT:'PINTURA',QTDE:2,TAM:2000}));
  linhas.push(record('OBAPROV',{CODPERF:codigo,
   CODTRATEXT:'PINTURA',BARRA:6000,NUMBARRAS:2}));
 }
 // Mais duas linhas de barras para atingir 105 referências, sem duplicação
 // do comprimento dentro do mesmo perfil.
 for(const i of [1,2])linhas.push(record('OBAPROV',{
  CODPERF:'CP'+String(i).padStart(3,'0'),CODTRATEXT:'PINTURA',
  BARRA:6500,NUMBARRAS:3}));
 for(let i=1;i<=132;i++){
  const codigo='AC'+String(i).padStart(3,'0');
  linhas.push(record('ACES',{CODACES:codigo,REF:'FABRICANTE FICTICIO',
   DESCRICAO:'ACESSORIO PARA TESTE '+i,LINHA:'LINHA TESTE',
   UNID:'PC',UNID_EMB:'CX'}));
  linhas.push(record('OBCALCA',{ITEMOBRA:1+((i-1)%70),CODACES:codigo,
   PRENATA:'PRETO',QTDE:3,UNID:'PC'}));
 }
 return linhas.join('\n')+'</ExportObras>';
}
const zipVolume=gerarZip([['Export/ExpObras.xml',inventarXmlVolume(),8]]);
const xmlVolume=await pipeline.cemExtrairXML(zipVolume);
const obraVolume=pipeline.cemLerObra(xmlVolume);
const esquadriasVolume=pipeline.cemMontarEsquadrias(obraVolume);
const materiaisVolume=pipeline.cemMontarPayload(obraVolume);
assert.equal(obraVolume.valid.length,70,'Somente 70 esquadrias calculadas');
assert.equal(obraVolume.other,24,'Itens fora de cálculo não integram obra');
assert.equal(esquadriasVolume.length,70);
assert.equal(materiaisVolume.perfis.length,103);
assert.equal(materiaisVolume.acessorios.length,132);
const barrasVolume=materiaisVolume.perfis.flatMap(x=>x.variacoes.flatMap(v=>
 v.barras_planejadas||[]));
assert.equal(barrasVolume.length,105);
const r70=preco.precificar({
 fabricacaoOriginalCentavos:7000000,instalacaoOriginalCentavos:3000000,
 percentualFabricacaoBp:5500,
 categorias:[{id:'esq',nome:'ESQUADRIAS',precoBaseCentavosM2:15000},
   {id:'gc',nome:'GUARDA-CORPO',precoBaseCentavosM2:25000}],
 itens:esquadriasVolume.map((x,i)=>({...x,id:'vol-'+i,
  categoriaId:i%2===0?'esq':'gc'}))
});
assert.equal(r70.itens.length,70);
assert.equal(r70.totais.fabricacaoCentavos,5500000);
assert.equal(r70.totais.instalacaoCentavos,4500000);
assert.equal(r70.itens.reduce((s,x)=>s+x.fabricacaoCentavos,0),5500000);
assert.equal(r70.itens.reduce((s,x)=>s+x.instalacaoCentavos,0),4500000);
assert.equal(r70.fechamento.diferencaCentavos,0);
console.log('OK: ZIP CEM sintético de volume — 70 itens, 24 excluídos, 103 perfis, 132 acessórios, 105 planos de barras, rateio 55/45 exato.');

