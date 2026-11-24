/* EWGEST v46.21 — conciliação fiscal de pedidos recebidos (sem novo movimento).
 * Carregado após compras-estoque.js, disponível somente para financeiro.
 */
(()=>{
'use strict';
const $=id=>document.getElementById(id);
const esc=x=>escapeHTML(String(x??''));
const fmt=x=>Number(x||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
const reais=x=>Number(x||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const option=(v,t)=>'<option value="'+esc(v)+'">'+esc(t)+'</option>';
const call=(name,body)=>request('/rest/v1/rpc/'+name,{
 method:'POST',token:session.access_token,body,timeoutMs:45000});
const pending=new Map();
function op(kind,data){
 const signature=JSON.stringify(data),found=pending.get(kind);
 if(found?.signature===signature)return found.id;
 const id=crypto.randomUUID();pending.set(kind,{signature,id});return id;
}
function normalizeUnit(value){
 const u=String(value||'').trim().toUpperCase();
 return ({BR:'BARRA',M:'MT',METRO:'MT',PEÇA:'PC',PECA:'PC',UNIDADE:'UN'})[u]||u;
}
function quantityAsInvoice(line,physical,invoiceUnit){
 const from=normalizeUnit(line?.unidade),to=normalizeUnit(invoiceUnit);
 const qty=Number(physical);
 if(!Number.isFinite(qty)||qty<=0)return null;
 if(from===to||(from==='PC'&&to==='UN')||(from==='UN'&&to==='PC'))return qty;
 if(from==='BARRA'&&to==='MT'){
  const length=Number(line.comprimento_mm);
  if(!Number.isInteger(length)||length<100||length>20000)return null;
  return Math.round(qty*length)/1000;
 }
 return null;
}
function compatible(line,fi,variations,category){
 const variant=variations.find(v=>v.id===line.variacao_id);
 if(!variant||category==='aluminio'&&variant.tipo!=='perfil'||
  category==='acessorios'&&variant.tipo!=='acessorio')return false;
 return variant.tipo==='perfil'?
   variant.perfil_id===fi.perfil_id&&Boolean(fi.perfil_id):
   variant.acessorio_id===fi.acessorio_id&&Boolean(fi.acessorio_id);
}
function chunks(list,size=60){
 const groups=[];
 for(let i=0;i<list.length;i+=size)groups.push(list.slice(i,i+size));
 return groups;
}
async function render(root,context){
 if(!context?.empresa_id||!root?.isConnected||!temPermissao('financeiro.despesas')||
 !temPermissao('financeiro.consultar')||!temPermissao('compras.consultar_valores'))return;
 const works=context.orders.filter(p=>p.obra_id&&p.status!=='CANCELADO');
 root.innerHTML='<h3>Conciliação de nota fiscal e pedido</h3>'+
  '<p class="hint">A nota deve estar aprovada no Financeiro. Aqui você vincula seus itens aos materiais que já foram recebidos por pedido — sem acrescentar estoque novamente.</p>'+
  '<label>Pedido de compra da obra<select id="ewCompNFOrder">'+option('','Selecione o pedido')+
  works.map(p=>option(p.id,'Pedido #'+p.numero+' · '+(context.workNames?.find(w=>w.id===p.obra_id)?.nome||'Obra'))).join('')+
  '</select></label><div id="ewCompNFNote"></div><div id="ewCompNFItems"></div>'+
  '<p id="ewCompNFStatus" role="status" class="feedback"></p>'+
  (context.orders.some(p=>p.local_empresa_id)?'<p class="hint">As notas do estoque empresarial são registradas na seção independente abaixo.</p>':'');
 const status=msg=>{if($('ewCompNFStatus'))$('ewCompNFStatus').textContent=msg||''};
 window.ewComprasNfeEmpresa?.render(root,context);
 let orderGeneration=0,noteGeneration=0;
 $('ewCompNFOrder').onchange=async()=>{
  const generation=++orderGeneration;
  ++noteGeneration;
  const id=$('ewCompNFOrder').value,p=context.orders.find(x=>x.id===id);
  $('ewCompNFNote').replaceChildren();$('ewCompNFItems').replaceChildren();status('');
  if(!p)return;
  const supplier=context.suppliers.find(x=>x.id===p.fornecedor_id)?.nome||'';
  if(!supplier){status('Fornecedor do pedido não localizado no cadastro.');return;}
  status('Consultando notas aprovadas da obra…');
  try{
   await ensureSession();
   const [notes,conciliacoes]=await Promise.all([
    apiGet('ew_obra_despesas',{select:'id,numero_documento,fornecedor,categoria,valor,status,criado_em',
     empresa_id:'eq.'+context.empresa_id,obra_id:'eq.'+p.obra_id,status:'eq.aprovada',limit:'1000'}),
    apiGet('ew_compras_nfe_conciliacoes',{
     select:'id,despesa_id,criado_em,desvinculado_em',empresa_id:'eq.'+context.empresa_id,
     pedido_id:'eq.'+p.id,order:'criado_em.desc',limit:'500'})
   ]);
   if(generation!==orderGeneration||!root.isConnected||$('ewCompNFOrder')?.value!==id)return;
   if((notes||[]).length>=1000||(conciliacoes||[]).length>=500)
    throw Error('Consulta atingiu o limite de registros; não é seguro exibir dados incompletos.');
   const available=(notes||[]).filter(x=>['aluminio','acessorios'].includes(x.categoria)
    &&String(x.fornecedor||'').trim().toLowerCase()===supplier.trim().toLowerCase());
   $('ewCompNFNote').innerHTML='<label>Nota aprovada no Financeiro<select id="ewCompNFDoc">'+
    option('','Selecione a nota')+
    available.map(n=>option(n.id,'NF '+(n.numero_documento||'s/n')+' · '+n.categoria+' · '+reais(n.valor))).join('')+
    '</select></label><div id="ewCompNFHistory"></div>';
   const rows=conciliacoes||[];
   $('ewCompNFHistory').innerHTML='<h4>Histórico de conciliações</h4>'+
    (rows.length?'<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr>'+
    '<th>Nota</th><th>Data</th><th>Status</th><th>Ação</th></tr></thead><tbody>'+
    rows.map(h=>'<tr><td>'+esc(available.find(n=>n.id===h.despesa_id)?.numero_documento||h.despesa_id)+
    '</td><td>'+esc(String(h.criado_em||'').slice(0,10))+'</td>'+
    '<td>'+esc(h.desvinculado_em?'Desvinculada':'Vinculada')+'</td><td>'+
    (!h.desvinculado_em&&temPermissao('financeiro.cancelar_despesas')?
     '<button type="button" class="btn secondary" data-nf-unlink="'+esc(h.id)+'">Desvincular</button>':'—')+
    '</td></tr>').join('')+'</tbody></table></div>':
     '<p class="hint">Nenhuma nota conciliada com este pedido.</p>');
   $('ewCompNFHistory').querySelectorAll('[data-nf-unlink]').forEach(btn=>{
    btn.onclick=async()=>{
     const cid=btn.dataset.nfUnlink;
     const reason=window.prompt('Motivo para desvincular a nota (5 a 400 caracteres):');
     if(reason===null)return;
     if(reason.trim().length<5||reason.trim().length>400){status('Motivo inválido.');return;}
     if(!window.confirm('Desvincular a nota deste pedido? O estoque não será alterado.'))return;
     btn.disabled=true;
     try{
      await call('ew_compras_desvincular_nfe',{p_conciliacao_id:cid,p_motivo:reason.trim(),
       p_operacao_id:op('unlink',{cid,reason:reason.trim()})});
      pending.delete('unlink');await window.ewCompras.abrir();
      $('comprasMensagem').textContent='Nota desvinculada; histórico e estoque preservados.';
     }catch(e){status('Não foi possível desvincular: '+e.message)}
     finally{btn.disabled=false;}
    };
   });
   $('ewCompNFDoc').onchange=async()=>{
    const noteRequest=++noteGeneration;
    const noteId=$('ewCompNFDoc').value;
    const current=()=>generation===orderGeneration&&noteRequest===noteGeneration&&root.isConnected&&$('ewCompNFOrder')?.value===id&&$('ewCompNFDoc')?.value===noteId;
    $('ewCompNFItems').replaceChildren();status('');
    if(!noteId)return;
    try{
     await ensureSession();
     const fiscalItems=await apiGet('ew_obra_despesas_itens',{
      select:'id,despesa_id,perfil_id,acessorio_id,unidade,quantidade,descricao',
      empresa_id:'eq.'+context.empresa_id,despesa_id:'eq.'+noteId,limit:'500'});
     if(!current())return;
     if((fiscalItems||[]).length>=500)throw Error('Nota atingiu o limite de itens; conciliação interrompida para evitar dados incompletos.');
     const owned=context.receipts.filter(x=>x.pedido_id===id&&!x.estornado_em);
     // Consultas limitadas à nota e aos recebimentos deste pedido.
     // Sem isso, vínculos de outras obras podem consumir o limite da API.
     const searches=[
      ...chunks((fiscalItems||[]).map(x=>x.id)).map(ids=>({despesa_item_id:'in.('+ids.join(',')+')'})),
      ...chunks(owned.map(x=>x.id)).map(ids=>({recebimento_id:'in.('+ids.join(',')+')'}))
     ];
     const result=await Promise.all(searches.map(filters=>
      apiGet('ew_compras_nfe_vinculos',{
       select:'id,recebimento_id,chave,despesa_item_id,quantidade_nota,desvinculado_em',
       empresa_id:'eq.'+context.empresa_id,limit:'1000',...filters})));
     if(result.some(rows=>rows.length>=1000))
      throw Error('Vínculos demais neste filtro; não é seguro conciliar com dados incompletos.');
     const linkedItems=[...new Map(result.flat().map(x=>[x.id,x])).values()];
     if(!current())return;
     const activeLinks=linkedItems.filter(x=>!x.desvinculado_em);
     const marked=new Set(activeLinks.map(x=>x.recebimento_id+'|'+x.chave));
     const fiscalUsed=new Map();
     for(const link of activeLinks){
      fiscalUsed.set(link.despesa_item_id,(fiscalUsed.get(link.despesa_item_id)||0)+Number(link.quantidade_nota));
     }
     const currentNote=available.find(n=>n.id===noteId);
     let html='';
     for(const rec of context.receipts.filter(x=>x.pedido_id===id&&!x.estornado_em)){
      for(const physical of rec.itens||[]){
       const line=p.itens.find(x=>String(x.chave)===String(physical.chave));
       if(!line)continue;
       const options=(fiscalItems||[]).filter(f=>
        compatible(line,f,context.variations,currentNote?.categoria)&&
        (quantityAsInvoice(line,physical.quantidade,f.unidade)??Infinity)<=
          Number(f.quantidade)-(fiscalUsed.get(f.id)||0)+0.0001);
       const blocked=marked.has(rec.id+'|'+physical.chave);
       html+='<tr data-nf-receipt="'+esc(rec.id)+'" data-nf-key="'+esc(physical.chave)+'">'+
        '<td><input type="checkbox" data-nf-mark '+(blocked||!options.length?'disabled':'')+'></td>'+
        '<td>'+esc(String(rec.criado_em||'').slice(0,10))+'</td>'+
        '<td>'+esc(context.variations.find(v=>v.id===line.variacao_id)?.nome||line.variacao_id)+'</td>'+
        '<td>'+fmt(physical.quantidade)+' '+esc(line.unidade)+'</td><td>'+
        (blocked?'Já vinculado':!options.length?'Sem item compatível':
        '<select data-nf-fiscal>'+option('','Escolha o item da nota')+
        options.map(f=>option(f.id,f.descricao+' · disponível '+fmt(Math.max(0,Number(f.quantidade)-(fiscalUsed.get(f.id)||0)))+' '+f.unidade)).join('')+
        '</select>')+'</td></tr>';
      }
     }
     $('ewCompNFItems').innerHTML='<form id="ewCompNFForm">'+
      '<p class="hint">Confira os itens e o saldo disponível de cada linha fiscal. Se selecionar várias entregas para uma linha, a soma também precisa caber no saldo da nota. Nenhum movimento físico será gerado.</p>'+
      '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead><tr>'+
      '<th>Vincular</th><th>Data</th><th>Material</th><th>Recebido</th><th>Item da nota</th>'+
      '</tr></thead><tbody>'+html+'</tbody></table></div>'+
      '<button type="submit" class="btn primary">Vincular nota sem duplicar estoque</button></form>';
     $('ewCompNFForm').onsubmit=async event=>{
      event.preventDefault();
      if(!current())return;
      const list=[...$('ewCompNFForm').querySelectorAll('[data-nf-receipt]')]
       .filter(row=>row.querySelector('[data-nf-mark]')?.checked)
       .map(row=>({despesa_item_id:row.querySelector('[data-nf-fiscal]')?.value||'',
        recebimento_id:row.dataset.nfReceipt,chave:row.dataset.nfKey}));
      if(!list.length||list.some(x=>!x.despesa_item_id)){
       status('Selecione as linhas físicas e seus itens fiscais.');return;
      }
      if(list.length>150){status('Associe no máximo 150 entregas por operação.');return;}
      const selectedByItem=new Map();
      for(const picked of list){
       const rec=owned.find(x=>x.id===picked.recebimento_id);
       const physical=rec?.itens?.find(x=>String(x.chave)===picked.chave);
       const line=p.itens.find(x=>String(x.chave)===picked.chave);
       const invoice=(fiscalItems||[]).find(x=>x.id===picked.despesa_item_id);
       const qty=quantityAsInvoice(line,physical?.quantidade,invoice?.unidade);
       if(!physical||!line||!invoice||qty===null||
          !compatible(line,invoice,context.variations,currentNote?.categoria)){
        status('Material, unidade ou quantidade incompatível com o item fiscal.');return;
       }
       selectedByItem.set(invoice.id,(selectedByItem.get(invoice.id)||0)+qty);
      }
      for(const [itemId,qty] of selectedByItem){
       const invoice=fiscalItems.find(x=>x.id===itemId);
       if(qty+(fiscalUsed.get(itemId)||0)>Number(invoice.quantidade)+0.0001){
        status('A soma das entregas excede o saldo da nota para '+invoice.descricao+'.');return;
       }
      }
      const btn=$('ewCompNFForm').querySelector('[type="submit"]');btn.disabled=true;
      try{
       await call('ew_compras_vincular_nfe_pedido',{p_pedido_id:id,p_despesa_id:noteId,
        p_vinculos:list,p_operacao_id:op('link',{id,noteId,list})});
       pending.delete('link');await window.ewCompras.abrir();
       $('comprasMensagem').textContent='Nota vinculada: estoque físico preservado sem nova entrada.';
      }catch(e){status('Vinculação não realizada: '+e.message)}
      finally{btn.disabled=false;}
     };
    }catch(e){if(current())status('Itens da nota indisponíveis: '+e.message)}
   };
   status(available.length?'':'Nenhuma nota de alumínio/acessórios desse fornecedor aprovada para a obra.');
  }catch(e){if(generation===orderGeneration&&root.isConnected)status('Falha ao consultar notas: '+e.message)}
 };
}
window.ewComprasNfe=Object.freeze({render,quantityAsInvoice,compatible});
})();
