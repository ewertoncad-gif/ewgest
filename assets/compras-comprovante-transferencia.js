/* EWGEST v46.21 — comprovante interno da transferência de locais.
 * Gera somente impressão/consulta. Não movimenta estoque, não é NF nem CT-e.
 */
(()=>{
'use strict';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const num=x=>Number(x||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
function documentHtml(movimento,{locais=[],materiais=[],empresa='EWGEST'}={}){
 if(!movimento?.id||!movimento?.empresa_id)throw Error('Transferência indisponível para emissão do comprovante.');
 const local=(tipo,id)=>locais.find(x=>x.value===tipo+':'+id)?.label||tipo+' · '+id;
 const material=materiais.find(x=>x.id===movimento.variacao_id)?.label||movimento.variacao_id;
 const date=String(movimento.criado_em||'').slice(0,19).replace('T',' ');
 const reversed=Boolean(movimento.estornado_em);
 const quadro=via=>
  '<article class="via"><header><strong>EWGEST · TRANSFERÊNCIA DE LOCAIS DE ESTOQUE</strong>'+
  '<small>'+esc(via)+'</small></header>'+
  '<p class="tag">Documento interno de conferência, sem nova movimentação de estoque.</p>'+
  '<table><tbody>'+
  '<tr><th>Operação</th><td>'+esc(movimento.id)+'</td></tr>'+
  '<tr><th>Empresa</th><td>'+esc(empresa)+'</td></tr>'+
  '<tr><th>Registrado em</th><td>'+esc(date)+'</td></tr>'+
  '<tr><th>Origem</th><td>'+esc(local(movimento.origem_tipo,movimento.origem_id))+
   ' · '+esc(movimento.origem_galpao)+'</td></tr>'+
  '<tr><th>Destino</th><td>'+esc(local(movimento.destino_tipo,movimento.destino_id))+
   ' · '+esc(movimento.destino_galpao)+'</td></tr>'+
  '<tr><th>Material</th><td>'+esc(material)+'</td></tr>'+
  '<tr><th>Quantidade</th><td>'+esc(num(movimento.quantidade))+' '+esc(movimento.unidade)+
   (movimento.comprimento_mm?' · Barra '+esc(movimento.comprimento_mm)+' mm':'')+'</td></tr>'+
  '<tr><th>Finalidade</th><td>'+esc(movimento.motivo)+'</td></tr>'+
  '<tr><th>Situação</th><td><strong>'+(reversed?'ESTORNADA':'REGISTRADA')+'</strong>'+
   (reversed?' · Estornada em '+esc(String(movimento.estornado_em).slice(0,19).replace('T',' '))+
   (movimento.estorno_motivo?' · Motivo: '+esc(movimento.estorno_motivo):''):'')+'</td></tr>'+
  '</tbody></table>'+
  '<footer><span>Conferência de origem: ____________________</span>'+
  '<span>Conferência de destino: ____________________</span></footer>'+
  '<p class="legal">Este espelho apenas reproduz a operação registrada. A impressão não gera romaneio, nota fiscal, frete ou nova entrada/saída. Verificar documentação fiscal/de transporte aplicável.</p></article>';
 return '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'+
  '<title>Transferência de locais · '+esc(movimento.id)+'</title>'+
  '<style>@page{size:A4 portrait;margin:12mm}body{font:11px Arial,sans-serif;color:#123151;margin:0}'+
  'article.via{padding:10px 8px 14px;page-break-inside:avoid;break-inside:avoid}'+
  '.via:first-child{border-bottom:1px dashed #667d96;margin-bottom:10px}header{display:flex;justify-content:space-between;font-size:13px}'+
  'header small{font-size:10px}table{border-collapse:collapse;width:100%;margin:12px 0}th,td{border:1px solid #bed0e0;padding:6px;text-align:left;vertical-align:top}'+
  'th{width:120px;background:#eef4fa}.tag{font-style:italic;color:#536f8a}footer{display:flex;justify-content:space-between;margin:15px 0;gap:10px}.legal{font-size:9px;color:#536f8a}'+
  '</style></head><body>'+quadro('VIA ORIGEM')+quadro('VIA DESTINO')+'</body></html>';
}
function imprimir(movimento,ctx){
 const html=documentHtml(movimento,ctx);
 const tab=window.open('about:blank','_blank');
 if(!tab)throw Error('Permita a abertura da guia de impressão para emitir o comprovante.');
 tab.document.open();tab.document.write(html);tab.document.close();
 tab.focus();tab.print();
}
window.ewTransferReceipt=Object.freeze({documentHtml,imprimir});
})();
