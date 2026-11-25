/* EWGEST #38 — baixa apenas quando almoxarife entrega relatório à produção.
 * A liberação técnica mantém o estoque intacto; toda baixa é transacional no SQL.
 * Não carrega despesas, orçamentos nem valores unitários nesta tela. */
(function(){
 'use strict';
 const byId=id=>node(id);
 const esc=value=>escapeHTML(String(value??''));
 const fmt=value=>Number(value||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
 let seq=0;
 let pending=[];
 const operationIds=new Map();
 function descricaoMaterial(item){
  const variation=matVariacoes.find(x=>x.id===item.variacao_id);
  const mat=variation?.tipo==='perfil'?
    matPerfis.find(x=>x.id===variation.perfil_id):
    matAcessorios.find(x=>x.id===variation?.acessorio_id);
  const cor=[variation?.cor,variation?.acabamento].filter(Boolean).join(' / ');
  return [mat?.codigo||'Material',mat?.descricao,cor].filter(Boolean).join(' · ');
 }
 function limpar(){
  seq++;pending=[];
  byId('entregasProducaoPanel').classList.add('hidden');
  byId('entregasProducaoLista').replaceChildren();
  byId('entregasProducaoStatus').textContent='';
 }
 async function buscar(obraId){
  if(!(isAlmoxarife()||isFullAdminUser())||!currentCompany||!obraId||!temPermissao('estoque.consultar')||!temPermissao('estoque.receber')){
   limpar();return;
  }
  const thisSeq=++seq;
  const panel=byId('entregasProducaoPanel');
  panel.classList.remove('hidden');
  byId('entregasProducaoLista').replaceChildren();
  byId('entregasProducaoStatus').textContent='Consultando relatórios liberados e ainda não entregues…';
  try{
   await ensureSession();
   const result=await request('/rest/v1/rpc/ew_entregas_pendentes_producao',{
     method:'POST',token:session.access_token,timeoutMs:30000,
     body:{p_empresa_id:currentCompany.id,p_obra_id:obraId}
   });
   if(thisSeq!==seq||byId('stockProducaoWork').value!==obraId)return;
   pending=Array.isArray(result)?result:[];
   render();
  }catch(e){
   if(thisSeq!==seq||byId('stockProducaoWork').value!==obraId)return;
   byId('entregasProducaoLista').replaceChildren();
   byId('entregasProducaoStatus').textContent='Não foi possível consultar as entregas à produção: '+e.message;
  }
 }
 function render(){
  const host=byId('entregasProducaoLista');
  if(!pending.length){
   byId('entregasProducaoStatus').textContent='Nenhum relatório de materiais aguardando entrega física nesta obra.';
   host.replaceChildren();return;
  }
  byId('entregasProducaoStatus').textContent=pending.length+' relatório(s) aguardando conferência física e entrega.';
  host.innerHTML=pending.map((x,index)=>{
   const itens=Array.isArray(x.materiais)?x.materiais:[];
   return '<div class="entregaRelatorio" data-entrega-index="'+index+'">'+
    '<div class="entregaRelatorioCabecalho"><strong>'+esc(x.tipo==='LOTE'?'Liberação em lote CEM':x.codigo||'Liberação técnica')+'</strong>'+
    '<span>'+esc(x.data||'')+' · Fábrica '+esc(x.fabrica||'')+'</span></div>'+
    '<p class="hint">Relatório: '+esc(x.arquivo||'Liberação no sistema')+
    ' · '+itens.length+' linha(s). Compare com o relatório impresso antes de entregar à produção.</p>'+
    '<div class="finTableWrap"><table class="finTable"><thead><tr>'+
    '<th>Material</th><th>Comprimento</th><th>Quantidade</th><th>Galpão de retirada</th></tr></thead><tbody>'+
    itens.map(m=>'<tr><td>'+esc(descricaoMaterial(m))+'</td>'+
      '<td>'+esc(m.comprimento_mm?fmt(m.comprimento_mm)+' mm':'—')+'</td>'+
      '<td>'+fmt(m.quantidade)+' '+esc(m.unidade||'')+'</td>'+
      '<td>'+esc(m.local_estoque||'—')+'</td></tr>').join('')+
    '</tbody></table></div>'+
    '<label class="entregaRelatorioConferida">'+
      '<input type="checkbox" class="entregaRelatorioCheck"> '+
      'Conferi o relatório impresso e entreguei todos os materiais acima à produção.</label>'+
    '<button class="btn primary entregaRelatorioConfirmar" type="button" disabled>'+
      'Confirmar entrega e dar baixa no estoque</button>'+
    '<p class="feedback entregaRelatorioErro" role="status"></p></div>';
  }).join('');
 }
 async function confirmar(card){
  const index=Number(card.dataset.entregaIndex),registro=pending[index];
  if(!registro||!currentCompany||!temPermissao('estoque.consultar')||!temPermissao('estoque.receber'))return;
  const obra=byId('stockProducaoWork').value;
  if(!obra||!card.querySelector('.entregaRelatorioCheck').checked)return;
  const unitCount=(registro.materiais||[]).reduce((n,x)=>n+Number(x.quantidade||0),0);
  if(!window.confirm('Confirma a ENTREGA FÍSICA à produção do relatório '+(registro.codigo||registro.arquivo||'')+
    '?\n\nSerão baixadas '+registro.materiais.length+' linha(s) de material ('+fmt(unitCount)+
    ' unidades das respectivas medidas e tipos) dos galpões informados.\\n\\nA liberação técnica por si só não movimenta o estoque.'))return;
  const btn=card.querySelector('.entregaRelatorioConfirmar');
  const msg=card.querySelector('.entregaRelatorioErro');
  btn.disabled=true;msg.textContent='Registrando entrega física no estoque…';
  const key=registro.tipo+'|'+registro.id;
  const operacao=operationIds.get(key)||crypto.randomUUID();
  operationIds.set(key,operacao);
  try{
   await ensureSession();
   const result=await request('/rest/v1/rpc/ew_confirmar_entrega_producao',{
    method:'POST',token:session.access_token,timeoutMs:50000,
    body:{p_empresa_id:currentCompany.id,p_obra_id:obra,
      p_tipo:registro.tipo,p_referencia_id:registro.id,p_operacao_id:operacao}
   });
   operationIds.delete(key);
   if(byId('stockProducaoWork').value!==obra)return;
   await buscar(obra);
   byId('entregasProducaoStatus').textContent=result?.repetida?
    'Esta entrega já estava registrada; não houve nova baixa.':
    'Materiais entregues e baixados do estoque. Operação vinculada ao relatório e usuário.';
  }catch(e){
   msg.textContent='Baixa não confirmada: '+e.message+
     '. Se houve perda de conexão, consulte as pendências antes de repetir.';
   btn.disabled=false;
  }
 }
 byId('entregasProducaoLista').addEventListener('change',event=>{
  if(!event.target.matches('.entregaRelatorioCheck'))return;
  const card=event.target.closest('[data-entrega-index]');
  const btn=card?.querySelector('.entregaRelatorioConfirmar');
  if(btn)btn.disabled=!event.target.checked;
 });
 byId('entregasProducaoLista').addEventListener('click',event=>{
  const btn=event.target.closest('.entregaRelatorioConfirmar');
  if(!btn)return;
  const card=btn.closest('[data-entrega-index]');
  if(card)confirmar(card);
 });
 window.ewCarregarEntregasProducao=buscar;
 window.ewLimparEntregasProducao=limpar;
})();
