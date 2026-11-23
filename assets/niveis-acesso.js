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
function selecionar(nivel){
 selecionado=nivel;
 const registro=niveis.find(x=>x.nivel===nivel);
 if(!registro)return;
 el('userLevelsTabs').innerHTML=niveis.map(l=>'<button type="button" class="accessLevelTab'+
  (l.nivel===selecionado?' active':'')+'" data-level="'+l.nivel+'">'+esc(l.nome)+'</button>').join('');
 el('userLevelsTabs').querySelectorAll('[data-level]').forEach(b=>b.addEventListener('click',()=>selecionar(Number(b.dataset.level))));
 const groups=[...new Set(catalogo.map(x=>x.grupo))];
 el('userLevelsGroups').innerHTML=groups.map(group=>{
  const members=catalogo.filter(x=>x.grupo===group).sort((a,b)=>a.ordem-b.ordem);
  return '<fieldset class="accessLevelGroup"><legend>'+esc(group)+'</legend><div class="accessFlags">'+
   members.map(x=>'<label class="accessFlag"><input type="checkbox" data-flag="'+esc(x.chave)+'"'+
    (registro.flags?.[x.chave]?' checked':'')+(nivel===1?' disabled':'')+'>'+
    '<span>'+esc(x.descricao)+'</span></label>').join('')+
   '</div></fieldset>';
 }).join('');
 el('userLevelsInfo').textContent=nivel===1?
  'Nível 01 protegido: todas as flags habilitadas permanentemente para evitar perda do acesso de administração.':
  'Alterar flags afeta todos os usuários desse nível. A permissão é conferida no banco a cada operação.';
 el('userLevelsSave').disabled=nivel===1;
 el('userLevelsStatus').textContent='';
}
async function nivelAcessoPreparar(){
 configurarSeletores();
 if(!currentCompany||currentAccessLevel!==1||!temPermissao('niveis.gerenciar')){
  el('userLevelsPanel').classList.add('hidden');return;
 }
 el('userLevelsPanel').classList.remove('hidden');
 el('userLevelsStatus').textContent='Carregando níveis e permissões…';
 await ensureSession();
 const data=await request('/rest/v1/rpc/ew_listar_niveis',{method:'POST',
  token:session.access_token,body:{p_empresa_id:currentCompany.id}});
 if(!Array.isArray(data?.niveis)||!Array.isArray(data?.catalogo))throw new Error('Matriz de níveis inválida.');
 niveis=data.niveis;catalogo=data.catalogo;
 selecionar(niveis.some(x=>x.nivel===selecionado)?selecionado:2);
}
el('userLevelsReload').addEventListener('click',()=>{
 nivelAcessoPreparar().catch(e=>el('userLevelsStatus').textContent='Erro: '+e.message);
});
el('userLevelsSave').addEventListener('click',async()=>{
 const registro=niveis.find(x=>x.nivel===selecionado);
 if(!registro||selecionado===1||!isFullAdminUser())return;
 const btn=el('userLevelsSave');
 const flags=[...el('userLevelsGroups').querySelectorAll('[data-flag]:checked')].map(x=>x.dataset.flag);
 if(!window.confirm('Salvar as permissões do nível '+String(selecionado).padStart(2,'0')+
  '? Todos os usuários desse nível serão afetados imediatamente.'))return;
 btn.disabled=true;el('userLevelsStatus').textContent='Salvando flags com auditoria…';
 try{
  await ensureSession();
  const result=await request('/rest/v1/rpc/ew_salvar_nivel',{
   method:'POST',token:session.access_token,
   body:{p_empresa_id:currentCompany.id,p_nivel:selecionado,p_flags:flags}});
  registro.flags=result.flags;
  el('userLevelsStatus').textContent='Nível '+String(selecionado).padStart(2,'0')+
   ' atualizado. '+flags.length+' flags habilitadas e histórico de alteração registrado.';
 }catch(e){el('userLevelsStatus').textContent='Não foi possível salvar: '+e.message;}
 finally{btn.disabled=false;}
});
window.nivelAcessoPreparar=nivelAcessoPreparar;
window.nivelAcessoConfigurarSeletores=configurarSeletores;
})();