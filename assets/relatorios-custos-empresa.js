/* EWGEST v46.21 — relatório de custos do estoque empresarial.
 * Somente consultas. Não inclui receitas/faturamentos nem despesas de obras.
 */
(()=>{
'use strict';
const BRL=new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'});
const plain=x=>String(x??'');
const escapeHtml=x=>plain(x).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const currency=c=>BRL.format(Number(c||0)/100);
const el=id=>document.getElementById(id);
const option=(value,label)=>new Option(label,value);
const auth=()=>temPermissao('relatorios.financeiros')&&
 temPermissao('compras.consultar_valores')&&temPermissao('financeiro.consultar');

async function pages(table,params){
 const data=[],size=1000,limit=20000;
 for(let offset=0;offset<limit;offset+=size){
  const result=await apiGet(table,{...params,limit:String(size),offset:String(offset)});
  if(!Array.isArray(result))throw Error('Consulta incompleta para '+table+'.');
  data.push(...result);
  if(result.length<size)return data;
 }
 throw Error('O relatório excede 20 mil registros. Refine o período.');
}
function restoreOptions(select,entries,defaultLabel){
 if(!select)return;
 const old=select.value;
 select.replaceChildren(option('',defaultLabel));
 for(const item of entries)select.add(option(item.id,item.nome));
 if([...select.options].some(x=>x.value===old))select.value=old;
}
async function carregarFiltros(empresaId){
 if(!auth()||!empresaId)return;
 const [locations,suppliers]=await Promise.all([
  pages('ew_compras_locais_empresa',{select:'id,nome',empresa_id:'eq.'+empresaId,order:'nome.asc'}),
  pages('ew_fornecedores',{select:'id,nome',empresa_id:'eq.'+empresaId,order:'nome.asc'})
 ]);
 restoreOptions(el('reportCompanyLocal'),locations,'Todos os locais da empresa');
 restoreOptions(el('reportCompanySupplier'),suppliers,'Todos os fornecedores');
}
function preparar(notas,locais,fornecedores,{localId='',fornecedorId='',inicio='',fim='',incluirCanceladas=false}={}){
 const loc=new Map(locais.map(x=>[x.id,x.nome]));
 const forn=new Map(fornecedores.map(x=>[x.id,x.nome]));
 const filtered=notas.filter(n=>{
  if(localId&&n.local_empresa_id!==localId)return false;
  if(fornecedorId&&n.fornecedor_id!==fornecedorId)return false;
  const day=String(n.data_documento||'').slice(0,10);
  if(inicio&&day<inicio)return false;
  if(fim&&day>fim)return false;
  return true;
 });
 const sorted=[...filtered].sort((a,b)=>String(b.data_documento).localeCompare(String(a.data_documento))||
  String(a.id).localeCompare(String(b.id)));
 let activeCount=0,activeCents=0,cancelCount=0;
 const sum=new Map();
 for(const n of sorted){
  const key=n.local_empresa_id,old=sum.get(key)||{local:loc.get(key)||'Local indisponível',
   ativos:0,valor_centavos:0,cancelados:0};
  const canceled=String(n.status||'').toUpperCase()==='CANCELADA';
  if(canceled){old.cancelados++;cancelCount++;}
  else if(String(n.status).toUpperCase()==='ATIVA'){
   old.ativos++;activeCount++;old.valor_centavos+=Number(n.valor_centavos)||0;
   activeCents+=Number(n.valor_centavos)||0;
  }else throw Error('Situação fiscal desconhecida: '+n.status);
  sum.set(key,old);
 }
 const byLocal=[...sum.values()].sort((a,b)=>a.local.localeCompare(b.local,'pt-BR'));
 const list=sorted.filter(n=>incluirCanceladas||n.status==='ATIVA').map(n=>[
   loc.get(n.local_empresa_id)||'Local indisponível',
   forn.get(n.fornecedor_id)||'Fornecedor histórico',
   String(n.data_documento||'').slice(0,10),
   n.numero_documento,
   n.pedido_id?'Pedido vinculado ('+plain(n.pedido_id).slice(0,8)+')':'—',
   n.status==='CANCELADA'?'CANCELADA':'ATIVA',
   currency(n.valor_centavos),
   String(n.criado_em||'').slice(0,10)
 ]);
 return {byLocal,list,activeCount,activeCents,cancelCount,documents:filtered.length,shown:list.length};
}
function table(headers,rows){
 return '<table class="reportsTable"><thead><tr>'+headers.map(x=>'<th>'+escapeHtml(x)+'</th>').join('')+
 '</tr></thead><tbody>'+rows.map(row=>'<tr>'+row.map(x=>'<td>'+escapeHtml(x)+'</td>').join('')+
 '</tr>').join('')+'</tbody></table>';
}
async function gerar({empresaId,localId='',fornecedorId='',inicio='',fim='',incluirCanceladas=false}={}){
 if(!auth()||!empresaId)throw Error('Seu nível não permite consultar custos financeiros empresariais.');
 if(inicio&&fim&&inicio>fim)throw Error('Data inicial posterior à data final.');
 await ensureSession();
 const empresa='eq.'+empresaId;
 const [notas,locais,fornecedores]=await Promise.all([
  pages('ew_compras_notas_empresa',{select:'id,local_empresa_id,pedido_id,fornecedor_id,numero_documento,data_documento,valor_centavos,status,criado_em',
    empresa_id:empresa,order:'data_documento.desc'}),
  pages('ew_compras_locais_empresa',{select:'id,nome',empresa_id:empresa,order:'nome.asc'}),
  pages('ew_fornecedores',{select:'id,nome',empresa_id:empresa,order:'nome.asc'})
 ]);
 if(localId&&!locais.some(x=>x.id===localId))throw Error('Local de estoque não encontrado nesta empresa.');
 if(fornecedorId&&!fornecedores.some(x=>x.id===fornecedorId))throw Error('Fornecedor não encontrado nesta empresa.');
 const calc=preparar(notas,locais,fornecedores,
  {localId,fornecedorId,inicio,fim,incluirCanceladas});
 const summaryHeaders=['Local de estoque da empresa','Notas ativas','Custos ativos','Notas canceladas'];
 const summaryCsv=calc.byLocal.map(s=>[s.local,s.ativos,currency(s.valor_centavos),s.cancelados]);
 const headers=['Local de estoque','Fornecedor','Data da nota','Número','Pedido','Situação','Custo fiscal','Registrada em'];
 const html='<h3>Custos de compra do estoque próprio da empresa</h3>'+
  '<p class="hint">Sem vínculo com obra. São despesas de compra de material e não faturamento. Notas canceladas ficam fora dos totais ativos.</p>'+
  '<p><strong>'+calc.activeCount+' notas ativas · '+escapeHtml(currency(calc.activeCents))+
  '</strong> em custos empresariais. '+calc.cancelCount+' cancelada(s) no período.</p>'+
  (summaryCsv.length?table(summaryHeaders,summaryCsv):
   '<p class="reportsEmpty">Não há notas fiscais empresariais neste filtro.</p>');
 return {title:'Custos do estoque da empresa',headers,rows:calc.list,summaryHeaders,
  summaryCsv,summaryHtml:html,totalActiveCents:calc.activeCents,
  notesCount:calc.documents,shown:calc.shown};
}
window.ewCustosEmpresa=Object.freeze({carregarFiltros,gerar});
})();
