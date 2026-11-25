/* EWGEST v46.21 — Compras e locais de estoque da empresa.
 * Ativado apenas com permissões e migração no servidor. Não duplica NF-e.
 */
(()=>{
'use strict';
const $=id=>document.getElementById(id);
const esc=x=>escapeHTML(x);
const money=c=>(Number(c||0)/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const number=x=>Number(x||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
const say=(id,msg)=>{if($(id))$(id).textContent=msg||''};
const permission=key=>temPermissao(key);
const rpc=(fn,body)=>request('/rest/v1/rpc/'+fn,{method:'POST',token:session.access_token,body,timeoutMs:45000});
const option=(v,t)=>'<option value="'+esc(v)+'">'+esc(t)+'</option>';
const validQty=(v,un)=>{const q=Number(v);return Number.isFinite(q)&&q>0&&q<=1000000&&
 Math.abs(q*1000-Math.round(q*1000))<1e-7&&
 (!['BARRA','MT','PC','PR','CJ','UN'].includes(un)||Number.isSafeInteger(q))};
const parseMoney=v=>{let s=String(v??'').trim().replace(/^R\$\s*/,'');
 if(/^\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?$/.test(s))s=s.replace(/\./g,'');
 if(!/^\d+(?:[.,]\d{1,2})?$/.test(s))return null;
 const c=Math.round(Number(s.replace(',','.'))*100);
 return Number.isSafeInteger(c)&&c>=0&&c<=100000000000?c:null;};
// Mesmo padrão monetário BRL usado nos totais de Compras e Recebimento.
const formatMoneyInput=c=>money(c);
function bindQuoteMoney(){
 $('comprasCotacaoItens').querySelectorAll('[data-quote-key] input').forEach(input=>{
  input.addEventListener('input',()=>input.setCustomValidity(''));
  input.addEventListener('blur',()=>{const cents=parseMoney(input.value);
   if(cents!==null)input.value=formatMoneyInput(cents);
  });
 });
}
// A API pode limitar cada resposta, mesmo com limit superior. Ler páginas
// pequenas e ordenadas por ID; nunca calcular saldos de uma página isolada.
async function readAllRows(table,filters){
 const rows=[];const pageSize=500;
 for(let offset=0;offset<100000;offset+=pageSize){
  const page=await apiGet(table,{...filters,order:'id.asc',limit:String(pageSize),offset:String(offset)});
  if(!Array.isArray(page))throw Error('Resposta inválida ao consultar '+table+'.');
  rows.push(...page);
  if(page.length<pageSize){
   if(new Set(rows.map(x=>x.id)).size!==rows.length)throw Error('Consulta mudou durante a leitura. Atualize a tela.');
   return rows;
  }
 }
 throw Error('Limite de segurança da consulta atingido. Não é possível calcular o saldo completo.');
}
const pendingOps=new Map();
function operationToken(kind,payload){const signature=JSON.stringify(payload);const old=pendingOps.get(kind);
 if(old&&old.signature===signature)return old.id;
 const id=crypto.randomUUID();pendingOps.set(kind,{signature,id});return id;
}
let tab='solicitacao',locals=[],suppliers=[],suppliersAll=[],galpoes=[],variations=[],sols=[],quotes=[],orders=[],receipts=[],stockEpoch=0,receivingEpoch=0,loaded=false;
function titleLocal(row){const work=works.find(w=>w.id===row.obra_id);
 const loc=locals.find(x=>x.id===row.local_empresa_id);
 return work?'Obra · '+work.nome:loc?'Empresa · '+loc.nome:'Local indisponível';}
function destinoOptions(){return works.map(w=>option('obra:'+w.id,'Obra · '+w.nome)).join('')+
 locals.filter(x=>x.ativo).map(x=>option('empresa:'+x.id,'Empresa · '+x.nome)).join('');}
function productLabel(v){return v.nome||v.id}
let requestNeeds=[],requestNeedsReady=false,requestNeedsEpoch=0;
function purchaseOptions(catalog,needs,kind,extras,category,search){
 const options=[];const key=(id,mm)=>id+'|'+(mm??'');
 const byId=new Map(catalog.map(v=>[v.id,v]));
 for(const n of needs){
  const v=byId.get(n.variacao_id);if(!v)continue;
  if(!extras&&n.faltante!==null&&Number(n.faltante)<=0)continue;
  if(!extras&&v.tipo==='perfil'&&n.comprimento_mm==null)continue;
  options.push({...v,...n,id:v.id,key:key(v.id,n.comprimento_mm),planned:true});
 }
 if(extras||kind==='empresa'){
  for(const v of catalog){
   if(options.some(n=>n.key===key(v.id,v.comprimento_mm)))continue;
   options.push({...v,key:key(v.id,v.comprimento_mm),planned:false});
  }
 }
 const norm=x=>String(x||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
 return options.filter(v=>(!category||v.tipo===category)&&norm(productLabel(v)+' '+(v.acabamento||'')).includes(norm(search))).sort((a,b)=>productLabel(a).localeCompare(productLabel(b),'pt-BR')||Number(a.comprimento_mm||0)-Number(b.comprimento_mm||0));
}
function requestOptions(all=false){
 const kind=$('comprasDestino')?.value.split(':')[0];
 if(!kind||!requestNeedsReady)return [];
 return purchaseOptions(variations,requestNeeds,kind,$('comprasExtras').checked,all?'':$('comprasCategoria').value,all?'':$('comprasBuscaMaterial').value.trim());
}
function optionLabel(v){
 const base=productLabel(v)+(v.comprimento_mm?' · '+number(v.comprimento_mm)+' mm':'');
 if(!v.planned)return base+' · Extra / sem previsão';
 if(v.faltante===null)return base+' · Previsão não informada';
 return base+' · Falta '+number(v.faltante)+' '+v.unidade+(Number(v.faltante)<=0?' (atendido)':'');
}
function updateRequestRows(reset=false){
 const opts=requestOptions(),eligible=requestOptions(true);
 for(const row of $('comprasLinhas').children){
  const select=row.querySelector('[data-buy="variation"]'),old=reset?'':select.value;
  const previous=eligible.find(v=>v.key===old);
  const visible=previous&&!opts.some(v=>v.key===old)?[previous,...opts]:opts;
  select.innerHTML=option('','Selecione')+visible.map(v=>option(v.key,optionLabel(v))).join('');
  if(previous){select.value=old;row.querySelector('[data-buy="length"]').disabled=previous.unidade!=='BARRA'||(previous.planned&&previous.comprimento_mm!=null&&!$('comprasExtras').checked);}
  else {select.value='';row.querySelector('[data-buy="info"]').textContent='';}
  select.disabled=!requestNeedsReady||!visible.length;
 }
 $('comprasAddLine').disabled=!requestNeedsReady||!opts.length;
 $('comprasSolicitarForm').querySelector('[type=submit]').disabled=!requestNeedsReady||!eligible.length;
}
async function loadRequestNeeds(){
 const epoch=++requestNeedsEpoch,form=$('comprasSolicitarForm'),dest=$('comprasDestino').value,company=currentCompany.id;
 requestNeeds=[];requestNeedsReady=false;updateRequestRows(true);
 if(!dest){say('comprasMateriaisStatus','Escolha o local de estoque.');return;}
 const [kind,id]=dest.split(':');
 say('comprasMateriaisStatus','Consultando materiais da obra…');
 try{
  const needs=kind==='obra'?await rpc('ew_compras_necessidades_obra',{p_empresa_id:company,p_obra_id:id}):[];
  if(epoch!==requestNeedsEpoch||form!==$('comprasSolicitarForm')||company!==currentCompany?.id)return;
  if(!Array.isArray(needs))throw Error('Resposta inválida de necessidades.');
  requestNeeds=needs;requestNeedsReady=true;
  say('comprasMateriaisStatus',kind==='empresa'?'Estoque independente: catálogo completo.':needs.length?'Materiais previstos ainda não atendidos.':'Obra sem previsão importada. Marque a opção de materiais extras para solicitar.');
  updateRequestRows(true);
 }catch(e){if(epoch===requestNeedsEpoch&&form===$('comprasSolicitarForm'))say('comprasMateriaisStatus','Não foi possível consultar necessidades: '+e.message);}
}
async function reload(){
 if((!permission('compras.consultar')&&!permission('compras.receber'))||!currentCompany)return;
 await ensureSession();
 const empresa='eq.'+currentCompany.id;
 const [ls,fs,gs,vs,ps,as,so,co,po,re]=await Promise.all([
  apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'1000'}),
  apiGet('ew_fornecedores',{select:'id,nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'1000'}),
  apiGet('ew_locais_fisicos',{select:'nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'200'}),
  readAllRows('ew_materiais_variacoes',{select:'id,tipo,perfil_id,acessorio_id,cor,acabamento,ativo',empresa_id:empresa,ativo:'eq.true'}),
  readAllRows('ew_perfis',{select:'id,codigo,descricao,comprimento_comercial_mm',empresa_id:empresa}),
  readAllRows('ew_acessorios',{select:'id,codigo,descricao,unidade_item',empresa_id:empresa}),
  apiGet('ew_compras_solicitacoes',{select:'*',empresa_id:empresa,order:'criado_em.desc',limit:'1000'}),
  apiGet('ew_compras_cotacoes',{select:'*',empresa_id:empresa,order:'criado_em.desc',limit:'1000'}),
  rpc('ew_compras_pedidos_resumo',{p_empresa_id:currentCompany.id}),
  readAllRows('ew_compras_recebimentos',{select:'id,pedido_id,itens,criado_em,galpao,estornado_em,estorno_motivo',empresa_id:empresa})
 ]);
 const perf=new Map((ps||[]).map(p=>[p.id,p])),acc=new Map((as||[]).map(a=>[a.id,a]));
 locals=ls||[];suppliersAll=fs||[];suppliers=suppliersAll.filter(x=>x.ativo);galpoes=(gs||[]).filter(x=>x.ativo).map(x=>x.nome);
 variations=(vs||[]).map(v=>{const m=v.tipo==='perfil'?perf.get(v.perfil_id):acc.get(v.acessorio_id);
 return {...v,unidade:v.tipo==='perfil'?'BARRA':m?.unidade_item||'PC',
  comprimento_mm:v.tipo==='perfil'?Number(m?.comprimento_comercial_mm)||6000:null,
  nome:(m?.codigo||'?')+' · '+(m?.descricao||'Material')+' · '+v.cor};}).filter(x=>x.nome);
 sols=so||[];quotes=co||[];orders=po||[];receipts=re||[];loaded=true;
}
function receivedMap(pedidoId){const m=new Map();
 for(const rec of receipts.filter(x=>x.pedido_id===pedidoId&&!x.estornado_em))
  for(const line of rec.itens||[])m.set(String(line.chave),(m.get(String(line.chave))||0)+Number(line.quantidade||0));
 return m;}
function orderStatus(p){if(p.status==='CANCELADO')return 'Cancelado';const rec=receivedMap(p.id);let all=true,some=false;
 for(const it of p.itens||[]){const n=rec.get(String(it.chave))||0;if(n>0)some=true;if(n+1e-8<Number(it.quantidade))all=false;}
 return all?'Recebido':some?'Parcial':'Pendente';}
function formRow(index){
 return '<div class="ewComprasLine" data-buy-line="'+index+'"><label>Material<select data-buy="variation" required>'+option('','Selecione')+requestOptions().map(v=>option(v.key,optionLabel(v))).join('')+'</select></label>'+
 '<label>Quantidade<input data-buy="qty" type="number" min="1" step="1" value="1" required></label>'+
 '<label>Unidade<input data-buy="unit" readonly value="BARRA"></label>'+
 '<label>Comprimento (mm)<input data-buy="length" type="number" min="100" max="20000" value="6000"></label>'+
 '<button class="btn secondary" type="button" data-buy-remove>Remover</button><p data-buy="info" class="hint" style="grid-column:1/-1;margin:0"></p></div>';
}
function makeLine(){const container=$('comprasLinhas');if(!container)return;const div=document.createElement('div');div.innerHTML=formRow(container.children.length);
 const row=div.firstElementChild;container.append(row);
 row.querySelector('[data-buy="variation"]').addEventListener('change',()=>{
  const v=requestOptions(true).find(v=>v.key===row.querySelector('[data-buy="variation"]').value);if(!v)return;
  row.querySelector('[data-buy="unit"]').value=v.unidade;
  row.querySelector('[data-buy="length"]').value=v.comprimento_mm||'';
  row.querySelector('[data-buy="length"]').disabled=v.unidade!=='BARRA'||(v.planned&&v.comprimento_mm!=null&&!$('comprasExtras').checked);
  const qty=row.querySelector('[data-buy="qty"]');
  qty.min=v.unidade==='KG'?'0.001':'1';
  qty.step=v.unidade==='KG'?'0.001':'1';
  if(v.planned&&Number(v.faltante)>0)qty.value=String(v.faltante);else qty.value=qty.min;
  row.querySelector('[data-buy="info"]').textContent=v.planned&&v.prevista!=null?'Previsto: '+number(v.prevista)+' · Em estoque: '+number(v.fisico)+' · Atendido: '+number(v.atendida)+' · Falta: '+number(v.faltante)+' '+v.unidade:v.planned?'Material previsto sem quantidade importada.':'Material extra ou sem previsão.';
 });
 row.querySelector('[data-buy-remove]').addEventListener('click',()=>{if(container.children.length>1)row.remove()});
}
function cancelDetails(item){
 if(!item.cancelado_em)return '';
 const date=String(item.cancelado_em).slice(0,10).split('-').reverse().join('/');
 return '<div class="hint">Cancelado em '+esc(date)+(item.cancelamento_motivo?' · '+esc(item.cancelamento_motivo):'')+'</div>';
}
async function cancelarRegistro(tipo,id){
 const cfg={
  solicitacao:{text:'solicitação',rpc:'ew_compras_cancelar_solicitacao',arg:'p_solicitacao_id',flag:'compras.solicitar'},
  cotacao:{text:'cotação',rpc:'ew_compras_cancelar_cotacao',arg:'p_cotacao_id',flag:'compras.cotar'},
  pedido:{text:'pedido',rpc:'ew_compras_cancelar_pedido',arg:'p_pedido_id',flag:'compras.pedir'}
 };
 const c=cfg[tipo];
 if(!c||!permission(c.flag))return;
 const value=window.prompt('Motivo para cancelar a '+c.text+' (5 a 400 caracteres):');
 if(value===null)return;
 const reason=value.trim();
 if(reason.length<5||reason.length>400){say('comprasMensagem','Informe um motivo entre 5 e 400 caracteres.');return;}
 if(!window.confirm('Confirmar cancelamento? O histórico e a justificativa serão preservados, sem alterar estoque ou notas fiscais.'))return;
 const button=[...$('comprasConteudo').querySelectorAll('[data-compras-cancel]')]
   .find(b=>b.dataset.comprasCancel===id);
 if(button)button.disabled=true;
 try{
  const args={p_motivo:reason,p_operacao_id:operationToken('cancel_'+tipo,{tipo,id,reason})};
  args[c.arg]=id;
  await rpc(c.rpc,args);pendingOps.delete('cancel_'+tipo);
  await reload();groupCatalog=null;groupLinks=[];render();say('comprasMensagem','Cancelamento realizado. Histórico e estoque preservados.');
 }catch(e){say('comprasMensagem','Cancelamento bloqueado: '+e.message)}
 finally{if(button?.isConnected)button.disabled=false;}
}
function bindCancelButtons(){
 $('comprasConteudo').querySelectorAll('[data-compras-cancel]').forEach(b=>
  b.addEventListener('click',()=>void cancelarRegistro(b.dataset.comprasTipo,b.dataset.comprasCancel)));
}
function renderRequest(){
 const editable=permission('compras.solicitar');
 $('comprasConteudo').innerHTML='<h2>Solicitação de materiais</h2>'+
 (editable?'<form id="comprasSolicitarForm" class="ewComprasForm"><label>Local de estoque de destino<select id="comprasDestino" required>'+option('','Escolha o local')+destinoOptions()+'</select></label>'+
 '<label>Observações<textarea id="comprasObservacoes" rows="2" maxlength="600"></textarea></label>'+
 '<h3>Materiais solicitados</h3><div class="ewComprasActions" style="align-items:end;flex-wrap:wrap"><label>Categoria<select id="comprasCategoria"><option value="">Todos os materiais</option><option value="perfil">Perfis</option><option value="acessorio">Acessórios</option></select></label><label>Buscar material<input id="comprasBuscaMaterial" type="search" placeholder="Código, descrição ou cor"></label><label style="display:flex;align-items:center;gap:8px"><input id="comprasExtras" type="checkbox" style="width:16px;height:16px"> Mostrar materiais extras e já atendidos</label></div><p id="comprasMateriaisStatus" class="hint" role="status"></p><div id="comprasLinhas"></div><div class="ewComprasActions"><button class="btn secondary" id="comprasAddLine" type="button">+ Adicionar material</button><button class="btn primary" type="submit">Criar solicitação</button></div></form>':'')+
 '<h3>Solicitações registradas</h3><div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Data</th><th>Destino</th><th>Itens</th><th>Situação</th><th>Ação</th></tr></thead><tbody>'+
 sols.map(s=>'<tr><td>'+esc(String(s.criado_em||'').slice(0,10).split('-').reverse().join('/'))+'</td><td>'+esc(titleLocal(s))+'</td><td>'+number((s.itens||[]).length)+'</td><td>'+esc(s.status)+cancelDetails(s)+'</td><td>'+(editable&&s.status==='ABERTA'&&!orders.some(p=>p.solicitacao_id===s.id)?'<button type="button" class="btn secondary" data-compras-tipo="solicitacao" data-compras-cancel="'+esc(s.id)+'">Cancelar</button>':'—')+'</td></tr>').join('')+
 '</tbody></table></div>';bindCancelButtons();if(editable){requestNeeds=[];requestNeedsReady=false;makeLine();$('comprasAddLine').onclick=makeLine;
 $('comprasDestino').onchange=loadRequestNeeds;$('comprasCategoria').onchange=()=>updateRequestRows();$('comprasBuscaMaterial').oninput=()=>updateRequestRows();$('comprasExtras').onchange=()=>updateRequestRows();void loadRequestNeeds();
 $('comprasSolicitarForm').onsubmit=async e=>{e.preventDefault();const value=$('comprasDestino').value;
 const lines=[...document.querySelectorAll('#comprasLinhas .ewComprasLine')].map((row,i)=>{
  const get=x=>row.querySelector('[data-buy="'+x+'"]').value;
  const v=requestOptions(true).find(v=>v.key===get('variation'));
  return {chave:String(i+1),variacao_id:v?.id||'',quantidade:Number(get('qty')),
   unidade:get('unit'),comprimento_mm:get('unit')==='BARRA'?Number(get('length')):null};});
 if(!value||lines.some(x=>!x.variacao_id||!validQty(x.quantidade,x.unidade)||
   (x.unidade==='BARRA'&&(!Number.isSafeInteger(x.comprimento_mm)||x.comprimento_mm<100||x.comprimento_mm>20000)))){
  say('comprasMensagem','Preencha destino, material e quantidades válidas.');return;}
 if(!requestNeedsReady)return;
 if(!$('comprasExtras').checked&&value.startsWith('obra:')){
  const combined=new Map();for(const line of lines){const k=line.variacao_id+'|'+(line.comprimento_mm??'');combined.set(k,(combined.get(k)||0)+line.quantidade);}
  const eligible=requestOptions(true);
  for(const [k,q] of combined){const v=eligible.find(v=>v.key===k);if(!v||v.faltante!==null&&q>Number(v.faltante)+1e-8){say('comprasMensagem','Quantidade ou comprimento fora da necessidade. Marque materiais extras e já atendidos para solicitar além da previsão.');return;}}
 }
 const [kind,id]=value.split(':');const btn=$('comprasSolicitarForm').querySelector('[type="submit"]');if(btn.disabled)return;btn.disabled=true;
 try{await ensureSession();await rpc('ew_compras_criar_solicitacao',{p_empresa_id:currentCompany.id,
  p_obra_id:kind==='obra'?id:null,p_local_empresa_id:kind==='empresa'?id:null,
  p_itens:lines,p_observacoes:$('comprasObservacoes').value,
  p_operacao_id:operationToken('solicitar',{value,lines,obs:$('comprasObservacoes').value})});
  pendingOps.delete('solicitar');
  await reload();renderRequest();say('comprasMensagem','Solicitação registrada.');
 }catch(e){say('comprasMensagem','Erro: '+e.message)}finally{btn.disabled=false;}};
 }}
let quotePreferredSolic='',groupCatalog=null,groupLinks=[],groupEpoch=0;
const linkFor=id=>groupLinks.find(x=>x.filha_id===id);
const eligibleSuppliers=id=>{
 const link=linkFor(id);
 if(!link)return groupCatalog?.legados?.includes(id)?suppliers:[];
 const group=groupCatalog?.grupos.find(g=>g.id===link.grupo_id&&g.ativo);
 return group?suppliers.filter(f=>groupCatalog.fornecedores.find(x=>x.id===f.id)?.grupos.includes(group.id)):[];
};
async function loadQuoteGroups(){
 const company=currentCompany.id,seq=++groupEpoch;
 const [catalog,links]=await Promise.all([rpc('ew_compras_grupos_catalogo',{p_empresa_id:company}),rpc('ew_compras_grupos_desdobrados',{p_empresa_id:company})]);
 if(seq!==groupEpoch||currentCompany?.id!==company)throw Error('Consulta de grupos substituída.');
 if(!Array.isArray(catalog?.grupos)||!Array.isArray(catalog?.fornecedores)||!Array.isArray(links))throw Error('Resposta inválida de grupos de compra.');
 groupCatalog=catalog;groupLinks=links;
}
function quoteLabel(s){const l=linkFor(s.id);return titleLocal(s)+' · '+(l?l.nome+' · ':'')+(s.itens||[]).length+' itens';}
function quoteGroupCards(parent,links){
 return '<h3>Grupos da solicitação</h3>'+links.map(l=>{
  const child=sols.find(x=>x.id===l.filha_id);const status=l.status==='PEDIDO_GERADO'?'Pedido gerado':l.status==='CANCELADA'?'Cancelado':'Aguardando cotação';
  return '<div class="ewComprasForm"><strong>'+esc(l.nome)+'</strong><span>'+esc(status)+' · '+number(child?.itens?.length||0)+' itens</span>'+(l.status==='ABERTA'?'<button type="button" class="btn secondary" data-escolher-grupo="'+esc(l.filha_id)+'">Cotar este grupo</button>':'')+'</div>';
 }).join('');
}
async function previewQuoteGroups(s,root,form,company){
 if(!s||!root)return;
 const links=groupLinks.filter(l=>l.solicitacao_id===s.id);
 if(links.length){
  root.innerHTML=quoteGroupCards(s,links);
  root.querySelectorAll('[data-escolher-grupo]').forEach(b=>b.onclick=()=>{quotePreferredSolic=b.dataset.escolherGrupo;renderQuote();});
  return;
 }
 root.textContent='Separando materiais por grupo…';
 try{
  const gs=await rpc('ew_compras_previa_grupos',{p_empresa_id:company,p_solicitacao_id:s.id});
  if(!root.isConnected||currentCompany?.id!==company||$('comprasCotacaoSolic')?.value!==s.id)return;
  if(!Array.isArray(gs)||!gs.length)throw Error('Nenhum grupo encontrado.');
  root.innerHTML='<h3>Grupos encontrados</h3>'+gs.map(g=>'<div class="ewComprasForm"><strong>'+esc(g.nome)+'</strong><div>'+g.itens.map(i=>'<div class="ewComprasGrupoItem"><span>'+esc(productLabel(variations.find(v=>v.id===i.variacao_id)||{nome:i.variacao_id}))+' · '+number(i.quantidade)+' '+esc(i.unidade)+'</span>'+(permission('compras.gerenciar_grupos')?'<button type="button" class="btn secondary" data-alterar-grupo="'+esc(i.variacao_id)+'" data-grupo-atual="'+esc(g.grupo_id||'')+'">Alterar grupo</button>':'')+'</div>').join('')+'</div><span class="hint">'+(g.fornecedores.length?esc(g.fornecedores.map(f=>f.nome).join(', ')):'Nenhum fornecedor classificado para este grupo')+'</span></div>').join('')+'<button type="button" id="comprasPrepararGrupos" class="btn primary" '+(gs.some(g=>!g.ativo)?'disabled':'')+'>Preparar cotações por grupo</button><p class="hint">A solicitação original ficará preservada; cada grupo poderá gerar seu próprio pedido.</p>';
  root.querySelectorAll('[data-alterar-grupo]').forEach(button=>button.onclick=()=>{
   if(!permission('compras.gerenciar_grupos')||currentCompany?.id!==company)return;
   const item=button.dataset.alterarGrupo,actual=button.dataset.grupoAtual;
   const row=button.closest('.ewComprasGrupoItem');
   if(row.querySelector('select'))return;
   const controls=document.createElement('div');controls.className='ewComprasGrupoEdicao';
   controls.innerHTML='<label>Novo grupo de compra<select aria-label="Novo grupo de compra">'+option('','Escolha o grupo')+groupCatalog.grupos.filter(g=>g.ativo).map(g=>option(g.id,g.nome)).join('')+'</select></label><button type="button" class="btn primary" data-salvar-grupo>Salvar grupo</button><button type="button" class="btn secondary" data-cancelar-grupo>Cancelar</button><p class="hint">Atualiza o grupo comercial desta variação também nas próximas cotações, sem alterar seu cadastro técnico ou estoque.</p>';
   row.append(controls);button.hidden=true;
   const select=controls.querySelector('select'),save=controls.querySelector('[data-salvar-grupo]'),cancel=controls.querySelector('[data-cancelar-grupo]');
   select.value=actual;save.disabled=!select.value||select.value===actual;
   select.onchange=()=>{save.disabled=!select.value||select.value===actual;};
   cancel.onclick=()=>{controls.remove();button.hidden=false;};
   save.onclick=async()=>{
    const target=select.value;if(!target||target===actual||save.disabled)return;
    const group=groupCatalog.grupos.find(g=>g.id===target&&g.ativo);if(!group)return;
    if(!confirm('Alterar o grupo deste material para '+group.nome+'? A classificação valerá para as próximas cotações.'))return;
    const prepare=$('comprasPrepararGrupos');save.disabled=true;cancel.disabled=true;select.disabled=true;if(prepare)prepare.disabled=true;
    root.querySelectorAll('[data-alterar-grupo]').forEach(b=>b.disabled=true);
    try{
     await ensureSession();
     if(currentCompany?.id!==company||!root.isConnected||$('comprasCotacaoSolic')?.value!==s.id)throw Error('Seleção alterada.');
     await rpc('ew_compras_classificar_material',{p_empresa_id:company,p_variacao_id:item,p_grupo_id:target});
     if(root.isConnected&&currentCompany?.id===company&&$('comprasCotacaoSolic')?.value===s.id){
      await previewQuoteGroups(s,root,form,company);say('comprasMensagem','Grupo do material atualizado. Confira a nova separação.');
     }
    }catch(e){if(root.isConnected){say('comprasMensagem','Não foi possível alterar o grupo: '+e.message);save.disabled=false;cancel.disabled=false;select.disabled=false;if(prepare)prepare.disabled=gs.some(g=>!g.ativo);root.querySelectorAll('[data-alterar-grupo]').forEach(b=>b.disabled=false);}}
   };
  });
  $('comprasPrepararGrupos').onclick=async()=>{const btn=$('comprasPrepararGrupos');if(btn.disabled)return;btn.disabled=true;
   try{await ensureSession();await rpc('ew_compras_desdobrar_grupos',{p_empresa_id:company,p_solicitacao_id:s.id,p_operacao_id:operationToken('desdobrar',{id:s.id})});
    pendingOps.delete('desdobrar');await reload();await loadQuoteGroups();quotePreferredSolic='';renderQuote();say('comprasMensagem','Grupos preparados. Selecione um dos grupos no campo Solicitação.');
   }catch(e){say('comprasMensagem','Desdobramento bloqueado: '+e.message);if(btn.isConnected)btn.disabled=false;}
  };
 }catch(e){if(root.isConnected&&$('comprasCotacaoSolic')?.value===s.id)root.textContent='Grupos indisponíveis: '+e.message;}
}
function groupingHtml(list){
 list=list.filter(s=>!linkFor(s.id));if(!permission('compras.agrupar')||!list.some(s=>s.obra_id))return '';
 const ids=[...new Set(list.filter(s=>s.obra_id).map(s=>s.obra_id))];
 return '<div class="ewComprasForm" id="comprasAgruparBox"><div class="ewComprasActions"><button class="btn primary" type="button" id="comprasAgruparAbrir" aria-expanded="false" aria-controls="comprasAgruparPainel">+ Juntar solicitações da mesma obra</button><span class="hint">Selecione duas ou mais solicitações abertas.</span></div><div id="comprasAgruparPainel" hidden>'+
 '<label>Obra<select id="comprasAgruparObra">'+option('','Escolha a obra')+ids.map(id=>option(id,works.find(w=>w.id===id)?.nome||id)).join('')+'</select></label>'+
 '<div id="comprasAgruparLista"></div><button class="btn secondary" id="comprasAgruparConfirmar" type="button" disabled>Juntar solicitações marcadas</button>'+
 '<p class="hint">Itens iguais serão somados por variação, unidade e comprimento. As originais permanecem no histórico.</p></div></div>';
}
function bindGrouping(list){
 const select=$('comprasAgruparObra');if(!select)return;
 const box=$('comprasAgruparLista'),btn=$('comprasAgruparConfirmar');
 const open=$('comprasAgruparAbrir'),panel=$('comprasAgruparPainel');
 open.onclick=()=>{panel.hidden=!panel.hidden;open.setAttribute('aria-expanded',String(!panel.hidden));open.textContent=panel.hidden?'+ Juntar solicitações da mesma obra':'− Fechar agrupamento';if(!panel.hidden)select.focus();};

 const checked=()=>[...box.querySelectorAll('input:checked')].map(x=>x.value).sort();
 select.onchange=()=>{
  box.innerHTML=list.filter(s=>!linkFor(s.id)&&s.obra_id===select.value&&!quotes.some(q=>q.solicitacao_id===s.id&&q.status!=='CANCELADA'))
   .map(s=>'<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" value="'+esc(s.id)+'" style="width:16px;height:16px"> '+esc(String(s.criado_em).slice(0,10))+' · '+number((s.itens||[]).length)+' itens · '+esc(s.observacoes||s.id.slice(0,8))+'</label>').join('');
  btn.disabled=true;box.onchange=()=>{btn.disabled=checked().length<2;};
 };
 btn.onclick=async()=>{
  const ids=checked(),obra=select.value;if(ids.length<2||!obra||!permission('compras.agrupar'))return;
  if(!confirm('Consolidar '+ids.length+' solicitações? As originais deixam de ficar disponíveis separadamente para cotação.'))return;
  btn.disabled=true;
  try{await ensureSession();const r=await rpc('ew_compras_agrupar_solicitacoes',{p_empresa_id:currentCompany.id,p_obra_id:obra,p_solicitacoes:ids,p_operacao_id:operationToken('agrupar',{obra,ids})});
   pendingOps.delete('agrupar');quotePreferredSolic=r.id;await reload();renderQuote();say('comprasMensagem','Solicitações agrupadas. Escolha o fornecedor.');
  }catch(e){say('comprasMensagem','Agrupamento bloqueado: '+e.message);btn.disabled=checked().length<2;}
 };
}
function quoteModel(core,s,f){
 return core.modelo(s.id,f,(s.itens||[]).map(i=>({...i,material:productLabel(variations.find(v=>v.id===i.variacao_id)||{nome:i.variacao_id})})));
}
function bindReplicarFornecedores(){
 const root=$('comprasConvites'),sol=$('comprasCotacaoSolic'),supplier=$('comprasCotacaoFornecedor');
 if(!root||!sol||!supplier)return ()=>{};
 let epoch=0;
 async function render(){
  const id=sol.value,company=currentCompany.id,seq=++epoch;
  root.replaceChildren();if(!id)return;
  const s=sols.find(x=>x.id===id);if(!s)return;
  try{
   const convites=await rpc('ew_compras_convites_cotacao',{p_empresa_id:company,p_solicitacao_id:id});
   if(!root.isConnected||seq!==epoch||sol.value!==id||currentCompany?.id!==company)return;
   if(!Array.isArray(convites))throw Error('Resposta inválida.');
   const exist=new Set(convites.map(x=>x.fornecedor_id));
   root.innerHTML='<h3>Fornecedores desta cotação</h3>'+
    (convites.length?'<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Fornecedor</th><th>Situação</th><th>Ação</th></tr></thead><tbody>'+
    convites.map(c=>'<tr><td>'+esc(c.fornecedor)+'</td><td>'+esc(c.status==='RESPONDIDA'?'Respondida':c.status==='ENCERRADA'?'Encerrada':'Aguardando retorno')+'</td><td>'+(c.ativo&&c.status!=='ENCERRADA'?'<button type="button" class="btn secondary" data-convite="'+esc(c.fornecedor_id)+'">Selecionar</button>':'—')+'</td></tr>').join('')+'</tbody></table></div>':'<p class="hint">Nenhum fornecedor selecionado em lote.</p>')+
    (permission('compras.replicar_cotacao')?'<details><summary>Replicar lista para vários fornecedores</summary><div style="max-height:240px;overflow:auto">'+eligibleSuppliers(id).filter(f=>!exist.has(f.id)).map(f=>'<label style="display:flex;align-items:center;gap:8px"><input type="checkbox" data-fornecedor="'+esc(f.id)+'" style="width:16px;height:16px"> '+esc(f.nome)+'</label>').join('')+'</div><button type="button" class="btn secondary" id="comprasReplicarLote">Criar cotações para selecionados</button></details>':'');
   root.querySelectorAll('[data-convite]').forEach(b=>b.onclick=()=>{supplier.value=b.dataset.convite;supplier.onchange?.();supplier.focus();});
   const btn=$('comprasReplicarLote');
   if(btn)btn.onclick=async()=>{
    const ids=[...root.querySelectorAll('[data-fornecedor]:checked')].map(x=>x.dataset.fornecedor);
    if(!ids.length||!permission('compras.replicar_cotacao'))return;
    btn.disabled=true;
    try{await ensureSession();await rpc('ew_compras_replicar_cotacao',{p_empresa_id:company,p_solicitacao_id:id,p_fornecedores:ids});
      if(root.isConnected&&sol.value===id&&currentCompany?.id===company){say('comprasMensagem','Fornecedores registrados. Selecione cada um para exportar ou importar seu Excel.');await render();}
    }catch(e){say('comprasMensagem','Não foi possível replicar: '+e.message);}finally{btn.disabled=false;}
   };
  }catch(e){if(root.isConnected&&seq===epoch)root.textContent='Convites indisponíveis: '+e.message;}
 }
 return render;
}
function bindQuoteExcel(){
 if(!$('comprasCotacaoExportar'))return;
 const sol=$('comprasCotacaoSolic'),supplier=$('comprasCotacaoFornecedor'),file=$('comprasCotacaoArquivo');
 const context=()=>{const s=sols.find(x=>x.id===sol.value),f=eligibleSuppliers(sol.value).find(x=>x.id===supplier.value);if(!s||!f)throw Error('Selecione solicitação e fornecedor.');return {s,f};};
 $('comprasCotacaoExportar').onclick=async()=>{
  try{if(!permission('compras.cotacao_excel'))return;const {s,f}=context(),core=await import('/assets/compras-cotacao-xlsx.mjs?v=20261125d');
   const blob=core.exportarXlsx(quoteModel(core,s,f.id),{empresa:currentCompany?.nome||'EWGEST',obra:titleLocal(s),grupo:linkFor(s.id)?.nome||'Materiais',fornecedor:f.nome}),url=URL.createObjectURL(blob),a=document.createElement('a');
   a.href=url;a.download='cotacao_'+f.nome.replace(/[^a-zA-Z0-9_-]+/g,'_')+'_'+s.id.slice(0,8)+'.xlsx';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
   say('comprasMensagem','Planilha exportada. Peça ao fornecedor para preencher somente o preço unitário.');
  }catch(e){say('comprasMensagem',e.message);}
 };
 file.onchange=async()=>{
  try{if(!permission('compras.cotacao_excel')||!file.files?.length)return;const {s,f}=context(),company=currentCompany.id,core=await import('/assets/compras-cotacao-xlsx.mjs?v=20261125d');
   const prices=core.validarRetorno(quoteModel(core,s,f.id),await core.lerXlsx(file.files[0]));
   if(!file.isConnected||company!==currentCompany?.id||sol.value!==s.id||supplier.value!==f.id)throw Error('Seleção mudou; importe novamente.');
   const inputs=new Map([...document.querySelectorAll('[data-quote-key]')].map(row=>[row.dataset.quoteKey,row.querySelector('input')]));
   if(prices.some(p=>!inputs.has(p.chave)))throw Error('Itens da cotação mudaram.');
   for(const p of prices)inputs.get(p.chave).value=formatMoneyInput(p.preco_unitario_centavos);
   say('comprasMensagem','Planilha validada. Confira os preços e clique em Registrar cotação.');
  }catch(e){say('comprasMensagem','Importação bloqueada: '+e.message);}finally{file.value='';}
 };
}
function renderQuote(){
 if(!permission('compras.consultar_valores')){
  $('comprasConteudo').innerHTML='<h2>Cotações</h2><p class="hint">Os valores dos fornecedores são restritos aos níveis com permissão para consultar preços.</p>';return;
 }
 const root=$('comprasConteudo');
 if(!groupCatalog){root.innerHTML='<p class="hint">Consultando grupos de compra…</p>';void loadQuoteGroups().then(()=>{if(tab==='cotacao')renderQuote();}).catch(e=>{if(tab==='cotacao')root.textContent='Grupos indisponíveis: '+e.message;});return;}
 const list=sols.filter(s=>s.status==='ABERTA'&&!orders.some(p=>p.solicitacao_id===s.id)),editable=permission('compras.cotar');
 $('comprasConteudo').innerHTML='<h2>Cotação</h2><p class="hint">Cotação por fornecedor. Várias cotações podem ser comparadas para uma solicitação; apenas a escolhida vira pedido.</p>'+
 (editable?groupingHtml(list.filter(s=>s.status==='ABERTA'))+'<form id="comprasCotarForm" class="ewComprasForm"><label>Solicitação<select id="comprasCotacaoSolic" required>'+option('','Escolha')+list.map(s=>option(s.id,quoteLabel(s))).join('')+'</select></label>'+
 '<div id="comprasGruposPrevia"></div><div id="comprasGrupoEditor" hidden><label>Fornecedor<select id="comprasCotacaoFornecedor" required>'+option('','Escolha')+'</select></label><div id="comprasCotacaoItens"></div><div id="comprasConvites"></div>'+
 (permission('compras.cotacao_excel')?'<div class="ewComprasActions" style="flex-wrap:wrap"><button type="button" class="btn secondary" id="comprasCotacaoExportar">Exportar Excel para fornecedor</button><label>Importar Excel preenchido<input id="comprasCotacaoArquivo" type="file" accept=".xlsx"></label></div>':'')+
 '<button class="btn primary" type="submit">Registrar cotação</button></div></form>':'')+
 '<h3>Cotações registradas</h3><div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Fornecedor</th><th>Destino</th><th>Total</th><th>Situação</th><th>Ação</th></tr></thead><tbody>'+
 quotes.map(q=>{const s=sols.find(x=>x.id===q.solicitacao_id);return '<tr><td>'+esc(suppliers.find(x=>x.id===q.fornecedor_id)?.nome||'Fornecedor')+'</td><td>'+esc(s?titleLocal(s):'-')+'</td><td>'+money(q.total_centavos)+'</td><td>'+esc(q.status==='CANCELADA'?'Cancelada':orders.some(p=>p.cotacao_id===q.id)?'Pedido gerado':'Em avaliação')+cancelDetails(q)+'</td><td>'+(editable&&q.status!=='CANCELADA'&&s?.status==='ABERTA'&&!orders.some(p=>p.solicitacao_id===q.solicitacao_id)?'<button type="button" class="btn secondary" data-compras-tipo="cotacao" data-compras-cancel="'+esc(q.id)+'">Cancelar</button>':'—')+(editable&&permission('compras.replicar_cotacao')&&s?.status==='ABERTA'&&q.status!=='CANCELADA'?'<button class="btn secondary" type="button" data-cotacao-replicar="'+esc(q.solicitacao_id)+'">Replicar lista</button>':'')+'</td></tr>'}).join('')+'</tbody></table></div>';bindCancelButtons();
 bindGrouping(list.filter(s=>s.status==='ABERTA'));bindQuoteExcel();const renderConvites=bindReplicarFornecedores();
 $('comprasConteudo').querySelectorAll('[data-cotacao-replicar]').forEach(b=>b.onclick=()=>{quotePreferredSolic=b.dataset.cotacaoReplicar;renderQuote();$('comprasCotacaoFornecedor').focus();say('comprasMensagem','Lista replicada. Selecione outro fornecedor e exporte o Excel; preços anteriores não foram copiados.');});
 if(editable){$('comprasCotacaoSolic').onchange=()=>{
  const s=sols.find(x=>x.id===$('comprasCotacaoSolic').value),editor=$('comprasGrupoEditor'),supplier=$('comprasCotacaoFornecedor'),preview=$('comprasGruposPrevia');
  const isGroup=s&&(linkFor(s.id)||groupCatalog.legados?.includes(s.id));
  editor.hidden=!isGroup;supplier.disabled=!isGroup;preview.replaceChildren();
  supplier.innerHTML=option('','Escolha')+(isGroup?eligibleSuppliers(s.id).map(x=>option(x.id,x.nome)).join(''):'');
  $('comprasCotarForm').querySelector('[type=submit]').disabled=!isGroup||!eligibleSuppliers(s.id).length;
  if(!isGroup){$('comprasCotacaoItens').replaceChildren();$('comprasConvites').replaceChildren();if(s)void previewQuoteGroups(s,preview,$('comprasCotarForm'),currentCompany.id);return;}
  if(!eligibleSuppliers(s.id).length){
   preview.innerHTML='<p class="hint">Nenhum fornecedor habilitado neste grupo. Cadastros do sistema → Fornecedores → Grupos atendidos por fornecedor.</p>';
   if(permission('compras.gerenciar_grupos')&&$('cadastroJumpFornecedores')){
    const btn=document.createElement('button');btn.type='button';btn.className='btn primary';btn.id='comprasAbrirCadastroFornecedor';btn.textContent='Classificar fornecedores';
    btn.onclick=()=>{$('cadastroJumpFornecedores').click();};preview.append(btn);
   }
  }
  void renderConvites();
  $('comprasCotacaoItens').innerHTML=s?'<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Material</th><th>Quantidade</th><th>Un.</th><th>Preço unitário (R$)</th></tr></thead><tbody>'+
  (s.itens||[]).map(i=>'<tr data-quote-key="'+esc(i.chave)+'"><td>'+esc(productLabel(variations.find(v=>v.id===i.variacao_id)||{nome:i.variacao_id}))+'</td><td>'+number(i.quantidade)+'</td><td>'+esc(i.unidade)+'</td><td><input type="text" inputmode="decimal" required placeholder="R$ 0,00" aria-label="Preço unitário em reais" style="text-align:right;font-variant-numeric:tabular-nums"></td></tr>').join('')+'</tbody></table></div>':'';
  bindQuoteMoney();
 };
 if(quotePreferredSolic&&list.some(s=>s.id===quotePreferredSolic)){$('comprasCotacaoSolic').value=quotePreferredSolic;$('comprasCotacaoSolic').onchange();}quotePreferredSolic='';
 $('comprasCotacaoFornecedor').onchange=()=>{$('comprasCotacaoItens').querySelectorAll('input').forEach(i=>i.value='');};
 $('comprasCotarForm').onsubmit=async e=>{e.preventDefault();const s=sols.find(x=>x.id===$('comprasCotacaoSolic').value);
 const precos=[...document.querySelectorAll('[data-quote-key]')].map(row=>({chave:row.dataset.quoteKey,preco_unitario_centavos:parseMoney(row.querySelector('input').value)}));
 if(!s||!eligibleSuppliers(s.id).some(f=>f.id===$('comprasCotacaoFornecedor').value)||precos.some(x=>x.preco_unitario_centavos===null)){say('comprasMensagem','Valores inválidos.');return;}
 try{await rpc('ew_compras_criar_cotacao',{p_solicitacao_id:s.id,p_fornecedor_id:$('comprasCotacaoFornecedor').value,
 p_precos:precos,p_operacao_id:operationToken('cotar',{id:s.id,fornecedor:$('comprasCotacaoFornecedor').value,precos})});
 pendingOps.delete('cotar');await reload();renderQuote();say('comprasMensagem','Cotação registrada.');
 }catch(err){say('comprasMensagem','Erro: '+err.message)}};
 }}
function renderOrder(){
 const editable=permission('compras.pedir')&&permission('compras.aprovar_pedido')&&permission('compras.consultar_valores');
 const pending=quotes.filter(q=>q.status!=='CANCELADA'&&sols.some(s=>s.id===q.solicitacao_id&&s.status==='ABERTA')&&!orders.some(p=>p.solicitacao_id===q.solicitacao_id));
 $('comprasConteudo').innerHTML='<h2>Pedidos de compra</h2><p class="hint">A aprovação compromete o orçamento da obra imediatamente. O recebimento físico acontece exclusivamente no setor Recebimento.</p>'+
 (editable?'<form id="comprasPedidoForm" class="ewComprasForm"><label>Cotação aprovada<select id="comprasPedidoCotacao" required>'+option('','Escolha')+
 pending.map(q=>{const s=sols.find(x=>x.id===q.solicitacao_id);return option(q.id,(s?titleLocal(s):'Solicitação')+' · '+(suppliersAll.find(f=>f.id===q.fornecedor_id)?.nome||'Fornecedor')+' · '+money(q.total_centavos))}).join('')+
 '</select></label><button class="btn primary" type="submit">Aprovar cotação e gerar pedido</button></form>':'')+
 '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Pedido</th><th>Destino</th><th>Valor</th><th>Recebimento</th><th>Ação</th></tr></thead><tbody>'+
 orders.map(p=>'<tr><td>#'+number(p.numero)+'</td><td>'+esc(titleLocal(p))+'</td><td>'+(permission('compras.consultar_valores')?money(p.total_centavos):'Restrito')+'</td><td>'+esc(orderStatus(p))+cancelDetails(p)+'</td><td>'+(editable&&p.status==='ABERTO'&&!receipts.some(r=>r.pedido_id===p.id)?'<button type="button" class="btn secondary" data-compras-tipo="pedido" data-compras-cancel="'+esc(p.id)+'">Cancelar</button>':'—')+'</td></tr>').join('')+'</tbody></table></div>';bindCancelButtons();
 if(editable)$('comprasPedidoForm').onsubmit=async e=>{e.preventDefault();const id=$('comprasPedidoCotacao').value;
 const q=pending.find(x=>x.id===id);if(!q||!permission('compras.aprovar_pedido'))return;
 if(!window.confirm('Aprovar o pedido de '+money(q.total_centavos)+'? O valor será comprometido no orçamento se for compra para obra.'))return;
 const btn=$('comprasPedidoForm').querySelector('button[type=submit]');if(btn.disabled)return;btn.disabled=true;
 try{await rpc('ew_compras_criar_pedido',{p_cotacao_id:id,p_operacao_id:operationToken('pedir',{id})});
 pendingOps.delete('pedir');await reload();renderOrder();say('comprasMensagem','Pedido aprovado, disponível para recebimento.');
 }catch(err){say('comprasMensagem','Erro: '+err.message)}finally{btn.disabled=false;}};
 if(permission('financeiro.despesas')&&permission('compras.consultar_valores')){
  const box=document.createElement('section');box.id='ewComprasConciliacao';box.className='section panel';
  $('comprasConteudo').appendChild(box);void window.ewComprasNfe?.render(box,contextoConciliacao());
 }
}
const etapasCompras={
 solicitacao:{titulo:'Solicitação de compra',descricao:'Registre e consulte as solicitações de materiais.'},
 cotacao:{titulo:'Cotação',descricao:'Compare fornecedores e preços por grupo de compra.'},
 pedido:{titulo:'Compra',descricao:'Aprove cotações, gere pedidos e acompanhe os recebimentos.'}
};
function render(){
 const etapa=etapasCompras[tab];
 if($('comprasPaginaTitulo'))$('comprasPaginaTitulo').textContent=etapa.titulo;
 if($('comprasPaginaDescricao'))$('comprasPaginaDescricao').textContent=etapa.descricao;
 for(const [k,id] of [['solicitacao','comprasTabSolicitacao'],['cotacao','comprasTabCotacao'],['pedido','comprasTabPedido']]){
  const btn=$(id);if(!btn)continue;btn.classList.toggle('active',k===tab);
  if(k===tab)btn.setAttribute('aria-current','page');else btn.removeAttribute('aria-current');
 }
 if(tab==='solicitacao')renderRequest();else if(tab==='cotacao')renderQuote();else renderOrder();
}
let comprasNavEpoch=0;
async function abrir(etapa=tab){
 if(!permission('compras.consultar')||!Object.hasOwn(etapasCompras,etapa))return;
 const seq=++comprasNavEpoch;tab=etapa;setView('compras');
 $('navComprasSubmenu')?.classList.remove('hidden');$('navCompras')?.setAttribute('aria-expanded','true');
 if($('comprasPaginaTitulo'))$('comprasPaginaTitulo').textContent=etapasCompras[tab].titulo;
 if($('comprasPaginaDescricao'))$('comprasPaginaDescricao').textContent=etapasCompras[tab].descricao;
 $('comprasConteudo').replaceChildren();say('comprasMensagem','Carregando compras…');
 try{await reload();if(seq!==comprasNavEpoch||$('compras')?.classList.contains('hidden'))return;groupCatalog=null;groupLinks=[];render();say('comprasMensagem','')}
 catch(e){if(seq===comprasNavEpoch)say('comprasMensagem','Compras ainda indisponíveis: '+e.message);}
}
// Os controles antigos movem estoque apenas entre obras existentes.
// Para um local da empresa, bloquear ações legadas até a transferência dedicada.
for(const id of ['stockTransferPickLocal','stockTransferPickWork','stockManageLocations']){
 $(id)?.addEventListener('click',event=>{
  if(!$('stockWork')?.value.startsWith('empresa:'))return;
  event.preventDefault();event.stopImmediatePropagation();
  say('stockMessage','Transferências e estornos do local da empresa dependem da rotina específica de estoque; não use uma obra fictícia.');
 },true);
}
for(const [tabValue,id] of [['solicitacao','comprasTabSolicitacao'],['cotacao','comprasTabCotacao'],['pedido','comprasTabPedido']])
 $(id)?.addEventListener('click',()=>{if(permission('compras.consultar'))void abrir(tabValue);});
async function carregarLocaisRecebimento(select){
 if(!permission('compras.receber')||!currentCompany)return;
 try{
  await ensureSession();
  const values=await apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',empresa_id:'eq.'+currentCompany.id,ativo:'eq.true',order:'nome.asc'});
  for(const loc of values||[])select.add(new Option('Empresa · '+loc.nome,'empresa:'+loc.id));
 }catch(e){say('recebimentoMessage','Locais empresariais indisponíveis: '+e.message);}
}
async function atualizarRecebimento(obraId,preferredOrder=''){
 const epoch=++receivingEpoch;
 const box=$('ewComprasRecebimento');
 box.classList.toggle('hidden',!obraId||!permission('compras.receber')||!permission('estoque.receber'));
 if(box.classList.contains('hidden'))return;
 box.innerHTML='<h2>Receber por pedido de compra</h2><p class="hint">Entrada física por pedido, sem lançamento fiscal automático. Consulte as quantidades já recebidas antes de confirmar.</p><p class="feedback">Consultando pedidos pendentes…</p>';
 try{await reload();if(epoch!==receivingEpoch||$('recebimentoWork').value!==obraId)return;
 const empresaDestino=obraId.startsWith('empresa:');
 const ativos=orders.filter(p=>(empresaDestino?p.local_empresa_id===obraId.slice(8):p.obra_id===obraId)&&p.status!=='CANCELADO');
 box.innerHTML='<div class="recebimentoPedidoEntrada"><h2>Receber por pedido de compra</h2><p class="hint">Receba todo ou parte do pedido; somente o saldo efetivamente confirmado será acrescentado ao estoque físico.</p></div><div class="recebimentoPedidoHistorico"><h2>Histórico de recebimentos por pedido</h2><p class="hint">Selecione o pedido para conferir as entradas e estornar um recebimento específico.</p></div>'+
 '<label>Pedido<select id="ewReceberPedido">'+option('','Selecione o pedido')+ativos.map(p=>option(p.id,'#'+p.numero+' · '+orderStatus(p))).join('')+'</select></label>'+
 '<form id="ewReceberForm" class="hidden"><div id="ewReceberItens"></div><label>Galpão de destino<select id="ewReceberGalpao" required>'+
 option('','Selecione')+galpoes.map(g=>option(g,g)).join('')+'</select></label>'+
 '<div class="ewComprasActions"><button type="submit" class="btn primary">Confirmar recebimento físico</button></div></form>'+ 
 '<div id="ewReceberHistorico"></div>'+ 
 '<p id="ewReceberMessage" class="feedback" role="status"></p>';
 $('ewReceberPedido').onchange=()=>{const p=orders.find(x=>x.id===$('ewReceberPedido').value),form=$('ewReceberForm');
 form.classList.toggle('hidden',!p);if(!p){$('ewReceberHistorico').replaceChildren();return;}
 const received=receivedMap(p.id);
 const historico=receipts.filter(r=>r.pedido_id===p.id);
 const podeEstornar=permission('estoque.estornar')&&permission('compras.receber');
 $('ewReceberHistorico').innerHTML='<h3>Histórico de recebimentos deste pedido</h3>'+
 (historico.length?'<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Data</th><th>Galpão</th><th>Quantidade</th><th>Status</th><th>Ação</th></tr></thead><tbody>'+
 historico.map(r=>'<tr><td>'+esc(String(r.criado_em||'').slice(0,10).split('-').reverse().join('/'))+
 '</td><td>'+esc(r.galpao||'-')+'</td><td>'+number((r.itens||[]).length)+
 ' item(ns) (quantidades na tabela acima)</td><td>'+esc(r.estornado_em?'Estornado: '+(r.estorno_motivo||''):'Recebido')+
 '</td><td>'+(podeEstornar&&!r.estornado_em?'<button type="button" class="btn secondary" data-ew-reverse="'+esc(r.id)+'">Estornar</button>':'—')+'</td></tr>').join('')+
 '</tbody></table></div>':'<p class="hint">Nenhum recebimento registrado.</p>');
 $('ewReceberHistorico').querySelectorAll('[data-ew-reverse]').forEach(button=>{
  button.addEventListener('click',async ()=>{
   if(!podeEstornar)return;
   const id=button.dataset.ewReverse, motivo=window.prompt('Motivo do estorno (5 a 400 caracteres):');
   if(motivo===null)return;
   const reason=motivo.trim();
   if(reason.length<5||reason.length>400){say('ewReceberMessage','Motivo deve ter entre 5 e 400 caracteres.');return;}
   if(!window.confirm('Confirmar estorno do recebimento? O estoque físico só será revertido se não houver saídas posteriores.'))return;
   button.disabled=true;
   try{await rpc('ew_compras_estornar_recebimento',{p_recebimento_id:id,p_motivo:reason,
     p_operacao_id:operationToken('estornar_recebimento',{id,reason})});
    pendingOps.delete('estornar_recebimento');await atualizarRecebimento(obraId,p.id);if($('recebimentoWork').value===obraId)say('ewReceberMessage','Recebimento estornado. Histórico atualizado.');
   }catch(err){say('ewReceberMessage','Estorno bloqueado: '+err.message);}
   finally{button.disabled=false;}
  });
 });
 $('ewReceberItens').innerHTML='<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Receber</th><th>Material</th><th>Pedido</th><th>Recebido</th><th>Falta</th><th>Agora</th></tr></thead><tbody>'+
 (p.itens||[]).map(it=>{const r=received.get(String(it.chave))||0,remain=Math.max(0,Number(it.quantidade)-r);
 return '<tr data-receive-key="'+esc(it.chave)+'"><td><input type="checkbox" '+(remain<=0?'disabled':'')+'></td><td>'+esc(productLabel(variations.find(v=>v.id===it.variacao_id)||{nome:it.variacao_id}))+'</td>'+
 '<td>'+number(it.quantidade)+' '+esc(it.unidade)+'</td><td>'+number(r)+'</td><td><strong>'+number(remain)+'</strong></td>'+
 '<td><input type="number" min="'+(it.unidade==='KG'?'0.001':'1')+'" step="'+(it.unidade==='KG'?'0.001':'1')+'" max="'+remain+'" value="" '+(remain<=0?'disabled':'')+'></td></tr>';}).join('')+'</tbody></table></div>';
 };
 $('ewReceberForm').onsubmit=async e=>{e.preventDefault();const p=orders.find(x=>x.id===$('ewReceberPedido').value);if(!p)return;
 const m=receivedMap(p.id),itens=[...document.querySelectorAll('[data-receive-key]')].filter(row=>row.querySelector('[type=checkbox]').checked).map(row=>({chave:row.dataset.receiveKey,quantidade:Number(row.querySelector('[type=number]').value)}));
 if(!itens.length||itens.some(it=>{const line=p.itens.find(x=>String(x.chave)===it.chave);return !line||!validQty(it.quantidade,line.unidade)||
 it.quantidade>Number(line.quantidade)-(m.get(it.chave)||0)})){say('ewReceberMessage','Marque itens e informe quantidades inteiras dentro do saldo pendente.');return;}
 const button=$('ewReceberForm').querySelector('[type=submit]');if(button.disabled)return;button.disabled=true;
 try{await rpc('ew_compras_receber_pedido',{p_pedido_id:p.id,p_galpao:$('ewReceberGalpao').value,
  p_itens:itens,p_operacao_id:operationToken('receber',{pedido:p.id,galpao:$('ewReceberGalpao').value,itens})});
  pendingOps.delete('receber');
  if(epoch===receivingEpoch&&$('recebimentoWork').value===obraId){
   await atualizarRecebimento(obraId,p.id);
   if($('recebimentoWork').value===obraId)say('ewReceberMessage','Recebimento confirmado.');
  }
 }catch(err){if(epoch===receivingEpoch)say('ewReceberMessage','Erro ao receber: '+err.message);}finally{button.disabled=false;}
 };
 if(preferredOrder&&ativos.some(p=>p.id===preferredOrder)){$('ewReceberPedido').value=preferredOrder;$('ewReceberPedido').onchange();}
 }catch(e){if(epoch===receivingEpoch&&box.querySelector('.feedback'))box.querySelector('.feedback').textContent='Pedidos indisponíveis: '+e.message;}
}
async function carregarLocaisEstoque(prefer=''){
 if(!permission('estoque.consultar'))return;try{
 await ensureSession();locals=await apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',
 empresa_id:'eq.'+currentCompany.id,order:'nome.asc'})||[];
 const select=$('stockWork'),old=prefer||select.value;
 for(const opt of [...select.options].filter(o=>o.value.startsWith('empresa:')))opt.remove();
 for(const x of locals.filter(l=>l.ativo))
  select.appendChild(new Option('Empresa · '+x.nome,'empresa:'+x.id));
 if(old&&[...select.options].some(op=>op.value===old)){select.value=old;if(old.startsWith('empresa:'))renderEstoqueEmpresa();}
 }catch(e){say('stockMessage','Locais de estoque da empresa indisponíveis: '+e.message);}
}
async function renderEstoqueEmpresa(){
 const id=$('stockWork').value.replace(/^empresa:/,''),pane=$('ewEstoqueEmpresaPainel'),epoch=++stockEpoch;
 $('stockRecords').classList.add('hidden');pane.classList.remove('hidden');$('insumosStockPanel')?.classList.add('hidden');$('stockLegend')?.classList.add('hidden');
 $('stockPerfCount').textContent='—';$('stockAcesCount').textContent='—';$('stockCounted').textContent='—';
 pane.innerHTML='<p class="hint">Consultando saldo físico da empresa…</p>';
 try{const rows=await readAllRows('ew_compras_estoque_empresa',{select:'id,variacao_id,unidade,comprimento_mm,quantidade_delta,galpao',empresa_id:'eq.'+currentCompany.id,local_empresa_id:'eq.'+id});
 if(epoch!==stockEpoch||$('stockWork').value!=='empresa:'+id)return;
 const totals=new Map();for(const r of rows||[]){if($('stockFactoryFilter').value&&$('stockFactoryFilter').value!==r.galpao)continue;
 const key=[r.variacao_id,r.unidade,r.comprimento_mm||'',r.galpao].join('|');const old=totals.get(key)||{...r,quantidade:0};old.quantidade+=Number(r.quantidade_delta);totals.set(key,old)}
 const all=[...totals.values()];const list=all.filter(x=>!$('stockHideZero').checked||Math.abs(x.quantidade)>1e-9);$('stockCounted').textContent=String(all.filter(x=>Math.abs(x.quantidade)>1e-9).length);
 const displayMaterial=id=>{const v=variations.find(v=>v.id===id)||matVariacoes.find(v=>v.id===id);if(!v)return id;
 const mat=v.tipo==='perfil'?matPerfis.find(p=>p.id===v.perfil_id):matAcessorios.find(a=>a.id===v.acessorio_id);
 return mat?(mat.codigo+' · '+mat.descricao+' · '+v.cor):id;};
 pane.innerHTML='<h3>Estoque físico da empresa</h3><p class="hint">Este local não está vinculado a uma obra. A coluna Quantidade necessária não se aplica.</p>'+
 '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Material</th><th>Galpão</th><th>Comprimento</th><th>Em estoque</th></tr></thead><tbody>'+
 list.map(x=>'<tr><td>'+esc(displayMaterial(x.variacao_id))+'</td><td>'+esc(x.galpao)+'</td><td>'+esc(x.comprimento_mm?x.comprimento_mm+' mm':'—')+'</td><td><strong>'+number(x.quantidade)+' '+esc(x.unidade)+'</strong></td></tr>').join('')+
 '</tbody></table></div>';
 }catch(e){pane.innerHTML='<p class="feedback">Não foi possível consultar o estoque da empresa: '+esc(e.message)+'</p>';}
}
async function criarLocalEmpresa(){
 if(!permission('estoque.gerenciar_locais'))return;
 const nome=window.prompt('Nome do novo local de estoque da empresa (sem obra):');
 if(nome===null)return;if(nome.trim().length<3||nome.trim().length>100){say('stockMessage','Nome inválido.');return;}
 try{const novo=await rpc('ew_compras_criar_local_empresa',{p_empresa_id:currentCompany.id,p_nome:nome.trim()});
 await carregarLocaisEstoque();
 if(novo?.id){$('stockWork').value='empresa:'+novo.id;renderEstoqueEmpresa();}
 say('stockMessage','Local de estoque cadastrado.');}
 catch(e){say('stockMessage','Não foi possível cadastrar local: '+e.message);}
}

function stockDestinations(){
 return works.map(w=>({value:'OBRA:'+w.id,label:'Obra · '+w.nome}))
 .concat(locals.filter(x=>x.ativo).map(x=>({value:'EMPRESA:'+x.id,label:'Empresa · '+x.nome})));
}
function stockMaterialCatalog(){
 return matVariacoes.filter(v=>v.ativo!==false).map(v=>{
  const m=v.tipo==='perfil'?matPerfis.find(p=>p.id===v.perfil_id):matAcessorios.find(a=>a.id===v.acessorio_id);
  const unit=v.tipo==='perfil'?'BARRA':String(m?.unidade_item||'PC').trim().toUpperCase();
  return {id:v.id,label:(m?.codigo||'?')+' · '+(m?.descricao||'')+' · '+v.cor,
   unidade:unit,comprimento:v.tipo==='perfil'?(Number(m?.comprimento_comercial_mm)||6000):null};
 }).filter(x=>x.label);
}
async function abrirTransferLocal(){
 if(!permission('estoque.transferir_obras')||!permission('estoque.consultar'))return;
 const pane=$('ewTransferLocalPanel');pane.classList.remove('hidden');
 pane.innerHTML='<h3>Transferência entre locais de estoque</h3><p class="feedback">Carregando locais e movimentações…</p>';
 try{
  await ensureSession();
  locals=await apiGet('ew_compras_locais_empresa',{
   select:'id,nome,ativo',empresa_id:'eq.'+currentCompany.id,limit:'1000'})||[];
  const history=await apiGet('ew_compras_transferencias',{
   select:'*',empresa_id:'eq.'+currentCompany.id,order:'criado_em.desc',limit:'200'});
  const dest=stockDestinations(),products=stockMaterialCatalog(),houses=[...stockLocaisFisicos].sort();
  const locOpts=option('','Selecione um local')+dest.map(x=>option(x.value,x.label)).join('');
  const whOpts=option('','Selecione um galpão')+houses.map(x=>option(x,x)).join('');
  pane.innerHTML='<div class="ewComprasActions"><h3>Transferir materiais entre locais</h3>'+
   '<button type="button" class="btn secondary" id="ewTransClose">Fechar</button></div>'+
   '<p class="hint">Estoques de obra e estoques próprios da empresa são distintos. Esta operação não registra nova compra, não altera nota fiscal e exige saldo disponível no local de origem. Transferências entre duas obras continuam no fluxo já existente.</p>'+
   '<form id="ewTransferLocalForm" class="ewComprasForm">'+
   '<div class="ewTransferGrid"><label>Local de origem<select id="ewTransSource" required>'+locOpts+'</select></label>'+
   '<label>Local de destino<select id="ewTransDest" required>'+locOpts+'</select></label>'+
   '<label>Galpão de origem<select id="ewTransWhSource" required>'+whOpts+'</select></label>'+
   '<label>Galpão de destino<select id="ewTransWhDest" required>'+whOpts+'</select></label>'+
   '<label>Material / variação<select id="ewTransMaterial" required>'+option('','Selecione um material')+
    products.map(x=>option(x.id,x.label)).join('')+'</select></label>'+
   '<label>Quantidade<input id="ewTransQty" type="number" min="0.001" max="1000000" step="any" required></label>'+
   '<label>Unidade<input id="ewTransUnit" readonly required></label>'+
   '<label>Comprimento da barra (mm)<input id="ewTransLength" type="number" min="100" max="20000"></label></div>'+
   '<label>Motivo / observação<textarea id="ewTransReason" maxlength="350" required rows="2"></textarea></label>'+
   '<div><button type="submit" class="btn primary">Registrar transferência</button></div></form>'+
   '<p id="ewTransMessage" class="feedback" role="status"></p>'+
   '<h4>Histórico de transferências entre locais</h4>'+
   '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr>'+
   '<th>Data</th><th>Origem</th><th>Destino</th><th>Material</th><th>Qtd.</th><th>Status</th><th>Ação</th>'+
   '</tr></thead><tbody>'+
   (history||[]).map(t=>{
    const localLabel=(tipo,id,galpao)=>dest.find(x=>x.value===tipo+':'+id)?.label||tipo+' · '+id;
    const product=products.find(x=>x.id===t.variacao_id);
    const reversed=t.estornado_em!==null;
    const undo=permission('estoque.estornar')&&!reversed;
    return '<tr><td>'+esc(String(t.criado_em||'').slice(0,10).split('-').reverse().join('/'))+'</td>'+
     '<td>'+esc(localLabel(t.origem_tipo,t.origem_id)+' · '+t.origem_galpao)+'</td>'+
     '<td>'+esc(localLabel(t.destino_tipo,t.destino_id)+' · '+t.destino_galpao)+'</td>'+
     '<td>'+esc(product?.label||t.variacao_id)+'</td><td>'+number(t.quantidade)+' '+esc(t.unidade)+'</td>'+
     '<td>'+esc(reversed?'Estornada':'Ativa')+'</td><td>'+
     '<button type="button" class="btn secondary" data-ew-transfer-print="'+esc(t.id)+'">Imprimir espelho</button> '+
     (undo?'<button type="button" class="btn secondary" data-ew-transfer-undo="'+esc(t.id)+'">Estornar</button>':'')+
     '</td></tr>';
   }).join('')+'</tbody></table></div>';
  const selected=$('stockWork')?.value||'';
  const selectedValue=selected.startsWith('empresa:')?'EMPRESA:'+selected.slice(8):selected?'OBRA:'+selected:'';
  if([...$('ewTransSource').options].some(x=>x.value===selectedValue))$('ewTransSource').value=selectedValue;
  $('ewTransMaterial').addEventListener('change',()=>{
   const p=products.find(x=>x.id===$('ewTransMaterial').value);if(!p)return;
   $('ewTransUnit').value=p.unidade;
   $('ewTransLength').disabled=p.unidade!=='BARRA';
   $('ewTransLength').value=p.comprimento||'';
   $('ewTransQty').step=['BARRA','PC','PR','CJ','UN','MT'].includes(p.unidade)?'1':'0.001';
  });
  $('ewTransClose').onclick=()=>pane.classList.add('hidden');
  $('ewTransferLocalForm').onsubmit=async e=>{
   e.preventDefault();
   const src=$('ewTransSource').value,dst=$('ewTransDest').value;
   const [srcType,srcId]=src.split(':'),[dstType,dstId]=dst.split(':');
   const qty=Number($('ewTransQty').value),material=products.find(x=>x.id===$('ewTransMaterial').value);
   const length=material?.unidade==='BARRA'?Number($('ewTransLength').value):null;
   const reason=$('ewTransReason').value.trim();
   if(!srcId||!dstId||!material||reason.length<5||reason.length>350||
     (srcType==='OBRA'&&dstType==='OBRA')||
     (src===dst&&$('ewTransWhSource').value===$('ewTransWhDest').value)||
     !validQty(qty,material.unidade)||
     (material.unidade==='BARRA'&&(!Number.isSafeInteger(length)||length<100||length>20000))){
    say('ewTransMessage','Confira origem, destino, material, quantidade e motivo. Para transferências entre obras, use o botão específico.');return;
   }
   const payload={empresa:currentCompany.id,src,dst,galpao1:$('ewTransWhSource').value,
    galpao2:$('ewTransWhDest').value,material:material.id,length,qty,reason};
   const button=$('ewTransferLocalForm').querySelector('[type="submit"]');button.disabled=true;
   try{
    await rpc('ew_compras_transferir_locais',{
     p_empresa_id:currentCompany.id,
     p_origem_tipo:srcType,p_origem_id:srcId,p_destino_tipo:dstType,p_destino_id:dstId,
     p_variacao_id:material.id,p_comprimento_mm:length,p_unidade:material.unidade,
     p_quantidade:qty,p_origem_galpao:$('ewTransWhSource').value,
     p_destino_galpao:$('ewTransWhDest').value,p_motivo:reason,
     p_operacao_id:operationToken('transferir_estoque',payload)});
    pendingOps.delete('transferir_estoque');
    await abrirEstoque();await abrirTransferLocal();
    say('ewTransMessage','Transferência registrada.');
   }catch(err){say('ewTransMessage','Transferência não realizada: '+err.message)}
   finally{button.disabled=false;}
  };
  pane.querySelectorAll('[data-ew-transfer-print]').forEach(button=>
   button.addEventListener('click',()=>{
    try{
     const movement=(history||[]).find(t=>t.id===button.dataset.ewTransferPrint);
     if(!movement)throw Error('Movimento não encontrado neste histórico. Atualize a lista.');
     if(!window.ewTransferReceipt)throw Error('Módulo de impressão indisponível.');
     window.ewTransferReceipt.imprimir(movement,{locais:dest,materiais:products,
      empresa:currentCompany?.nome||'Empresa'});
    }catch(err){say('ewTransMessage','Não foi possível imprimir espelho: '+err.message)}
   }));
  pane.querySelectorAll('[data-ew-transfer-undo]').forEach(button=>
   button.addEventListener('click',async ()=>{
    const id=button.dataset.ewTransferUndo;
    const prompt=window.prompt('Motivo para estornar a transferência (5 a 400 caracteres):');
    if(prompt===null)return;
    const reason=prompt.trim();
    if(reason.length<5||reason.length>400){say('ewTransMessage','Informe motivo válido.');return;}
    if(!window.confirm('Estornar as duas pontas desta transferência? A operação será bloqueada caso tenha ocorrido consumo ou saída posterior.'))return;
    button.disabled=true;
    try{
     await rpc('ew_compras_estornar_transferencia',{
      p_transferencia_id:id,p_motivo:reason,
      p_operacao_id:operationToken('estornar_transferencia',{id,reason})});
     pendingOps.delete('estornar_transferencia');
     await abrirEstoque();await abrirTransferLocal();
     say('ewTransMessage','Transferência estornada; histórico preservado.');
    }catch(err){say('ewTransMessage','Estorno bloqueado: '+err.message)}
    finally{button.disabled=false;}
   }));
 }catch(err){pane.innerHTML='<p class="feedback">Transferências indisponíveis: '+esc(err.message)+'</p>';}
}

function contextoConciliacao(){return permission('financeiro.despesas')&&permission('compras.consultar_valores')?
 {empresa_id:currentCompany?.id,orders,suppliers:suppliersAll,receipts,variations,workNames:works.map(w=>({id:w.id,nome:w.nome})),localNames:locals.map(x=>({id:x.id,nome:x.nome}))}:null;}
window.ewCompras=Object.freeze({abrir,carregarLocaisRecebimento,atualizarRecebimento,carregarLocaisEstoque,renderEstoqueEmpresa,criarLocalEmpresa,abrirTransferLocal,contextoConciliacao});
})();
