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
 (!['BARRA','MT','PC','PR','CJ','UN'].includes(un)||Number.isSafeInteger(q))};
const parseMoney=v=>{const s=String(v||'').replace(/^R\\$\\s*/,'').replace(/\\s/g,'');
 if(!/^\\d+(?:[.,]\\d{1,2})?$/.test(s))return null;const c=Math.round(Number(s.replace(',','.'))*100);
 return Number.isSafeInteger(c)&&c>=0?c:null;};
let tab='solicitacao',locals=[],suppliers=[],galpoes=[],variations=[],sols=[],quotes=[],orders=[],receipts=[],stockEpoch=0,loaded=false;
function titleLocal(row){const work=works.find(w=>w.id===row.obra_id);
 const loc=locals.find(x=>x.id===row.local_empresa_id);
 return work?'Obra · '+work.nome:loc?'Empresa · '+loc.nome:'Local indisponível';}
function destinoOptions(){return works.map(w=>option('obra:'+w.id,'Obra · '+w.nome)).join('')+
 locals.filter(x=>x.ativo).map(x=>option('empresa:'+x.id,'Empresa · '+x.nome)).join('');}
function productLabel(v){return v.nome||v.id}
function products(){return variations.map(v=>option(v.id,productLabel(v))).join('')}
async function reload(){
 if(!permission('compras.consultar')||!currentCompany)return;
 await ensureSession();
 const empresa='eq.'+currentCompany.id;
 const [ls,fs,gs,vs,ps,as,so,co,po,re]=await Promise.all([
  apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'1000'}),
  apiGet('ew_fornecedores',{select:'id,nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'1000'}),
  apiGet('ew_locais_fisicos',{select:'nome,ativo',empresa_id:empresa,order:'nome.asc',limit:'200'}),
  apiGet('ew_materiais_variacoes',{select:'id,tipo,perfil_id,acessorio_id,cor,acabamento,ativo',empresa_id:empresa,ativo:'eq.true',limit:'10000'}),
  apiGet('ew_perfis',{select:'id,codigo,descricao,comprimento_comercial_mm',empresa_id:empresa,limit:'5000'}),
  apiGet('ew_acessorios',{select:'id,codigo,descricao,unidade_item',empresa_id:empresa,limit:'5000'}),
  apiGet('ew_compras_solicitacoes',{select:'*',empresa_id:empresa,order:'criado_em.desc',limit:'1000'}),
  apiGet('ew_compras_cotacoes',{select:'*',empresa_id:empresa,order:'criado_em.desc',limit:'1000'}),
  apiGet('ew_compras_pedidos',{select:'*',empresa_id:empresa,order:'criado_em.desc',limit:'1000'}),
  apiGet('ew_compras_recebimentos',{select:'id,pedido_id,itens,criado_em',empresa_id:empresa,limit:'3000'})
 ]);
 const perf=new Map((ps||[]).map(p=>[p.id,p])),acc=new Map((as||[]).map(a=>[a.id,a]));
 locals=ls||[];suppliers=(fs||[]).filter(x=>x.ativo);galpoes=(gs||[]).filter(x=>x.ativo).map(x=>x.nome);
 variations=(vs||[]).map(v=>{const m=v.tipo==='perfil'?perf.get(v.perfil_id):acc.get(v.acessorio_id);
 return {...v,unidade:v.tipo==='perfil'?'BARRA':m?.unidade_item||'PC',
  comprimento_mm:v.tipo==='perfil'?Number(m?.comprimento_comercial_mm)||6000:null,
  nome:(m?.codigo||'?')+' · '+(m?.descricao||'Material')+' · '+v.cor};}).filter(x=>x.nome);
 sols=so||[];quotes=co||[];orders=po||[];receipts=re||[];loaded=true;
}
function receivedMap(pedidoId){const m=new Map();
 for(const rec of receipts.filter(x=>x.pedido_id===pedidoId))
  for(const line of rec.itens||[])m.set(String(line.chave),(m.get(String(line.chave))||0)+Number(line.quantidade||0));
 return m;}
function orderStatus(p){const rec=receivedMap(p.id);let all=true,some=false;
 for(const it of p.itens||[]){const n=rec.get(String(it.chave))||0;if(n>0)some=true;if(n+1e-8<Number(it.quantidade))all=false;}
 return all?'Recebido':some?'Parcial':'Pendente';}
function formRow(index){
 return '<div class="ewComprasLine" data-buy-line="'+index+'"><label>Material<select data-buy="variation" required>'+option('','Selecione')+products()+'</select></label>'+
 '<label>Quantidade<input data-buy="qty" type="number" min="1" step="1" value="1" required></label>'+
 '<label>Unidade<input data-buy="unit" readonly value="BARRA"></label>'+
 '<label>Comprimento (mm)<input data-buy="length" type="number" min="100" max="20000" value="6000"></label>'+
 '<button class="btn secondary" type="button" data-buy-remove>Remover</button></div>';
}
function makeLine(){const container=$('comprasLinhas');if(!container)return;const div=document.createElement('div');div.innerHTML=formRow(container.children.length);
 const row=div.firstElementChild;container.append(row);
 row.querySelector('[data-buy="variation"]').addEventListener('change',()=>{
  const v=variations.find(v=>v.id===row.querySelector('[data-buy="variation"]').value);if(!v)return;
  row.querySelector('[data-buy="unit"]').value=v.unidade;
  row.querySelector('[data-buy="length"]').value=v.comprimento_mm||'';
  row.querySelector('[data-buy="length"]').disabled=v.unidade!=='BARRA';
 });
 row.querySelector('[data-buy-remove]').addEventListener('click',()=>{if(container.children.length>1)row.remove()});
}
function renderRequest(){
 const editable=permission('compras.solicitar');
 $('comprasConteudo').innerHTML='<h2>Solicitação de materiais</h2>'+
 (editable?'<form id="comprasSolicitarForm" class="ewComprasForm"><label>Local de estoque de destino<select id="comprasDestino" required>'+option('','Escolha o local')+destinoOptions()+'</select></label>'+
 '<label>Observações<textarea id="comprasObservacoes" rows="2" maxlength="600"></textarea></label>'+
 '<h3>Materiais solicitados</h3><div id="comprasLinhas"></div><div class="ewComprasActions"><button class="btn secondary" id="comprasAddLine" type="button">+ Adicionar material</button><button class="btn primary" type="submit">Criar solicitação</button></div></form>':'')+
 '<h3>Solicitações registradas</h3><div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Data</th><th>Destino</th><th>Itens</th><th>Situação</th></tr></thead><tbody>'+
 sols.map(s=>'<tr><td>'+esc(String(s.criado_em||'').slice(0,10).split('-').reverse().join('/'))+'</td><td>'+esc(titleLocal(s))+'</td><td>'+number((s.itens||[]).length)+'</td><td>'+esc(s.status)+'</td></tr>').join('')+
 '</tbody></table></div>';if(editable){makeLine();$('comprasAddLine').onclick=makeLine;
 $('comprasSolicitarForm').onsubmit=async e=>{e.preventDefault();const value=$('comprasDestino').value;
 const lines=[...document.querySelectorAll('#comprasLinhas .ewComprasLine')].map((row,i)=>{
  const get=x=>row.querySelector('[data-buy="'+x+'"]').value;
  return {chave:String(i+1),variacao_id:get('variation'),quantidade:Number(get('qty')),
   unidade:get('unit'),comprimento_mm:get('unit')==='BARRA'?Number(get('length')):null};});
 if(!value||lines.some(x=>!x.variacao_id||!validQty(x.quantidade,x.unidade)||
   (x.unidade==='BARRA'&&(!Number.isSafeInteger(x.comprimento_mm)||x.comprimento_mm<100||x.comprimento_mm>20000)))){
  say('comprasMensagem','Preencha destino, material e quantidades válidas.');return;}
 const [kind,id]=value.split(':');const btn=$('comprasSolicitarForm').querySelector('[type="submit"]');btn.disabled=true;
 try{await ensureSession();await rpc('ew_compras_criar_solicitacao',{p_empresa_id:currentCompany.id,
  p_obra_id:kind==='obra'?id:null,p_local_empresa_id:kind==='empresa'?id:null,
  p_itens:lines,p_observacoes:$('comprasObservacoes').value,p_operacao_id:crypto.randomUUID()});
  await reload();renderRequest();say('comprasMensagem','Solicitação registrada.');
 }catch(e){say('comprasMensagem','Erro: '+e.message)}finally{btn.disabled=false;}};
 }}
function renderQuote(){
 const list=sols.filter(s=>s.status==='ABERTA'&&!orders.some(p=>p.solicitacao_id===s.id)),editable=permission('compras.cotar');
 $('comprasConteudo').innerHTML='<h2>Cotação</h2><p class="hint">Cotação por fornecedor. Várias cotações podem ser comparadas para uma solicitação; apenas a escolhida vira pedido.</p>'+
 (editable?'<form id="comprasCotarForm" class="ewComprasForm"><label>Solicitação<select id="comprasCotacaoSolic" required>'+option('','Escolha')+list.map(s=>option(s.id,titleLocal(s)+' · '+(s.itens||[]).length+' itens')).join('')+'</select></label>'+
 '<label>Fornecedor<select id="comprasCotacaoFornecedor" required>'+option('','Escolha')+suppliers.map(x=>option(x.id,x.nome)).join('')+'</select></label><div id="comprasCotacaoItens"></div><button class="btn primary" type="submit">Registrar cotação</button></form>':'')+
 '<h3>Cotações registradas</h3><div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Fornecedor</th><th>Destino</th><th>Total</th><th>Situação</th></tr></thead><tbody>'+
 quotes.map(q=>{const s=sols.find(x=>x.id===q.solicitacao_id);return '<tr><td>'+esc(suppliers.find(x=>x.id===q.fornecedor_id)?.nome||'Fornecedor')+'</td><td>'+esc(s?titleLocal(s):'-')+'</td><td>'+money(q.total_centavos)+'</td><td>'+esc(orders.some(p=>p.cotacao_id===q.id)?'Pedido gerado':'Em avaliação')+'</td></tr>'}).join('')+'</tbody></table></div>';
 if(editable){$('comprasCotacaoSolic').onchange=()=>{
  const s=sols.find(x=>x.id===$('comprasCotacaoSolic').value);
  $('comprasCotacaoItens').innerHTML=s?'<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Material</th><th>Quantidade</th><th>Un.</th><th>Preço unitário (R$)</th></tr></thead><tbody>'+
  (s.itens||[]).map(i=>'<tr data-quote-key="'+esc(i.chave)+'"><td>'+esc(productLabel(variations.find(v=>v.id===i.variacao_id)||{nome:i.variacao_id}))+'</td><td>'+number(i.quantidade)+'</td><td>'+esc(i.unidade)+'</td><td><input type="text" inputmode="decimal" required placeholder="0,00"></td></tr>').join('')+'</tbody></table></div>':'';
 };
 $('comprasCotarForm').onsubmit=async e=>{e.preventDefault();const s=sols.find(x=>x.id===$('comprasCotacaoSolic').value);
 const precos=[...document.querySelectorAll('[data-quote-key]')].map(row=>({chave:row.dataset.quoteKey,preco_unitario_centavos:parseMoney(row.querySelector('input').value)}));
 if(!s||precos.some(x=>x.preco_unitario_centavos===null)){say('comprasMensagem','Valores inválidos.');return;}
 try{await rpc('ew_compras_criar_cotacao',{p_solicitacao_id:s.id,p_fornecedor_id:$('comprasCotacaoFornecedor').value,
 p_precos:precos,p_operacao_id:crypto.randomUUID()});await reload();renderQuote();say('comprasMensagem','Cotação registrada.');
 }catch(err){say('comprasMensagem','Erro: '+err.message)}};
 }}
function renderOrder(){
 const editable=permission('compras.pedir');
 const pending=quotes.filter(q=>!orders.some(p=>p.solicitacao_id===q.solicitacao_id));
 $('comprasConteudo').innerHTML='<h2>Pedidos de compra</h2><p class="hint">O pedido é formado pela cotação escolhida. O recebimento físico acontece exclusivamente no setor Recebimento.</p>'+
 (editable?'<form id="comprasPedidoForm" class="ewComprasForm"><label>Cotação aprovada<select id="comprasPedidoCotacao" required>'+option('','Escolha')+
 pending.map(q=>{const s=sols.find(x=>x.id===q.solicitacao_id);return option(q.id,(s?titleLocal(s):'Solicitação')+' · '+money(q.total_centavos))}).join('')+
 '</select></label><button class="btn primary" type="submit">Gerar pedido</button></form>':'')+
 '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Pedido</th><th>Destino</th><th>Valor</th><th>Recebimento</th></tr></thead><tbody>'+
 orders.map(p=>'<tr><td>#'+number(p.numero)+'</td><td>'+esc(titleLocal(p))+'</td><td>'+money(p.total_centavos)+'</td><td>'+esc(orderStatus(p))+'</td></tr>').join('')+'</tbody></table></div>';
 if(editable)$('comprasPedidoForm').onsubmit=async e=>{e.preventDefault();const id=$('comprasPedidoCotacao').value;
 try{await rpc('ew_compras_criar_pedido',{p_cotacao_id:id,p_operacao_id:crypto.randomUUID()});
 await reload();renderOrder();say('comprasMensagem','Pedido criado e disponível para recebimento.');
 }catch(err){say('comprasMensagem','Erro: '+err.message)}};
}
function render(){for(const [k,id] of [['solicitacao','comprasTabSolicitacao'],['cotacao','comprasTabCotacao'],['pedido','comprasTabPedido']])
 $(id).classList.toggle('primary',k===tab);
 if(tab==='solicitacao')renderRequest();else if(tab==='cotacao')renderQuote();else renderOrder();
}
async function abrir(){
 if(!permission('compras.consultar'))return;setView('compras');
 say('comprasMensagem','Carregando compras…');try{await reload();render();say('comprasMensagem','')}
 catch(e){say('comprasMensagem','Compras ainda indisponíveis: '+e.message);}
}
for(const [tabValue,id] of [['solicitacao','comprasTabSolicitacao'],['cotacao','comprasTabCotacao'],['pedido','comprasTabPedido']])
 $(id).addEventListener('click',()=>{tab=tabValue;if(loaded)render();});
async function carregarLocaisRecebimento(select){
 if(!permission('compras.receber')||!currentCompany)return;
 try{
  await ensureSession();
  const values=await apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',empresa_id:'eq.'+currentCompany.id,ativo:'eq.true',order:'nome.asc'});
  for(const loc of values||[])select.add(new Option('Empresa · '+loc.nome,'empresa:'+loc.id));
 }catch(e){say('recebimentoMessage','Locais empresariais indisponíveis: '+e.message);}
}
async function atualizarRecebimento(obraId){
 const box=$('ewComprasRecebimento');
 box.classList.toggle('hidden',!obraId||!permission('compras.receber')||!permission('estoque.receber'));
 if(box.classList.contains('hidden'))return;
 box.innerHTML='<h2>Receber por pedido de compra</h2><p class="hint">Entrada física por pedido, sem lançamento fiscal automático. Consulte as quantidades já recebidas antes de confirmar.</p><p class="feedback">Consultando pedidos pendentes…</p>';
 try{await reload();if($('recebimentoWork').value!==obraId)return;
 const empresaDestino=obraId.startsWith('empresa:');
 const ativos=orders.filter(p=>(empresaDestino?p.local_empresa_id===obraId.slice(8):p.obra_id===obraId)&&orderStatus(p)!=='Recebido');
 box.innerHTML='<h2>Receber por pedido de compra</h2><p class="hint">Receba todo ou parte do pedido; somente o saldo efetivamente confirmado será acrescentado ao estoque físico.</p>'+
 '<label>Pedido<select id="ewReceberPedido">'+option('','Selecione o pedido')+ativos.map(p=>option(p.id,'#'+p.numero+' · '+orderStatus(p))).join('')+'</select></label>'+
 '<form id="ewReceberForm" class="hidden"><div id="ewReceberItens"></div><label>Galpão de destino<select id="ewReceberGalpao" required>'+
 option('','Selecione')+galpoes.map(g=>option(g,g)).join('')+'</select></label>'+
 '<div class="ewComprasActions"><button type="submit" class="btn primary">Confirmar recebimento físico</button></div></form>'+
 '<p id="ewReceberMessage" class="feedback" role="status"></p>';
 $('ewReceberPedido').onchange=()=>{const p=orders.find(x=>x.id===$('ewReceberPedido').value),form=$('ewReceberForm');
 form.classList.toggle('hidden',!p);if(!p)return;const received=receivedMap(p.id);
 $('ewReceberItens').innerHTML='<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr><th>Receber</th><th>Material</th><th>Pedido</th><th>Recebido</th><th>Falta</th><th>Agora</th></tr></thead><tbody>'+
 (p.itens||[]).map(it=>{const r=received.get(String(it.chave))||0,remain=Math.max(0,Number(it.quantidade)-r);
 return '<tr data-receive-key="'+esc(it.chave)+'"><td><input type="checkbox" '+(remain<=0?'disabled':'')+'></td><td>'+esc(productLabel(variations.find(v=>v.id===it.variacao_id)||{nome:it.variacao_id}))+'</td>'+
 '<td>'+number(it.quantidade)+' '+esc(it.unidade)+'</td><td>'+number(r)+'</td><td><strong>'+number(remain)+'</strong></td>'+
 '<td><input type="number" min="1" step="1" max="'+remain+'" value="" '+(remain<=0?'disabled':'')+'></td></tr>';}).join('')+'</tbody></table></div>';
 };
 $('ewReceberForm').onsubmit=async e=>{e.preventDefault();const p=orders.find(x=>x.id===$('ewReceberPedido').value);if(!p)return;
 const m=receivedMap(p.id),itens=[...document.querySelectorAll('[data-receive-key]')].filter(row=>row.querySelector('[type=checkbox]').checked).map(row=>({chave:row.dataset.receiveKey,quantidade:Number(row.querySelector('[type=number]').value)}));
 if(!itens.length||itens.some(it=>{const line=p.itens.find(x=>String(x.chave)===it.chave);return !line||!validQty(it.quantidade,line.unidade)||
 it.quantidade>Number(line.quantidade)-(m.get(it.chave)||0)})){say('ewReceberMessage','Marque itens e informe quantidades inteiras dentro do saldo pendente.');return;}
 const button=$('ewReceberForm').querySelector('[type=submit]');button.disabled=true;
 try{await rpc('ew_compras_receber_pedido',{p_pedido_id:p.id,p_galpao:$('ewReceberGalpao').value,
  p_itens:itens,p_operacao_id:crypto.randomUUID()});say('ewReceberMessage','Recebimento confirmado.');
  await atualizarRecebimento(obraId);
 }catch(err){say('ewReceberMessage','Erro ao receber: '+err.message);}finally{button.disabled=false;}
 };
 }catch(e){box.querySelector('.feedback').textContent='Pedidos indisponíveis: '+e.message;}
}
async function carregarLocaisEstoque(){
 if(!permission('estoque.consultar'))return;try{
 await ensureSession();locals=await apiGet('ew_compras_locais_empresa',{select:'id,nome,ativo',
 empresa_id:'eq.'+currentCompany.id,order:'nome.asc'})||[];
 const select=$('stockWork'),old=select.value;for(const x of locals.filter(l=>l.ativo))
  select.appendChild(new Option('Empresa · '+x.nome,'empresa:'+x.id));
 if(old&&[...select.options].some(op=>op.value===old)){select.value=old;if(old.startsWith('empresa:'))renderEstoqueEmpresa();}
 }catch(e){say('stockMessage','Locais de estoque da empresa indisponíveis: '+e.message);}
}
async function renderEstoqueEmpresa(){
 const id=$('stockWork').value.replace(/^empresa:/,''),pane=$('ewEstoqueEmpresaPainel'),epoch=++stockEpoch;
 $('stockRecords').classList.add('hidden');pane.classList.remove('hidden');$('insumosStockPanel')?.classList.add('hidden');$('stockLegend')?.classList.add('hidden');
 $('stockPerfCount').textContent='—';$('stockAcesCount').textContent='—';$('stockCounted').textContent='—';
 pane.innerHTML='<p class="hint">Consultando saldo físico da empresa…</p>';
 try{const rows=await apiGet('ew_compras_estoque_empresa',{select:'variacao_id,unidade,comprimento_mm,quantidade_delta,galpao',empresa_id:'eq.'+currentCompany.id,local_empresa_id:'eq.'+id,limit:'30000'});
 if(epoch!==stockEpoch||$('stockWork').value!=='empresa:'+id)return;
 const totals=new Map();for(const r of rows||[]){if($('stockFactoryFilter').value&&$('stockFactoryFilter').value!==r.galpao)continue;
 const key=[r.variacao_id,r.unidade,r.comprimento_mm||'',r.galpao].join('|');const old=totals.get(key)||{...r,quantidade:0};old.quantidade+=Number(r.quantidade_delta);totals.set(key,old)}
 const list=[...totals.values()].filter(x=>x.quantidade>0);$('stockCounted').textContent=String(list.length);
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
 try{await rpc('ew_compras_criar_local_empresa',{p_empresa_id:currentCompany.id,p_nome:nome.trim()});
 await carregarLocaisEstoque();say('stockMessage','Local de estoque cadastrado.');}
 catch(e){say('stockMessage','Não foi possível cadastrar local: '+e.message);}
}
window.ewCompras=Object.freeze({abrir,carregarLocaisRecebimento,atualizarRecebimento,carregarLocaisEstoque,renderEstoqueEmpresa,criarLocalEmpresa});
})();
