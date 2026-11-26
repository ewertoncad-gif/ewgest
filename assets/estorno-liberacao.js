(()=>{'use strict';
const el=id=>document.getElementById(id);
let epoch=0,submitting=false;
const msg=s=>el('releaseUndoStatus').textContent=s;
const rpc=(name,body)=>request('/rest/v1/rpc/'+name,{method:'POST',token:session.access_token,body});
function close(){if(submitting)return;epoch++;el('releaseUndoOverlay').classList.add('hidden');}
async function abrir(esquadria){
 if(submitting||!temPermissao('liberacoes.cancelar'))return;
 const item=elements.find(x=>x.id===esquadria),seq=++epoch,company=currentCompany?.id;
 if(!item||!company)return;
 el('releaseUndoOverlay').classList.remove('hidden');
 el('releaseUndoTitle').textContent='Estornar liberação · '+item.codigo;
 el('releaseUndoList').replaceChildren();msg('Conferindo liberações e dependências…');
 try{
  await ensureSession();const rows=await rpc('ew_listar_estornos_liberacao',{p_esquadria_id:esquadria});
  if(seq!==epoch||company!==currentCompany?.id)return;
  if(!Array.isArray(rows))throw Error('Resposta inválida.');
  msg(rows.length?'Selecione a liberação que deseja estornar.':'Nenhuma liberação ativa.');
  for(const r of rows){
   const row=document.createElement('div');row.className='releaseCancelAllItem';
   const info=document.createElement('div'),title=document.createElement('strong'),desc=document.createElement('div'),btn=document.createElement('button');
   title.textContent=r.quantidade+' unidade(s) · '+(r.componente==='completo'?'Completa':r.componente==='marco'?'Marco':'Folhas');
   desc.className='hint';desc.textContent=[String(r.data||'').split('-').reverse().join('/'),r.fabrica||'Fábrica não informada',r.impedimento].filter(Boolean).join(' · ');
   info.append(title,desc);btn.type='button';btn.className='btn secondary releaseCancellationButton';btn.textContent='Estornar';btn.disabled=!!r.impedimento;btn.title=r.impedimento||'Estornar somente este registro';
   btn.addEventListener('click',async()=>{
    if(submitting||r.impedimento||seq!==epoch||company!==currentCompany?.id||!temPermissao('liberacoes.cancelar'))return;
    const reason=window.prompt('Motivo do estorno (5 a 400 caracteres):');
    if(reason===null)return;if(reason.trim().length<5||reason.trim().length>400){msg('Informe motivo válido.');return;}
    if(!window.confirm('Estornar esta liberação? O estoque não será alterado automaticamente. O histórico será preservado.'))return;
    submitting=true;btn.disabled=true;msg('Registrando estorno…');
    try{
     await ensureSession();await rpc('ew_estornar_liberacao_individual',{p_liberacao_id:r.id,p_motivo:reason.trim()});
     try{await loadPanel();const w=works.find(x=>x.id===item.obra_id);if(w){if(detailMode!=='releaseUndo')detailMode='release';renderDetail(w);node('detailError').textContent='Liberação estornada. Histórico preservado.';}}catch(e){msg('Estorno confirmado, mas a atualização falhou. Recarregue a página.');return;}
     submitting=false;await abrir(esquadria);
    }catch(e){msg('Estorno bloqueado: '+e.message);btn.disabled=false;}
    finally{submitting=false;}
   });
   row.append(info,btn);el('releaseUndoList').append(row);
  }
 }catch(e){if(seq===epoch)msg('Não foi possível consultar: '+e.message);}
}
el('releaseUndoClose').addEventListener('click',close);
window.ewReleaseUndo=Object.freeze({abrir});
})();