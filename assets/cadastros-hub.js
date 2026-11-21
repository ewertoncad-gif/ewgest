/* EWGEST | Central de cadastros — compartilha módulos e tabelas existentes. */
(()=>{
 'use strict';
 const $=id=>node(id);
 let fornecedores=[],galpoes=[];
 function informar(msg){$('cadastrosMessage').textContent=msg;}
 function listaHTML(itens){
  return itens.length?itens.map(x=>'<div class="cadastrosListRow"><span>'+
   escapeHTML(x.nome)+'</span>'+(x.ativo?'':'<small>Inativo</small>')+'</div>').join(''):
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
   $('cadastroFornecedorList').innerHTML=listaHTML(fornecedores);
   $('cadastroGalpaoList').innerHTML=listaHTML(galpoes);
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
  if(!isFullAdminUser()||!currentCompany){informar('Cadastro reservado ao ADM.');return;}
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
