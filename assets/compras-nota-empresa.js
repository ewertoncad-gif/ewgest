/* EWGEST v46.21 — notas fiscais de estoque próprio da empresa, sem obra fictícia. */
(()=>{
'use strict';
const $=id=>document.getElementById(id);
const esc=x=>escapeHTML(String(x??''));
const fmt=x=>Number(x||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
const money=c=>(Number(c||0)/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const option=(value,label)=>'<option value="'+esc(value)+'">'+esc(label)+'</option>';
const ops=new Map();
function token(kind,payload){const signature=JSON.stringify(payload),old=ops.get(kind);
 if(old?.signature===signature)return old.id;
 const id=crypto.randomUUID();ops.set(kind,{id,signature});return id;}
function cents(raw){
 const text=String(raw||'').trim().replace(/^R\$\s*/,'').replace(/\s/g,'');
 if(!/^\d+(?:[.,]\d{1,2})?$/.test(text))return null;
 const n=Math.round(Number(text.replace(',','.'))*100);
 return Number.isSafeInteger(n)&&n>=0?n:null;
}
function today(){
 const d=new Date();
 return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');
}
const rpc=(name,body)=>request('/rest/v1/rpc/'+name,{
 method:'POST',token:session.access_token,body,timeoutMs:45000});
async function render(root,ctx){
 if(!ctx?.empresa_id||!root?.isConnected)return;
 const orders=ctx.orders.filter(p=>p.local_empresa_id&&p.status!=='CANCELADO');
 const section=document.createElement('div');section.id='ewNfeEmpresaPanel';
 root.appendChild(section);
 section.innerHTML='<h3>Notas fiscais do estoque próprio da empresa</h3>'+
 '<p class="hint">Lance o custo do material recebido em estoque empresarial sem vinculá-lo a uma obra. Esta nota não aumenta o saldo físico e pode ser cancelada com histórico.</p>'+
 '<label>Pedido para estoque da empresa<select id="ewNfeEmpOrder">'+option('','Selecione um pedido')+
 orders.map(p=>option(p.id,'Pedido #'+p.numero+' · '+(ctx.suppliers.find(f=>f.id===p.fornecedor_id)?.nome||'Fornecedor')+
 ' · '+(ctx.localNames?.find(l=>l.id===p.local_empresa_id)?.nome||'Estoque da empresa'))).join('')+
 '</select></label><div id="ewNfeEmpContent"></div>'+
 '<p class="feedback" id="ewNfeEmpStatus" role="status"></p>';
 const say=msg=>{if($('ewNfeEmpStatus'))$('ewNfeEmpStatus').textContent=msg||''};
 $('ewNfeEmpOrder').onchange=async()=>{
  const orderId=$('ewNfeEmpOrder').value,p=orders.find(x=>x.id===orderId);
  $('ewNfeEmpContent').replaceChildren();say('');
  if(!p)return;
  say('Consultando documentos e recebimentos…');
  try{
   await ensureSession();
   const [docs,already]=await Promise.all([
    apiGet('ew_compras_notas_empresa',{
     select:'id,numero_documento,valor_centavos,data_documento,status,criado_em,cancelamento_motivo',
     empresa_id:'eq.'+ctx.empresa_id,pedido_id:'eq.'+p.id,order:'criado_em.desc',limit:'500'}),
    apiGet('ew_compras_notas_empresa_itens',{
     select:'recebimento_id,chave,cancelado_em',
     empresa_id:'eq.'+ctx.empresa_id,limit:'3000'})
   ]);
   if(!$('ewNfeEmpOrder')||$('ewNfeEmpOrder').value!==p.id)return;
   const seen=new Set((already||[]).filter(x=>!x.cancelado_em)
     .map(x=>x.recebimento_id+'|'+x.chave));
   const active=(docs||[]).filter(d=>d.status==='ATIVA');
   const total=active.reduce((sum,d)=>sum+Number(d.valor_centavos||0),0);
   let physicalRows='';
   for(const rec of ctx.receipts.filter(r=>r.pedido_id===p.id&&!r.estornado_em)){
    for(const line of rec.itens||[]){
     const orderLine=p.itens.find(x=>String(x.chave)===String(line.chave));
     if(!orderLine)continue;
     const used=seen.has(rec.id+'|'+line.chave),mat=ctx.variations.find(v=>v.id===orderLine.variacao_id);
     physicalRows+='<tr data-ew-emp-rec="'+esc(rec.id)+'" data-ew-emp-key="'+esc(String(line.chave))+'">'+
     '<td><input type="checkbox" data-ew-emp-pick '+(used?'disabled':'')+'></td>'+
     '<td>'+esc(String(rec.criado_em||'').slice(0,10))+'</td>'+
     '<td>'+esc(mat?.nome||orderLine.variacao_id)+'</td>'+
     '<td>'+fmt(line.quantidade)+' '+esc(orderLine.unidade)+'</td>'+
     '<td>'+(used?'Já lançado em nota':'<input type="text" data-ew-emp-amount inputmode="decimal" placeholder="0,00">')+'</td></tr>';
    }
   }
   $('ewNfeEmpContent').innerHTML='<div class="ewComprasTableWrap"><table class="ewComprasTable">'+
    '<thead><tr><th>Nota</th><th>Data</th><th>Valor</th><th>Status</th><th>Ação</th></tr></thead><tbody>'+
    (docs||[]).map(doc=>'<tr><td>'+esc(doc.numero_documento)+'</td><td>'+
      esc(doc.data_documento)+'</td><td>'+money(doc.valor_centavos)+'</td><td>'+
      esc(doc.status)+'</td><td>'+(doc.status==='ATIVA'&&temPermissao('financeiro.cancelar_despesas')?
       '<button type="button" class="btn secondary" data-ew-emp-cancel="'+esc(doc.id)+'">Cancelar nota</button>':'—')+
      '</td></tr>').join('')+'</tbody></table></div>'+
    '<p class="hint">Total de notas ativas deste pedido: <strong>'+money(total)+'</strong> (custo empresarial; não é despesa da obra).</p>'+
    '<form id="ewNfeEmpForm" class="ewComprasForm">'+
    '<div class="ewTransferGrid"><label>Número da nota<input id="ewNfeEmpNumber" maxlength="100" required></label>'+
    '<label>Data da nota<input id="ewNfeEmpDate" type="date" value="'+today()+'" required></label>'+
    '<label>Chave da NF-e (opcional, 44 dígitos)<input id="ewNfeEmpKey" maxlength="44"></label>'+
    '<label>Valor total (R$)<input id="ewNfeEmpTotal" type="text" inputmode="decimal" placeholder="0,00" required></label></div>'+
    '<label>Observações<textarea id="ewNfeEmpObs" rows="2" maxlength="1000"></textarea></label>'+
    '<h4>Vincular os materiais que esta nota está cobrando</h4>'+
    '<div class="ewComprasTableWrap"><table class="ewComprasTable"><thead>'+
    '<tr><th>Vincular</th><th>Data recebida</th><th>Material</th><th>Qtd. física</th><th>Subtotal da nota (R$)</th></tr>'+
    '</thead><tbody>'+physicalRows+'</tbody></table></div>'+
    '<button type="submit" class="btn primary">Registrar nota sem nova entrada física</button></form>';
   $('ewNfeEmpContent').querySelectorAll('[data-ew-emp-cancel]').forEach(button=>{
    button.onclick=async()=>{
     const id=button.dataset.ewEmpCancel;
     const mot=window.prompt('Motivo para cancelar a nota (5 a 400 caracteres):');
     if(mot===null)return;const reason=mot.trim();
     if(reason.length<5||reason.length>400){say('Motivo inválido.');return;}
     if(!window.confirm('Cancelar esta nota empresarial? O custo fica cancelado, mas o estoque físico não será alterado.'))return;
     button.disabled=true;
     try{
      await rpc('ew_compras_cancelar_nota_empresa',{p_nota_id:id,p_motivo:reason,
       p_operacao_id:token('cancelar_nota',{id,reason})});
      ops.delete('cancelar_nota');await window.ewCompras.abrir();
      $('comprasMensagem').textContent='Nota empresarial cancelada. Estoque inalterado.';
     }catch(e){say('Cancelamento bloqueado: '+e.message)}
     finally{button.disabled=false;}
    };
   });
   $('ewNfeEmpForm').onsubmit=async event=>{
    event.preventDefault();
    const number=$('ewNfeEmpNumber').value.trim(),date=$('ewNfeEmpDate').value,
     key=$('ewNfeEmpKey').value.trim(),total=cents($('ewNfeEmpTotal').value);
    const items=[...$('ewNfeEmpForm').querySelectorAll('[data-ew-emp-rec]')]
     .filter(row=>row.querySelector('[data-ew-emp-pick]')?.checked)
     .map(row=>({recebimento_id:row.dataset.ewEmpRec,chave:row.dataset.ewEmpKey,
       valor_total_centavos:cents(row.querySelector('[data-ew-emp-amount]')?.value)}));
    if(!number||!date||total===null||total<=0||!items.length||
     items.some(i=>i.valor_total_centavos===null)||
     items.reduce((acc,i)=>acc+i.valor_total_centavos,0)!==total||
     (key&&!/^\d{44}$/.test(key))){
     say('Informe documento, itens e subtotais válidos. A soma deve ser igual ao valor total da nota.');return;
    }
    const button=$('ewNfeEmpForm').querySelector('[type="submit"]');button.disabled=true;
    const payload={orderId,number,date,key,total,items};
    try{
     await rpc('ew_compras_registrar_nota_empresa',{
      p_pedido_id:orderId,p_numero_documento:number,p_data_documento:date,
      p_chave_nfe:key||null,p_valor_centavos:total,p_itens:items,
      p_observacoes:$('ewNfeEmpObs').value,p_operacao_id:token('nota_empresa',payload)});
     ops.delete('nota_empresa');await window.ewCompras.abrir();
     $('comprasMensagem').textContent='Nota empresarial registrada. Nenhum material entrou novamente no estoque.';
    }catch(e){say('Nota não registrada: '+e.message)}
    finally{button.disabled=false;}
   };
   say('');
  }catch(e){say('Não foi possível consultar documentos empresariais: '+e.message)}
 };
}
window.ewComprasNfeEmpresa=Object.freeze({render});
})();
