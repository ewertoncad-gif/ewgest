/* EWGEST | Central de cadastros — compartilha módulos e tabelas existentes. */
(()=>{
 'use strict';
 const $=id=>node(id);
 let fornecedores=[],galpoes=[];
 function informar(msg){$('cadastrosMessage').textContent=msg;}
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
  }catch(e){informar('Não foi possível consultar cadastros: '+e.message);}
 }
 async function abrir(){
  if(!canAdministrate()||!currentCompany)return;
  setView('cadastros');informar('Carregando cadastros…');
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
 $('navCadastros').addEventListener('click',abrir);
 $('navAccessories').addEventListener('click',async()=>{
  if(!canAdministrate())return;
  matSelecionarTipo('acessorio');
  await abrirMateriais();
 });
 $('cadastroJumpFornecedores').addEventListener('click',()=>
  $('cadastroFornecedores').scrollIntoView({behavior:'smooth',block:'start'}));
 $('cadastroJumpGalpoes').addEventListener('click',()=>
  $('cadastroGalpoes').scrollIntoView({behavior:'smooth',block:'start'}));
 $('cadastroFornecedorForm').addEventListener('submit',e=>salvar(e,'fornecedor'));
 $('cadastroGalpaoForm').addEventListener('submit',e=>salvar(e,'galpao'));
})();
