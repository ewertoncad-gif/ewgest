(()=>{'use strict';
const el=id=>document.getElementById(id);
let op=null,signature='',busy=false;
const allowed=()=>temPermissao('cadastros.consultar')&&temPermissao('obras.importar');
const form=el('worksManualForm'),status=el('worksManualStatus');
el('worksCreateManual').addEventListener('click',()=>{
 if(!allowed()||busy)return;form.reset();op=null;signature='';status.textContent='';form.classList.remove('hidden');el('worksManualName').focus();
});
el('worksManualClose').addEventListener('click',()=>{if(!busy)form.classList.add('hidden');});
form.addEventListener('submit',async event=>{
 event.preventDefault();if(busy||!allowed()||!currentCompany)return;
 const company=currentCompany.id;
 const body={p_empresa_id:company,p_nome:el('worksManualName').value.trim(),p_codigo:el('worksManualCode').value.trim(),p_cliente:el('worksManualClient').value.trim(),p_prazo:el('worksManualDue').value||null};
 if(body.p_nome.length<3||body.p_codigo.toUpperCase().startsWith('MAN-')){status.textContent='Informe nome válido. O prefixo MAN- é reservado para estoque legado.';return;}
 const sig=JSON.stringify(body);if(signature!==sig||!op){signature=sig;op=crypto.randomUUID();}body.p_operacao_id=op;
 busy=true;el('worksManualSave').disabled=true;status.textContent='Cadastrando obra…';
 try{
  await ensureSession();const r=await request('/rest/v1/rpc/ew_cadastrar_obra_manual',{method:'POST',token:session.access_token,body});
  if(!r?.id)throw Error('Cadastro não confirmado.');
  if(currentCompany?.id!==company)return;
  try{await loadPanel();abrirGerenciamentoObras();node('manageWorksFeedback').textContent='Obra '+r.nome+' cadastrada. Estoque vinculado criado.';}catch(e){status.textContent='Obra cadastrada. Atualize a lista antes de tentar novamente.';return;}
  op=null;signature='';
 }catch(e){status.textContent='Não foi possível cadastrar: '+e.message;}
 finally{busy=false;el('worksManualSave').disabled=false;}
});
})();