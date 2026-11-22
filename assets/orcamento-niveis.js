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
 // Formatação apenas visual: o servidor continua recebendo valores numéricos em R$.
 // Números inteiros digitados significam reais: 183200 -> R$ 183.200,00.
 function moedaPartes(entrada){
  const bruto=String(entrada??'');
  const temPrefixo=/^\s*R\$\s*/i.test(bruto);
  const texto=bruto.replace(/^\s*R\$\s*/i,'').replace(/\s/g,'');
  if(!texto||!/^[\d.,]+$/.test(texto))return null;
  let inteira=texto,fracao='',decimal=false;
  if(texto.includes(',')){
   // Padrão BR: apenas a vírgula separa centavos. Pontos são milhares.
   if((texto.match(/,/g)||[]).length!==1)return null;
   [inteira,fracao]=texto.split(',');
   decimal=true;
   if(!/^\d{0,2}$/.test(fracao))return null;
  }else if(!temPrefixo&&/^\d{4,}\.\d{1,2}$/.test(texto)){
   // Aceita colagem de valor externo como 2500.75 sem confundir o
   // ponto de milhar que a própria máscara gera enquanto se digita.
   const pos=texto.lastIndexOf('.');
   inteira=texto.slice(0,pos);
   fracao=texto.slice(pos+1);
   decimal=true;
  }
  // Durante a digitação, o último grupo de milhares pode estar incompleto.
  // Exemplo: R$ 1.8320 deve ser interpretado como 18320 reais, e não
  // ser rejeitado ou convertido para 1 real e 8320 centavos.
  if(inteira!==''&&!/^\d+(?:\.\d+)*$/.test(inteira))return null;
  const digitos=(inteira.replaceAll('.','')||'0').replace(/^0+(?=\d)/,'');
  if(digitos.length>12)return null;
  return {inteira:digitos,fracao,decimal};
 }
 function moedaCentavos(entrada){
  const partes=moedaPartes(entrada);
  if(!partes)return null;
  const centavos=Number(partes.inteira)*100+Number(partes.fracao.padEnd(2,'0'));
  return Number.isSafeInteger(centavos)?centavos:null;
 }
 function moedaExibir(entrada,completarCentavos=false){
  const partes=moedaPartes(entrada);
  if(!partes)return String(entrada??'').replace(/^\s*R\$\s*$/i,'');
  const milhar=partes.inteira.replace(/\B(?=(\d{3})+(?!\d))/g,'.');
  return 'R$ '+milhar+(completarCentavos?
   ','+partes.fracao.padEnd(2,'0'):
   partes.decimal?','+partes.fracao:'');
 }
 function moedaMascaraAoDigitar(input){
  const antes=input.value,pos=input.selectionStart??antes.length;
  const esquerda=antes.slice(0,pos);
  const quantidade=(esquerda.match(/\d/g)||[]).length;
  const depois=moedaExibir(antes);
  if(antes===depois)return;
  input.value=depois;
  if(!depois)return;
  let novoCursor=depois.startsWith('R$ ')?3:0,contagem=0;
  if(quantidade>0){
   for(let i=novoCursor;i<depois.length;i++){
    if(/\d/.test(depois[i]))contagem++;
    if(contagem===quantidade){novoCursor=i+1;break;}
   }
   if(contagem<quantidade)novoCursor=depois.length;
  }
  if(esquerda.includes(',')&&depois.includes(','))
   novoCursor=Math.max(novoCursor,depois.indexOf(',')+1);
  input.setSelectionRange(novoCursor,novoCursor);
 }
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
 function normalizarValorTotalPreenchido(){
  const campo=node('cemQuoteTotal');
  // Formulários restaurados pelo navegador nem sempre disparam o evento input.
  // Só formatar automaticamente se o usuário não estiver editando o campo.
  if(campo.value.trim()&&document.activeElement!==campo)
   campo.value=moedaExibir(campo.value,true);
 }
 function somaAtualizar(){
  normalizarValorTotalPreenchido();
  const totalCentavos=moedaCentavos(node('cemQuoteTotal').value)??0;
  let cents=0;
  for(let i=0;i<linhas.length;i++){
   const valorCentavos=moedaCentavos(linhas[i].valor);
   if(valorCentavos!==null)cents+=valorCentavos;
   const row=node('cemQuoteRows').querySelector('[data-budget-index="'+i+'"]');
   const percent=row?.querySelector('[data-budget-percent]');
   if(percent)percent.value=totalCentavos>0&&valorCentavos!==null?
    (valorCentavos/totalCentavos*100).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2})+'%':'—';
  }
  const diff=totalCentavos-cents;
  node('cemQuoteSoma').textContent='Soma dos níveis: '+dinheiro(cents/100)+
   ' · Valor total: '+dinheiro(totalCentavos/100)+(totalCentavos>0?
   (diff===0?' · 100% conferido':' · Diferença: '+dinheiro(diff/100)):'');
  node('cemQuoteSoma').classList.toggle('finNegative',totalCentavos>0&&diff!==0);
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
    '<td><input type="text" inputmode="decimal" autocomplete="off" required data-budget-field="valor" aria-label="Valor do nível '+(i+1)+' em reais" placeholder="R$ 0,00" value="'+escapeHTML(x.valor)+'"></td>'+
    '<td><input readonly data-budget-percent aria-label="Percentual do nível '+(i+1)+'"></td>'+
    '<td><select required data-budget-field="empresa" aria-label="Empresa da linha '+(i+1)+'">'+empresas+'</select></td>'+
    '<td><input type="checkbox" data-budget-field="faturar" aria-label="Este nível é para faturamento"'+(x.faturar?' checked':'')+'></td>'+
    '<td><button type="button" class="btn secondary" data-budget-remove="'+i+'">Remover</button></td></tr>';
  }).join('');
  somaAtualizar();
 }
 function adicionarLinha(nivel='',empresa=''){
  if(linhas.length>=100){node('cemQuoteError').textContent='Limite de 100 níveis por obra.';return;}
  linhas.push({nivel,empresa:empresa||'',valor:'',faturar:false});
  render();
 }
 function validar(){
  if(!pronto)throw new Error('Ainda não foi possível carregar os cadastros.');
  const raw=node('cemQuoteTotal').value.trim(),totalCentavos=moedaCentavos(raw);
  if(!raw||totalCentavos===null||totalCentavos<=0)
   throw new Error('Valor total inválido. Informe um valor em reais com até duas casas decimais.');
  if(!linhas.length)throw new Error('Adicione ao menos um nível.');
  const niveis=linhas.map((x,i)=>{
   const cat=catalogoNiveis.find(n=>n.nome===x.nivel),empresa=catalogoEmpresas.find(n=>n===x.empresa);
   if(!cat||!empresa)throw new Error('Escolha nível e empresa na linha '+(i+1)+'.');
   const rawValor=String(x.valor).trim(),valorCentavos=moedaCentavos(rawValor);
   if(!rawValor||valorCentavos===null)
    throw new Error('Informe um valor válido na linha '+(i+1)+'.');
   return {nivel:cat.nome,categoria_base:cat.categoria_base,empresa_faturamento:empresa,
    valor:valorCentavos/100,faturar:Boolean(x.faturar)};
  });
  const cents=niveis.reduce((s,x)=>s+Math.round(x.valor*100),0);
  if(cents!==totalCentavos)throw new Error('Os valores dos níveis devem somar exatamente 100% da obra.');
  return {valor_total:totalCentavos/100,niveis};
 }
 const oldQuoteSoma=cemQuoteSomaAtualizar;
 node('cemQuoteForm').querySelectorAll('input').forEach(x=>x.removeEventListener('input',oldQuoteSoma));
 const oldQuoteClose=cemQuoteFechar;
 node('cemQuoteCancel').removeEventListener('click',oldQuoteClose);
 const oldQuoteSubmit=cemQuoteConfirmar;
 node('cemQuoteForm').removeEventListener('submit',oldQuoteSubmit);
 cemQuoteSomaAtualizar=somaAtualizar;
 cemQuoteValidar=validar;
 cemQuoteFechar=function(){
  node('cemQuoteOverlay').classList.add('hidden');
  if(cemParsed){cemParsed.confirmacaoInicialFeita=false;cemParsed.orcamentoDraft=null;cemParsed.precificacaoDraft=null;}
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
   const fabricacao=values.niveis.filter(x=>x.categoria_base==='fabricacao').reduce((s,x)=>s+Math.round(x.valor*100),0);
   const instalacao=values.niveis.filter(x=>x.categoria_base==='instalacao').reduce((s,x)=>s+Math.round(x.valor*100),0);
   if(fabricacao+instalacao>0){
    if(!window.ewPrecificacaoImportacao?.abrir)
     throw new Error('A etapa de precificação não foi carregada. Atualize a página antes de importar.');
    r.orcamentoDraft=values;r.precificacaoDraft=null;
    node('cemQuoteError').textContent='';
    node('cemQuoteOverlay').classList.add('hidden');
    window.ewPrecificacaoImportacao.abrir(r,values,async(draft)=>{
     r.precificacaoDraft=draft;r.confirmacaoInicialFeita=true;
     await cemImportarSelecionados();
     if(!r.jaImportado)throw new Error(node('cemImportResult').textContent||'A gravação não foi confirmada.');
    });
    return;
   }
   // Para obras sem fabricação/instalação (ACM, manutenção etc.), manter o
   // fluxo legado sem exigir preços por m² fictícios.
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
 node('cemQuoteTotal').addEventListener('focus',event=>{
  // Quando o browser preenche o campo sem input/change, corrige ao receber foco.
  if(event.target.value.trim())event.target.value=moedaExibir(event.target.value,true);
 });
 node('cemQuoteTotal').addEventListener('input',event=>{
  moedaMascaraAoDigitar(event.target);
  somaAtualizar();
 });
 node('cemQuoteTotal').addEventListener('blur',event=>{
  event.target.value=moedaExibir(event.target.value,true);
  somaAtualizar();
 });
 node('cemQuoteCancel').addEventListener('click',cemQuoteFechar);
 node('cemQuoteForm').addEventListener('submit',cemQuoteConfirmar);
 node('cemQuoteRows').addEventListener('input',event=>{
  const row=event.target.closest('[data-budget-index]'),field=event.target.dataset.budgetField;
  if(!row||!field)return;
  const x=linhas[Number(row.dataset.budgetIndex)];if(!x)return;
  if(field==='valor')moedaMascaraAoDigitar(event.target);
  x[field]=field==='faturar'?event.target.checked:event.target.value;
  somaAtualizar();
 });
 node('cemQuoteRows').addEventListener('focusout',event=>{
  const el=event.target,row=el.closest('[data-budget-index]');
  if(!row||el.dataset.budgetField!=='valor')return;
  el.value=moedaExibir(el.value,true);
  const item=linhas[Number(row.dataset.budgetIndex)];
  if(item)item.valor=el.value;
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
  if(r&&!r.obraExistente&&r.orcamentoDraft?.niveis&&!r.precificacaoDraft){
   const temPreco=r.orcamentoDraft.niveis.some(x=>
    ['fabricacao','instalacao'].includes(x.categoria_base)&&Math.round(Number(x.valor)*100)>0);
   if(temPreco){
    if(!window.ewPrecificacaoImportacao?.abrir)
     throw new Error('Tela de precificação não disponível. Atualize a página.');
    window.ewPrecificacaoImportacao.abrir(r,r.orcamentoDraft,async(draft)=>{
     r.precificacaoDraft=draft;r.confirmacaoInicialFeita=true;
     await cemImportarSelecionados();
     if(!r.jaImportado)throw new Error(node('cemImportResult').textContent||'A gravação não foi confirmada.');
    });
    return;
   }
  }
  return oldImport();
 };
 node('cemCommit').addEventListener('click',cemImportarSelecionados);
 cemAtualizarBotao();
})();