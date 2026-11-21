/* EWGEST #34: estoque físico de vidros/outros insumos.
 * Não lê orçamento nem valores de NF; apenas catálogo e saldos por obra.
 * Todos os lançamentos e transferências ocorrem nas RPCs transacionais. */
(function(){
 'use strict';
 const byId=id=>node(id),esc=x=>escapeHTML(String(x??''));
 const fmt=n=>Number(n||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
 let catalogo=[],saldos=[],historico=[],carregando=false,editId=null,transferOp=null,categoriaAtual='vidros';
 const tipos={vidros:'Vidros',outros:'Outros insumos'};
 const unidades={PC:'PC',UN:'UN',M2:'m²',MT:'m',KG:'kg',CX:'CX',CJ:'CJ',PR:'PR'};
 async function rpc(func,args){
  await ensureSession();
  return request('/rest/v1/rpc/'+func,{
   method:'POST',token:session.access_token,body:args,timeoutMs:90000});
 }
 function aviso(id,msg){byId(id).textContent=msg;}
 async function carregarCatalogo(){
  if(!(isFullAdminUser()||isAlmoxarife())||!currentCompany)return;
  try{
   catalogo=await rpc('ew_insumos_catalogo_listar',{p_empresa_id:currentCompany.id});
   if(!Array.isArray(catalogo))throw Error('Resposta inesperada do catálogo.');
   mostrarCatalogo();sugestoes();
  }catch(e){aviso('cadastroInsumosStatus','Não foi possível consultar o catálogo: '+e.message);}
 }
 function sugestoes(){
  const host=byId('insumoCatalogoSugestoes');
  if(!host)return;
  const cat=byId('finCostCategory').value;
  host.replaceChildren();
  for(const c of catalogo.filter(x=>x.ativo&&x.categoria===cat)){
   const o=document.createElement('option');o.value=c.descricao;host.appendChild(o);
  }
 }
 function mostrarCatalogo(){
  const host=byId('cadastroInsumosList');
  if(!host)return;
  const filtro=byId('cadastroInsumosCategory').value;
  const itens=catalogo.filter(x=>x.categoria===filtro);
  host.innerHTML=itens.length?itens.map(x=>
   '<div class="cadastrosListRow insumosCatalogRow">'+
   '<span><strong>'+esc(x.descricao)+'</strong> · '+esc(unidades[x.unidade]||x.unidade)+
   (x.ativo?'':' · Inativo')+'</span>'+
   (isFullAdminUser()?'<div><button type="button" class="btn secondary" data-insumo-edit="'+esc(x.id)+'">Editar</button> '+
    '<button type="button" class="btn secondary" data-insumo-delete="'+esc(x.id)+'">Excluir</button></div>':'')+
   '</div>').join(''):'<p class="hint">Ainda não existem materiais desta categoria.</p>';
 }
 function editar(id){
  if(!isFullAdminUser())return;
  const c=catalogo.find(x=>x.id===id);
  if(!c)return;
  editId=c.id;
  byId('cadastroInsumosCategory').value=c.categoria;
  byId('cadastroInsumosDescription').value=c.descricao;
  byId('cadastroInsumosUnit').value=c.unidade;
  byId('cadastroInsumosSave').textContent='Salvar alterações';
  byId('cadastroInsumosCancel').classList.remove('hidden');
  aviso('cadastroInsumosStatus','Edição permitida somente para materiais sem histórico de movimentações.');
  byId('cadastroInsumosDescription').focus();
 }
 function encerrarEdicao(){
  editId=null;byId('cadastroInsumosForm').reset();
  byId('cadastroInsumosCategory').value=categoriaAtual;
  byId('cadastroInsumosSave').textContent='Cadastrar material';
  byId('cadastroInsumosCancel').classList.add('hidden');
  mostrarCatalogo();
 }
 async function enviarCadastro(event){
  event.preventDefault();
  if(!isFullAdminUser()||!currentCompany)return;
  const descricao=byId('cadastroInsumosDescription').value.trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const categoria=byId('cadastroInsumosCategory').value,unidade=byId('cadastroInsumosUnit').value;
  if(descricao.length<2||descricao.length>500){aviso('cadastroInsumosStatus','Descrição deve ter de 2 a 500 caracteres.');return;}
  const btn=byId('cadastroInsumosSave');btn.disabled=true;
  try{
   await rpc('ew_insumo_gerenciar_catalogo',{
    p_empresa_id:currentCompany.id,p_acao:editId?'editar':'criar',p_id:editId,
    p_categoria:categoria,p_descricao:descricao,p_unidade:unidade});
   encerrarEdicao();await carregarCatalogo();
   aviso('cadastroInsumosStatus','Material salvo no catálogo. Nenhum saldo físico foi alterado.');
  }catch(e){aviso('cadastroInsumosStatus','Não foi possível salvar: '+e.message);}
  finally{btn.disabled=false;}
 }
 async function excluirCadastro(id){
  if(!isFullAdminUser())return;
  const c=catalogo.find(x=>x.id===id);if(!c)return;
  if(!window.confirm('Excluir '+c.descricao+' ('+c.unidade+')? O servidor bloqueará se houver qualquer histórico de uso.'))return;
  try{
   await rpc('ew_insumo_gerenciar_catalogo',{
     p_empresa_id:currentCompany.id,p_acao:'excluir',p_id:id,
     p_categoria:null,p_descricao:null,p_unidade:null});
   await carregarCatalogo();aviso('cadastroInsumosStatus','Material sem histórico excluído.');
  }catch(e){aviso('cadastroInsumosStatus','Exclusão bloqueada: '+e.message);}
 }
 async function carregarSaldos(){
  if(carregando||!isFullAdminUser()||!currentCompany)return;
  const obra=byId('stockWork').value;
  if(!obra){saldos=[];historico=[];renderEstoqueInsumos();return;}
  carregando=true;aviso('insumosStockMessage','Consultando saldos físicos de vidros e insumos…');
  try{
   const [itens,transfers]=await Promise.all([
    rpc('ew_insumos_saldos_obra',{p_empresa_id:currentCompany.id,p_obra_id:obra}),
    rpc('ew_insumos_transferencias_obra',{p_empresa_id:currentCompany.id,p_obra_id:obra})
   ]);
   saldos=Array.isArray(itens)?itens:[];
   historico=Array.isArray(transfers)?transfers:[];
   aviso('insumosStockMessage','');
  }catch(e){saldos=[];historico=[];aviso('insumosStockMessage','Não foi possível carregar estoques: '+e.message);}
  finally{carregando=false;renderEstoqueInsumos();}
 }
 function renderEstoqueInsumos(){
  const panel=byId('insumosStockPanel'),obra=byId('stockWork').value;
  const tipo=byId('stockType').value,filtrar=['vidros','outros'].includes(tipo);
  panel.classList.toggle('hidden',['perfil','acessorio'].includes(tipo));
  const list=byId('insumosStockTable');
  if(!obra){
    list.innerHTML='<p class="hint">Selecione uma obra para consultar vidros e outros insumos.</p>';
    byId('insumosTransferHistory').innerHTML='';
    byId('insumosTransferOpen').disabled=true;
    return;
  }
  const busca=byId('stockSearch').value.trim().toLocaleUpperCase('pt-BR');
  const local=byId('stockFactoryFilter').value;
  const rows=saldos.filter(x=>(!filtrar||x.categoria===tipo)&&
    (!local||x.galpao===local)&&
    (x.descricao.toLocaleUpperCase('pt-BR').includes(busca)||
     String(x.unidade).includes(busca)));
  list.innerHTML=rows.length?
   '<div class="stockTableWrap"><table class="stockTable insumosStockTable"><thead><tr>'+
   '<th>Categoria</th><th>Descrição / identificação</th><th>Unidade</th><th>Saldo físico</th><th>Galpão</th></tr></thead><tbody>'+
   rows.map(x=>'<tr><td>'+esc(tipos[x.categoria]||x.categoria)+'</td>'+
    '<td>'+esc(x.descricao)+'</td><td>'+esc(unidades[x.unidade]||x.unidade)+'</td>'+
    '<td><strong>'+fmt(x.saldo)+'</strong></td><td>'+esc(x.galpao)+'</td></tr>').join('')+
   '</tbody></table></div>':
   '<p class="hint">Não há saldos de vidros/insumos para os filtros desta obra.</p>';
  const available=saldos.filter(x=>Number(x.saldo)>0);
  byId('insumosTransferOpen').disabled=!available.length;
  const seen=new Set();
  const display=historico.filter(x=>{
   if(seen.has(x.operacao_id))return false;seen.add(x.operacao_id);return true;
  });
  byId('insumosTransferHistory').innerHTML=display.length?
   '<div class="stockTableWrap"><table class="stockTable insumosHistoryTable"><thead><tr><th>Material</th><th>Quantidade</th><th>Origem</th><th>Destino</th><th>Estado</th></tr></thead><tbody>'+
   display.map(x=>'<tr><td>'+esc(x.material)+'</td><td>'+fmt(x.quantidade)+' '+esc(x.unidade)+'</td>'+
    '<td>'+esc(x.obra_origem)+' / '+esc(x.galpao_origem)+'</td><td>'+
    esc(x.obra_destino)+' / '+esc(x.galpao_destino)+'</td><td>'+
    (x.estornada?'Estornada':
     '<button type="button" class="btn secondary" data-insumo-revert="'+esc(x.operacao_id)+'">Estornar</button>')+
    '</td></tr>').join('')+'</tbody></table></div>':
    '<p class="hint">Sem transferências de vidros/insumos nesta obra.</p>';
 }
 function abrirTransferencia(){
  const obra=byId('stockWork').value;if(!obra)return;
  const opts=saldos.filter(x=>Number(x.saldo)>0);
  if(!opts.length){aviso('insumosStockMessage','Não há saldo físico disponível para transferência.');return;}
  const origem=byId('insumosTransferSource');
  origem.replaceChildren(new Option('Selecione o material e galpão',''));
  opts.forEach((x,i)=>origem.add(new Option(
   (tipos[x.categoria]||x.categoria)+' · '+x.descricao+' · '+fmt(x.saldo)+' '+x.unidade+' · '+x.galpao,
   String(saldos.indexOf(x)))));
  const destino=byId('insumosTransferWork');
  destino.replaceChildren(new Option('Selecione a obra de destino',''));
  const active=new Set(stockLocais.filter(x=>!x.excluido_em).map(x=>x.obra_id));
  works.filter(w=>active.has(w.id)).forEach(w=>destino.add(new Option(w.nome+' · '+(w.codigo||''),w.id)));
  destino.value=obra;
  const locais=byId('insumosTransferLocal');
  locais.replaceChildren(new Option('Selecione o galpão',''));
  stockLocaisFisicos.forEach(v=>locais.add(new Option(v,v)));
  byId('insumosTransferQty').value='';
  byId('insumosTransferReason').value='';
  byId('insumosTransferFormPanel').classList.remove('hidden');
  aviso('insumosTransferStatus','');
  transferOp=null;
  origem.focus();
 }
 function fecharTransferencia(){
  byId('insumosTransferFormPanel').classList.add('hidden');
  byId('insumosTransferForm').reset();transferOp=null;
 }
 function atualizarUnidadeTransferencia(){
  const id=byId('insumosTransferSource').value;
  const row=id===''?null:saldos[Number(id)],field=byId('insumosTransferQty');
  if(!row)return;
  field.max=String(row.saldo);
  field.step=['PC','UN','CX','CJ','PR'].includes(row.unidade)?'1':'0.001';
  field.min=field.step;
  field.title='Saldo na origem: '+fmt(row.saldo)+' '+row.unidade;
  transferOp=null;
 }
 async function enviarTransferencia(event){
  event.preventDefault();
  if(!isFullAdminUser()||!currentCompany)return;
  const origemId=byId('insumosTransferSource').value;
  const item=origemId===''?null:saldos[Number(origemId)];
  const origemObra=byId('stockWork').value,destinoObra=byId('insumosTransferWork').value;
  const destinoLocal=byId('insumosTransferLocal').value,qty=Number(byId('insumosTransferQty').value);
  if(!item){aviso('insumosTransferStatus','Selecione o material de origem.');return;}
  if(!Number.isFinite(qty)||qty<=0||qty>Number(item.saldo)||
   Math.abs(qty*1000-Math.round(qty*1000))>0.00001||
   (['PC','UN','CX','CJ','PR'].includes(item.unidade)&&!Number.isInteger(qty))){
   aviso('insumosTransferStatus','Quantidade inválida ou superior ao saldo.');return;
  }
  if(!destinoObra||!destinoLocal||(destinoObra===origemObra&&destinoLocal===item.galpao)){
   aviso('insumosTransferStatus','Selecione obra ou galpão de destino diferente da origem.');return;
  }
  if(!window.confirm('Transferir '+fmt(qty)+' '+item.unidade+' de '+item.descricao+
   ' para o galpão '+destinoLocal+'? Esta movimentação não gera nota nem despesa.'))return;
  const btn=byId('insumosTransferForm').querySelector('button[type="submit"]');
  btn.disabled=true;transferOp ||= crypto.randomUUID();
  try{
   const r=await rpc('ew_insumos_transferir',{
    p_empresa_id:currentCompany.id,p_origem_obra_id:origemObra,
    p_destino_obra_id:destinoObra,p_insumo_id:item.insumo_id,
    p_origem_local:item.galpao,p_destino_local:destinoLocal,
    p_quantidade:qty,p_observacao:byId('insumosTransferReason').value.trim(),
    p_operacao_id:transferOp});
   fecharTransferencia();
   await carregarSaldos();
   aviso('insumosStockMessage',r?.ja_registrado?
    'Transferência já registrada anteriormente, sem repetição.':
    'Transferência física concluída. Histórico preservado, sem novo custo financeiro.');
  }catch(e){
   aviso('insumosTransferStatus','Não foi possível transferir: '+e.message+
    ' Confira o histórico antes de repetir; a operação mantém o mesmo identificador.');
  }finally{btn.disabled=false;}
 }
 async function estornarTransferencia(op){
  if(!isFullAdminUser()||!currentCompany)return;
  const reason=window.prompt('Informe o motivo para estornar a transferência (mínimo 5 caracteres):','');
  if(reason===null||reason.trim().length<5)return;
  if(!window.confirm('Estornar esta transferência? A operação será bloqueada se o destino já não tiver saldo suficiente.'))return;
  try{
   await rpc('ew_insumos_estornar_transferencia',{
    p_empresa_id:currentCompany.id,p_transferencia_operacao_id:op,p_motivo:reason.trim()});
   await carregarSaldos();aviso('insumosStockMessage','Transferência estornada com trilha de auditoria.');
  }catch(e){aviso('insumosStockMessage','Estorno bloqueado: '+e.message);}
 }
 // Integrar à abertura do Estoque existente sem substituir os controles de perfis.
 const abrirEstoqueOriginal=abrirEstoque;
 abrirEstoque=async function(){
  await abrirEstoqueOriginal();
  await carregarSaldos();
 };
 byId('stockWork').addEventListener('change',carregarSaldos);
 byId('stockFactoryFilter').addEventListener('change',renderEstoqueInsumos);
 byId('stockType').addEventListener('change',renderEstoqueInsumos);
 byId('stockSearch').addEventListener('input',renderEstoqueInsumos);
 byId('insumosStockRefresh').addEventListener('click',carregarSaldos);
 byId('insumosTransferOpen').addEventListener('click',abrirTransferencia);
 byId('insumosTransferCancel').addEventListener('click',fecharTransferencia);
 byId('insumosTransferSource').addEventListener('change',atualizarUnidadeTransferencia);
 for(const id of ['insumosTransferWork','insumosTransferLocal','insumosTransferQty','insumosTransferReason'])
  byId(id).addEventListener('change',()=>{transferOp=null;});
 byId('insumosTransferForm').addEventListener('submit',enviarTransferencia);
 byId('insumosTransferHistory').addEventListener('click',e=>{
  const button=e.target.closest('[data-insumo-revert]');if(button)estornarTransferencia(button.dataset.insumoRevert);
 });
 byId('cadastroInsumosForm').addEventListener('submit',enviarCadastro);
 byId('cadastroInsumosCancel').addEventListener('click',encerrarEdicao);
 byId('cadastroInsumosCategory').addEventListener('change',()=>{if(!editId)mostrarCatalogo();});
 byId('cadastroInsumosList').addEventListener('click',e=>{
  const edit=e.target.closest('[data-insumo-edit]'),del=e.target.closest('[data-insumo-delete]');
  if(edit)editar(edit.dataset.insumoEdit);
  if(del)excluirCadastro(del.dataset.insumoDelete);
 });
 function abrirCategoria(categoria){
  if(!canAdministrate()||!currentCompany||!Object.hasOwn(tipos,categoria))return;
  categoriaAtual=categoria;
  encerrarEdicao();
  byId('cadastroInsumosCategory').value=categoria;
  const nome=tipos[categoria];
  byId('cadastroInsumosTitle').textContent='Cadastro de '+nome.toLowerCase();
  byId('cadastroInsumosSubtitle').textContent=categoria==='vidros'
   ?'Catálogo e unidades dos vidros utilizados nas obras.'
   :'Catálogo e unidades de outros insumos utilizados nas obras.';
  aviso('cadastroInsumosStatus','');
  setView('insumosPage');
  carregarCatalogo();
 }
 byId('navVidros').addEventListener('click',()=>abrirCategoria('vidros'));
 byId('navOutrosInsumos').addEventListener('click',()=>abrirCategoria('outros'));
 byId('finCostCategory').addEventListener('change',sugestoes);
 const carregarRecebimentoOriginal=carregarRecebimento;
 carregarRecebimento=async function(){
  await carregarRecebimentoOriginal();
  await carregarCatalogo();
 };
})();
