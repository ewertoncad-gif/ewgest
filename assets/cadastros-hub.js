/* EWGEST | Central de cadastros — compartilha módulos e tabelas existentes. */
(()=>{
 'use strict';
 const $=id=>node(id);
 let fornecedores=[],galpoes=[];
 function informar(msg){
  for(const id of ['cadastrosMessage','cadastroFornecedorMessage','cadastroGalpaoMessage']){
   const target=$(id);if(target)target.textContent=msg;
  }
 }
 function listaHTML(itens,tipo){
  return itens.length?itens.map(x=>
    '<div class="cadastrosListRow" style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">'+
     '<span>'+escapeHTML(x.nome)+(x.ativo?'':' <small>Inativo</small>')+'</span>'+
     (isFullAdminUser()?'<button type="button" class="btn secondary" data-cadastro-editar="'+
       escapeHTML(x.id)+'" data-cadastro-tipo="'+tipo+'">Editar / excluir</button>':'')+
    '</div>').join(''):
   '<p class="hint">Nenhum cadastro ainda.</p>';
 }
 async function recarregar(){
  if(!canAdministrate()||!currentCompany)return;
  try{
   await ensureSession();
   const emp='eq.'+currentCompany.id;
   const [fs,gs]=await Promise.all([
    apiGet('ew_fornecedores',{select:'id,nome,ativo',empresa_id:emp,order:'nome.asc',limit:'1000'}),
    apiGet('ew_locais_fisicos',{select:'id,nome,ativo',empresa_id:emp,order:'nome.asc',limit:'500'})
   ]);
   fornecedores=fs||[];galpoes=gs||[];
   $('cadastroFornecedorList').innerHTML=listaHTML(fornecedores,'fornecedor');
   $('cadastroGalpaoList').innerHTML=listaHTML(galpoes,'galpao');
   informar('');
   if(!$('fornecedoresPage').classList.contains('hidden'))await abrirGruposFornecedor($('cadastroGrupoFornecedor')?.value||'');
  }catch(e){informar('Não foi possível consultar cadastros: '+e.message);}
 }
 function abrir(){
  if(!canAdministrate()||!currentCompany)return;
  fecharEdicao();
  informar('');
  setView('cadastros');
  $('cadastroGruposCompra')?.classList.add('hidden');
  $('cadastroJumpGruposCompra')?.classList.toggle('hidden',!temPermissao('compras.gerenciar_grupos'));
 }
 async function abrirCategoria(tipo){
  if(!canAdministrate()||!currentCompany)return;
  fecharEdicao();
  const alvo=tipo==='fornecedor'?'fornecedoresPage':'galpoesPage';
  setView(alvo);
  informar('Consultando '+(tipo==='fornecedor'?'fornecedores':'galpões')+'…');
  await recarregar();
 }
 async function salvar(event,tipo){
  event.preventDefault();
  if(!currentCompany||
   (tipo==='fornecedor'?!isFullAdminUser():!canAdministrate())){
   informar('Seu perfil não tem permissão para realizar este cadastro.');return;
  }
  const id=tipo==='fornecedor'?'cadastroFornecedorNome':'cadastroGalpaoNome';
  const campo=$(id),botao=event.currentTarget.querySelector('[type="submit"]');
  const nome=campo.value.trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const max=tipo==='fornecedor'?180:80;
  if(nome.length<3||nome.length>max){informar('Informe nome com 3 a '+max+' caracteres.');return;}
  const atual=tipo==='fornecedor'?fornecedores:galpoes;
  if(atual.some(x=>x.nome===nome)){informar('Este cadastro já existe.');return;}
  botao.disabled=true;
  try{
   await ensureSession();
   if(tipo==='fornecedor'){
    await request('/rest/v1/ew_fornecedores',{method:'POST',token:session.access_token,
     body:{empresa_id:currentCompany.id,nome,criado_por:currentUser.id}});
   }else await cadastrarGalpaoEmpresa(nome);
   campo.value='';
   await recarregar();
   informar((tipo==='fornecedor'?'Fornecedor ':'Galpão ')+nome+
    ' cadastrado. Já pode ser selecionado nos lançamentos.');
  }catch(e){informar('Não foi possível cadastrar: '+e.message);}
  finally{botao.disabled=false;}
 }

 let editando=null;
 function fecharEdicao(){
  editando=null;
  $('cadastroEditPanel').classList.add('hidden');
  $('cadastroEditNome').value='';
  $('cadastroEditMessage').textContent='';
 }
 function abrirEdicao(id,tipo){
  if(!isFullAdminUser())return;
  const atual=tipo==='fornecedor'?fornecedores:galpoes;
  const item=atual.find(x=>x.id===id);if(!item)return;
  editando={tipo,id,nome:item.nome};
  $('cadastroEditTitle').textContent=(tipo==='fornecedor'?'Fornecedor':'Galpão')+' — editar ou excluir';
  $('cadastroEditNome').value=item.nome;
  $('cadastroEditNome').maxLength=tipo==='fornecedor'?180:80;
  $('cadastroEditMessage').textContent='';
  // O mesmo editor atende fornecedores e galpões sem duplicar formulários.
  $(tipo==='fornecedor'?'fornecedoresPage':'galpoesPage').appendChild($('cadastroEditPanel'));
  $('cadastroEditPanel').classList.remove('hidden');
  $('cadastroEditPanel').scrollIntoView({behavior:'smooth',block:'nearest'});
 }
 async function salvarEdicao(acao){
  if(!editando||!isFullAdminUser()||!currentCompany)return;
  const {tipo,id,nome}=editando;
  const novo=$('cadastroEditNome').value.trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const status=$('cadastroEditMessage');
  if(acao==='editar'&&(novo.length<3||novo.length>(tipo==='fornecedor'?180:80))){
   status.textContent='Informe nome válido.';return;
  }
  if(acao==='excluir'&&!window.confirm('Excluir o cadastro '+nome+'? O sistema bloqueará caso esteja sendo usado por notas ou estoque.'))return;
  const btn=$(acao==='editar'?'cadastroEditSave':'cadastroEditDelete');
  btn.disabled=true;
  status.textContent='Conferindo vínculos e salvando…';
  try{
   await ensureSession();
   await request('/rest/v1/rpc/ew_gerenciar_cadastro_auxiliar',{
    method:'POST',token:session.access_token,
    body:{p_empresa_id:currentCompany.id,p_tipo:tipo,p_id:id,
      p_acao:acao,p_nome:acao==='editar'?novo:null}
   });
   fecharEdicao();await recarregar();
   informar(acao==='editar'?'Cadastro atualizado com histórico preservado.':
      'Cadastro excluído porque não possuía referências operacionais.');
  }catch(e){
   status.textContent='Não foi possível '+(acao==='editar'?'editar':'excluir')+': '+e.message;
  }finally{btn.disabled=false;}
 }
 function cliqueLista(e){
  const btn=e.target.closest('[data-cadastro-editar]');
  if(btn)abrirEdicao(btn.dataset.cadastroEditar,btn.dataset.cadastroTipo);
 }
 $('cadastroFornecedorList').addEventListener('click',cliqueLista);
 $('cadastroGalpaoList').addEventListener('click',cliqueLista);
 $('cadastroEditSave').addEventListener('click',()=>salvarEdicao('editar'));
 $('cadastroEditDelete').addEventListener('click',()=>salvarEdicao('excluir'));
 $('cadastroEditCancel').addEventListener('click',fecharEdicao);
 // A gestão de saldos/estornos fica exclusivamente na tela Estoque.
 $('navCadastros').addEventListener('click',abrir);
 $('navAccessories').addEventListener('click',async()=>{
  if(!canAdministrate())return;
  matSelecionarTipo('acessorio');
  await abrirMateriais();
 });

 const gruposRpc=(fn,body)=>request('/rest/v1/rpc/'+fn,{method:'POST',token:session.access_token,body});
 let fornecedorGrupoEpoch=0;
 async function abrirGruposFornecedor(prefer=''){
  const root=$('cadastroFornecedorGrupos');
  if(!root)return;
  const seq=++fornecedorGrupoEpoch,empresa=currentCompany?.id;
  if(!empresa||!canAdministrate()||!temPermissao('compras.gerenciar_grupos')){root.classList.add('hidden');root.replaceChildren();return;}
  root.classList.remove('hidden');root.textContent='Consultando grupos de compra…';
  try{
   await ensureSession();
   const cat=await gruposRpc('ew_compras_grupos_catalogo',{p_empresa_id:empresa});
   if(seq!==fornecedorGrupoEpoch||currentCompany?.id!==empresa)return;
   const esc=escapeHTML,groups=cat.grupos||[],suppliers=cat.fornecedores||[];
   root.innerHTML='<h2>Grupos atendidos por fornecedor</h2><p class="hint">Marque os grupos de compra que cada fornecedor atende. Somente fornecedores habilitados no grupo aparecem nas novas cotações.</p>'+
    '<label>Fornecedor<select id="cadastroGrupoFornecedor"><option value="">Selecione o fornecedor</option>'+suppliers.map(f=>'<option value="'+esc(f.id)+'">'+esc(f.nome)+(f.ativo?'':' · Inativo')+'</option>').join('')+'</select></label><div id="cadastroGrupoFlags" class="topactions" style="margin:14px 0"></div>'+
    '<button id="cadastroGrupoSalvarFornecedor" type="button" class="btn primary" disabled>Salvar grupos do fornecedor</button><p id="cadastroGrupoFornecedorStatus" class="feedback" role="status"></p>';
   const supplier=$('cadastroGrupoFornecedor'),flags=$('cadastroGrupoFlags'),save=$('cadastroGrupoSalvarFornecedor'),status=$('cadastroGrupoFornecedorStatus');
   supplier.onchange=()=>{const f=suppliers.find(x=>x.id===supplier.value);flags.innerHTML=f?groups.filter(g=>g.ativo).map(g=>'<label style="display:flex;gap:8px;align-items:center;min-width:140px"><input type="checkbox" data-grupo="'+esc(g.id)+'" style="width:16px;height:16px" '+(f.grupos.includes(g.id)?'checked':'')+'> '+esc(g.nome)+'</label>').join(''):'';save.disabled=!f;status.textContent='';};
   supplier.value=prefer;supplier.onchange();
   save.onclick=async()=>{const id=supplier.value;if(!id||save.disabled)return;const ids=[...flags.querySelectorAll('input:checked')].map(x=>x.dataset.grupo);
    save.disabled=true;supplier.disabled=true;flags.querySelectorAll('input').forEach(x=>x.disabled=true);
    try{await ensureSession();if(currentCompany?.id!==empresa||seq!==fornecedorGrupoEpoch)throw Error('Seleção alterada.');
     await gruposRpc('ew_compras_salvar_grupos_fornecedor',{p_empresa_id:empresa,p_fornecedor_id:id,p_grupos:ids});
     if(seq===fornecedorGrupoEpoch&&currentCompany?.id===empresa){await abrirGruposFornecedor(id);const result=$('cadastroGrupoFornecedorStatus');if(result)result.textContent='Grupos do fornecedor salvos.';}
    }catch(err){if(seq===fornecedorGrupoEpoch)status.textContent=err.message;}finally{if(save.isConnected){save.disabled=false;supplier.disabled=false;flags.querySelectorAll('input').forEach(x=>x.disabled=false);}}
   };
  }catch(e){if(seq===fornecedorGrupoEpoch)root.textContent='Grupos indisponíveis: '+e.message;}
 }
 async function abrirGrupos(){
  if(!canAdministrate()||!currentCompany||!temPermissao('compras.gerenciar_grupos'))return;
  const root=$('cadastroGruposCompra'),empresa=currentCompany.id;
  root.classList.remove('hidden');root.textContent='Consultando grupos…';
  try{
   await ensureSession();const [cat,insumos]=await Promise.all([gruposRpc('ew_compras_grupos_catalogo',{p_empresa_id:empresa}),gruposRpc('ew_compras_insumos_grupos_listar',{p_empresa_id:empresa})]);
   if(currentCompany?.id!==empresa)return;
   const esc=escapeHTML,groups=cat.grupos||[];
   root.innerHTML='<h2>Grupos de compra</h2><p class="hint">Cadastre e organize os grupos de compra. Os vínculos com fornecedores ficam em Cadastro de fornecedores.</p>'+
    '<form id="cadastroGrupoForm" class="cadastrosNovoForm"><label>Código<input id="cadastroGrupoCodigo" maxlength="40" required placeholder="FERRAMENTAS"></label><label>Nome<input id="cadastroGrupoNome" maxlength="100" required></label><label><input type="checkbox" id="cadastroGrupoAtivo" checked> Ativo</label><button class="btn primary" type="submit">Salvar grupo</button></form>'+
    '<div class="cadastrosList">'+groups.map(g=>'<div class="cadastrosListRow"><span>'+esc(g.nome)+(g.ativo?'':' · Inativo')+'</span> <button class="btn secondary" type="button" data-editar-grupo="'+esc(g.id)+'">Editar</button></div>').join('')+'</div>'+
    '<h3>Classificação de vidros e outros insumos</h3><p class="hint">Use o catálogo de Vidros e Outros insumos para cadastrar os materiais. A classificação comercial não altera seu estoque nem categoria financeira.</p>'+
    '<label>Material<select id="cadastroGrupoInsumo"><option value="">Escolha</option>'+insumos.map(i=>'<option value="'+esc(i.id)+'">'+esc(i.descricao)+' · '+esc(i.unidade)+'</option>').join('')+'</select></label>'+
    '<label>Grupo de compra<select id="cadastroGrupoInsumoDestino"><option value="">Padrão da categoria</option>'+groups.filter(g=>g.ativo&&!['PERFIS','ACESSORIOS'].includes(g.codigo)).map(g=>'<option value="'+esc(g.id)+'">'+esc(g.nome)+'</option>').join('')+'</select></label>'+
    '<button id="cadastroGrupoSalvarInsumo" type="button" class="btn primary" disabled>Salvar classificação do material</button><p id="cadastroGrupoStatus" class="feedback" role="status"></p>';
   const status=$('cadastroGrupoStatus'),code=$('cadastroGrupoCodigo'),name=$('cadastroGrupoNome'),active=$('cadastroGrupoAtivo');
   root.querySelectorAll('[data-editar-grupo]').forEach(b=>b.onclick=()=>{const g=groups.find(x=>x.id===b.dataset.editarGrupo);code.value=g.codigo;name.value=g.nome;active.checked=g.ativo;code.readOnly=true;name.focus();});
   const reset=document.createElement('button');reset.type='button';reset.className='btn secondary';reset.textContent='Novo grupo';reset.onclick=()=>{code.readOnly=false;code.value='';name.value='';active.checked=true;code.focus();};$('cadastroGrupoForm').append(reset);
   $('cadastroGrupoForm').onsubmit=async e=>{e.preventDefault();const btn=e.currentTarget.querySelector('[type=submit]');btn.disabled=true;try{await ensureSession();if(currentCompany?.id!==empresa)throw Error('Empresa alterada.');await gruposRpc('ew_compras_salvar_grupo',{p_empresa_id:empresa,p_codigo:code.value.trim().toUpperCase(),p_nome:name.value.trim(),p_ativo:active.checked});await abrirGrupos();$('cadastroGrupoStatus').textContent='Grupo salvo.';}catch(err){status.textContent=err.message;}finally{btn.disabled=false;}};
   const insumo=$('cadastroGrupoInsumo'),destino=$('cadastroGrupoInsumoDestino'),salvarInsumo=$('cadastroGrupoSalvarInsumo');
   insumo.onchange=()=>{const i=insumos.find(x=>x.id===insumo.value);destino.value=i?.grupo_id||'';salvarInsumo.disabled=!i;};
   salvarInsumo.onclick=async()=>{const id=insumo.value;if(!id)return;salvarInsumo.disabled=true;try{await ensureSession();if(currentCompany?.id!==empresa)throw Error('Empresa alterada.');await gruposRpc('ew_compras_insumo_classificar_grupo',{p_empresa_id:empresa,p_insumo_id:id,p_grupo_id:destino.value||null});await abrirGrupos();$('cadastroGrupoInsumo').value=id;$('cadastroGrupoInsumo').onchange();$('cadastroGrupoStatus').textContent='Classificação do material salva.';}catch(err){status.textContent=err.message;}finally{if(salvarInsumo.isConnected)salvarInsumo.disabled=false;}};
  }catch(e){root.textContent='Grupos indisponíveis: '+e.message;}
 }
 $('cadastroJumpGruposCompra')?.addEventListener('click',abrirGrupos);
 $('cadastroJumpFornecedores').addEventListener('click',()=>abrirCategoria('fornecedor'));
 $('cadastroJumpGalpoes').addEventListener('click',()=>abrirCategoria('galpao'));
 document.querySelectorAll('.cadastrosBack').forEach(button=>
  button.addEventListener('click',abrir));
 $('cadastroFornecedorForm').addEventListener('submit',e=>salvar(e,'fornecedor'));
 $('cadastroGalpaoForm').addEventListener('submit',e=>salvar(e,'galpao'));
})();
