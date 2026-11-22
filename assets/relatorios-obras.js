/* EWGEST v46.16 — relatórios de consulta. Sem RPC de escrita, sem mutação de estoque. */
(function(){
'use strict';
const el=id=>document.getElementById(id);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const brl=n=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const qtd=n=>Number(n||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
const stamp=d=>{if(!d)return '—';const t=new Date(d);return Number.isFinite(t.getTime())?t.toLocaleString('pt-BR'):'—';};
let rows=[],headers=[],reportTitle='',running=false,summaryCsv=[],summaryHeaders=[];
let obras=[],nomeObras=new Map(),nomeUsuarios=new Map();
const tipos={
 ABERTURA:'Abertura manual de estoque',AJUSTE:'Ajuste de estoque',
 COMPRA:'Recebimento físico / compra',IMPORTACAO_CEM:'Importação técnica CEM',
 PLANO_CORTE:'Baixa de produção',PLANO_CORTE_LOTE:'Baixa de lote de corte',
 SAIDA_MANUAL:'Baixa manual',TRANSFERENCIA:'Transferência',ESTORNO:'Estorno'
};
async function listarTudo(table,extra={},limit=1000,max=20000){
 const dados=[];
 for(let offset=0;offset<max;offset+=limit){
  const pagina=await apiGet(table,{...extra,limit:String(limit),offset:String(offset)});
  if(!Array.isArray(pagina))throw new Error('A consulta de '+table+' não retornou uma lista.');
  dados.push(...pagina);
  if(pagina.length<limit)return dados;
 }
 throw new Error('O relatório excedeu '+max+' registros. Reduza o período para evitar um arquivo incompleto.');
}
function selectObras(){
 const selecao=el('reportWork').value;
 el('reportWork').replaceChildren(new Option('Todas as obras',''));
 for(const o of obras){
  const label=o.nome+(o.codigo?' · '+o.codigo:'')+(o.arquivada_em?' (arquivada)':'');
  el('reportWork').add(new Option(label,o.id));
 }
 el('reportWork').value=obras.some(o=>o.id===selecao)?selecao:'';
}
async function carregarCatalogos(){
 if(!currentCompany)throw new Error('Selecione uma empresa.');
 const empresa='eq.'+currentCompany.id;
 const [ob,users]=await Promise.all([
  listarTudo('obras',{select:'id,nome,codigo,arquivada_em',empresa_id:empresa,order:'nome.asc'}),
  listarTudo('usuarios_login',{select:'usuario_id,nome,login',empresa_id:empresa,order:'nome.asc'})
 ]);
 obras=ob;nomeObras=new Map(ob.map(o=>[o.id,o.nome+(o.codigo?' · '+o.codigo:'')+(o.arquivada_em?' (arquivada)':'')]));
 nomeUsuarios=new Map(users.map(u=>[u.usuario_id,u.nome||u.login||String(u.usuario_id).slice(0,8)]));
 selectObras();
 const multi=el('reportWorkChecks');
 const checked=new Set([...multi.querySelectorAll('input:checked')].map(x=>x.value));
 multi.replaceChildren();
 for(const o of obras){
  const lbl=document.createElement('label'),cb=document.createElement('input');
  cb.type='checkbox';cb.value=o.id;cb.checked=checked.has(o.id);
  lbl.append(cb,document.createTextNode(' '+o.nome+(o.codigo?' · '+o.codigo:'')+(o.arquivada_em?' (arquivada)':'')));
  multi.append(lbl);
 }
}
function obra(id){return nomeObras.get(id)||'Obra histórica '+String(id||'').slice(0,8);}
function usuario(id){return nomeUsuarios.get(id)||'Usuário '+String(id||'').slice(0,8);}
function dentro(d){
 if(!d)return false;
 if(el('reportFullPeriod').checked)return true;
 const dia=String(d).slice(0,10),ini=el('reportStart').value,fim=el('reportEnd').value;
 return (!ini||dia>=ini)&&(!fim||dia<=fim);
}
function contexto(){
 const ini=el('reportStart').value,fim=el('reportEnd').value;
 if(!el('reportFullPeriod').checked&&ini&&fim&&ini>fim)
  throw new Error('A data inicial não pode ser posterior à data final.');
 const modo=el('reportType').value;
 let obraIds=null;
 if(modo==='faturamento'&&el('reportWorkScope').value==='selected'){
  obraIds=new Set([...el('reportWorkChecks').querySelectorAll('input:checked')].map(x=>x.value));
  if(!obraIds.size)throw new Error('Marque pelo menos uma obra para consolidar o faturamento.');
 }
 return {empresa:'eq.'+currentCompany.id,obraId:modo==='faturamento'?'':el('reportWork').value,obraIds};
}
function tabela(cabecalhos,linhas){
 if(!linhas.length)return '<p class="reportsEmpty">Nenhum registro encontrado nos filtros selecionados.</p>';
 return '<table class="reportsTable"><thead><tr>'+cabecalhos.map(h=>'<th>'+esc(h)+'</th>').join('')+
 '</tr></thead><tbody>'+linhas.map(l=>'<tr>'+l.map(c=>'<td>'+esc(c)+'</td>').join('')+'</tr>').join('')+'</tbody></table>';
}
function agruparPorObra(faturas){
 const mapa=new Map();
 for(const f of faturas){
  const k=f.obra_id;
  if(!mapa.has(k))mapa.set(k,{obra:obra(k),fab:0,inst:0,documentos:0});
  const v=mapa.get(k);const valor=Number(f.valor_total)||0;
  if(f.categoria==='fabricacao')v.fab+=valor;
  else if(f.categoria==='instalacao')v.inst+=valor;
  v.documentos++;
 }
 return [...mapa.values()].sort((a,b)=>a.obra.localeCompare(b.obra,'pt-BR'));
}
async function faturamento(ctx){
 const base={empresa_id:ctx.empresa,select:'id,obra_id,categoria,data_faturamento,numero_documento,valor_total,status,cancelado_em,criado_por,criado_em,observacoes',order:'criado_em.asc'};
 const [faturas,itens,esq]=await Promise.all([
  listarTudo('ew_obra_faturamentos',base),
  listarTudo('ew_obra_faturamentos_itens',{empresa_id:ctx.empresa,select:'faturamento_id,esquadria_id,quantidade,valor_unitario,valor_total'}),
  listarTudo('esquadrias',{empresa_id:ctx.empresa,select:'id,codigo,descricao,obra_id'})
 ]);
 const codes=new Map(esq.map(e=>[e.id,e]));
 const linhasPorFat=new Map();
 for(const item of itens){if(!linhasPorFat.has(item.faturamento_id))linhasPorFat.set(item.faturamento_id,[]);linhasPorFat.get(item.faturamento_id).push(item);}
 const filtro=faturas.filter(f=>(!ctx.obraIds||ctx.obraIds.has(f.obra_id))&&dentro(f.data_faturamento));
 const ativos=filtro.filter(f=>!f.cancelado_em&&String(f.status).toLowerCase()!=='cancelado');
 const exibidos=el('reportCancelled').checked?filtro:ativos;
 const resumo=agruparPorObra(ativos);
 const totalFab=resumo.reduce((n,x)=>n+x.fab,0),totalInst=resumo.reduce((n,x)=>n+x.inst,0);
 summaryHeaders=['Obra','Documentos','Fabricação','Instalação','Total'];
 summaryCsv=[...resumo.map(x=>[x.obra,x.documentos,brl(x.fab),brl(x.inst),brl(x.fab+x.inst)]),
  ['TOTAL GERAL',ativos.length,brl(totalFab),brl(totalInst),brl(totalFab+totalInst)]];
 let sum='<div class="reportsKpis"><div><span>Faturado ativo</span><strong>'+brl(totalFab+totalInst)+'</strong></div>'+
 '<div><span>Fabricação</span><strong>'+brl(totalFab)+'</strong></div>'+
 '<div><span>Instalação</span><strong>'+brl(totalInst)+'</strong></div>'+
 '<div><span>Documentos ativos</span><strong>'+ativos.length+'</strong></div></div>';
 sum+='<h3>Totais por obra</h3>'+tabela(['Obra','Documentos','Fabricação','Instalação','Total'],
  summaryCsv);
 el('reportSummary').innerHTML=sum;
 headers=['Obra','Data','Documento','Categoria','Situação','Esquadria','Descrição','Quantidade','Valor unitário','Valor item','Valor documento','Registrado por','Observações'];
 rows=[];
 for(const f of exibidos){
  const lista=linhasPorFat.get(f.id)||[null];
  for(const i of lista){
   const e=i?codes.get(i.esquadria_id):null;
   rows.push([
    obra(f.obra_id),String(f.data_faturamento).slice(0,10),f.numero_documento,
    f.categoria==='fabricacao'?'Fabricação':f.categoria==='instalacao'?'Instalação':f.categoria,
    f.cancelado_em||String(f.status).toLowerCase()==='cancelado'?'CANCELADO':String(f.status).toUpperCase(),
    e?.codigo||'',e?.descricao||'',i?qtd(i.quantidade):'',i?brl(i.valor_unitario):'',
    i?brl(i.valor_total):'',brl(f.valor_total),usuario(f.criado_por),f.observacoes||''
   ]);
  }
 }
 reportTitle='Faturamentos por obra';
 el('reportTable').innerHTML='<h3>Documentos e itens faturados</h3>'+
 tabela(headers,rows)+'<p class="hint">Valores de documentos cancelados não entram nos totais. O valor do documento pode repetir nas linhas de seus itens; não some essa coluna.</p>';
 return {contagem:filtro.length,visiveis:exibidos.length};
}
function materialIndex(vars,perfis,acess){
 const p=new Map(perfis.map(x=>[x.id,x])),a=new Map(acess.map(x=>[x.id,x]));
 return new Map(vars.map(v=>{
  const item=v.perfil_id?p.get(v.perfil_id):a.get(v.acessorio_id);
  return [v.id,{codigo:item?.codigo||'Sem código',
    descricao:item?.descricao||'Material histórico',cor:v.cor||v.acabamento||''}];
 }));
}
function rotuloMovimento(m,porTransferencia,nfeMap){
 if(m.origem!=='TRANSFERENCIA'){
  const original=m.estorno_de_id?' · Referência '+String(m.estorno_de_id).slice(0,8):'';
  const nfe=nfeMap.get(m.id);
  return (tipos[m.origem]||m.origem)+original+(nfe?' · Recebimento físico NF-e':'');
 }
 const outros=(porTransferencia.get(m.transferencia_id)||[]).filter(x=>x.id!==m.id);
 const par=outros.find(x=>Number(x.quantidade_delta)===-Number(m.quantidade_delta) &&
  x.variacao_id===m.variacao_id && x.unidade===m.unidade);
 if(!par)return 'Transferência sem par identificado — conferir';
 if(par.obra_id!==m.obra_id)
  return Number(m.quantidade_delta)<0?'Enviado para '+obra(par.obra_id):'Recebido de '+obra(par.obra_id);
 return Number(m.quantidade_delta)<0?'Saída para galpão '+par.local_estoque:
  'Recebido do galpão '+par.local_estoque;
}
async function estoque(ctx){
 const [movs,vars,perfis,acess,nfes]=await Promise.all([
  listarTudo('ew_estoque_obras_movimentos',{empresa_id:ctx.empresa,
   select:'id,empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,criado_em,local_estoque,estorno_de_id,transferencia_id,observacao,usuario_id',order:'criado_em.asc'}),
  listarTudo('ew_materiais_variacoes',{empresa_id:ctx.empresa,select:'id,perfil_id,acessorio_id,cor,acabamento'}),
  listarTudo('ew_perfis',{empresa_id:ctx.empresa,select:'id,codigo,descricao'}),
  listarTudo('ew_acessorios',{empresa_id:ctx.empresa,select:'id,codigo,descricao'}),
  listarTudo('ew_nfe_recebimentos',{empresa_id:ctx.empresa,select:'movimento_id,estornado_em'})
 ]);
 const materiais=materialIndex(vars,perfis,acess);
 const nfeMap=new Map(nfes.map(x=>[x.movimento_id,x]));
 const transfers=new Map(),saldos=new Map();
 for(const m of movs)if(m.transferencia_id){
  if(!transfers.has(m.transferencia_id))transfers.set(m.transferencia_id,[]);
  transfers.get(m.transferencia_id).push(m);
 }
 const linhaMov=movs.map(m=>{
  const mat=materiais.get(m.variacao_id)||{codigo:'Sem código',descricao:'Cadastro histórico',cor:''};
  const chave=JSON.stringify([m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque]);
  const atual=(saldos.get(chave)||0)+Number(m.quantidade_delta);
  saldos.set(chave,atual);
  const delta=Number(m.quantidade_delta);
  return {m,linha:[obra(m.obra_id),stamp(m.criado_em),mat.codigo,mat.descricao,mat.cor,
   m.comprimento_mm?String(Number(m.comprimento_mm)/1000).replace('.',',')+' m':'—',
   m.local_estoque||'—',rotuloMovimento(m,transfers,nfeMap),
   (delta>0?'+':'')+qtd(delta),m.unidade,qtd(atual),usuario(m.usuario_id),
   m.observacao||'',String(m.id)]};
 });
 const filtros=new Set([...document.querySelectorAll('[data-report-stock]:checked')].map(x=>x.dataset.reportStock));
 if(!filtros.size)throw new Error('Marque pelo menos um tipo de movimentação.');
 const classificacao=m=>{
  if(m.origem==='TRANSFERENCIA'){
   const par=(transfers.get(m.transferencia_id)||[]).find(p=>p.id!==m.id);
   return par&&par.obra_id!==m.obra_id?'obras':'galpoes';
  }
  if(m.origem==='COMPRA'||m.origem==='ABERTURA')return 'recebimento';
  if(m.origem==='PLANO_CORTE'||m.origem==='PLANO_CORTE_LOTE'||m.origem==='SAIDA_MANUAL')return 'producao';
  if(m.origem==='SAIDA_OBRA')return 'direto';
  return 'outros';
 };
 const filtradas=linhaMov.filter(({m})=>(!ctx.obraId||m.obra_id===ctx.obraId)&&
  dentro(m.criado_em)&&filtros.has(classificacao(m)))
  .reverse();
 headers=['Obra','Data/hora','Código','Material','Cor','Barra','Galpão','Operação',
  'Movimento','Unidade','Saldo após movimento','Responsável','Observações','ID movimento'];
 rows=filtradas.map(x=>x.linha);
 const entradas=filtradas.filter(x=>Number(x.m.quantidade_delta)>0).length;
 const saidas=filtradas.filter(x=>Number(x.m.quantidade_delta)<0).length;
 el('reportSummary').innerHTML='<div class="reportsKpis">'+
 '<div><span>Movimentações</span><strong>'+rows.length+'</strong></div>'+
 '<div><span>Entradas / contrapartidas positivas</span><strong>'+entradas+'</strong></div>'+
 '<div><span>Saídas / contrapartidas negativas</span><strong>'+saidas+'</strong></div></div>'+
 '<p class="hint">A quantidade é mostrada na unidade original de cada material; não se somam barras, peças e metros. '+
 'Os saldos são por material, comprimento, obra e galpão e incluem movimentos anteriores ao período selecionado.</p>';
 reportTitle='Movimentações de estoque por obra';
 el('reportTable').innerHTML='<h3>Histórico de movimentações</h3>'+tabela(headers,rows);
 return {contagem:rows.length};
}
async function gerar(){
 if(running||!canAdministrate()||!currentCompany)return;
 rows=[];headers=[];summaryCsv=[];summaryHeaders=[];el('reportCsv').disabled=true;el('reportPrint').disabled=true;
 el('reportTable').replaceChildren();el('reportSummary').replaceChildren();
 const tipo=el('reportType').value;
 running=true;el('reportGenerate').disabled=true;
 el('reportStatus').textContent='Consultando registros, usuários e obras arquivadas…';
 try{
  const ctx=contexto();
  await ensureSession();
  await carregarCatalogos();
  if(ctx.obraId && !obras.some(o=>o.id===ctx.obraId))throw new Error('A obra não está mais disponível para consulta.');
  el('reportWork').value=ctx.obraId;
  const geradores={faturamento,estoque,liberacoes,expedicao,aluminio};
  if(!geradores[tipo])throw new Error('Relatório inexistente.');
  const res=await geradores[tipo](ctx);
  el('reportStatus').textContent='Relatório concluído: '+res.contagem+' registro(s) consultado(s). '+
   (tipo==='faturamento'?'Totais excluem documentos cancelados.':'Consulta sem alteração dos registros.');
  el('reportCsv').disabled=!rows.length;el('reportPrint').disabled=!rows.length;
 }catch(e){el('reportStatus').textContent='Não foi possível gerar: '+e.message;}
 finally{running=false;el('reportGenerate').disabled=false;}
}
function csv(){
 if(!rows.length)return;
 const enc=v=>{
  const texto=String(v??'');
  // Impede que códigos, descrições ou observações virem fórmulas ao abrir no Excel.
  const seguro=/^[\\s\\r\\n]*[=+@-]/.test(texto)?"'"+texto:texto;
  return '"'+seguro.replace(/"/g,'""')+'"';
 };
 const tabelaPrincipal=[headers,...rows].map(r=>r.map(enc).join(';')).join('\r\n');
 const resumo=summaryHeaders.length?[
  'RESUMO POR OBRA',summaryHeaders.map(enc).join(';'),
  ...summaryCsv.map(r=>r.map(enc).join(';')),'','DETALHAMENTO',''
 ].join('\r\n'):'';
 const text='\ufeff'+resumo+tabelaPrincipal;
 const url=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8;'}));
 const a=document.createElement('a');a.href=url;
 a.download=el('reportType').value+
  '_ewgest_'+new Date().toISOString().slice(0,10)+'.csv';
 document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function imprimir(){
 if(!rows.length)return;
 const w=window.open('about:blank','_blank');
 if(!w){el('reportStatus').textContent='Permita a abertura de guias para imprimir o relatório.';return;}
 const html='<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>'+
  esc(reportTitle)+' · EWGEST</title><style>body{font:11px Arial,sans-serif;color:#14243a;margin:20px}'+
  'h1{font-size:18px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #cbd5e1;padding:5px;text-align:left;vertical-align:top}'+
  'th{background:#edf3fa}thead{display:table-header-group}@page{size:landscape;margin:12mm}</style></head><body>'+
  '<h1>EWGEST · '+esc(reportTitle)+'</h1><p>Gerado em '+esc(stamp(new Date().toISOString()))+
  ' · Obra: '+esc(el('reportWork').selectedOptions[0]?.text||'Todas as obras')+'</p>'+
  el('reportSummary').innerHTML+tabela(headers,rows)+'</body></html>';
 w.document.open();w.document.write(html);w.document.close();w.focus();w.print();
}
el('navRelatorios').addEventListener('click',async()=>{
 if(!canAdministrate())return;
 setView('relatorios');
 el('reportStatus').textContent='Consulta sem movimentação de estoque. Clique em Gerar relatório.';
 el('reportTable').replaceChildren();el('reportSummary').replaceChildren();
 el('reportCsv').disabled=true;el('reportPrint').disabled=true;rows=[];
 try{await ensureSession();await carregarCatalogos();}
 catch(e){el('reportStatus').textContent='Erro ao preparar obras e usuários: '+e.message;}
});
function exibirFiltros(){
 const tipo=el('reportType').value,isBilling=tipo==='faturamento',stock=tipo==='estoque';
 el('reportMultiple').classList.toggle('hidden',!isBilling);
 el('reportWork').closest('label').classList.toggle('hidden',isBilling);
 el('reportStockOptions').classList.toggle('hidden',!stock);
 el('reportCancelledWrap').classList.toggle('hidden',!['faturamento','liberacoes','expedicao'].includes(tipo));
 el('reportWorkChecks').classList.toggle('hidden',el('reportWorkScope').value!=='selected'||!isBilling);
}
function periodo(){
 const todo=el('reportFullPeriod').checked;
 el('reportStart').disabled=todo;el('reportEnd').disabled=todo;
}
el('reportFullPeriod').addEventListener('change',periodo);
el('reportWorkScope').addEventListener('change',exibirFiltros);
el('reportType').addEventListener('change',()=>{
 exibirFiltros();
 el('reportSummary').replaceChildren();el('reportTable').replaceChildren();
 el('reportCsv').disabled=true;el('reportPrint').disabled=true;rows=[];
});
periodo();exibirFiltros();
el('reportGenerate').addEventListener('click',gerar);
el('reportCsv').addEventListener('click',csv);
el('reportPrint').addEventListener('click',imprimir);
})();