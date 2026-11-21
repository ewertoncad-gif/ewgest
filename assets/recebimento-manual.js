/* EWGEST — recebimento manual de materiais e NF.
 * Mantém o fluxo legado de notas pendentes do almoxarifado intacto.
 * Estoque + despesa são registrados pelo servidor em uma única transação.
 */
(function(){
 let rows=[],miscRows=[],category='aluminio';
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
 // Quantidade recebida de barras: número natural positivo, nunca fração,
 // negativo, notação científica nem quantidade interpretada como decimal.
 function isNaturalBarQuantity(value){
  const raw=String(value??'').trim(),number=Number(raw);
  return /^[0-9]+$/.test(raw)&&Number.isSafeInteger(number)&&number>=1&&number<=1000000;
 }
 function stockCategory(){return category==='aluminio'||category==='acessorios'}
 function plannedRows(matId='',variationId=''){
  if(!finState)return [];
  const isPerfil=category==='aluminio',type=isPerfil?'perfil':'acessorio';
  const field=isPerfil?'perfil_id':'acessorio_id';
  const seen=new Set();
  return (finState.materiaisObra||[]).filter(m=>m.tipo===type&&
   (!matId||m[field]===matId)&&(!variationId||m.variacao_id===variationId))
   .filter(m=>{
    // Uma importação repetida do mesmo ZIP pode recriar a mesma linha de
    // necessidade. Não duplicar um quantitativo rigorosamente idêntico.
    const key=[m.tipo,m[field],m.variacao_id,m.unidade_prevista,
      m.quantidade_prevista,m.comprimento_total_m,m.linhas_calculo].join('|');
    if(seen.has(key))return false;
    seen.add(key);return true;
   });
 }
 function getMaterials(){
  if(!finState||!stockCategory())return [];
  const isPerfil=category==='aluminio',field=isPerfil?'perfil_id':'acessorio_id';
  const ids=new Set(plannedRows().map(m=>m[field]).filter(Boolean));
  return (isPerfil?finState.perfis:finState.acessorios).filter(m=>ids.has(m.id))
   .sort((a,b)=>String(a.codigo).localeCompare(String(b.codigo),'pt-BR',{numeric:true}));
 }
 function getVariations(matId){
  if(!finState||!matId)return [];
  const ids=new Set(plannedRows(matId).map(m=>m.variacao_id).filter(Boolean));
  return finState.variacoes.filter(v=>v.ativo!==false&&ids.has(v.id)&&(
   category==='aluminio'?v.tipo==='perfil'&&v.perfil_id===matId:
   v.tipo==='acessorio'&&v.acessorio_id===matId));
 }
 // Preferir plano da obra persistido em ew_cem_obras_materiais. Apenas
 // obras antigas (coluna NULL) utilizam o histórico técnico IMPORTACAO_CEM.
 // Mesmo [] é autoritativo: não somar o plano com estoque inicial.
 function plannedBarRows(variationId=''){
  const modern=(finState?.materiaisObra||[]).filter(m=>m.tipo==='perfil'&&
   (!variationId||m.variacao_id===variationId)&&Array.isArray(m.barras_planejadas));
  const modernIds=new Set(modern.map(m=>m.variacao_id));
  const planned=modern.flatMap(m=>m.barras_planejadas.map(b=>({
   variacao_id:m.variacao_id,comprimento_mm:Number(b.comprimento_mm),
   quantidade_delta:Number(b.quantidade)}))).filter(b=>
    Number.isSafeInteger(b.comprimento_mm)&&b.comprimento_mm>=100&&
    b.comprimento_mm<=20000&&Number.isSafeInteger(b.quantidade_delta)&&b.quantidade_delta>0);
  const legacy=(finState?.barrasCem||[]).filter(x=>
   (!variationId||x.variacao_id===variationId)&&!modernIds.has(x.variacao_id)&&
   Number.isSafeInteger(Number(x.comprimento_mm))&&Number(x.comprimento_mm)>=100&&
   Number(x.comprimento_mm)<=20000&&Number(x.quantidade_delta)>0);
  return [...planned,...legacy];
 }
 function selectOptions(){
  return getMaterials().flatMap(mat=>getVariations(mat.id).flatMap(v=>{
   const lengths=category==='aluminio'?
    [...new Set(plannedBarRows(v.id).map(x=>Number(x.comprimento_mm)))].sort((a,b)=>a-b):[];
   return (lengths.length?lengths:[null]).map(length=>({
    mat,v,length,value:v.id+'|'+(length===null?'':length)
   }));
  }));
 }
 function formatQty(n){
  return Number(n||0).toLocaleString('pt-BR',{minimumFractionDigits:0,maximumFractionDigits:3});
 }
 function barLabel(n){return formatQty(n)+(Number(n)===1?' barra':' barras');}
 function autoBarLength(row){
  if(category!=='aluminio'||!row.material||!row.variacao)return null;
  const selecionado=selectOptions().find(x=>x.value===row.selectionKey);
  // Somente o plano de barras do CEM específico desta obra define a medida.
  // O comprimento comercial genérico do cadastro não substitui esse dado.
  return selecionado?.length??null;
 }
 function quantityData(row){
  if(!row.material||!row.variacao)
   return {needed:'—',received:'—',pending:'—',note:'Selecione o material para consultar.'};
  const all=plannedRows(row.material,row.variacao);
  if(!all.length)return {needed:'—',received:'—',pending:'—',note:'Material não previsto na obra.'};
  const registered=(finState.stockReceipts||[]).filter(x=>x.variacao_id===row.variacao);
  if(category==='aluminio'){
   // Não usar cortes, metros lineares ou comprimento total da peça como
   // quantidade de barras necessárias. A comparação é BARRA X BARRA
   // com o mesmo código, cor, comprimento e obra.
   const availablePlan=plannedBarRows(row.variacao);
   const hasAnyPlan=availablePlan.length>0;
   const length=Number(row.comprimento);
   if(!String(row.comprimento).trim()||!Number.isSafeInteger(length)||length<100||length>20000)
    return {needed:hasAnyPlan?'—':'Não importado',received:'—',pending:'—',
     note:hasAnyPlan?'Selecione uma medida do plano do CEM.':
      'Plano de barras ausente nesta obra. Use o ZIP original do CEM; não digite uma medida presumida.'};
   const planned=availablePlan.filter(x=>Number(x.comprimento_mm)===length);
   const hasPlan=planned.length>0;
   const expected=planned.reduce((sum,x)=>sum+Number(x.quantidade_delta||0),0);
   const received=registered.filter(x=>x.unidade==='BARRA'&&Number(x.comprimento_mm)===length)
    .reduce((sum,x)=>sum+Number(x.quantidade||0),0);
   return {
    needed:hasPlan?barLabel(expected):(hasAnyPlan?'Não planejado':'Não importado'),
    received:barLabel(received),
    pending:hasPlan?barLabel(Math.max(0,expected-received)):'—',
    note:hasPlan?'Quantidade de barras planejada no CEM, sem confundir com saldo físico.':
     hasAnyPlan?'Comprimento não planejado para este perfil e cor. A barra real pode ser recebida sem alterar o plano.':
      'Barras necessárias não importadas para esta obra. Informe o comprimento real recebido; a entrada não cria necessidade planejada.'
   };
  }
  const wanted=new Map(),invoices=new Map();
  for(const item of all){
   const unit=String(item.unidade_prevista||'').trim().toUpperCase()||'N/I';
   wanted.set(unit,(wanted.get(unit)||0)+Number(item.quantidade_prevista||0));
  }
  for(const item of registered){
   const unit=String(item.unidade||'').trim().toUpperCase()||'N/I';
   invoices.set(unit,(invoices.get(unit)||0)+Number(item.quantidade||0));
  }
  const label=map=>[...map.entries()].map(([u,n])=>formatQty(n)+' '+u).join(' + ')||'0';
  const sameUnit=wanted.size===1&&[...invoices.keys()].every(u=>wanted.has(u));
  const first=sameUnit?[...wanted.entries()][0]:null;
  return {needed:label(wanted),received:label(invoices),pending:first?
   formatQty(Math.max(0,first[1]-(invoices.get(first[0])||0)))+' '+first[0]:'—',
   note:sameUnit?'Quantidade física na unidade do CEM.':'Unidades não compatíveis; saldo não pode ser calculado.'};
 }
 function quantityInfo(row){
  if(!row.material)return 'Selecione um material desta obra para consultar os quantitativos.';
  const q=quantityData(row);
  return '<strong>Necessário:</strong> '+q.needed+
   ' | <strong>Já recebido em NF:</strong> '+q.received+
   ' | <strong>Falta receber:</strong> '+q.pending+' ('+q.note+')';
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
  const opts=selectOptions();
  body.innerHTML=rows.map((row,i)=>{
   const options='<option value="">'+(opts.length?'Selecione material da obra':'Nenhum material vinculado à obra')+'</option>'+
    opts.map(({mat,v,length,value})=>'<option value="'+escapeHTML(value)+'"'+(row.selectionKey===value?' selected':'')+'>'+
      escapeHTML(mat.codigo+' — '+mat.descricao+' · '+[v.cor,v.acabamento].filter(Boolean).join(' / ')+
       (category==='aluminio'?(length?' · '+Number(length).toLocaleString('pt-BR')+' mm':
        ' · BARRAS NÃO IMPORTADAS'):'') )+'</option>').join('');
   const variation=opts.find(x=>x.value===row.selectionKey)?.v;
   const color=variation?[variation.cor,variation.acabamento].filter(Boolean).join(' / '):'—';
   const auto=autoBarLength(row),unit=unitFor(row.material);
   // O comprimento veio do CEM na seleção, mas deve permanecer editável na NF.
   const q=quantityData(row);
   const length=Number(row.comprimento),validLength=String(row.comprimento).trim()&&
    Number.isSafeInteger(length)&&length>=100&&length<=20000;
   const isPlanned=category==='aluminio'&&validLength&&
    plannedBarRows(row.variacao).some(x=>Number(x.comprimento_mm)===length);
   let lengthField='<span class="finManualEmpty">—</span>';
   if(category==='aluminio'&&row.material){
    if(!plannedBarRows(row.variacao).length){
     lengthField='<span class="finManualMissingPlan" role="status" '+
      'title="O plano de barras desta obra não está cadastrado. Atualize os perfis pela opção Importar arquivo técnico do menu.">'+
      'Plano de barras não importado</span>';
    }else{
     lengthField='<input class="finManualLength" type="number" inputmode="numeric" min="100" max="20000" step="1" required'+
      ' aria-label="Comprimento real da barra em milímetros"'+
      ' title="Predefinido pelo CEM quando disponível; altere se a compra chegou em outra medida."'+
      ' placeholder="Barra (mm)" value="'+escapeHTML(row.comprimento)+'">'+
      '<small class="finManualLengthHint">'+(isPlanned?'Medida do CEM':validLength?
       'Fora do plano do CEM':'Medida do CEM')+'</small>';
    }
   }
   const stats=html=>'<td class="finManualStat">'+html+'</td>';
   return '<tr data-manual-row="'+i+'">'+
    '<td><select class="finManualMaterial" required aria-label="Material da obra '+(i+1)+'">'+options+'</select></td>'+
    '<td><span class="finManualReadonly">'+escapeHTML(color)+'</span></td>'+
    '<td>'+lengthField+'</td>'+
    stats('<strong>'+escapeHTML(q.needed)+'</strong>')+
    stats('<strong>'+escapeHTML(q.received)+'</strong>')+
    stats('<strong>'+escapeHTML(q.pending)+'</strong>')+
    '<td><input class="finManualQty" '+(category==='aluminio'?
     'type="text" inputmode="numeric" pattern="[0-9]*" maxlength="7" title="Somente barras inteiras: 1, 2, 3..."':
     'type="number" inputmode="decimal" min="0.001" step="0.001"')+
    ' required placeholder="Qtd." value="'+escapeHTML(row.quantidade)+'" aria-label="Recebendo agora '+(i+1)+'"></td>'+
    '<td class="hint">'+escapeHTML(unit||'—')+'</td>'+
    '<td><input class="finManualSubtotal" type="text" inputmode="decimal" required placeholder="R$ 0,00" value="'+escapeHTML(row.valor)+'" aria-label="Subtotal do material '+(i+1)+'"></td>'+
    '<td><button class="btn secondary" type="button" data-manual-remove="'+i+'">Remover</button></td></tr>';
  }).join('');
  const message=byId('finManualDetail');
  if(message)message.textContent=category==='aluminio'?
   'O comprimento é preenchido conforme o plano de barras importado do CEM e pode ser alterado se a compra tiver outro tamanho. Quando aparecer "Plano de barras não importado", atualize somente Perfis em "Importar arquivo técnico" pelo menu, sem excluir a obra.':
   'Necessário, recebido e falta receber são calculados na unidade de cada acessório, quando compatível.';
  updateSum();
 }

 function miscReset(){
  miscRows=[{descricao:'',quantidade:'',unidade:'PC',valor:''}];
  miscRender();
 }
 function miscRender(){
  const body=byId('finMiscRows');if(!body)return;
  const units=['PC','UN','M2','MT','KG','CX','CJ','PR'];
  body.innerHTML=miscRows.map((m,i)=>'<tr data-misc-row="'+i+'">'+
   '<td><input class="finMiscDescription" required maxlength="500" placeholder="Descrição do vidro ou insumo" value="'+escapeHTML(m.descricao)+'"></td>'+
   '<td><input class="finMiscQty" type="number" inputmode="decimal" min="0.001" max="1000000" step="0.001" required placeholder="Qtd." value="'+escapeHTML(m.quantidade)+'"></td>'+
   '<td><select class="finMiscUnit">'+units.map(u=>'<option value="'+u+'"'+(u===m.unidade?' selected':'')+'>'+(u==='M2'?'m²':u)+'</option>').join('')+'</select></td>'+
   '<td><input class="finMiscAmount" inputmode="decimal" required placeholder="R$ 0,00" value="'+escapeHTML(m.valor)+'"></td>'+
   '<td><button type="button" class="btn secondary" data-misc-remove="'+i+'">Remover</button></td>'+
   '</tr>').join('');
  miscUpdateSum();
 }
 function miscUpdateSum(){
  const centsList=miscRows.map(x=>cents(x.valor));
  const total=centsList.reduce((a,v)=>a+(v||0),0);
  byId('finCostTotal').value=total>0?finMoney(total/100):'';
  byId('finMiscSum').textContent='Total da nota: '+finMoney(total/100)+
   (centsList.every(v=>v!==null)&&total>0?' · Soma conferida':' · Preencha as linhas');
 }
 function miscNormalized(){
  if(!miscRows.length||miscRows.length>100)throw Error('Informe de 1 a 100 itens.');
  return miscRows.map((r,i)=>{
   const descricao=r.descricao.trim(),quantidade=Number(r.quantidade),centavos=cents(r.valor);
   if(descricao.length<2||descricao.length>500)throw Error('Descrição inválida no item '+(i+1)+'.');
   if(!String(r.quantidade).trim()||!Number.isFinite(quantidade)||quantidade<=0||quantidade>1000000||
    Math.abs(quantidade*1000-Math.round(quantidade*1000))>0.00001)
    throw Error('Quantidade inválida no item '+(i+1)+'.');
   if(!['PC','UN','M2','MT','KG','CX','CJ','PR'].includes(r.unidade))throw Error('Unidade inválida no item '+(i+1)+'.');
   if(centavos===null||centavos<0)throw Error('Subtotal inválido no item '+(i+1)+'.');
   const total=centavos/100;
   return {codigo:'',descricao,unidade:r.unidade,quantidade,
     valor_unitario:Math.round(total/quantidade*1e6)/1e6,valor_total:total};
  });
 }
 function updateSum(){
  const totalField=byId('finCostTotal');
  const valores=rows.map(r=>cents(r.valor));
  const soma=valores.reduce((sum,n)=>sum+(n??0),0);
  if(stockCategory()){
   // A nota de materiais é a soma dos itens, não um segundo valor digitado.
   // Recalcular a cada edição, inclusão e remoção de linha.
   totalField.value=soma>0?finMoney(soma/100):'';
  }
  const nota=cents(totalField.value);
  const completo=valores.every(n=>n!==null);
  const confere=nota!==null&&nota>0&&completo&&soma===nota;
  byId('finManualSum').textContent=
   'Total dos itens: '+finMoney(soma/100)+' · Valor da nota: '+finMoney((nota||0)/100)+
   (stockCategory()?(completo&&soma>0?' · Total atualizado automaticamente':
     !completo?' · Complete os valores dos materiais':''):
    nota!==null&&nota>0?(confere?' · Valores conferem':
     ' · Diferença: '+finMoney((nota-soma)/100)):'');
  byId('finManualSum').classList.toggle('finManualCorrect',confere);
 }
 function renderForm(){
  category=byId('finCostCategory').value;
  const hasStock=stockCategory();
  byId('finManualStockBlock').classList.toggle('hidden',!hasStock);
  byId('finMiscBlock').classList.toggle('hidden',hasStock);
  byId('finManualLocalLabel').classList.toggle('hidden',!hasStock);
  byId('finManualLocal').required=hasStock;
  byId('finCostVendor').required=true;
  byId('finCostDate').required=true;
  byId('finCostSubmit').textContent=hasStock?'Registrar nota e entrada no estoque':'Registrar itens e nota (sem entrada em estoque)';
  byId('finCostTotal').readOnly=true;
  byId('finCostTotal').title='Calculado automaticamente pela soma dos valores dos itens.';
  const list=hasStock?getMaterials():[];
  byId('finManualAdd').disabled=hasStock&&!list.length;
  byId('finCostSubmit').disabled=hasStock&&!list.length;
  byId('finManualHint').textContent=hasStock?
   (list.length?
    'Somente materiais cadastrados nesta obra aparecem na lista. Necessidade: quantitativos do CEM. Já recebido: entradas físicas registradas por nota. Confirme quantidade e galpão antes de gravar.':
    'Esta obra não possui materiais desta categoria vinculados à sua lista técnica. Não é possível dar entrada por este formulário.'):
   'Vidros e outros insumos são discriminados na nota, sem saldo físico automático enquanto não existir catálogo próprio destes materiais.';
  if(hasStock)resetRows();else miscReset();
 }
 function hojeLocalISO(){
  const now=new Date(),pad=n=>String(n).padStart(2,'0');
  return now.getFullYear()+'-'+pad(now.getMonth()+1)+'-'+pad(now.getDate());
 }
 function preencherFornecedores(prefer=''){
  const select=byId('finCostVendor'),old=prefer||select.value;
  select.innerHTML='<option value="">Selecione o fornecedor</option>'+
   (finState?.fornecedores||[]).slice().sort((a,b)=>a.nome.localeCompare(b.nome,'pt-BR'))
    .map(f=>'<option value="'+escapeHTML(f.nome)+'">'+escapeHTML(f.nome)+'</option>').join('');
  if((finState?.fornecedores||[]).some(f=>f.nome===old))select.value=old;
 }
 function preencherGalpoes(prefer=''){
  const select=byId('finManualLocal'),old=prefer||select.value;
  select.innerHTML='<option value="">Selecione o galpão</option>'+
   (finState?.galpoes||[]).slice().sort((a,b)=>a.localeCompare(b,'pt-BR'))
    .map(g=>'<option value="'+escapeHTML(g)+'">'+escapeHTML(g)+'</option>').join('');
  if((finState?.galpoes||[]).includes(old))select.value=old;
 }
 function initForm(){
  if(!finState)return;
  preencherFornecedores();preencherGalpoes();
  if(!byId('finCostDate').value)byId('finCostDate').value=hojeLocalISO();
  byId('finCostMessage').textContent='';
  renderForm();
 }
 let cadastroTipo=null;
 function cadastroAbrir(tipo){
  if(!finState||!isFullAdminUser())return;
  cadastroTipo=tipo;
  const box=byId('finRegistryPanel'),input=byId('finRegistryName');
  box.classList.remove('hidden');
  byId('finRegistryTitle').textContent=tipo==='fornecedor'?'Cadastrar fornecedor':'Cadastrar galpão';
  input.value='';input.maxLength=tipo==='fornecedor'?180:80;
  input.placeholder=tipo==='fornecedor'?'Nome ou razão social':'Nome do galpão';
  byId('finRegistryMessage').textContent='';
  input.focus();
 }
 function cadastroFechar(){
  cadastroTipo=null;
  byId('finRegistryPanel').classList.add('hidden');
  byId('finRegistryMessage').textContent='';
 }
 async function cadastroSalvar(){
  if(!finState||!isFullAdminUser()||!cadastroTipo)return;
  const tipo=cadastroTipo,button=byId('finRegistrySave'),msg=byId('finRegistryMessage');
  const nome=String(byId('finRegistryName').value||'').trim()
   .replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const max=tipo==='fornecedor'?180:80;
  if(nome.length<3||nome.length>max){
   msg.textContent='Informe um nome entre 3 e '+max+' caracteres.';return;
  }
  if((tipo==='fornecedor'&&(finState.fornecedores||[]).some(f=>f.nome===nome))||
     (tipo==='galpao'&&(finState.galpoes||[]).includes(nome))){
   msg.textContent='Este cadastro já existe. Selecione na lista.';return;
  }
  button.disabled=true;
  try{
   await ensureSession();
   if(tipo==='fornecedor'){
    await request('/rest/v1/ew_fornecedores',{method:'POST',token:session.access_token,
     body:{empresa_id:currentCompany.id,nome,criado_por:currentUser.id}});
    finState.fornecedores.push({nome});
    preencherFornecedores(nome);
   }else{
    const novo=await cadastrarGalpaoEmpresa(nome);
    finState.galpoes.push(novo);
    preencherGalpoes(novo);
   }
   cadastroFechar();
   byId('finCostMessage').textContent=(tipo==='fornecedor'?'Fornecedor ':'Galpão ')+
    nome+' cadastrado e selecionado.';
  }catch(e){msg.textContent='Não foi possível cadastrar: '+e.message;}
  finally{button.disabled=false;}
 }
 function normalizeItem(row,i){
  const mat=getMaterials().find(m=>m.id===row.material);
  const variacao=getVariations(row.material).find(v=>v.id===row.variacao);
  if(!mat||!variacao)throw new Error('Escolha material e cor/variação na linha '+(i+1)+'.');
  const rawQty=String(row.quantidade).trim(),qty=Number(rawQty);
  const amount=cents(row.valor);
  if(category==='aluminio'&&!isNaturalBarQuantity(rawQty))
   throw new Error('Quantidade de barras: informe somente números inteiros positivos (1, 2, 3...).');
  if(!rawQty||!Number.isFinite(qty)||qty<=0||qty>1000000||
    Math.abs(qty*1000-Math.round(qty*1000))>0.00001)
   throw new Error('Quantidade física inválida na linha '+(i+1)+'.');
  if(amount===null||amount<0)throw new Error('Subtotal do material inválido na linha '+(i+1)+'.');
  const length=category==='aluminio'?Number(row.comprimento):null;
  if(category==='aluminio'){
   if(!plannedBarRows(row.variacao).length)
    throw new Error('Plano de barras deste perfil não importado para a obra. Use "Importar arquivo técnico" no menu e atualize somente Perfis com o ZIP original.');
   if(!Number.isSafeInteger(qty))
    throw new Error('Perfis exigem quantidades inteiras de barras na linha '+(i+1)+'.');
   if(!String(row.comprimento).trim()||!Number.isSafeInteger(length)||length<100||length>20000)
    throw new Error('Informe o comprimento real da barra entre 100 e 20.000 mm (linha '+(i+1)+').');
  }
  return {variacao_id:variacao.id,quantidade:qty,comprimento_mm:length,valor_total:amount/100};
 }
 async function submit(event){
  event.preventDefault();
  if(!finState||!(isFullAdminUser()||isAlmoxarife()))return;
  const el=byId('finCostMessage'),btn=byId('finCostSubmit');
  const note=cents(byId('finCostTotal').value);
  if(note===null||note<=0){el.textContent='Informe o valor total da nota com centavos válidos.';return;}
  const number=byId('finCostNumber').value.trim(),vendor=byId('finCostVendor').value.trim();
  if(stockCategory()&&(!vendor||!(finState.fornecedores||[]).some(f=>f.nome===vendor))){
   el.textContent='Selecione um fornecedor cadastrado antes de registrar a nota.';return;
  }
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
   }else{
    if(!vendor||!(finState.fornecedores||[]).some(f=>f.nome===vendor))
     throw Error('Selecione um fornecedor cadastrado.');
    items=miscNormalized();
    if(items.reduce((a,i)=>a+Math.round(i.valor_total*100),0)!==note)
     throw Error('A soma dos itens não confere com o valor total da nota.');
   }
  }catch(e){el.textContent=e.message;return;}
  const medidasForaPlano=hasStock&&category==='aluminio'?rows.filter(r=>
   !plannedBarRows(r.variacao).some(x=>Number(x.comprimento_mm)===Number(r.comprimento))):[];
  const avisoMedidas=medidasForaPlano.length?'\n\nATENÇÃO: '+medidasForaPlano.length+
   ' item(ns) têm comprimento diferente do plano de barras do CEM, ou não possuem plano importado. '+
   'O estoque receberá o comprimento real informado, sem alterar o planejamento original.':'';
  const text='Registrar nota '+number+' no valor de '+finMoney(note/100)+' para esta obra?'+
   (hasStock?'\n\nIsto dará entrada IMEDIATA de '+items.length+' material(is) no estoque da obra, galpão '+location+'.':
    '\n\nEsta operação registrará somente a despesa; NÃO movimentará estoque.')+
   avisoMedidas+'\n\nConfirme apenas itens e quantidades realmente recebidos.';
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
    response=await request(isAlmoxarife()?
    '/rest/v1/rpc/ew_receber_materiais_almox':'/rest/v1/rpc/ew_registrar_recebimento_manual_financeiro',{
     method:'POST',token:session.access_token,timeoutMs:120000,
     body:{...common,p_local_estoque:location,p_itens:items}
    });
   }else{
    response=await request(isAlmoxarife()?
     '/rest/v1/rpc/ew_receber_despesa_com_itens_almox':'/rest/v1/rpc/ew_registrar_despesa_financeira',{
     method:'POST',token:session.access_token,timeoutMs:90000,
     body:isAlmoxarife()?{...common,p_itens:items}:{...common,p_origem:'manual',p_chave_nfe:null,p_itens:items}
    });
   }
   const repeated=Boolean(response?.ja_registrado);
   finCostOpId=null;
   await carregarRecebimento();
   byId('recebimentoMessage').textContent=repeated?
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
 // Obras com orçamento por níveis usam uma única tabela financeira. Obras
 // anteriores preservam o resumo tradicional de categorias.
 const oldResumo=finRenderResumo;
 finRenderResumo=function(){
  if(!finState)return;
  const state=finState,levels=state.orcamentoNiveis||[];
  if(!levels.length){
   oldResumo();
   initForm();
   return;
  }
  const faturas=new Map(),despesas=new Map();
  for(const f of state.faturas)if(f.status==='emitido')
   faturas.set(f.categoria,(faturas.get(f.categoria)||0)+Number(f.valor_total||0));
  for(const d of state.despesas)if(d.status==='aprovada')
   despesas.set(d.categoria,(despesas.get(d.categoria)||0)+Number(d.valor||0));
  const totalF=levels.filter(n=>n.faturar).reduce((sum,n)=>sum+Number(n.valor||0),0);
  const realizado=[...faturas.values()].reduce((sum,v)=>sum+v,0);
  const gastos=[...despesas.values()].reduce((sum,v)=>sum+v,0);
  byId('finTotals').innerHTML='<span><strong>Valor da obra: '+finMoney(state.orcamento.valor_total)+'</strong></span>'+
   '<span><strong>Faturado: '+finMoney(realizado)+'</strong></span>'+
   '<span><strong>A faturar: '+finMoney(Math.max(0,totalF-realizado))+'</strong></span>'+
   '<span><strong>Gastos registrados: '+finMoney(gastos)+'</strong></span>';

  // Um grupo interno pode reunir vários níveis personalizados. Sem vínculo
  // do lançamento ao nível específico, não podemos atribuir gasto/receita
  // arbitrariamente a uma linha (nem deduzi-lo duas vezes).
  const counts=new Map();
  for(const n of levels){
   const key=String(n.categoria_base)+'|'+(n.faturar?'receita':'gasto');
   counts.set(key,(counts.get(key)||0)+1);
  }
  let naoDiscriminados=false;
  const rows=levels.map(n=>{
   const base=String(n.categoria_base||'');
   const key=base+'|'+(n.faturar?'receita':'gasto');
   const canBill=n.faturar&&['fabricacao','instalacao'].includes(base);
   const canSpend=!n.faturar&&['aluminio','acessorios','vidros','outros'].includes(base);
   const known=(counts.get(key)===1)&&(n.faturar||canSpend);
   // Faturamento de outros níveis ainda não pode ser lançado no EWGEST;
   // exibir zero registrado, distinguindo previsão de emissão disponível.
   const real=known?(n.faturar?(faturas.get(base)||0):(despesas.get(base)||0)):null;
   const previsto=Number(n.valor||0),restante=real===null?null:
    (Math.round(previsto*100)-Math.round(real*100))/100;
   if(real===null)naoDiscriminados=true;
   const finalidade=n.faturar?(
    canBill?'Faturamento':'Faturamento (emissão pendente)'
   ):'Controle de gastos';
   return '<tr><td>'+escapeHTML(n.nivel_nome)+'</td>'+
    '<td>'+escapeHTML(n.empresa_faturamento_nome)+'</td>'+
    '<td align="right">'+finMoney(previsto)+'</td>'+
    '<td align="right">'+Number(n.percentual||0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2})+'%</td>'+
    '<td>'+finalidade+'</td>'+
    '<td align="right">'+(real===null?'—':finMoney(real))+'</td>'+
    '<td align="right"'+(restante!==null&&restante<0?' class="finNegative"':'')+'>'+
    (restante===null?'—':finMoney(restante))+'</td></tr>';
  }).join('');
  byId('finSummary').innerHTML=
   '<h3>Orçamento por níveis e acompanhamento financeiro</h3>'+
   '<div class="finTableWrap"><table class="finTable"><thead><tr>'+
   '<th>Nível</th><th>Empresa</th><th align="right">Previsto</th>'+
   '<th align="right">% da obra</th><th>Finalidade</th>'+
   '<th align="right">Realizado</th><th align="right">Restante</th>'+
   '</tr></thead><tbody>'+rows+'</tbody></table></div>'+
   '<p class="hint">Realizado considera apenas despesas aprovadas e faturamentos emitidos registrados no EWGEST. '+
   'Romaneios não contabilizam faturamento. Níveis de faturamento fora de fabricação/instalação '+
   'ainda não podem ter nota emitida por este módulo.'+
   (naoDiscriminados?' Quando vários níveis compartilham uma categoria interna ou não possuem categoria '+
    'de lançamento correspondente, seus valores realizados não são distribuídos automaticamente (—).':'')+
   '</p>';
  initForm();
 };
 byId('finExpenseForm').removeEventListener('submit',finRegistrarCusto);
 if(typeof window!=='undefined')window.ewRecebimentoManualInit=initForm;
 byId('finExpenseForm').addEventListener('submit',submit);
 byId('finCostCategory').addEventListener('change',()=>{
  category=byId('finCostCategory').value;
  renderForm();
 });
 byId('finCostTotal').addEventListener('blur',moneyInput);
 byId('finCostTotal').addEventListener('input',updateSum);
 byId('finSupplierAdd').addEventListener('click',()=>cadastroAbrir('fornecedor'));
 byId('finWarehouseAdd').addEventListener('click',()=>cadastroAbrir('galpao'));
 byId('finRegistrySave').addEventListener('click',cadastroSalvar);
 byId('finRegistryCancel').addEventListener('click',cadastroFechar);
 byId('finManualAdd').addEventListener('click',()=>{
  if(rows.length>=100){byId('finCostMessage').textContent='Limite de 100 materiais por nota.';return;}
  rows.push({material:'',variacao:'',comprimento:'',quantidade:'',valor:''});renderRows();
 });

 byId('finMiscAdd').addEventListener('click',()=>{
  if(miscRows.length>=100){byId('finCostMessage').textContent='Limite de 100 itens por nota.';return;}
  miscRows.push({descricao:'',quantidade:'',unidade:'PC',valor:''});miscRender();
 });
 byId('finMiscRows').addEventListener('input',event=>{
  const tr=event.target.closest('[data-misc-row]');if(!tr)return;
  const item=miscRows[Number(tr.dataset.miscRow)];if(!item)return;
  if(event.target.matches('.finMiscDescription'))item.descricao=event.target.value;
  if(event.target.matches('.finMiscQty'))item.quantidade=event.target.value;
  if(event.target.matches('.finMiscAmount')){item.valor=event.target.value;miscUpdateSum();}
 });
 byId('finMiscRows').addEventListener('change',event=>{
  const tr=event.target.closest('[data-misc-row]');if(!tr)return;
  const item=miscRows[Number(tr.dataset.miscRow)];
  if(item&&event.target.matches('.finMiscUnit'))item.unidade=event.target.value;
 });
 byId('finMiscRows').addEventListener('focusout',event=>{
  const tr=event.target.closest('[data-misc-row]');
  if(!tr||!event.target.matches('.finMiscAmount'))return;
  moneyInput(event);
  miscRows[Number(tr.dataset.miscRow)].valor=event.target.value;miscUpdateSum();
 });
 byId('finMiscRows').addEventListener('click',event=>{
  const btn=event.target.closest('[data-misc-remove]');if(!btn)return;
  miscRows.splice(Number(btn.dataset.miscRemove),1);
  if(!miscRows.length)miscRows=[{descricao:'',quantidade:'',unidade:'PC',valor:''}];
  miscRender();
 });
 byId('finManualRows').addEventListener('change',event=>{
  const tr=event.target.closest('[data-manual-row]');if(!tr)return;
  const i=Number(tr.dataset.manualRow),r=rows[i];if(!r)return;
  if(event.target.matches('.finManualMaterial')){
   const optionKey=event.target.value;
   const selected=selectOptions().find(x=>x.value===optionKey);
   r.material=selected?.mat.id||'';
   r.variacao=selected?.v.id||'';
   r.selectionKey=selected?.value||'';
   r.comprimento=selected?.length?String(selected.length):'';
   r.quantidade='';r.valor='';
   renderRows();
  }
 });
 byId('finManualRows').addEventListener('input',event=>{
  const tr=event.target.closest('[data-manual-row]');if(!tr)return;
  const r=rows[Number(tr.dataset.manualRow)];if(!r)return;
  if(event.target.matches('.finManualQty')){
   const value=event.target.value;
   if(category==='aluminio'&&!/^[0-9]*$/.test(value)){
    // Não transformar "3,001" em 3001 silenciosamente:
    // restaurar o último valor válido e orientar o usuário.
    event.target.value=r.quantidade||'';
    byId('finCostMessage').textContent=
     'Quantidade de barras: use apenas números inteiros positivos (1, 2, 3...).';
    return;
   }
   r.quantidade=value;
  }
  if(event.target.matches('.finManualLength')){
   r.comprimento=event.target.value;
   // Atualiza os indicadores sem recriar o campo durante a digitação.
   const q=quantityData(r),cells=tr.querySelectorAll('.finManualStat strong');
   if(cells.length===3){
    cells[0].textContent=q.needed;cells[1].textContent=q.received;
    cells[2].textContent=q.pending;
   }
   const length=Number(r.comprimento);
   const planned=r.comprimento.trim()&&Number.isSafeInteger(length)&&
    plannedBarRows(r.variacao).some(x=>Number(x.comprimento_mm)===length);
   const hint=tr.querySelector('.finManualLengthHint');
   if(hint)hint.textContent=planned?'Medida do CEM':
    r.comprimento.trim()?'Fora do plano do CEM':'Informe a medida';
  }
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
