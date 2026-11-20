/* EWGEST — Orçamento por níveis na importação do CEM.
 * Carregado após o script legado. Intercepta SOMENTE a confirmação da obra nova
 * e a etapa de orçamento. O fluxo de obras existentes permanece inalterado.
 * Requer a proposta SQL revisada e aplicada antes da publicação do frontend.
 */
(function(){
 const grupos=[
  ['aluminio','ALUMÍNIO'],['acessorios','COMPONENTES'],['vidros','VIDROS'],
  ['outros','OUTROS INSUMOS'],['fabricacao','FABRICAÇÃO'],['instalacao','INSTALAÇÃO']
 ];
 let catalogoNiveis=[],catalogoEmpresas=[],linhas=[],pronto=false;
 const norm=(s)=>String(s||'').trim().toLocaleUpperCase('pt-BR');
 const dinheiro=(s)=>Number(s||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
 const cadastroInfo=(s)=>{node('cemQuoteCatalogInfo').textContent=s;};
 const oldAtualizar=cemAtualizarBotao;
 cemAtualizarBotao=function(...args){
  const result=oldAtualizar(...args),r=cemParsed;
  if(r&&!r.obraExistente){
   node('cemCommit').textContent='Próxima etapa';
   if(!node('cemCommit').disabled)node('cemCommitHint').textContent=
    'Próxima etapa: cadastrar valores e níveis; nenhum dado da obra será gravado ainda.';
  }
  return result;
 };
 function somaAtualizar(){
  const total=Number(node('cemQuoteTotal').value||0);
  let cents=0;
  for(let i=0;i<linhas.length;i++){
   const valor=Number(linhas[i].valor||0);
   if(Number.isFinite(valor))cents+=Math.round(valor*100);
   const row=node('cemQuoteRows').querySelector('[data-budget-index="'+i+'"]');
   const percent=row?.querySelector('[data-budget-percent]');
   if(percent)percent.value=total>0&&Number.isFinite(valor)?
    (valor/total*100).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2})+'%':'—';
  }
  const diff=Math.round(total*100)-cents;
  node('cemQuoteSoma').textContent='Soma dos níveis: '+dinheiro(cents/100)+
   ' · Valor total: '+dinheiro(total)+(total>0?
   (diff===0?' · 100% conferido':' · Diferença: '+dinheiro(diff/100)):'');
  node('cemQuoteSoma').classList.toggle('finNegative',total>0&&diff!==0);
 }
 function render(){
  node('cemQuoteRows').innerHTML=linhas.map((x,i)=>{
   const niveis='<option value="">Selecione</option>'+catalogoNiveis.map(n=>
    '<option value="'+escapeHTML(n.nome)+'"'+(x.nivel===n.nome?' selected':'')+'>'+
      escapeHTML(n.nome)+'</option>').join('');
   const empresas='<option value="">Selecione</option>'+catalogoEmpresas.map(n=>
    '<option value="'+escapeHTML(n)+'"'+(x.empresa===n?' selected':'')+'>'+
      escapeHTML(n)+'</option>').join('');
   return '<tr data-budget-index="'+i+'">'+
    '<td><select required data-budget-field="nivel" aria-label="Nível da linha '+(i+1)+'">'+niveis+'</select></td>'+
    '<td><input type="number" min="0" max="999999999999.99" step="0.01" required data-budget-field="valor" aria-label="Valor do nível '+(i+1)+'" value="'+escapeHTML(x.valor)+'"></td>'+
    '<td><input readonly data-budget-percent aria-label="Percentual do nível '+(i+1)+'"></td>'+
    '<td><select required data-budget-field="empresa" aria-label="Empresa da linha '+(i+1)+'">'+empresas+'</select></td>'+
    '<td><input type="checkbox" data-budget-field="faturar" aria-label="Este nível é para faturamento"'+(x.faturar?' checked':'')+'></td>'+
    '<td><button type="button" class="btn secondary" data-budget-remove="'+i+'">Remover</button></td></tr>';
  }).join('');
  somaAtualizar();
 }
 function adicionarLinha(nivel='',empresa=''){
  if(linhas.length>=100){node('cemQuoteError').textContent='Limite de 100 níveis por obra.';return;}
  linhas.push({nivel,empresa:empresa||catalogoEmpresas[0]||'',valor:'',faturar:true});
  render();
 }
 function validar(){
  if(!pronto)throw new Error('Ainda não foi possível carregar os cadastros.');
  const raw=node('cemQuoteTotal').value.trim(),total=Number(raw);
  if(!raw||!Number.isFinite(total)||total<=0||total>999999999999.99||
   Math.abs(total*100-Math.round(total*100))>0.00001)
   throw new Error('Valor total inválido. Use valores positivos com até duas casas decimais.');
  if(!linhas.length)throw new Error('Adicione ao menos um nível.');
  const niveis=linhas.map((x,i)=>{
   const cat=catalogoNiveis.find(n=>n.nome===x.nivel),empresa=catalogoEmpresas.find(n=>n===x.empresa);
   if(!cat||!empresa)throw new Error('Escolha nível e empresa na linha '+(i+1)+'.');
   const valor=Number(x.valor),rawValor=String(x.valor).trim();
   if(!rawValor||!Number.isFinite(valor)||valor<0||valor>999999999999.99||
    Math.abs(valor*100-Math.round(valor*100))>0.00001)
    throw new Error('Informe um valor válido na linha '+(i+1)+'.');
   return {nivel:cat.nome,categoria_base:cat.categoria_base,empresa_faturamento:empresa,
    valor:Math.round(valor*100)/100,faturar:Boolean(x.faturar)};
  });
  const cents=niveis.reduce((s,x)=>s+Math.round(x.valor*100),0);
  if(cents!==Math.round(total*100))throw new Error('Os valores dos níveis devem somar exatamente 100% da obra.');
  return {valor_total:Math.round(total*100)/100,niveis};
 }
 const oldQuoteSoma=cemQuoteSomaAtualizar;
 node('cemQuoteTotal').removeEventListener('input',oldQuoteSoma);
 const oldQuoteClose=cemQuoteFechar;
 node('cemQuoteCancel').removeEventListener('click',oldQuoteClose);
 const oldQuoteSubmit=cemQuoteConfirmar;
 node('cemQuoteForm').removeEventListener('submit',oldQuoteSubmit);
 cemQuoteSomaAtualizar=somaAtualizar;
 cemQuoteValidar=validar;
 cemQuoteFechar=function(){
  node('cemQuoteOverlay').classList.add('hidden');
  if(cemParsed)cemParsed.confirmacaoInicialFeita=false;
 };
 cemQuoteAbrir=async function(r){
  node('cemQuoteForm').reset();
  node('cemQuoteError').textContent='';
  node('cemQuoteWork').textContent=r.nomeObra+' · '+r.codigo+' · '+(r.clienteObra||'Cliente não informado');
  node('cemQuoteOverlay').classList.remove('hidden');
  node('cemQuoteSave').disabled=true;pronto=false;linhas=[];catalogoNiveis=[];catalogoEmpresas=[];
  node('cemQuoteRows').replaceChildren();
  cadastroInfo('Carregando níveis e empresas...');
  try{
   await ensureSession();
   if(!currentCompany?.id)throw new Error('Empresa do usuário não identificada.');
   const filtro='eq.'+currentCompany.id;
   const [niveis,empresas]=await Promise.all([
    apiGet('ew_niveis_orcamento_catalogo',{select:'nome,categoria_base,ativo',empresa_id:filtro,limit:'500'}),
    apiGet('ew_empresas_faturamento_catalogo',{select:'nome,ativo',empresa_id:filtro,limit:'500'})
   ]);
   if(cemParsed!==r||!session){cemQuoteFechar();return;}
   const mapa=new Map(grupos.map(([categoria_base,nome])=>[nome,{nome,categoria_base}]));
   for(const n of niveis||[])if(n.ativo!==false){
    mapa.set(norm(n.nome),{nome:norm(n.nome),categoria_base:n.categoria_base});
   }
   catalogoNiveis=[...mapa.values()].sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));
   catalogoEmpresas=[...new Set([currentCompany?.nome,...(empresas||[])
    .filter(e=>e.ativo!==false).map(e=>e.nome)].map(norm).filter(Boolean))]
    .sort((a,b)=>a.localeCompare(b,'pt-BR'));
   pronto=true;node('cemQuoteSave').disabled=false;
   cadastroInfo('Catálogos carregados. Novos níveis e empresas serão salvos somente com a confirmação final da obra.');
   adicionarLinha();
   node('cemQuoteTotal').focus();
  }catch(e){
   cadastroInfo('Não foi possível carregar níveis e empresas. A importação está bloqueada.');
   node('cemQuoteError').textContent=e.message;
  }
 };
 cemQuoteConfirmar=async function(event){
  event.preventDefault();
  const r=cemParsed;if(!r||r.jaImportado||r.obraExistente){cemQuoteFechar();return;}
  try{
   const values=validar();
   const custo=values.niveis.filter(x=>!x.faturar).reduce((s,x)=>s+x.valor,0);
   if(!window.confirm('Confirmar importação da nova obra?'+
    '\n\n'+r.nomeObra+' ('+r.codigo+')'+
    '\nTotal: '+dinheiro(values.valor_total)+
    '\nNíveis: '+values.niveis.length+
    '\nNíveis exclusivos para gastos: '+dinheiro(custo)+
    '\n\nA obra, esquadrias, materiais e orçamento serão registrados. O estoque físico seguirá zerado até recebimento real.'))return;
   r.orcamentoDraft=values;r.confirmacaoInicialFeita=true;
   node('cemQuoteError').textContent='';
   node('cemQuoteOverlay').classList.add('hidden');
   await cemImportarSelecionados();
  }catch(e){node('cemQuoteError').textContent=e.message;}
 };
 node('cemQuoteTotal').addEventListener('input',somaAtualizar);
 node('cemQuoteCancel').addEventListener('click',cemQuoteFechar);
 node('cemQuoteForm').addEventListener('submit',cemQuoteConfirmar);
 node('cemQuoteRows').addEventListener('input',event=>{
  const row=event.target.closest('[data-budget-index]'),field=event.target.dataset.budgetField;
  if(!row||!field)return;
  const x=linhas[Number(row.dataset.budgetIndex)];if(!x)return;
  x[field]=field==='faturar'?event.target.checked:event.target.value;
  somaAtualizar();
 });
 node('cemQuoteRows').addEventListener('change',event=>{
  const row=event.target.closest('[data-budget-index]'),field=event.target.dataset.budgetField;
  if(!row||!field)return;
  const x=linhas[Number(row.dataset.budgetIndex)];if(!x)return;
  x[field]=field==='faturar'?event.target.checked:event.target.value;
  somaAtualizar();
 });
 node('cemQuoteRows').addEventListener('click',event=>{
  const btn=event.target.closest('[data-budget-remove]');if(!btn)return;
  linesRemove(Number(btn.dataset.budgetRemove));
 });
 function linesRemove(i){
  linhas.splice(i,1);
  if(linhas.length===0)adicionarLinha();else render();
 }
 node('cemQuoteAddRow').addEventListener('click',()=>adicionarLinha());
 node('cemQuoteSaveLevel').addEventListener('click',()=>{
  try{
   if(!pronto)throw new Error('Aguarde os cadastros.');
   const nome=norm(node('cemQuoteNewLevel').value),categoria_base=node('cemQuoteNewGroup').value;
   if(nome.length<2||nome.length>120)throw new Error('Nível: informe de 2 a 120 caracteres.');
   const antigo=catalogoNiveis.find(n=>n.nome===nome);
   if(antigo)throw new Error(antigo.categoria_base===categoria_base?
    'O nível já existe: selecione-o na tabela.':'O nível já existe com outro grupo financeiro.');
   catalogoNiveis.push({nome,categoria_base});
   catalogoNiveis.sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'));
   if(linhas.length)linhas[linhas.length-1].nivel=nome;
   node('cemQuoteNewLevel').value='';node('cemQuoteError').textContent='';render();
  }catch(e){node('cemQuoteError').textContent=e.message;}
 });
 node('cemQuoteSaveCompany').addEventListener('click',()=>{
  try{
   if(!pronto)throw new Error('Aguarde os cadastros.');
   const nome=norm(node('cemQuoteNewCompany').value);
   if(nome.length<2||nome.length>120)throw new Error('Empresa: informe de 2 a 120 caracteres.');
   if(catalogoEmpresas.includes(nome))throw new Error('A empresa já existe: selecione-a na tabela.');
   catalogoEmpresas.push(nome);
   catalogoEmpresas.sort((a,b)=>a.localeCompare(b,'pt-BR'));
   if(linhas.length)linhas[linhas.length-1].empresa=nome;
   node('cemQuoteNewCompany').value='';node('cemQuoteError').textContent='';render();
  }catch(e){node('cemQuoteError').textContent=e.message;}
 });
 // O botão inicial para obras novas só avança para o orçamento.
 // A confirmação definitiva ocorre no submit do modal acima.
 const oldImport=cemImportarSelecionados;
 node('cemCommit').removeEventListener('click',oldImport);
 cemImportarSelecionados=async function(){
  const r=cemParsed;
  cemAtualizarBotao();
  if(node('cemCommit').disabled)return;
  if(r&&!r.obraExistente&&!r.orcamentoDraft){
   await cemQuoteAbrir(r);
   return;
  }
  return oldImport();
 };
 node('cemCommit').addEventListener('click',cemImportarSelecionados);
 cemAtualizarBotao();
})();