/* EWGEST v45.6 — cadastro de unidades de medida por empresa.
 * Codigos sao historicos, nao ha conversao automatica de unidades. */
(function(){
 'use strict';
 const byId=id=>document.getElementById(id);
 const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"\u0027":'&#39;'}[c]));
 const defaults=[
  {codigo:'PC',nome:'Peça',ativo:true,padrao:true},
  {codigo:'UN',nome:'Unidade',ativo:true,padrao:true},
  {codigo:'M2',nome:'Metro quadrado',ativo:true,padrao:true},
  {codigo:'MT',nome:'Metro',ativo:true,padrao:true},
  {codigo:'KG',nome:'Quilograma',ativo:true,padrao:true},
  {codigo:'CX',nome:'Caixa',ativo:true,padrao:true},
  {codigo:'CJ',nome:'Conjunto',ativo:true,padrao:true},
  {codigo:'PR',nome:'Par',ativo:true,padrao:true}
 ];
 let unidades=defaults.slice(),empresaId=null,carregada=false,emCurso=null,editCodigo=null,bloqueado=false;
 const isAdmin=()=>typeof isFullAdminUser==='function'&&isFullAdminUser();
 function informar(s){const label=byId('unidadeMessage');if(label)label.textContent=s;}
 function lista(){return unidades.filter(u=>u.ativo).map(x=>({...x}));}
 function ativa(codigo){return unidades.some(u=>u.ativo&&u.codigo===codigo);}
 function nome(codigo){return unidades.find(x=>x.codigo===codigo)?.nome||codigo;}
 function selecionar(){
  const select=byId('cadastroInsumosUnit');
  if(select){
   const old=select.value;
   select.replaceChildren();
   unidades.filter(u=>u.ativo).forEach(u=>{
    const opt=document.createElement('option');
    opt.value=u.codigo;opt.textContent=u.codigo+' — '+u.nome;select.appendChild(opt);
   });
   if(ativa(old))select.value=old;
  }
  if(typeof window.ewRecebimentoAtualizarUnidades==='function')
   window.ewRecebimentoAtualizarUnidades();
 }
 function render(){
  const host=byId('unidadeLista');
  if(!host)return;
  const visiveis=unidades.slice().sort((a,b)=>a.codigo.localeCompare(b.codigo,'pt-BR'));
  host.innerHTML=visiveis.length?visiveis.map(u=>
   '<div class="unidadeRow"><div><strong>'+esc(u.codigo)+'</strong> — '+esc(u.nome)+
   (u.padrao?' <small>Unidade padrão</small>':'')+
   '</div><div class="unidadeRowActions">'+
   (isAdmin()?'<button class="btn secondary" type="button" data-u-edit="'+esc(u.codigo)+'">Editar descrição</button>'+
   (!u.padrao?' <button class="btn secondary" type="button" data-u-remove="'+esc(u.codigo)+'">Excluir</button>':''):'')+
   '</div></div>').join(''):'<p class="hint">Nenhuma unidade cadastrada.</p>';
  byId('unidadeForm').classList.toggle('hidden',!isAdmin());
 }
 async function rpc(fn,payload){
  await ensureSession();
  return request('/rest/v1/rpc/'+fn,{method:'POST',token:session.access_token,body:payload,timeoutMs:30000});
 }
 async function carregar(force=false){
  if(!currentCompany||!canAdministrate()&&!isAlmoxarife())return;
  if(empresaId===currentCompany.id&&carregada&&!force)return;
  if(emCurso)return emCurso;
  emCurso=(async()=>{
   const id=currentCompany.id;
   try{
    const data=await rpc('ew_unidades_medida_listar',{p_empresa_id:id});
    if(!Array.isArray(data))throw Error('Resposta inesperada do catálogo de unidades.');
    if(currentCompany?.id!==id)return;
    unidades=data;empresaId=id;carregada=true;
    selecionar();render();
    informar('');
   }catch(err){
    if(byId('unidadesPage')&&!byId('unidadesPage').classList.contains('hidden'))
     informar('Falha ao carregar unidades: '+err.message);
   }finally{emCurso=null;}
  })();
  return emCurso;
 }
 async function abrir(){
  if(!canAdministrate())return;
  byId('unidadeCodigo').value='';
  byId('unidadeNome').value='';
  cancelarEdicao();
  setView('unidadesPage');
  informar('Consultando unidades de medida…');
  await carregar(true);
 }
 function cancelarEdicao(){
  editCodigo=null;
  byId('unidadeEdicao').classList.add('hidden');
  byId('unidadeNovoNome').value='';
 }
 function editar(codigo){
  const unidade=unidades.find(x=>x.codigo===codigo);
  if(!unidade||!isAdmin())return;
  editCodigo=codigo;
  byId('unidadeEdicaoTitulo').textContent='Editar descrição de '+codigo;
  byId('unidadeNovoNome').value=unidade.nome;
  byId('unidadeEdicao').classList.remove('hidden');
  byId('unidadeNovoNome').focus({preventScroll:true});
 }
 async function gravar(acao,codigo,nomeNovo){
  if(!isAdmin()||!currentCompany||bloqueado)return false;
  bloqueado=true;
  try{
   await rpc('ew_unidades_medida_gerenciar',{
    p_empresa_id:currentCompany.id,p_acao:acao,p_codigo:codigo,p_nome:nomeNovo||null
   });
   carregada=false;
   await carregar(true);
   informar(acao==='criar'?'Unidade '+codigo+' cadastrada. Disponível para vidros, outros insumos e recebimentos.':
    acao==='renomear'?'Descrição da unidade atualizada.':'Unidade não utilizada excluída.');
   return true;
  }catch(err){informar('Não foi possível salvar: '+err.message);return false;}
  finally{bloqueado=false;}
 }
 byId('navUnidades').addEventListener('click',abrir);
 byId('unidadeForm').addEventListener('submit',async e=>{
  e.preventDefault();
  const codigo=byId('unidadeCodigo').value.trim().toUpperCase();
  const descricao=byId('unidadeNome').value.trim();
  if(!/^[A-Z0-9]{1,8}$/.test(codigo)){
   informar('Código com 1 a 8 letras ou números, sem espaços. Ex.: L, ML, M3.');return;
  }
  if(descricao.length<2||descricao.length>80){informar('Informe descrição entre 2 e 80 caracteres.');return;}
  if(await gravar('criar',codigo,descricao))byId('unidadeForm').reset();
 });
 byId('unidadeEdicaoForm').addEventListener('submit',async e=>{
  e.preventDefault();
  const codigo=editCodigo,nomeNovo=byId('unidadeNovoNome').value.trim();
  if(!codigo||nomeNovo.length<2)return;
  if(await gravar('renomear',codigo,nomeNovo))cancelarEdicao();
 });
 byId('unidadeEditCancel').addEventListener('click',cancelarEdicao);
 byId('unidadeLista').addEventListener('click',async e=>{
  const editarBtn=e.target.closest('[data-u-edit]'),
   removerBtn=e.target.closest('[data-u-remove]');
  if(editarBtn){editar(editarBtn.dataset.uEdit);return;}
  if(!removerBtn||!isAdmin())return;
  const codigo=removerBtn.dataset.uRemove;
  if(!window.confirm('Excluir unidade '+codigo+'? O sistema bloqueará a exclusão se houver cadastro ou nota vinculada.'))return;
  await gravar('excluir',codigo,null);
 });
 for(const id of ['navVidros','navOutrosInsumos','navRecebimento','navFinanceiro']){
  const el=byId(id);if(el)el.addEventListener('click',()=>{carregar().catch(()=>{});});
 }
 window.ewUnidadesMedida={lista,ativa,nome,carregar};
})();