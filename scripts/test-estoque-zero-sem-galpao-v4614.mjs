import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const start=html.indexOf('function renderEstoque(){');
const end=html.indexOf('function mmOrNull(value){',start);
assert.ok(start>0&&end>start,'Localizar função real de renderização de estoque');
const source=html.slice(start,end);
assert.match(source,/const gruposComSaldo=\[\.\.\.grupos.values\(\)\]\.filter/);
assert.match(source,/local_estoque:'',quantidade:0,informado:false/);
assert.match(html,/EWGEST <strong>· v46\.24<\/strong>/);

const variation=(id,tipo,code,plan,perWork=[])=>({
 v:{id,tipo,cor:'ANOD-1002',acabamento:'ANODIZADO'},
 mat:{codigo:code,descricao:'MATERIAL DE TESTE',fabricante:'HYDRO',unidade_item:'PC'},
 link:plan ? {barras_planejadas:[{comprimento_mm:6000,quantidade:plan}]}:
   (tipo==='acessorio'?{quantidade_prevista:2,unidade_prevista:'MT'}:null),
 perWork,
});
const movement=(q,local,mm=6000,unit='BARRA')=>({
 quantidade_delta:q,comprimento_mm:mm,unidade:unit,local_estoque:local,
});
const workItems=[
 // Dois pares compensados: a mesma linha GN096 deve ficar como no CEM.
 variation('v096','perfil','GN096',2,[
  movement(2,'AFOGADOS'),movement(-2,'AFOGADOS'),
  movement(2,'IMBIRIBEIRA'),movement(-2,'IMBIRIBEIRA')
 ]),
 // Item que nunca teve entrada.
 variation('v037','perfil','GN037',2,[]),
 // AF já zerado; IMB tem saldo 4. Mostrar apenas IMB.
 variation('v095','perfil','GN095',4,[
  movement(4,'AFOGADOS'),movement(-4,'AFOGADOS'),movement(4,'IMBIRIBEIRA'),
 ]),
 // Acessório totalmente recebido, transferido e estornado.
 variation('vGUA','acessorio','GUA0070PTO',null,[
  movement(1,'AFOGADOS',null,'MT'),movement(-1,'AFOGADOS',null,'MT'),
  movement(1,'IMBIRIBEIRA',null,'MT'),movement(-1,'IMBIRIBEIRA',null,'MT')
 ]),
 // Material manual, sem plano do CEM, mas com comprimento histórico.
 variation('v097','perfil','GN097',null,[
  movement(1,'AFOGADOS'),movement(-1,'AFOGADOS')
 ]),
];
const els=new Map();
const node=id=>{
 if(!els.has(id))els.set(id,{
  value:'',innerHTML:'',textContent:'',disabled:false,
  classList:{toggle(){},add(){},remove(){}},
  querySelectorAll:()=>[],
 });
 return els.get(id);
};
node('stockWork').value='obra-ficticia';
node('stockFactoryFilter').value='';
node('stockType').value='';
const context={
 node,stockLocais:[{obra_id:'obra-ficticia'}],
 estoqueDados:()=>workItems,
 stockNecessidade:x=>({
  necessaria:x.v.tipo==='perfil'?'2 barras':'2 MT',
  texto:'Pendente de recebimento',tom:'pending',
  detalhe:'Saldo total na obra: 0',
 }),
 mmOrNull:v=>Number.isFinite(Number(v))&&Number(v)>=100?Number(v):null,
 matFormat:n=>String(n),
 releaseUnidadeAcessorio:u=>u||'PC',
 escapeHTML:s=>String(s),
};
vm.createContext(context);
vm.runInContext(source,context);

const rows=()=>node('stockRecords').innerHTML
 .split('<tr>').slice(1).filter(x=>!x.startsWith('<th>'));
const ofCode=(code)=>rows().filter(x=>x.includes('<strong>'+code+'</strong>'));
const needsBaseline=(code)=>{
 const matches=ofCode(code);
 assert.equal(matches.length,1,'Somente uma linha para o estoque zerado de '+code);
 assert.match(matches[0],/stockEmptyValue">0 /,'Saldo zerado deve usar formato original de estoque');
 assert.match(matches[0],/<td><strong>—<\/strong><\/td>/,'Saldo zero não deve mostrar galpão histórico');
 return matches[0];
};
context.renderEstoque();
const gn096=needsBaseline('GN096');
assert.match(gn096,/6\.000 mm/,'Preservar o comprimento previsto no CEM');
needsBaseline('GN037');
needsBaseline('GUA0070PTO');
needsBaseline('GN097');
const gn095=ofCode('GN095');
assert.equal(gn095.length,1,'Grupo zerado em AF não pode aparecer quando há saldo em IMB');
assert.match(gn095[0],/stockValue">4 barra\(s\)/);
assert.match(gn095[0],/<td><strong>IMBIRIBEIRA<\/strong><\/td>/);
assert.doesNotMatch(gn095[0],/>AFOGADOS</);
assert.equal(node('stockCounted').textContent,'1',
 'Não contar como estoque físico materiais que apenas têm movimentações históricas');

node('stockFactoryFilter').value='AFOGADOS';
context.renderEstoque();
assert.equal(rows().length,0,'Filtro AF não mostra grupos já zerados');
assert.equal(node('stockCounted').textContent,'0');

node('stockFactoryFilter').value='IMBIRIBEIRA';
context.renderEstoque();
assert.equal(ofCode('GN095').length,1);
assert.equal(ofCode('GN096').length,0,'Zero local não aparece como saldo disponível');

node('stockFactoryFilter').value='';
workItems[0].perWork.push(movement(1,'AFOGADOS'));
context.renderEstoque();
const recebido=ofCode('GN096');
assert.equal(recebido.length,1,'Ao receber de novo, não duplicar com linha genérica 0');
assert.match(recebido[0],/stockValue">1 barra\(s\)/);
assert.match(recebido[0],/<td><strong>AFOGADOS<\/strong><\/td>/);
assert.equal(node('stockCounted').textContent,'2');
workItems[0].perWork.push(movement(-1,'AFOGADOS'));
context.renderEstoque();
needsBaseline('GN096');
assert.equal(node('stockCounted').textContent,'1');

console.log('OK v46.14: estorno 0 volta ao estado original (—), transferências históricas sem duplicar; saldo positivo por galpão mantido.');
