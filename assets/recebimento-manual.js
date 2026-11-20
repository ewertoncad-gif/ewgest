/* EWGEST — recebimento manual de materiais e NF.
 * Mantém o fluxo legado de notas pendentes do almoxarifado intacto.
 * Estoque + despesa são registrados pelo servidor em uma única transação.
 */
(function(){
 let rows=[],category='aluminio';
 const byId=id=>node(id);
 const cents=s=>{
  let t=String(s??'').trim().replace(/^\s*R\$\s*/i,'').replace(/\s/g,'');
  if(!t||!/^[0-9.,]+$/.test(t))return null;
  if((t.match(/,/g)||[]).length>1)return null;
  let inteiro=t,frac='';
  if(t.includes(',')){[inteiro,frac]=t.split(',');}
  else if(/^\d{4,}\.\d{1,2}$/.test(t)&&!t.startsWith('R$')){let i=t.lastIndexOf('.');inteiro=t.slice(0,i);frac=t.slice(i+1);}
  if(!/^\d+(?:\.\d+)*$/.test(inteiro)||!/^\d{0,2}$/.test(frac))return null;
  let num=inteiro.replace(/\./g,'');if(num.length>12)return null;
  let result=Number(num)*100+Number(frac.padEnd(2,'0'));
  return Number.isSafeInteger(result)?result:null;
 };
 const toMoney=s=>{
  const c=cents(s);return c===null?String(s||''):finMoney(c/100);
 };
 function moneyInput(e){
  const el=e.target;if(!el.value.trim())return;
  const value=toMoney(el.value);
  if(cents(value)!==null)el.value=value;
 }
 function stockCategory(){return category==='aluminio'||category==='acessorios'}
 function getMaterials(){
  if(!finState)return [];
  return category==='aluminio'?finState.perfis:finState.acessorios;
 }
 function getVariations(matId){
  if(!finState||!matId)return [];
  return finState.variacoes.filter(v=>v.ativo!==false&&(
   category==='aluminio'?v.tipo==='perfil'&&v.perfil_id===matId:
   v.tipo==='acessorio'&&v.acessorio_id===matId));
 }
 function unitFor(matId){
  if(category==='aluminio')return 'BARRA';
  const mat=finState?.acessorios.find(m=>m.id===matId);
  return mat?releaseUnidadeAcessorio(mat.unidade_item||''):'';
 }
 function resetRows(){
  rows=[{material:'',variacao:'',comprimento:'',quantidade:'',valor:''}];
  renderRows();
 }
 function renderRows(){
  const body=byId('finManualRows');
  if(!finState){body.innerHTML='';return;}
  const mats=getMaterials();
  body.innerHTML=rows.map((row,i)=>{
   const materialOptions='<option value="">Selecione material</option>'+mats.map(m=>
    '<option value="'+escapeHTML(m.id)+'"'+(row.material===m.id?' selected':'')+'>'+
      escapeHTML(m.codigo+' — '+m.descricao)+'</option>').join('');
   const variations=getVariations(row.material);
   const variationOptions='<option value="">Selecione cor/variação</option>'+variations.map(v=>
    '<option value="'+escapeHTML(v.id)+'"'+(row.variacao===v.id?' selected':'')+'>'+
      escapeHTML(v.cor+(category==='aluminio'?' / '+v.acabamento:''))+'</option>').join('');
   const unit=unitFor(row.material);
   return '<tr data-manual-row="'+i+'">'+
    '<td><select class="finManualMaterial" required aria-label="Material '+(i+1)+'">'+materialOptions+'</select></td>'+
    '<td><select class="finManualVariation" required aria-label="Variação '+(i+1)+'">'+variationOptions+'</select></td>'+
    '<td><input class="finManualLength" type="number" min="100" max="20000" step="1" '+(category==='acessorios'?'disabled ':'')+
     'placeholder="'+(category==='aluminio'?'Ex.: 6000':'—')+'" value="'+escapeHTML(row.comprimento)+'" aria-label="Comprimento da barra '+(i+1)+'"></td>'+
    '<td><input class="finManualQty" type="number" min="0.001" step="'+(category==='aluminio'?'1':'0.001')+
     '" required placeholder="Qtd." value="'+escapeHTML(row.quantidade)+'" aria-label="Quantidade física '+(i+1)+'"></td>'+
    '<td class="hint">'+escapeHTML(unit||'—')+'</td>'+
    '<td><input class="finManualSubtotal" type="text" inputmode="decimal" required placeholder="R$ 0,00" value="'+escapeHTML(row.valor)+'" aria-label="Subtotal do material '+(i+1)+'"></td>'+
    '<td><button class="btn secondary" type="button" data-manual-remove="'+i+'">Remover</button></td></tr>';
  }).join('');
  updateSum();
 }
 function updateSum(){
  const note=cents(byId('finCostTotal').value);
  if(stockCategory()&&rows.length===1&&note!==null){
   // Nota de um único material: todo o valor é deste item, sem rateio arbitrário.
   rows[0].valor=finMoney(note/100);
   const el=byId('finManualRows').querySelector('.finManualSubtotal');
   if(el&&document.activeElement!==el)el.value=rows[0].valor;
  }
  const values=rows.map(r=>cents(r.valor));
  const sum=values.reduce((v,n)=>v+(n??0),0);
  const match=note!==null&&note>0&&values.every(v=>v!==null)&&sum===note;
  byId('finManualSum').textContent=
   'Total dos itens: '+finMoney(sum/100)+' · Valor da nota: '+
   finMoney((note||0)/100)+(note!==null&&note>0?
    (match?' · Valores conferem':' · Diferença: '+finMoney((note-sum)/100)):'');
  byId('finManualSum').classList.toggle('finManualCorrect',match);
 }
 function renderForm(){
  category=byId('finCostCategory').value;
  const hasStock=stockCategory();
  byId('finManualStockBlock').classList.toggle('hidden',!hasStock);
  byId('finManualLocalLabel').classList.toggle('hidden',!hasStock);
  byId('finManualLocal').required=hasStock;
  byId('finCostSubmit').textContent=hasStock?'Registrar nota e entrada no estoque':'Registrar despesa sem movimentar estoque';
  byId('finManualHint').textContent=hasStock?
   'A confirmação aumenta imediatamente o estoque físico da obra no galpão escolhido. Verifique cada quantidade recebida antes de gravar.':
   'Esta categoria será registrada somente como despesa. Não haverá movimentação física de estoque: o catálogo atual permite recebimento automático de perfis e acessórios.';
  resetRows();
 }
 function initForm(){
  if(!finState)return;
  const select=byId('finManualLocal'),prev=select.value;
  select.innerHTML='<option value="">Selecione o galpão</option>'+
   finState.galpoes.map(g=>'<option value="'+escapeHTML(g)+'">'+escapeHTML(g)+'</option>').join('');
  if(finState.galpoes.includes(prev))select.value=prev;
  byId('finCostMessage').textContent='';
  renderForm();
 }
 function normalizeItem(row,i){
  const mat=getMaterials().find(m=>m.id===row.material);
  const variacao=getVariations(row.material).find(v=>v.id===row.variacao);
  if(!mat||!variacao)throw new Error('Escolha material e cor/variação na linha '+(i+1)+'.');
  const rawQty=String(row.quantidade).trim(),qty=Number(rawQty);
  const amount=cents(row.valor);
  if(!rawQty||!Number.isFinite(qty)||qty<=0||qty>1000000||
    Math.abs(qty*1000-Math.round(qty*1000))>0.00001)
   throw new Error('Quantidade física inválida na linha '+(i+1)+'.');
  if(amount===null||amount<0)throw new Error('Subtotal do material inválido na linha '+(i+1)+'.');
  const length=category==='aluminio'?Number(row.comprimento):null;
  if(category==='aluminio'&&(!Number.isSafeInteger(qty)||!String(row.comprimento).trim()||
      !Number.isSafeInteger(length)||length<100||length>20000))
    throw new Error('Perfil exige barras inteiras e comprimento entre 100 e 20.000 mm na linha '+(i+1)+'.');
  return {variacao_id:variacao.id,quantidade:qty,comprimento_mm:length,valor_total:amount/100};
 }
 async function submit(event){
  event.preventDefault();
  if(!finState||!isFullAdminUser())return;
  const el=byId('finCostMessage'),btn=byId('finCostSubmit');
  const note=cents(byId('finCostTotal').value);
  if(note===null||note<=0){el.textContent='Informe o valor total da nota com centavos válidos.';return;}
  const number=byId('finCostNumber').value.trim(),vendor=byId('finCostVendor').value.trim();
  if(!number){el.textContent='Informe o número da nota/documento.';return;}
  const hasStock=stockCategory(),location=byId('finManualLocal').value;
  let items=[];
  try{
   if(hasStock){
    if(!location)throw new Error('Selecione o galpão onde os materiais foram recebidos.');
    if(!rows.length)throw new Error('Inclua ao menos um material.');
    items=rows.map(normalizeItem);
    const sum=items.reduce((v,item)=>v+Math.round(item.valor_total*100),0);
    if(sum!==note)throw new Error('A soma dos itens deve ser igual ao valor total da nota.');
   }
  }catch(e){el.textContent=e.message;return;}
  const text='Registrar nota '+number+' no valor de '+finMoney(note/100)+' para esta obra?'+
   (hasStock?'\n\nIsto dará entrada IMEDIATA de '+items.length+' material(is) no estoque da obra, galpão '+location+'.':
    '\n\nEsta operação registrará somente a despesa; NÃO movimentará estoque.')+
   '\n\nConfirme apenas itens e quantidades realmente recebidos.';
  if(!window.confirm(text))return;
  btn.disabled=true;finCostOpId ||= crypto.randomUUID();
  el.textContent=hasStock?'Registrando nota e estoque na mesma operação…':'Registrando despesa…';
  try{
   await ensureSession();
   let response;
   const common={p_empresa_id:currentCompany.id,p_obra_id:finState.obraId,
    p_categoria:category,p_valor:note/100,p_fornecedor:vendor,p_numero_documento:number,
    p_data_documento:byId('finCostDate').value||null,
    p_observacoes:byId('finCostNotes').value.trim(),p_operacao_id:finCostOpId};
   if(hasStock){
    response=await request('/rest/v1/rpc/ew_registrar_recebimento_manual_financeiro',{
     method:'POST',token:session.access_token,timeoutMs:120000,
     body:{...common,p_local_estoque:location,p_itens:items}
    });
   }else{
    response=await request('/rest/v1/rpc/ew_registrar_despesa_financeira',{
     method:'POST',token:session.access_token,timeoutMs:90000,
     body:{...common,p_origem:'manual',p_chave_nfe:null,p_itens:[]}
    });
   }
   const repeated=Boolean(response?.ja_registrado);
   finCostOpId=null;
   await finLoad();
   byId('finMessage').textContent=repeated?
    'Este lançamento já constava registrado; o estoque não foi duplicado.':
    hasStock?'Nota registrada e materiais recebidos: o estoque físico da obra foi atualizado.':
    'Despesa registrada sem movimentação de estoque.';
  }catch(e){
   el.textContent='Falha ou resposta inconclusiva: '+e.message+
    '. Confira o histórico antes de repetir; a operação impede duplicidade por identificador.';
  }finally{btn.disabled=false;}
 }
 // Valor total deixa de mostrar apenas fabricação/instalação se outro nível
 // também tiver flag de faturamento (ex.: OUTROS INSUMOS para Artefal).
 const oldResumo=finRenderResumo;
 finRenderResumo=function(){
  oldResumo();
  if(!finState)return;
  const state=finState,levels=state.orcamentoNiveis||[];
  if(levels.length){
   const totalF=levels.filter(n=>n.faturar).reduce((s,n)=>s+Number(n.valor||0),0);
   const emissivel=levels.filter(n=>n.faturar&&['fabricacao','instalacao'].includes(n.categoria_base))
    .reduce((s,n)=>s+Number(n.valor||0),0);
   const outras=totalF-emissivel;
   const realizado=state.faturas.filter(f=>f.status==='emitido')
    .reduce((s,f)=>s+Number(f.valor_total||0),0);
   const gastos=state.despesas.filter(d=>d.status==='aprovada')
    .reduce((s,d)=>s+Number(d.valor||0),0);
   byId('finTotals').innerHTML='<span><strong>Valor da obra: '+finMoney(state.orcamento.valor_total)+'</strong></span>'+
    '<span><strong>Faturado: '+finMoney(realizado)+'</strong></span>'+
    '<span><strong>A faturar (todos os níveis): '+finMoney(Math.max(0,totalF-realizado))+'</strong></span>'+
    '<span><strong>Disponível no módulo por esquadria: '+finMoney(Math.max(0,emissivel-realizado))+'</strong></span>'+
    (outras>0?'<span><strong>Outros níveis faturáveis (sem emissão aqui): '+finMoney(outras)+'</strong></span>':'')+
    '<span><strong>Gastos registrados: '+finMoney(gastos)+'</strong></span>';
   const existing=byId('finSummary').querySelectorAll('table');
   if(existing.length>1){
    const groupTable=existing[existing.length-1];
    groupTable.querySelector('th:nth-child(2)').textContent='Controle técnico anterior';
    for(const [i,[key]] of finCategories.entries()){
     const row=groupTable.tBodies[0]?.rows[i];if(!row)continue;
     const assigned=levels.filter(n=>n.categoria_base===key),f=assigned.filter(n=>n.faturar);
     if(!assigned.length)continue;
     const label=f.length===assigned.length?'Faturamento':f.length?'Misto':'Gasto';
     row.cells[1].textContent=label+
       ((f.length&& !['fabricacao','instalacao'].includes(key))?' (emissão pendente)':'');
    }
   }
   byId('finSummary').insertAdjacentHTML('beforeend',
    '<p class="hint">O quadro técnico acima mantém os agrupamentos históricos de custos. Os níveis personalizados e suas flags são a referência para o orçamento; outros níveis faturáveis ainda não têm emissão neste módulo.</p>');
  }
  initForm();
 };
 byId('finExpenseForm').removeEventListener('submit',finRegistrarCusto);
 byId('finExpenseForm').addEventListener('submit',submit);
 byId('finCostCategory').addEventListener('change',()=>{
  category=byId('finCostCategory').value;
  renderForm();
 });
 byId('finCostTotal').addEventListener('blur',moneyInput);
 byId('finCostTotal').addEventListener('input',updateSum);
 byId('finManualAdd').addEventListener('click',()=>{
  if(rows.length>=100){byId('finCostMessage').textContent='Limite de 100 materiais por nota.';return;}
  rows.push({material:'',variacao:'',comprimento:'',quantidade:'',valor:''});renderRows();
 });
 byId('finManualRows').addEventListener('change',event=>{
  const tr=event.target.closest('[data-manual-row]');if(!tr)return;
  const i=Number(tr.dataset.manualRow),r=rows[i];if(!r)return;
  if(event.target.matches('.finManualMaterial')){
   r.material=event.target.value;r.variacao='';r.quantidade='';r.comprimento='';r.valor='';
   renderRows();
  }else if(event.target.matches('.finManualVariation'))r.variacao=event.target.value;
 });
 byId('finManualRows').addEventListener('input',event=>{
  const tr=event.target.closest('[data-manual-row]');if(!tr)return;
  const r=rows[Number(tr.dataset.manualRow)];if(!r)return;
  if(event.target.matches('.finManualQty'))r.quantidade=event.target.value;
  if(event.target.matches('.finManualLength'))r.comprimento=event.target.value;
  if(event.target.matches('.finManualSubtotal')){r.valor=event.target.value;updateSum();}
 });
 byId('finManualRows').addEventListener('focusout',event=>{
  const tr=event.target.closest('[data-manual-row]');if(!tr||!event.target.matches('.finManualSubtotal'))return;
  moneyInput(event);
  rows[Number(tr.dataset.manualRow)].valor=event.target.value;
  updateSum();
 });
 byId('finManualRows').addEventListener('click',event=>{
  const btn=event.target.closest('[data-manual-remove]');if(!btn)return;
  rows.splice(Number(btn.dataset.manualRemove),1);
  if(!rows.length)rows=[{material:'',variacao:'',comprimento:'',quantidade:'',valor:''}];
  renderRows();
 });
})();
