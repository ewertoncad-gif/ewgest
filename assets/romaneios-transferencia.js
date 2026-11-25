/* EWGEST v45.4: romaneios de transferencias fisicas entre galpoes.
 * Documentos espelham movimentos ja realizados, SEM nova baixa de estoque. */
(function(){
'use strict';
const el=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>Number(v||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
let docs=[],editId=null,busy=false;
let editVersion=0,motoristas=[],veiculos=[],transporteCarregado=false;
function empresa(){return typeof currentCompany!=='undefined'&&currentCompany?currentCompany.id:null;}
function dataHoje(){const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');}
function erro(v){el('romTransfStatus').textContent=String(v||'');}
function avisoDocumento(id,message){
 erro(message);
 const lista=el('romTransfList');
 const alvo=lista&&[...lista.querySelectorAll('[data-t-status]')].find(n=>n.dataset.tStatus===id);
 if(alvo)alvo.textContent=String(message||'');
}
function rota(d){return d.origem+' → '+d.destino;}
function obra(id){
 return (typeof works!=='undefined'&&works||[]).find(w=>w.id===id)?.nome||'Obra indisponível';
}
function obraArquivada(id){return !(typeof works!=='undefined'&&works||[]).some(w=>w.id===id);}
function ativo(d){return d.status==='RASCUNHO'||d.status==='EMITIDO';}
function estaEstornado(d){return (d.itens||[]).some(i=>i.tipo==='TRANSFERENCIA'&&i.estornado);}
function itemResumo(i){
 return '<tr><td>'+esc(i.codigo||'—')+'</td><td>'+esc(i.descricao)+
 (i.cor?' · '+esc(i.cor):'')+'</td><td>'+num(i.quantidade)+' '+esc(i.unidade)+
 (i.comprimento_mm?' · '+num(i.comprimento_mm)+' mm':'')+'</td><td>'+
 (i.tipo==='AVULSO'?'Avulso (sem movimentação de estoque)':i.estornado?'Transferência estornada':esc(obra(i.origem_obra_id)))+
 '</td></tr>';
}
function podeJuntar(){return typeof temPermissao==='function'&&temPermissao('romaneios.juntar')&&temPermissao('romaneios.transferir');}
function render(){
 el('romTransfMerge').classList.toggle('hidden',!podeJuntar());
 const box=el('romTransfList');
 if(!box)return;
 const exibidos=docs.filter(d=>!obraArquivada(d.obra_id));
 if(!exibidos.length){
  box.innerHTML='<p class="hint">Nenhum romaneio de transferência de obra em andamento. Os documentos encerrados permanecem apenas na auditoria.</p>';
  return;
 }
 box.innerHTML=exibidos.map(d=>{
 const emitted=d.status==='EMITIDO';
 const grouped=d.status==='AGRUPADO';
 const historico=obraArquivada(d.obra_id);
 return '<div class="romTransfDoc'+(grouped?' grouped':'')+'"><div class="romTransfDocHead">'+
 '<label class="romTransfPick">'+(d.status==='RASCUNHO'&&!historico&&podeJuntar()?
 '<input type="checkbox" data-transf-pick="'+esc(d.id)+'" aria-label="Selecionar '+esc(d.numero)+' para juntar">':'')+
 '<strong>'+esc(d.numero)+'</strong></label><span class="romTransfState">'+
 esc(grouped?'AGRUPADO':d.status)+'</span></div><div class="romTransfMeta"><strong>'+esc(rota(d))+
 '</strong> · '+esc(d.data||'')+' · '+(d.itens||[]).length+' item(ns) · '+esc(obra(d.obra_id))+
 (historico?' · <strong>OBRA ARQUIVADA · SOMENTE HISTÓRICO</strong>':'')+
 (estaEstornado(d)?' · <strong class="romTransfWarning">TRANSFERÊNCIA ESTORNADA</strong>':'')+
 (grouped?' · Número histórico, pode ser reutilizado · Agrupado no '+esc(docs.find(x=>x.id===d.agrupado_em)?.numero||'romaneio principal'):'')+
 '</div><div class="romTransfBtns">'+
 '<button type="button" class="btn secondary" data-t-view="'+esc(d.id)+'">Consultar</button>'+
 (d.status==='RASCUNHO'&&!historico?'<button type="button" class="btn secondary" data-t-edit="'+esc(d.id)+'">Editar / incluir itens</button>':'')+
 (d.status==='RASCUNHO'&&!historico?'<button type="button" class="btn primary" data-t-emit="'+esc(d.id)+'">Emitir e imprimir</button>':'')+
 (emitted?'<button type="button" class="btn secondary" data-t-print="'+esc(d.id)+'">Imprimir / reimprimir</button>':'')+
 '</div><p class="romTransfDocMessage" data-t-status="'+esc(d.id)+'" role="status"></p></div>';
 }).join('');
 box.querySelectorAll('[data-t-view]').forEach(x=>x.addEventListener('click',()=>visualizar(x.dataset.tView)));
 box.querySelectorAll('[data-t-edit]').forEach(x=>x.addEventListener('click',()=>editar(x.dataset.tEdit)));
 box.querySelectorAll('[data-t-emit]').forEach(x=>x.addEventListener('click',()=>emitir(x.dataset.tEmit)));
 box.querySelectorAll('[data-t-print]').forEach(x=>x.addEventListener('click',()=>imprimir(x.dataset.tPrint)));
}
async function rpc(nome,args){
 await ensureSession();
 return await request('/rest/v1/rpc/'+nome,{method:'POST',token:session.access_token,body:args});
}
async function carregar(){
 if(!empresa()||busy)return;
 busy=true;erro('Consultando os romaneios de transferência…');
 try{
  const response=await rpc('ew_romaneios_transferencia_listar',{p_empresa_id:empresa()});
  docs=Array.isArray(response)?response:[];
  erro('Transferências entre galpões de obras em andamento: '+
   docs.filter(d=>ativo(d)&&!obraArquivada(d.obra_id)).length+'.');
  render();
 }catch(e){erro('Não foi possível consultar romaneios de transferência: '+e.message);}
 finally{busy=false;}
}
function close(){editVersion++;el('romTransfOverlay').classList.add('hidden');editId=null;transporteCarregado=false;}
function addRow(value={}){
 const div=document.createElement('div');div.className='romTransfExtra';
 div.innerHTML='<label>Código (opcional)<input data-av-codigo maxlength="40" value="'+esc(value.codigo||'')+'"></label>'+
 '<label>Descrição<input data-av-descricao maxlength="250" required value="'+esc(value.descricao||'')+'"></label>'+
 '<label>Quantidade<input data-av-qtd type="number" min="0.001" max="1000000" step="0.001" required value="'+esc(value.quantidade||1)+'"></label>'+
 '<label>Unidade<input data-av-unidade maxlength="12" required value="'+esc(value.unidade||'UN')+'"></label>'+
 '<button type="button" class="btn secondary" data-av-remove>Remover</button>';
 div.querySelector('[data-av-remove]').addEventListener('click',()=>div.remove());
 el('romTransfExtras').append(div);
}
function selecionarTransporte(id,lista,campo,valor){
 const seletor=el(id);
 const placeholder=id==='romTransfMotorista'?'Selecione um motorista cadastrado':'Selecione uma placa cadastrada';
 seletor.replaceChildren(new Option(placeholder,''));
 for(const registro of lista){
  const texto=String(registro[campo]||'').trim();
  if(texto)seletor.add(new Option(texto,texto));
 }
 seletor.value=lista.some(x=>x[campo]===valor)?valor:'';
 seletor.disabled=false;
}
async function carregarTransporteEdicao(id,version,motoristaAtual,placaAtual){
 try{
  const [drivers,vehicles]=await Promise.all([
   apiGet('romaneios_motoristas',{select:'id,nome,ativo',empresa_id:'eq.'+empresa(),ativo:'eq.true',order:'nome.asc'}),
   apiGet('romaneios_veiculos',{select:'id,placa,ativo',empresa_id:'eq.'+empresa(),ativo:'eq.true',order:'placa.asc'})
  ]);
  if(editVersion!==version||editId!==id)return;
  motoristas=Array.isArray(drivers)?drivers:[];
  veiculos=Array.isArray(vehicles)?vehicles:[];
  selecionarTransporte('romTransfMotorista',motoristas,'nome',motoristaAtual);
  selecionarTransporte('romTransfPlaca',veiculos,'placa',placaAtual);
  transporteCarregado=true;
  el('romTransfEditForm').querySelector('button[type="submit"]').disabled=false;
  const avisos=[];
  if(!motoristas.length)avisos.push('Não há motoristas ativos cadastrados.');
  if(!veiculos.length)avisos.push('Não há placas ativas cadastradas.');
  if(motoristaAtual&&!motoristas.some(x=>x.nome===motoristaAtual))avisos.push('O motorista anterior não está ativo; selecione outro.');
  if(placaAtual&&!veiculos.some(x=>x.placa===placaAtual))avisos.push('A placa anterior não está ativa; selecione outra.');
  el('romTransfEditStatus').textContent=avisos.length?
   avisos.join(' ')+' Cadastre novos motoristas ou veículos na emissão de romaneios da obra.':'';
 }catch(e){
  if(editVersion!==version||editId!==id)return;
  transporteCarregado=false;
  el('romTransfEditStatus').textContent='Não foi possível carregar os motoristas e placas cadastrados: '+e.message;
 }
}
function editar(id){
 const d=docs.find(x=>x.id===id);
 if(!d||d.status!=='RASCUNHO')return;
 editId=id;
 const version=++editVersion;
 transporteCarregado=false;
 motoristas=[];veiculos=[];
 el('romTransfEditTitle').textContent='Editar '+d.numero+' · '+rota(d);
 el('romTransfDate').value=d.data||dataHoje();
 for(const [field,label] of [
  ['romTransfMotorista','Carregando motoristas cadastrados…'],
  ['romTransfPlaca','Carregando placas cadastradas…']
 ]){
  const select=el(field);
  select.replaceChildren(new Option(label,''));
  select.disabled=true;
 }
 el('romTransfObs').value=d.observacoes||'';
 el('romTransfExtras').replaceChildren();
 (d.itens||[]).filter(i=>i.tipo==='AVULSO').forEach(addRow);
 const reais=(d.itens||[]).filter(i=>i.tipo==='TRANSFERENCIA');
 el('romTransfLinked').innerHTML='<table><thead><tr><th>Código</th><th>Material</th><th>Qtd.</th><th>Obra</th></tr></thead><tbody>'+
 reais.map(itemResumo).join('')+'</tbody></table>';
 el('romTransfEditStatus').textContent='Carregando motoristas e placas cadastrados…';
 el('romTransfEditForm').querySelector('button[type="submit"]').disabled=true;
 el('romTransfOverlay').classList.remove('hidden');
 void carregarTransporteEdicao(id,version,d.motorista||'',d.placa||'');
}
async function salvar(){
 const d=docs.find(x=>x.id===editId);
 if(!d||busy)return;
 const motorista=el('romTransfMotorista').value;
 const placa=el('romTransfPlaca').value;
 if(!transporteCarregado||!motoristas.some(x=>x.nome===motorista)||
    !veiculos.some(x=>x.placa===placa)){
  el('romTransfEditStatus').textContent='Selecione um motorista e uma placa ativos dos cadastros antes de salvar.';
  return;
 }
 const avulsos=[...el('romTransfExtras').querySelectorAll('.romTransfExtra')].map(row=>({
  codigo:row.querySelector('[data-av-codigo]').value.trim(),
  descricao:row.querySelector('[data-av-descricao]').value.trim(),
  quantidade:Number(row.querySelector('[data-av-qtd]').value),
  unidade:row.querySelector('[data-av-unidade]').value.trim()
 }));
 if(avulsos.some(x=>!x.descricao||!x.unidade||!Number.isFinite(x.quantidade)||x.quantidade<=0)){
  el('romTransfEditStatus').textContent='Revise os itens avulsos.';return;
 }
 busy=true;el('romTransfEditStatus').textContent='Salvando romaneio…';
 try{
  await rpc('ew_romaneio_transferencia_salvar',{
   p_empresa_id:empresa(),p_documento_id:d.id,
   p_data:el('romTransfDate').value,p_motorista:motorista,
   p_placa:placa,
   p_observacoes:el('romTransfObs').value,
   p_avulsos:avulsos
  });
  close();busy=false;await carregar();
 }catch(e){el('romTransfEditStatus').textContent='Não foi possível salvar: '+e.message;busy=false;}
}
async function juntar(){
 if(!podeJuntar()||busy)return;
 const ids=[...el('romTransfList').querySelectorAll('[data-transf-pick]:checked')].map(x=>x.dataset.transfPick);
 if(ids.length<2){erro('Selecione pelo menos dois romaneios em rascunho para juntar.');return;}
 const sel=docs.filter(x=>ids.includes(x.id)).sort((a,b)=>Number(a.numero.slice(2))-Number(b.numero.slice(2)));
 if(sel.length!==ids.length||sel.some(x=>x.status!=='RASCUNHO'||x.obra_id!==sel[0].obra_id||rota(x)!==rota(sel[0]))){
  erro('Só é possível juntar rascunhos da mesma obra e rota.');return;
 }
 if(!window.confirm('Juntar '+sel.map(x=>x.numero).join(' / ')+' em '+sel[0].numero+'? Os códigos históricos ficam registrados; números liberados no final da sequência poderão ser reutilizados.'))return;
 if(busy)return;
 busy=true;
 try{
  const result=await rpc('ew_romaneios_transferencia_juntar',{
   p_empresa_id:empresa(),p_principal_id:sel[0].id,p_outros:sel.slice(1).map(x=>x.id)});
  busy=false;await carregar();erro('Romaneios agrupados no '+result.numero+'. Próximo código da obra: '+result.proximo_codigo+'.');
 }catch(e){busy=false;erro('Falha ao juntar: '+e.message);}
}
async function emitir(id){
 const d=docs.find(x=>x.id===id);
 if(!d||busy||d.status!=='RASCUNHO')return;
 if(!d.motorista||!d.placa){
  editar(id);
  el('romTransfEditTitle').textContent='Complete o transporte antes de emitir '+d.numero;
  avisoDocumento(id,'O romaneio continua em rascunho. Selecione motorista e placa, salve e depois clique em Emitir e imprimir.');
  return;
 }
 if(estaEstornado(d)){avisoDocumento(id,'Há transferência estornada neste romaneio. Não é possível emitir.');return;}
 if(!window.confirm('Emitir e imprimir '+d.numero+'? Após emitir, o documento será bloqueado para edição. A operação não movimenta estoque novamente.'))return;
 // A guia deve ser aberta durante o clique, ANTES da chamada assíncrona.
 // Abrir depois do await pode ser bloqueado pelo navegador.
 const aba=window.open('about:blank','_blank');
 if(aba){
  try{
   aba.document.title='Preparando romaneio '+d.numero;
   aba.document.body.textContent='Emitindo '+d.numero+'… A prévia de impressão será aberta após a confirmação.';
  }catch(e){/* A emissão também funciona sem esta mensagem provisória. */}
 }
 busy=true;
 try{
  await rpc('ew_romaneio_transferencia_emitir',{p_empresa_id:empresa(),p_documento_id:id});
 }catch(e){
  busy=false;
  if(aba&&!aba.closed)aba.close();
  avisoDocumento(id,'Não foi possível emitir '+d.numero+'. Ele permanece em rascunho. '+e.message);
  return;
 }
 // O banco já confirmou a emissão. Manter o botão de reimprimir disponível
 // mesmo se a atualização da listagem falhar.
 d.status='EMITIDO';
 busy=false;
 render();
 let abriu=false;
 try{abriu=imprimir(id,aba);}catch(e){
  if(aba&&!aba.closed)aba.close();
  erro(d.numero+' emitido, mas ocorreu um erro ao preparar a impressão. Use Imprimir / reimprimir. '+e.message);
 }
 await carregar();
 avisoDocumento(id,abriu?
  d.numero+' emitido. A prévia e o comando de impressão foram abertos em outra guia. O botão Imprimir / reimprimir permanece disponível.':
  d.numero+' emitido. Não foi possível abrir a impressão automaticamente; use o botão Imprimir / reimprimir e autorize novas guias se necessário.');
}
function imprimir(id,janelaReservada=null){
 const d=docs.find(x=>x.id===id);
 if(!d||d.status!=='EMITIDO')return false;
 if(estaEstornado(d)){
  if(!window.confirm('Este romaneio contém transferência estornada. Imprimir apenas para consulta histórica, com aviso de estorno?')){
   if(janelaReservada&&!janelaReservada.closed)janelaReservada.close();
   return false;
  }
 }
 const janela=janelaReservada||window.open('about:blank','_blank');
 if(!janela||janela.closed){
  avisoDocumento(id,'O navegador bloqueou a nova guia. Permita pop-ups para o EWGEST e clique em Imprimir / reimprimir.');
  return false;
 }
 // Mesma identidade visual do comprovante de entrega de esquadrias:
 // logos, cabeçalho, tabela, assinaturas e paginação inteligente em duas vias.
 // A transformação abaixo é APENAS documental: não registra novas saídas.
 try{
  if(typeof window.ewConstruirHTMLRomaneioTransferencia!=='function')
   throw new Error('O modelo de impressão não está disponível. Atualize o EWGEST e tente novamente.');
  const linhas=(d.itens||[]).map((i,index)=>({
   sequencia:index+1,
   natureza:'material',
   codigo:String(i.codigo||'').trim(),
   descricao:[i.descricao,i.cor].filter(Boolean).join(' · '),
   medida:Number(i.comprimento_mm)>0?
    (Number(i.comprimento_mm)/1000).toLocaleString('pt-BR',
      {minimumFractionDigits:2,maximumFractionDigits:2})+' m':'',
   quantidade:Number(i.quantidade),
   unidade:String(i.unidade||'UN'),
   obra_origem:i.tipo==='AVULSO'?'Avulso (documental)':obra(i.origem_obra_id)
  }));
  if(!linhas.length)throw new Error('Este romaneio não contém materiais.');
  const html=window.ewConstruirHTMLRomaneioTransferencia({
   numero:d.numero,
   obra_id:d.obra_id,
   data_saida:d.data,
   origem_galpao:d.origem,
   destino_galpao:d.destino,
   motorista:d.motorista,
   placa:d.placa,
   observacoes:d.observacoes,
   transferencia_estornada:estaEstornado(d),
   status:d.status
  },linhas);
  const toolbar='<div class="viewToolbar" role="toolbar" aria-label="Ações do romaneio">'+
   '<strong>Romaneio '+esc(d.numero)+' · Transferência entre galpões</strong>'+
   '<div class="viewToolbarActions">'+
   '<button type="button" id="imprimirRomaneio">Imprimir</button>'+
   '<button type="button" id="fecharRomaneio">Fechar</button></div></div>';
  janela.opener=null;
  janela.document.open();
  janela.document.write(html.replace('<body>','<body>'+toolbar));
  janela.document.close();
  const imprimirBtn=janela.document.getElementById('imprimirRomaneio');
  const fecharBtn=janela.document.getElementById('fecharRomaneio');
  if(imprimirBtn)imprimirBtn.addEventListener('click',()=>janela.print());
  if(fecharBtn)fecharBtn.addEventListener('click',()=>janela.close());
  janela.focus();
  // Mesmo intervalo da impressão de esquadrias, para renderizar as logomarcas.
  try{
   if(typeof janela.setTimeout==='function')janela.setTimeout(()=>janela.print(),350);
   else janela.print();
  }catch(e){/* O botão manual Imprimir continua disponível na prévia. */}
 }catch(e){
  avisoDocumento(id,'Não foi possível preparar o romaneio para impressão: '+e.message);
  if(janela&&!janela.closed)janela.close();
  return false;
 }
 return true;
}
function visualizar(id){
 const d=docs.find(x=>x.id===id);
 if(!d)return;
 el('romTransfViewTitle').textContent=d.numero+' · '+rota(d);
 el('romTransfViewContent').innerHTML=
 '<p><strong>Situação:</strong> '+esc(d.status)+' · '+esc(d.data||'')+
 ' · <strong>Obra:</strong> '+esc(obra(d.obra_id))+'</p>'+
 '<p><strong>Motorista:</strong> '+esc(d.motorista||'—')+' · <strong>Placa:</strong> '+esc(d.placa||'—')+'</p>'+
 '<table><thead><tr><th>Código</th><th>Material</th><th>Quantidade</th><th>Origem / status</th></tr></thead><tbody>'+
 (d.itens||[]).map(itemResumo).join('')+'</tbody></table>'+
 '<p><strong>Observações:</strong> '+esc(d.observacoes||'—')+'</p>'+
 '<p class="hint">As linhas de transferência vêm do estoque e não podem ter suas quantidades alteradas pelo romaneio. Itens avulsos são somente documentais.</p>';
 el('romTransfViewOverlay').classList.remove('hidden');
}
el('romTransfReload').addEventListener('click',carregar);
el('romTransfMerge').addEventListener('click',juntar);
el('romTransfClose').addEventListener('click',close);
el('romTransfAddExtra').addEventListener('click',()=>addRow());
el('romTransfEditForm').addEventListener('submit',e=>{e.preventDefault();salvar();});
el('romTransfViewClose').addEventListener('click',()=>el('romTransfViewOverlay').classList.add('hidden'));
window.ewTransferRomaneiosReload=carregar;
})();