(()=>{'use strict';
const el=id=>document.getElementById(id);
let rows=[],epoch=0;
const allowed=()=>temPermissao('cadastros.consultar')&&temPermissao('estoque.gerenciar_locais');
const rpc=(name,body)=>request('/rest/v1/rpc/'+name,{method:'POST',token:session.access_token,body});
const msg=s=>el('cadastroLocaisStatus').textContent=s;
function render(){
 const term=el('cadastroLocaisBusca').value.trim().toLowerCase();
 const root=el('cadastroLocaisLista');root.replaceChildren();
 for(const r of rows.filter(x=>(x.nome+' '+(x.codigo||'')).toLowerCase().includes(term))){
  const row=document.createElement('div');row.className='cadastrosListRow';
  row.style.gap='12px';row.style.alignItems='center';
  const info=document.createElement('div'),name=document.createElement('strong'),desc=document.createElement('div');
  name.textContent=r.nome;desc.className='hint';
  desc.textContent=(r.tipo==='EMPRESA'?'Estoque da empresa':r.impedimento==='Vinculado a obra — cadastro permanente'?'Vinculado à obra':'Local manual legado')+(r.codigo?' · '+r.codigo:'')+' · '+(r.impedimento||'Sem saldo ou pendências');
  info.append(name,desc);const b=document.createElement('button');b.type='button';b.className='btn secondary';b.textContent='Excluir';b.disabled=!!r.impedimento;b.title=r.impedimento||'Excluir local preservando histórico';
  b.addEventListener('click',async()=>{
   if(!allowed()||r.impedimento)return;
   const reason=window.prompt('Motivo da exclusão do local '+r.nome+' (5 a 350 caracteres):');
   if(reason===null)return;if(reason.trim().length<5||reason.trim().length>350){msg('Informe motivo válido.');return;}
   if(!window.confirm('Excluir '+r.nome+' da lista de locais ativos? O histórico será preservado.'))return;
   b.disabled=true;
   try{await ensureSession();await rpc('ew_excluir_cadastro_local_estoque',{p_empresa_id:currentCompany.id,p_tipo:r.tipo,p_id:r.id,p_motivo:reason.trim()});
    // Retirar local manual do cache das obras usado por Compras e Estoque.
    if(r.tipo==='OBRA')works=works.filter(w=>w.id!==r.id);
    await refresh();msg('Local excluído. Histórico preservado.');
   }catch(e){msg('Exclusão bloqueada: '+e.message);b.disabled=!!r.impedimento;}
  });
  row.append(info,b);root.append(row);
 }
 if(!root.children.length){const p=document.createElement('p');p.className='hint';p.textContent='Nenhum local encontrado.';root.append(p);}
}
async function refresh(){
 if(!allowed())return;const seq=++epoch,company=currentCompany.id;
 msg('Consultando locais...');el('cadastroLocaisLista').replaceChildren();
 try{await ensureSession();const data=await rpc('ew_listar_cadastro_locais_estoque',{p_empresa_id:company});
  if(seq!==epoch||company!==currentCompany?.id)return;
  if(!Array.isArray(data))throw Error('Resposta inválida.');
  rows=data;render();msg(rows.length+' local(is) ativo(s).');
 }catch(e){if(seq===epoch)msg('Não foi possível consultar locais: '+e.message);}
}
async function abrir(){if(!allowed())return;setView('cadastroLocaisEstoque');await refresh();}
el('cadastroJumpLocaisEstoque').addEventListener('click',abrir);
el('cadastroLocaisVoltar').addEventListener('click',()=>setView('cadastros'));
el('cadastroLocaisAtualizar').addEventListener('click',refresh);
el('cadastroLocaisBusca').addEventListener('input',render);
el('cadastroLocaisNovo').addEventListener('click',async()=>{
 if(!allowed())return;
 const nome=window.prompt('Nome do novo local independente da empresa:');
 if(nome===null)return;if(nome.trim().length<3||nome.trim().length>100){msg('Nome inválido.');return;}
 const b=el('cadastroLocaisNovo');b.disabled=true;
 try{await ensureSession();await rpc('ew_compras_criar_local_empresa',{p_empresa_id:currentCompany.id,p_nome:nome.trim()});await refresh();msg('Local cadastrado.');}
 catch(e){msg('Não foi possível cadastrar: '+e.message);}finally{b.disabled=false;}
});
window.ewCadastroLocais=Object.freeze({abrir});
})();