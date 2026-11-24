/* EWGEST v46.20 — níveis e flags. O banco é a autoridade. */
(()=>{
'use strict';
const el=id=>document.getElementById(id);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const toRole={1:'administrador',2:'gerenciador',3:'tecnico',4:'almoxarife',
 5:'consulta',6:'consulta',7:'consulta',8:'consulta'};
let catalogo=[],niveis=[],selecionado=2;
function configurarSeletores(){
 for(const id of ['createUserLevel','userEditLevel']){
  const list=el(id);if(!list)continue;
  for(const opt of list.options){
   opt.disabled=!isFullAdminUser()&&Number(opt.value)<=2;
   opt.hidden=!isFullAdminUser()&&Number(opt.value)<=2;
  }
  if(id==='createUserLevel'&&!isFullAdminUser()&&Number(list.value)<=2)list.value='3';
 }
 el('createUserRole').value=toRole[Number(el('createUserLevel').value)]||'consulta';
}
function alteracaoNivel(idSelect,idInterno){
 const n=Number(el(idSelect).value);
 el(idInterno).value=toRole[n]||'consulta';
}
el('createUserLevel').addEventListener('change',()=>{
 alteracaoNivel('createUserLevel','createUserRole');
});
el('userEditLevel').addEventListener('change',()=>{
 alteracaoNivel('userEditLevel','userEditRole');
});
let saving=false,loading=false,loadEpoch=0,loadedCompany=null;
function dirty(){
 const row=niveis.find(x=>Number(x.nivel)===selecionado);
 return !!row&&[...el('userLevelsGroups').querySelectorAll('[data-flag]')].some(x=>x.checked!==!!row.flags?.[x.dataset.flag]);
}
function canEdit(){return !loading&&!saving&&selecionado!==1&&currentAccessLevel===1&&temPermissao('niveis.gerenciar')&&loadedCompany===currentCompany?.id;}
function updateControls(){
 const editable=canEdit();
 for(const id of ['userLevelsAll','userLevelsNone','userLevelsSave'])el(id).disabled=!editable;
 el('userLevelsReload').disabled=loading||saving;
 el('userLevelsTabs').querySelectorAll('button').forEach(x=>x.disabled=loading||saving);
 el('userLevelsGroups').querySelectorAll('[data-flag]').forEach(x=>x.disabled=!editable);
}
function filtrar(){
 const norm=x=>String(x).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const term=norm(el('userLevelsSearch').value.trim());
 el('userLevelsGroups').querySelectorAll('fieldset').forEach(group=>{
  const label=norm(group.querySelector('legend').textContent);
  let visible=false;
  group.querySelectorAll('.accessFlag').forEach(flag=>{
   flag.hidden=!!term&&!norm(flag.textContent+' '+flag.querySelector('input').dataset.flag+' '+label).includes(term);
   if(!flag.hidden)visible=true;
  });
  group.hidden=!visible;
 });
}
function selecionar(nivel){
 selecionado=nivel;
 const registro=niveis.find(x=>Number(x.nivel)===nivel);
 if(!registro)return;
 el('userLevelsTabs').innerHTML=niveis.map(l=>'<button type="button" class="accessLevelTab'+
  (Number(l.nivel)===selecionado?' active':'')+'" data-level="'+Number(l.nivel)+'" aria-pressed="'+(Number(l.nivel)===selecionado)+'"><strong>Nível '+String(l.nivel).padStart(2,'0')+'</strong><span>'+esc(l.nome)+'</span></button>').join('');
 el('userLevelsTabs').querySelectorAll('[data-level]').forEach(b=>b.addEventListener('click',()=>{
  const next=Number(b.dataset.level);if(next===selecionado||loading||saving)return;
  if(dirty()&&!window.confirm('Descartar alterações não salvas deste nível?'))return;
  selecionar(next);
 }));
 const groups=[...new Set(catalogo.map(x=>x.grupo))];
 el('userLevelsGroups').innerHTML=groups.map(group=>{
  const members=catalogo.filter(x=>x.grupo===group).sort((a,b)=>a.ordem-b.ordem);
  return '<fieldset class="accessLevelGroup"><legend>'+esc(group)+'</legend><div class="accessFlags">'+
   members.map(x=>'<label class="accessFlag"><input type="checkbox" data-flag="'+esc(x.chave)+'"'+
    (registro.flags?.[x.chave]||nivel===1?' checked':'')+(nivel===1?' disabled':'')+'>'+
    '<span>'+esc(x.descricao)+'</span></label>').join('')+
   '</div></fieldset>';
 }).join('');
 el('userLevelsInfo').textContent=nivel===1?
  'Nível 01 protegido: todas as flags habilitadas permanentemente para evitar perda do acesso de administração.':
  'Nível '+String(nivel).padStart(2,'0')+' · '+registro.nome+' — as alterações afetam todos os usuários deste nível.';
 el('userLevelsStatus').textContent='';
 el('userLevelsSearch').value='';filtrar();updateControls();
}
async function nivelAcessoPreparar(){
 configurarSeletores();
 const epoch=++loadEpoch;
 if(!currentCompany||currentAccessLevel!==1||!temPermissao('niveis.gerenciar')){
  el('userLevelsPanel').classList.add('hidden');return;
 }
 const company=currentCompany.id;
 loadedCompany=null;loading=true;
 el('userLevelsPanel').classList.remove('hidden');
 el('userLevelsTabs').replaceChildren();el('userLevelsGroups').replaceChildren();el('userLevelsInfo').textContent='';
 el('userLevelsStatus').textContent='Carregando níveis e permissões…';updateControls();
 try{
  await ensureSession();
  const data=await request('/rest/v1/rpc/ew_listar_niveis',{method:'POST',
   token:session.access_token,body:{p_empresa_id:company}});
  if(epoch!==loadEpoch||currentCompany?.id!==company||currentAccessLevel!==1)return;
  if(!Array.isArray(data?.niveis)||!Array.isArray(data?.catalogo)||data.niveis.length!==8||!data.catalogo.length)throw new Error('Matriz de níveis inválida ou incompleta.');
  niveis=data.niveis;catalogo=data.catalogo;loadedCompany=company;loading=false;
  selecionar(niveis.some(x=>Number(x.nivel)===selecionado)?selecionado:2);
 }finally{if(epoch===loadEpoch){loading=false;updateControls();}}
}
el('userLevelsSearch').addEventListener('input',filtrar);
for(const [id,value] of [['userLevelsAll',true],['userLevelsNone',false]])el(id).addEventListener('click',()=>{
 if(!canEdit())return;
 if(!window.confirm((value?'Marcar':'Desmarcar')+' todas as permissões deste nível, inclusive as ocultas pela busca?'))return;
 el('userLevelsGroups').querySelectorAll('[data-flag]').forEach(x=>x.checked=value);
});
el('userLevelsReload').addEventListener('click',()=>{
 if(dirty()&&!window.confirm('Descartar alterações não salvas e atualizar?'))return;
 nivelAcessoPreparar().catch(e=>el('userLevelsStatus').textContent='Erro: '+e.message);
});
el('userLevelsSave').addEventListener('click',async()=>{
 const nivel=selecionado,company=loadedCompany;
 const registro=niveis.find(x=>Number(x.nivel)===nivel);
 if(!registro||!canEdit()||!isFullAdminUser())return;
 const flags=[...el('userLevelsGroups').querySelectorAll('[data-flag]:checked')].map(x=>x.dataset.flag);
 if(!window.confirm('Salvar as permissões do nível '+String(nivel).padStart(2,'0')+
  '? Todos os usuários desse nível serão afetados imediatamente.'))return;
 saving=true;updateControls();el('userLevelsStatus').textContent='Salvando flags com auditoria…';
 try{
  await ensureSession();
  const result=await request('/rest/v1/rpc/ew_salvar_nivel',{
   method:'POST',token:session.access_token,
   body:{p_empresa_id:company,p_nivel:nivel,p_flags:flags}});
  if(loadedCompany!==company||selecionado!==nivel||currentCompany?.id!==company)return;
  registro.flags=result.flags;
  el('userLevelsStatus').textContent='Nível '+String(nivel).padStart(2,'0')+
   ' atualizado. '+flags.length+' flags habilitadas e histórico de alteração registrado.';
 }catch(e){el('userLevelsStatus').textContent='Não foi possível salvar: '+e.message;}
 finally{saving=false;updateControls();}
});
window.nivelAcessoPreparar=nivelAcessoPreparar;
window.nivelAcessoConfigurarSeletores=configurarSeletores;
})();