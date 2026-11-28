/* EWGEST — financeiro empresarial, contas programadas e movimentos efetivos. */
(()=>{
'use strict';
const el=id=>document.getElementById(id);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const auth=()=>temPermissao('financeiro.consultar')&&temPermissao('relatorios.financeiros');
const can=(tipo,cancelar=false)=>auth()&&temPermissao(tipo==='PAGAR'?(cancelar?'financeiro.cancelar_despesas':'financeiro.despesas'):(cancelar?'financeiro.cancelar_faturamento':'financeiro.faturar'));
const canOrigin=o=>o!=='NOTA_ESTOQUE'||temPermissao('compras.consultar_valores');
const cents=n=>{const v=Number(n);if(n===null||n===''||!Number.isSafeInteger(v)||v<0)throw Error('Valor financeiro inválido.');return v;};
const money=n=>(cents(n)/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
function parseMoney(v){
 const s=String(v).trim().replace(',','.');
 if(!/^\d{1,12}(?:\.\d{1,2})?$/.test(s))throw Error('Informe o valor com até duas casas decimais.');
 const [a,b='']=s.split('.'),n=Number(a)*100+Number(b.padEnd(2,'0'));
 if(!Number.isSafeInteger(n)||n<=0||n>100000000000000)throw Error('Valor fora do limite permitido.');
 return n;
}
let seq=0,state=null,busy=false,ops=new Map(),scope=null;
const live=()=>auth()&&currentCompany?.id&&session&&!el('financeiroEmpresa').classList.contains('hidden');
const valid=(n,id,uid)=>n===seq&&live()&&currentCompany.id===id&&currentUser?.id===uid;
function limpar(){seq++;state=null;scope=null;el('corpConteudo').replaceChildren();el('corpStatus').textContent='';}
function table(h,rows){return rows.length?'<div class="finTableWrap"><table class="finTable"><thead><tr>'+h.map(x=>'<th>'+esc(x)+'</th>').join('')+'</tr></thead><tbody>'+rows.join('')+'</tbody></table></div>':'<p class="hint">Nenhum registro.</p>';}
const cells=a=>'<tr>'+a.map(x=>'<td>'+esc(x)+'</td>').join('')+'</tr>';
const option=(v,l)=>'<option value="'+esc(v)+'">'+esc(l)+'</option>';
function kpi(l,v){return '<div class="stat"><div class="label">'+esc(l)+'</div><div class="number" style="font-size:clamp(16px,2vw,23px);overflow-wrap:anywhere">'+esc(v)+'</div></div>';}
function validate(r){
 if(!r||!Array.isArray(r.titulos)||!Array.isArray(r.documentos)||!Array.isArray(r.centros)||!Array.isArray(r.caixa_centros)||typeof r.escopo_completo!=='boolean')throw Error('Consulta incompleta.');
 for(const k of ['a_pagar_centavos','a_receber_centavos','vencido_pagar_centavos','vencido_receber_centavos','entradas_centavos','saidas_centavos','origens_pendentes','documentos_sem_programacao','titulos_total'])cents(r[k]);
 for(const t of r.titulos){if(!['PAGAR','RECEBER'].includes(t.tipo)||!Array.isArray(t.baixas)||cents(t.valor_centavos)!==cents(t.baixado_centavos)+cents(t.saldo_centavos)||!canOrigin(t.origem_tipo))throw Error('Título inconsistente.');}
 return r;
}
const dreClasses=Object.freeze({RECEITA_OPERACIONAL:'Receita operacional complementar',OUTRAS_RECEITAS:'Outras receitas',DEDUCOES:'Impostos e deduções sobre receita',CUSTO_MAO_OBRA:'Mão de obra reconhecida no resultado',CUSTO_INDIRETO:'Custos indiretos reconhecidos no resultado',CUSTO_SERVICOS:'Serviços e custos diretos reconhecidos',DESPESA_ADMIN:'Despesas administrativas',DESPESA_COMERCIAL:'Despesas comerciais',DESPESA_FINANCEIRA:'Despesas financeiras',IMPOSTO_LUCRO:'Tributos sobre lucro',FORA_RESULTADO:'Fora do resultado (patrimonial, adiantamento etc.)'});
const drePermitido=()=>auth()&&temPermissao('estoque.consultar')&&temPermissao('compras.consultar_valores');
const dreEditar=()=>drePermitido()&&temPermissao('financeiro.despesas')&&temPermissao('financeiro.faturar');
const dreOpcoes=t=>Object.keys(dreClasses).filter(k=>k==='FORA_RESULTADO'||(t==='RECEBER'?['RECEITA_OPERACIONAL','OUTRAS_RECEITAS'].includes(k):!['RECEITA_OPERACIONAL','OUTRAS_RECEITAS'].includes(k)));
function dreCalcular(r){
 if(!r||!r.classes||Array.isArray(r.classes)||!['manuais','materiais','reconhecimentos'].every(k=>Array.isArray(r[k])))throw Error('DRE incompleta.');
 for(const [k,v] of Object.entries(r.classes)){if(!Object.hasOwn(dreClasses,k))throw Error('Classe desconhecida.');cents(v);}
 const v=k=>cents(r.classes[k]??0),fab=cents(r.fabricacao_centavos),inst=cents(r.instalacao_centavos),mat=cents(r.material_reconhecido_centavos);
 const receita=fab+inst+v('RECEITA_OPERACIONAL'),liquida=receita-v('DEDUCOES');
 const custos=mat+v('CUSTO_MAO_OBRA')+v('CUSTO_INDIRETO')+v('CUSTO_SERVICOS'),bruto=liquida-custos;
 const parcial=bruto-v('DESPESA_ADMIN')-v('DESPESA_COMERCIAL')-v('DESPESA_FINANCEIRA')+v('OUTRAS_RECEITAS')-v('IMPOSTO_LUCRO');
 const p=cents(r.manuais_pendentes),total=cents(r.manuais_total),pend=cents(r.reconhecimentos_pendentes),disp=cents(r.materiais_disponiveis_total);
 if(![receita,liquida,custos,bruto,parcial].every(Number.isSafeInteger)||p>total||r.manuais.length>total||r.materiais.length>disp||
 r.reconhecimentos.filter(x=>!x.valido).length!==pend||r.reconhecimentos.filter(x=>x.valido).reduce((a,x)=>a+cents(x.valor_centavos),0)!==mat)throw Error('Totais da DRE não conciliam.');
 return {v,fab,inst,mat,receita,liquida,custos,bruto,parcial,p,total,pend,disp};
}
const signed=n=>(n/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
function renderDre(r){
 if(!r)return '<div class="section panel"><h2>DRE gerencial</h2><p class="hint">Consulta indisponível neste momento. Atualize para tentar novamente.</p></div>';
 const d=dreCalcular(r),v=d.v;
 const rows=[
 ['Faturamento de fabricação',d.fab],['Faturamento de instalação',d.inst],['Receitas operacionais complementares',v('RECEITA_OPERACIONAL')],['Receita bruta registrada',d.receita],
 ['Deduções',-v('DEDUCOES')],['Receita líquida parcial',d.liquida],['Material reconhecido no resultado',-d.mat],['Mão de obra reconhecida',-v('CUSTO_MAO_OBRA')],['Custos indiretos reconhecidos',-v('CUSTO_INDIRETO')],['Serviços / custos diretos reconhecidos',-v('CUSTO_SERVICOS')],['Resultado bruto parcial',d.bruto],
 ['Despesas administrativas',-v('DESPESA_ADMIN')],['Despesas comerciais',-v('DESPESA_COMERCIAL')],['Despesas financeiras',-v('DESPESA_FINANCEIRA')],['Outras receitas',v('OUTRAS_RECEITAS')],['Tributos sobre lucro',-v('IMPOSTO_LUCRO')],['Resultado dos lançamentos classificados (parcial)',d.parcial]];
 const edit=dreEditar();
 const manuais=r.manuais.map(t=>'<tr><td>'+esc(t.descricao)+'<div class="hint">'+esc(t.categoria)+' · '+esc(t.centro_custo)+'</div></td><td>'+esc(t.competencia)+'</td><td>'+esc(money(t.valor_centavos))+'</td><td>'+esc(dreClasses[t.classe]||'A classificar')+(t.motivo?'<div class="hint">'+esc(t.motivo)+'</div>':'')+'</td><td>'+((edit&&(!t.versao||can(t.tipo,true)))?'<button type="button" class="btn secondary" data-dre-class="'+esc(t.id)+'">'+(t.versao?'Revisar':'Classificar')+'</button>':'')+'</td></tr>');
 const reconhecimentos=r.reconhecimentos.map(x=>'<tr><td>'+esc(x.competencia)+'</td><td>'+esc(x.fabrica||'A atribuir')+'</td><td>'+esc(money(x.valor_centavos))+'</td><td>'+esc(x.valido?'Reconhecido':'Origem pendente')+'</td><td>'+esc(x.motivo)+'</td><td>'+(temPermissao('financeiro.cancelar_despesas')?'<button type="button" class="btn secondary" data-dre-reverse="'+esc(x.id)+'">Estornar</button>':'')+'</td></tr>');
 return '<div class="section panel"><h2>DRE gerencial · competência</h2>'+
 '<p class="notice">Apuração parcial. Não é lucro líquido definitivo: ainda depende do encerramento contábil, custos e receitas não registrados, tributos e conciliação. Compras e caixa não entram automaticamente; materiais somente após reconhecimento vinculado ao faturamento. O período considera a competência, não a data de pagamento.</p>'+
 '<div class="stats" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))">'+kpi('Receita registrada',signed(d.receita))+kpi('Resultado parcial classificado',signed(d.parcial))+kpi('Contas a classificar',String(d.p))+kpi('Reconhecimentos em conferência',String(d.pend))+'</div>'+
 table(['Demonstração','Valor (R$)'],rows.map(([l,n])=>cells([l,signed(n)])))+
 '<h3>Classificação de contas manuais</h3><p class="hint">Classifique uma única vez por competência. Use Fora do resultado para valores patrimoniais e adiantamentos. Não inclua novamente documentos de obra ou compras já registrados. Custos de produção entram somente quando reconhecidos no resultado.</p>'+
 (d.total>r.manuais.length?'<p class="hint">Mostrando 500 contas. Reduza o período para localizar outras.</p>':'')+
 table(['Conta','Competência','Valor','Classe','Ação'],manuais)+'<div id="dreClassForm"></div>'+
 '<h3>Reconhecimento de materiais no resultado</h3><p class="hint">Escolha um consumo fiscalmente comprovado e o faturamento de fabricação correspondente. Reconheça apenas a parcela de material efetivamente incorporada ao custo vendido. O saldo é limitado pelo custo comprovado; não gera novo pagamento nem baixa de estoque. Lote sem código exige conferência manual.</p>'+
 '<p class="hint">'+d.disp+' consumo(s) com saldo e faturamento compatível no período.</p>'+
 (edit&&r.materiais.length?'<form id="dreMatForm"><div class="finFormRows"><label>Consumo<select id="dreMat">'+option('','Selecione')+r.materiais.map(m=>option(m.movimento_id,m.obra+' · '+(m.codigo||'Lote / sem código')+' · '+(m.fabrica||'Fábrica a atribuir')+' · '+m.data_consumo+' · saldo '+money(m.saldo_centavos))).join('')+'</select></label><label>Faturamento<select id="dreFatura" required><option value="">Selecione o consumo</option></select></label><label>Valor a reconhecer (R$)<input id="dreValor" inputmode="decimal" required></label><label>Justificativa<input id="dreMotivo" minlength="5" maxlength="400" required></label></div><button id="dreMatSubmit" class="btn primary" type="submit">Reconhecer material</button></form>':'')+
 '<h3>Reconhecimentos do período</h3>'+table(['Competência','Fábrica','Valor','Situação','Justificativa','Ação'],reconhecimentos)+'</div>';
}
function bindDre(){
 if(!state?.dre)return;
 const d=state.dre;
 for(const b of el('corpDre').querySelectorAll('[data-dre-class]'))b.addEventListener('click',()=>{
  const t=d.manuais.find(x=>x.id===b.dataset.dreClass);if(!t||!dreEditar()||(t.versao&&!can(t.tipo,true)))return;
  el('dreClassForm').innerHTML='<form class="section panel" id="dreClasseForm"><h3>'+esc(t.descricao)+'</h3><div class="finFormRows"><label>Classe<select id="dreClasse">'+option('','Selecione')+dreOpcoes(t.tipo).map(k=>option(k,dreClasses[k])).join('')+'</select></label><label>Justificativa<input id="dreClasseMotivo" minlength="5" maxlength="400" required></label></div><button id="dreClasseSubmit" class="btn primary" type="submit">Salvar classificação</button> <button id="dreClasseFechar" class="btn secondary" type="button">Cancelar</button></form>';
  el('dreClasse').value=t.classe||'';el('dreClasseFechar').addEventListener('click',()=>el('dreClassForm').replaceChildren());
  el('dreClasseForm').addEventListener('submit',ev=>{ev.preventDefault();const k=el('dreClasse').value,m=el('dreClasseMotivo').value.trim();if(!dreOpcoes(t.tipo).includes(k)||m.length<5){el('corpStatus').textContent='Informe classe e justificativa.';return;}
   if(window.confirm('Classificar '+money(t.valor_centavos)+' em '+dreClasses[k]+'? A competência do título será mantida.'))void gravar('ew_dre_classificar_titulo',{p_titulo_id:t.id,p_versao:t.versao,p_classe:k,p_motivo:m},el('dreClasseSubmit'),'Classificação registrada.');});
  el('dreClassForm').scrollIntoView({block:'nearest',behavior:'smooth'});
 });
 if(el('dreMatForm')){
  el('dreMat').addEventListener('change',()=>{
   const m=d.materiais.find(x=>x.movimento_id===el('dreMat').value);
   el('dreFatura').innerHTML=option('','Selecione')+(m?m.faturas.map(f=>option(f.id,f.numero+' · '+f.data)).join(''):'');
   el('dreValor').value=m?(cents(m.saldo_centavos)/100).toFixed(2):'';
  });
  el('dreMatForm').addEventListener('submit',ev=>{ev.preventDefault();try{
   const m=d.materiais.find(x=>x.movimento_id===el('dreMat').value),f=el('dreFatura').value,n=parseMoney(el('dreValor').value),motivo=el('dreMotivo').value.trim();
   if(!dreEditar()||!m||!m.faturas.some(x=>x.id===f)||n>cents(m.saldo_centavos)||motivo.length<5)throw Error('Confira consumo, documento, saldo e justificativa.');
   if(window.confirm('Reconhecer '+money(n)+' de material efetivamente vendido no resultado deste faturamento? Não altera o estoque nem o caixa.'))void gravar('ew_dre_reconhecer_material',{p_movimento_id:m.movimento_id,p_faturamento_id:f,p_valor_centavos:n,p_motivo:motivo},el('dreMatSubmit'),'Material reconhecido no resultado.');
  }catch(e){el('corpStatus').textContent=e.message;}});
 }
 for(const b of el('corpDre').querySelectorAll('[data-dre-reverse]'))b.addEventListener('click',()=>{
  if(!temPermissao('financeiro.cancelar_despesas'))return;
  const motivo=window.prompt('Motivo do estorno do reconhecimento (5 a 400 caracteres):');if(motivo===null)return;
  if(motivo.trim().length<5||motivo.length>400){el('corpStatus').textContent='Informe motivo válido.';return;}
  if(window.confirm('Estornar somente o reconhecimento de resultado? Estoque e caixa permanecem inalterados.'))void gravar('ew_dre_estornar_material',{p_id:b.dataset.dreReverse,p_motivo:motivo.trim()},b,'Reconhecimento estornado.');
 });
}
function rateioValidar(r){
 if(!r||!['titulos','liberacoes','rateios','fabrica','obras','itens'].every(k=>Array.isArray(r[k])))throw Error('Rateio incompleto.');
 const receita=cents(r.receita_centavos),material=cents(r.material_centavos),industrial=cents(r.industrial_classificado_centavos),rateado=cents(r.rateado_centavos),pend=cents(r.rateios_pendentes);
 if(rateado>industrial||r.rateios.filter(x=>!x.valido).length!==pend||r.rateios.filter(x=>x.valido).reduce((a,x)=>a+cents(x.valor_centavos),0)!==rateado)throw Error('Rateios não conciliam.');
 for(const lista of [r.fabrica,r.obras]){
  for(const [k,total] of [['receita_centavos',receita],['material_centavos',material],['rateio_centavos',rateado]])if(lista.reduce((a,x)=>a+cents(x[k]),0)!==total)throw Error('Totais de contribuição não conciliam.');
 }
 const itensTotal=cents(r.itens_total),titulosTotal=cents(r.titulos_total);
 if(r.itens.length>itensTotal||r.titulos.length>titulosTotal)throw Error('Quantidade de registros não concilia.');
 const completo=r.itens.length===itensTotal;
 for(const [k,total] of [['receita_centavos',receita],['material_centavos',material],['rateio_centavos',rateado]]){
  const subtotal=r.itens.reduce((a,x)=>a+cents(x[k]),0);
  if(!Number.isSafeInteger(subtotal)||subtotal>total||(completo&&subtotal!==total))throw Error('Totais por código não conciliam.');
 }
 for(const x of r.itens){const a=Number(x.area_faturada);if(x.area_faturada===null||x.area_faturada===''||!Number.isFinite(a)||a<0)throw Error('Área faturada inválida.');}
 const contribuicao=receita-material-rateado;
 if(!Number.isSafeInteger(contribuicao))throw Error('Contribuição fora do limite.');
 return {receita,material,industrial,rateado,pend,saldo:industrial-rateado,contribuicao,itensTotal,titulosTotal};
}
function renderRateio(r){
 if(!r)return '<div class="section panel"><h2>Custos industriais e rentabilidade</h2><p class="hint">Consulta indisponível neste momento.</p></div>';
 const d=rateioValidar(r),edit=dreEditar(),titles=r.titulos.filter(t=>cents(t.valor_centavos)>cents(t.usado_centavos));
 const resultado=x=>cents(x.receita_centavos)-cents(x.material_centavos)-cents(x.rateio_centavos);
 const vals=x=>[money(x.receita_centavos),money(x.material_centavos),money(x.rateio_centavos),signed(resultado(x))];
 const headers=['Local','Receita fabricação','Material reconhecido','Custos industriais rateados','Contribuição parcial'];
 const area=x=>{const n=Number(x);if(!Number.isFinite(n)||n<0)throw Error('Área inválida.');return n.toLocaleString('pt-BR',{maximumFractionDigits:6});};
 return '<div class="section panel"><h2>Custos industriais e rentabilidade</h2><p class="notice">Contribuição parcial de fabricação = receita de fabricação menos material reconhecido e custos industriais rateados. Não é lucro definitivo e não inclui instalação, impostos, despesas gerais nem custos sem atribuição. Rateio não cria despesa: o título já está na DRE.</p>'+
 '<div class="stats" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))">'+kpi('Custos industriais classificados',money(d.industrial))+kpi('Custos industriais rateados',money(d.rateado))+kpi('Custos industriais a atribuir',money(d.saldo))+kpi('Rateios em conferência',String(d.pend))+kpi('Contribuição parcial de fabricação',signed(d.contribuicao))+'</div>'+
 '<h3>Contribuição por fábrica</h3>'+table(headers,r.fabrica.map(x=>cells([x.fabrica||'A atribuir',...vals(x)])))+
 '<h3>Contribuição por obra</h3>'+table(headers,r.obras.map(x=>cells([x.obra+' · '+x.codigo,...vals(x)])))+
 '<h3>Custo reconhecido por código de esquadria</h3><p class="hint">Material e custos industriais apropriados ao resultado no período. O custo por m² faturado é parcial, não custo completo de uma unidade física. Lotes sem identificação permanecem separados.</p>'+
 (cents(r.itens_total)>r.itens.length?'<p class="hint">Exibindo até 500 códigos; totais abrangem todos.</p>':'')+
 table(['Obra','Código','Área faturada (m²)','Material reconhecido','Custos rateados','Custo reconhecido total','Custo parcial/m²','Contribuição parcial'],r.itens.map(x=>{
  const c=cents(x.material_centavos)+cents(x.rateio_centavos),a=Number(x.area_faturada);
  return cells([x.obra,x.codigo||'Lote / sem código',area(a),money(x.material_centavos),money(x.rateio_centavos),money(c),a>0&&c>0?signed(c/a):'—',signed(resultado(x))]);
 }))+
 '<h3>Ratear mão de obra e despesas industriais</h3><p class="hint">Classifique antes o título na DRE como mão de obra, custo indireto ou serviço. Selecione a liberação completa de uma esquadria e informe somente a parcela efetivamente apropriada. O saldo do título limita a soma dos rateios. A lista apresenta até 500 liberações recentes compatíveis com o mês da competência.</p>'+
 (d.titulosTotal>r.titulos.length?'<p class="hint">Lista de títulos limitada a 500 registros. Reduza o período para localizar outros.</p>':'')+
 (edit&&titles.length?'<form id="rateioForm"><div class="finFormRows"><label>Título de custo<select id="rateioTitulo">'+option('','Selecione')+titles.map(t=>option(t.id,t.descricao+' · '+t.centro_custo+' · '+t.competencia+' · saldo '+money(cents(t.valor_centavos)-cents(t.usado_centavos)))).join('')+'</select></label><label>Liberação<select id="rateioLiberacao" required><option value="">Selecione o título</option></select></label><label>Valor (R$)<input id="rateioValor" inputmode="decimal" required></label><label>Critério / justificativa<input id="rateioMotivo" minlength="5" maxlength="400" required placeholder="Ex.: horas trabalhadas nesta liberação"></label></div><button id="rateioSubmit" class="btn primary" type="submit">Registrar rateio</button></form>':'<p class="hint">Nenhum título com saldo disponível para rateio, ou acesso somente consulta.</p>')+
 '<h3>Histórico de rateios ativos</h3>'+table(['Obra','Esquadria','Fábrica','Competência','Classe','Valor','Situação / critério','Ação'],r.rateios.map(x=>'<tr>'+[x.obra||'Histórico',x.codigo||'Histórico',x.fabrica,x.competencia,dreClasses[x.classe]||x.classe,money(x.valor_centavos),(x.valido?'Apropriado':'Em conferência')+' · '+x.motivo].map(v=>'<td>'+esc(v)+'</td>').join('')+'<td>'+(temPermissao('financeiro.cancelar_despesas')?'<button type="button" class="btn secondary" data-rateio-reverse="'+esc(x.id)+'">Estornar</button>':'')+'</td></tr>'))+'</div>';
}
function bindRateio(){
 if(!state?.rateio||!el('corpRateio'))return;
 const r=state.rateio;
 if(el('rateioForm')){
  const elegiveis=t=>r.liberacoes.filter(l=>(!t.galpao_id||t.centro_custo.trim()===l.fabrica.trim())&&l.data_liberacao.slice(0,7)<=t.competencia.slice(0,7));
  el('rateioTitulo').addEventListener('change',()=>{
   const t=r.titulos.find(x=>x.id===el('rateioTitulo').value);
   el('rateioLiberacao').innerHTML=option('','Selecione')+(t?elegiveis(t).map(l=>option(l.id,l.obra+' · '+l.codigo+' · '+l.fabrica+' · '+l.quantidade+' un. · '+l.data_liberacao)).join(''):'');
   el('rateioValor').value='';
  });
  el('rateioForm').addEventListener('submit',ev=>{ev.preventDefault();try{
   const t=r.titulos.find(x=>x.id===el('rateioTitulo').value),l=el('rateioLiberacao').value,n=parseMoney(el('rateioValor').value),m=el('rateioMotivo').value.trim();
   if(!dreEditar()||!t||!elegiveis(t).some(x=>x.id===l)||n>cents(t.valor_centavos)-cents(t.usado_centavos)||m.length<5)throw Error('Confira título, liberação, saldo e justificativa.');
   if(window.confirm('Atribuir '+money(n)+' à liberação escolhida? Não cria uma nova despesa na DRE.'))void gravar('ew_rateio_industrial_criar',{p_titulo_id:t.id,p_liberacao_id:l,p_versao:t.versao,p_valor_centavos:n,p_motivo:m},el('rateioSubmit'),'Rateio registrado.');
  }catch(e){el('corpStatus').textContent=e.message;}});
 }
 for(const b of el('corpRateio').querySelectorAll('[data-rateio-reverse]'))b.addEventListener('click',()=>{
  if(!temPermissao('financeiro.cancelar_despesas'))return;
  const m=window.prompt('Motivo do estorno do rateio (5 a 400 caracteres):');if(m===null)return;
  if(m.trim().length<5||m.length>400){el('corpStatus').textContent='Informe motivo válido.';return;}
  if(window.confirm('Estornar somente a atribuição de custo? O título e a DRE permanecem inalterados.'))void gravar('ew_rateio_industrial_estornar',{p_id:b.dataset.rateioReverse,p_motivo:m.trim()},b,'Rateio estornado.');
 });
}
function render(){
 const r=state,entradas=cents(r.entradas_centavos),saidas=cents(r.saidas_centavos);
 const tipos=['PAGAR','RECEBER'].filter(t=>can(t));
 const fonte=r.documentos.filter(d=>can(d.tipo)&&canOrigin(d.origem_tipo));
 el('corpConteudo').innerHTML=
 '<div class="stats" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))">'+
 kpi('Contas a pagar · saldo atual',money(r.a_pagar_centavos))+kpi('Contas a receber · saldo atual',money(r.a_receber_centavos))+
 kpi('A pagar vencido',money(r.vencido_pagar_centavos))+kpi('A receber vencido',money(r.vencido_receber_centavos))+
 kpi('Recebimentos no período',money(entradas))+kpi('Pagamentos no período',money(saidas))+
 kpi('Movimento líquido de caixa',((entradas-saidas)/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'}))+
 kpi('Documentos sem programação',String(r.documentos_sem_programacao))+'</div>'+
 '<p class="hint">Saldos dos títulos programados, não saldo bancário nem lucro. O período acima filtra as baixas efetivas; contas abertas incluem vencimentos de outros períodos. '+(r.escopo_completo?'':'Visão parcial: valores de notas do estoque próprio restritos pelo nível de acesso. ')+'Documentos ainda não programados não entram nas contas a pagar/receber.</p>'+
 (r.origens_pendentes?'<p class="error">'+r.origens_pendentes+' título(s) com origem cancelada ou divergente. Saldos desses títulos não entram no aberto; baixas reais continuam no caixa até conferência.</p>':'')+
 (tipos.length?'<div class="section panel"><h2>Programar conta</h2><form id="corpForm"><div class="finFormRows">'+
 '<label>Origem<select id="corpOrigem">'+option('MANUAL','Lançamento manual — sem documento cadastrado')+fonte.map(d=>option(d.origem_tipo+'|'+d.origem_id,(d.tipo==='PAGAR'?'Pagar':'Receber')+' · '+d.descricao+' · '+d.numero_documento+' · '+money(d.valor_centavos))).join('')+'</select></label>'+
 '<label>Vencimento<input id="corpVenc" type="date" required value="'+esc(todayLocal())+'"></label></div>'+
 '<div id="corpManual" class="finFormRows"><label>Tipo<select id="corpTipo">'+tipos.map(t=>option(t,t==='PAGAR'?'Conta a pagar':'Conta a receber')).join('')+'</select></label>'+
 '<label>Descrição<input id="corpDesc" minlength="3" maxlength="200" required placeholder="Ex.: Energia elétrica"></label>'+
 '<label>Fornecedor / cliente<input id="corpContra" maxlength="200" required></label><label>Documento<input id="corpDoc" maxlength="120"></label>'+
 '<label>Categoria<input id="corpCat" maxlength="80" required list="corpCats" placeholder="Selecione ou digite"><datalist id="corpCats">'+['Folha de pagamento','Energia elétrica','Água','Aluguel','Combustível','Impostos','Manutenção','Serviços','Outras despesas','Outras receitas'].map(v=>option(v,v)).join('')+'</datalist></label>'+
 '<label>Centro de custo<select id="corpCentro">'+option('GERAL','Geral')+option('ADMINISTRATIVO','Administrativo')+r.centros.map(g=>option(g.id,g.nome)).join('')+'</select></label>'+
 '<label>Competência<input id="corpComp" type="date" required value="'+esc(todayLocal())+'"></label></div>'+
 '<label>Valor (R$)<input id="corpValor" inputmode="decimal" required placeholder="0,00"></label><p id="corpOrigemHint" class="hint">Use lançamento manual somente para uma conta sem documento já registrado no EWGEST.</p>'+
 '<button id="corpCriar" type="submit" class="btn primary">Programar conta</button></form></div>':'')+
 '<div class="section panel"><h2>Contas programadas</h2><div class="finFormRows"><label>Tipo<select id="corpFiltroTipo">'+option('','Todas')+option('PAGAR','A pagar')+option('RECEBER','A receber')+'</select></label><label>Situação<select id="corpFiltroSituacao">'+option('ativas','Abertas, parciais e pendentes')+option('','Todas')+option('LIQUIDADO','Liquidadas')+option('CANCELADO','Canceladas')+'</select></label></div>'+
 (r.titulos_total>r.titulos.length?'<p class="hint">Lista limitada aos primeiros 500 registros; indicadores consideram todos os registros autorizados.</p>':'')+
 '<div id="corpTabela"></div><div id="corpBaixaForm"></div></div>'+
 '<div class="section panel"><h2>Movimentos de caixa por centro de custo</h2>'+table(['Centro','Recebimentos','Pagamentos'],r.caixa_centros.map(c=>cells([c.centro_custo,money(c.entradas_centavos),money(c.saidas_centavos)])))+
 '<p class="hint">Movimentos pagos/recebidos, não rentabilidade nem custo industrial. Documentos de obra são inicialmente classificados no centro Geral.</p></div>'+
 (drePermitido()?'<div id="corpDre">'+renderDre(r.dre)+'</div><div id="corpRateio">'+renderRateio(r.rateio)+'</div>':'');
 if(el('corpForm')){
  el('corpOrigem').addEventListener('change',mudarOrigem);
  el('corpForm').addEventListener('submit',criar);
 }
 for(const id of ['corpFiltroTipo','corpFiltroSituacao'])el(id).addEventListener('change',renderTitulos);
 renderTitulos();if(drePermitido()){bindDre();bindRateio();}
}
function mudarOrigem(){
 const f=el('corpOrigem').value,manual=f==='MANUAL',d=state.documentos.find(x=>x.origem_tipo+'|'+x.origem_id===f);
 el('corpManual').classList.toggle('hidden',!manual);
 for(const x of el('corpManual').querySelectorAll('input,select'))x.disabled=!manual;
 el('corpValor').readOnly=!manual;
 el('corpValor').value=manual?'':(cents(d.valor_centavos)/100).toFixed(2);
 el('corpOrigemHint').textContent=manual?'Use lançamento manual somente para uma conta sem documento já registrado no EWGEST.':d.descricao+' · documento '+d.numero_documento+' · competência '+d.competencia+'. Vínculo e valor serão validados no servidor.';
}
function renderTitulos(){
 const tipo=el('corpFiltroTipo').value,sit=el('corpFiltroSituacao').value;
 el('corpBaixaForm').replaceChildren();
 const lista=state.titulos.filter(t=>(!tipo||t.tipo===tipo)&&(!sit||(sit==='ativas'?['ABERTO','PARCIAL','ORIGEM PENDENTE'].includes(t.situacao):t.situacao===sit)));
 const rows=lista.map(t=>{
  const pode=can(t.tipo)&&canOrigin(t.origem_tipo)&&t.origem_valida&&!t.cancelado_em&&cents(t.saldo_centavos)>0;
  const cancelar=can(t.tipo,true)&&canOrigin(t.origem_tipo)&&!t.cancelado_em&&cents(t.baixado_centavos)===0;
  const hist=t.baixas.length?'<details><summary>'+t.baixas.length+' baixa(s)</summary>'+t.baixas.map(b=>'<div class="hint">'+esc(b.data_baixa)+' · '+esc(money(b.valor_centavos))+' · '+esc(b.meio||'')+(b.estornado_em?' · ESTORNADA: '+esc(b.estorno_motivo):can(t.tipo,true)&&canOrigin(t.origem_tipo)?' <button class="btn secondary" type="button" data-corp-reverse="'+esc(b.id)+'">Estornar baixa</button>':'')+'</div>').join('')+'</details>':'';
  return '<tr><td>'+esc(t.tipo==='PAGAR'?'A pagar':'A receber')+'</td><td><strong>'+esc(t.descricao)+'</strong><div class="hint">'+esc(t.contraparte)+' · '+esc(t.numero_documento)+' · '+esc(t.centro_custo)+'</div></td><td>'+esc(t.vencimento)+'</td><td>'+esc(money(t.valor_centavos))+'</td><td>'+esc(money(t.baixado_centavos))+'</td><td>'+esc(money(t.saldo_centavos))+'</td><td>'+esc(t.situacao)+(t.cancelado_em?'<div class="hint">'+esc(t.cancelamento_motivo)+'</div>':'')+'</td><td>'+
   (pode?'<button type="button" class="btn primary" data-corp-pay="'+esc(t.id)+'">'+(t.tipo==='PAGAR'?'Registrar pagamento':'Registrar recebimento')+'</button>':'')+
   (cancelar?'<button type="button" class="btn secondary" data-corp-cancel="'+esc(t.id)+'">Cancelar título</button>':'')+hist+'</td></tr>';
 });
 el('corpTabela').innerHTML=table(['Tipo','Conta / documento','Vencimento','Valor','Baixado','Saldo','Situação','Ações'],rows);
 for(const b of el('corpTabela').querySelectorAll('[data-corp-pay]'))b.addEventListener('click',()=>abrirBaixa(b.dataset.corpPay));
 for(const b of el('corpTabela').querySelectorAll('[data-corp-cancel]'))b.addEventListener('click',()=>cancelar(b.dataset.corpCancel,b));
 for(const b of el('corpTabela').querySelectorAll('[data-corp-reverse]'))b.addEventListener('click',()=>estornar(b.dataset.corpReverse,b));
}
async function abrir(){
 limpar();
 if(!live())return;
 const i=el('corpInicio'),f=el('corpFim');if(!f.value)f.value=todayLocal();if(!i.value)i.value=f.value.slice(0,7)+'-01';
 if(!i.value||!f.value||i.value>f.value){el('corpStatus').textContent='Informe um período válido.';return;}
 const n=++seq,id=currentCompany.id,uid=currentUser?.id;
 scope={id,uid,n};el('corpStatus').textContent='Consultando títulos e baixas…';
 try{await ensureSession();if(!valid(n,id,uid))return;
  const body={p_empresa_id:id,p_inicio:i.value,p_fim:f.value},args={method:'POST',token:session.access_token,timeoutMs:45000,body};
  const [r,dre,rateio]=await Promise.all([request('/rest/v1/rpc/ew_fin_empresa_consultar',args),drePermitido()?request('/rest/v1/rpc/ew_dre_consultar',args).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_rateio_industrial_consultar',args).catch(()=>null):null]);
  if(!valid(n,id,uid))return;state=validate(r);state.dre=drePermitido()?dre:null;
  if(state.dre){try{dreCalcular(state.dre);}catch(e){state.dre=null;}}
  state.rateio=drePermitido()?rateio:null;if(state.rateio){try{rateioValidar(state.rateio);}catch(e){state.rateio=null;}}
  render();el('corpStatus').textContent='Consulta concluída.';
 }catch(e){if(valid(n,id,uid)){state=null;el('corpConteudo').replaceChildren();el('corpStatus').textContent='Não foi possível carregar o financeiro: '+e.message;}}
}
async function gravar(rpc,body,btn,msg){
 if(busy||!scope||!valid(scope.n,scope.id,scope.uid))return;
 const {id,uid,n}=scope,key=JSON.stringify([id,uid,rpc,body]),op=ops.get(key)||crypto.randomUUID();
 ops.set(key,op);if(ops.size>100)ops.delete(ops.keys().next().value);
 busy=true;if(btn)btn.disabled=true;el('corpStatus').textContent='Registrando operação…';
 try{
  await ensureSession();if(!valid(n,id,uid))throw Error('Empresa, sessão ou tela alterada.');
  await request('/rest/v1/rpc/'+rpc,{method:'POST',token:session.access_token,timeoutMs:45000,body:{p_empresa_id:id,p_operacao_id:op,...body}});
  ops.delete(key);
  if(valid(n,id,uid)){await abrir();if(live()&&currentCompany.id===id&&currentUser?.id===uid)el('corpStatus').textContent=msg;}
 }catch(e){if(valid(n,id,uid))el('corpStatus').textContent='Operação não confirmada: '+e.message+'. Confira o histórico antes de tentar novamente.';}
 finally{busy=false;if(btn)btn.disabled=false;}
}
function criar(ev){
 ev.preventDefault();if(!state||busy)return;
 try{
  const src=el('corpOrigem').value,d=state.documentos.find(x=>x.origem_tipo+'|'+x.origem_id===src),manual=src==='MANUAL',tipo=manual?el('corpTipo').value:d?.tipo;
  if(!tipo||!can(tipo)||(!manual&&(!d||!canOrigin(d.origem_tipo))))throw Error('Sem permissão ou documento disponível.');
  const dados=manual?{tipo,origem_tipo:'MANUAL',descricao:el('corpDesc').value.trim(),contraparte:el('corpContra').value.trim(),numero_documento:el('corpDoc').value.trim(),categoria:el('corpCat').value.trim(),centro:el('corpCentro').value,competencia:el('corpComp').value,vencimento:el('corpVenc').value,valor_centavos:parseMoney(el('corpValor').value)}:{tipo,origem_tipo:d.origem_tipo,origem_id:d.origem_id,vencimento:el('corpVenc').value,valor_centavos:cents(d.valor_centavos)};
  if(!window.confirm('Programar '+money(dados.valor_centavos)+' para '+dados.vencimento+'? Nenhum pagamento ou recebimento será registrado agora.'))return;
  void gravar('ew_fin_empresa_criar_titulo',{p_dados:dados},el('corpCriar'),'Conta programada com sucesso.');
 }catch(e){el('corpStatus').textContent=e.message;}
}
function abrirBaixa(id){
 const t=state.titulos.find(x=>x.id===id);if(!t||!can(t.tipo)||!canOrigin(t.origem_tipo)||!t.origem_valida||t.cancelado_em||cents(t.saldo_centavos)<=0)return;
 const p=el('corpBaixaForm');p.innerHTML='<div class="panel section"><h3>'+esc(t.tipo==='PAGAR'?'Pagamento':'Recebimento')+' · '+esc(t.descricao)+'</h3><p class="hint">Saldo '+esc(money(t.saldo_centavos))+'</p><form id="corpBaixar"><div class="finFormRows"><label>Valor (R$)<input id="corpBaixaValor" inputmode="decimal" value="'+(cents(t.saldo_centavos)/100).toFixed(2)+'" required></label><label>Data efetiva<input id="corpBaixaData" type="date" max="'+esc(todayLocal())+'" value="'+esc(todayLocal())+'" required></label><label>Meio<select id="corpBaixaMeio">'+['Pix','Transferência','Boleto','Dinheiro','Cartão','Outro'].map(x=>option(x,x)).join('')+'</select></label><label>Observações<input id="corpBaixaObs" maxlength="400"></label></div><div class="topactions"><button id="corpBaixarBtn" class="btn primary" type="submit">Confirmar baixa</button><button id="corpBaixarFechar" class="btn secondary" type="button">Cancelar</button></div></form></div>';
 el('corpBaixarFechar').addEventListener('click',()=>p.replaceChildren());
 el('corpBaixar').addEventListener('submit',ev=>{ev.preventDefault();try{
  const v=parseMoney(el('corpBaixaValor').value);if(v>cents(t.saldo_centavos))throw Error('Valor supera o saldo.');
  if(!window.confirm('Confirma que '+money(v)+' foi efetivamente '+(t.tipo==='PAGAR'?'pago':'recebido')+'?'))return;
  void gravar('ew_fin_empresa_baixar',{p_titulo_id:t.id,p_valor_centavos:v,p_data:el('corpBaixaData').value,p_meio:el('corpBaixaMeio').value,p_observacoes:el('corpBaixaObs').value.trim()},el('corpBaixarBtn'),'Baixa registrada.');
 }catch(e){el('corpStatus').textContent=e.message;}});
 p.scrollIntoView({block:'nearest',behavior:'smooth'});
}
function cancelar(id,btn){
 const t=state.titulos.find(x=>x.id===id);if(!t||!can(t.tipo,true)||!canOrigin(t.origem_tipo)||t.cancelado_em||cents(t.baixado_centavos)!==0)return;
 const m=window.prompt('Motivo do cancelamento (5 a 400 caracteres):');if(m===null)return;if(m.trim().length<5||m.length>400){el('corpStatus').textContent='Informe motivo válido.';return;}
 if(window.confirm('Cancelar definitivamente o título? O histórico será preservado.'))void gravar('ew_fin_empresa_cancelar_titulo',{p_titulo_id:id,p_motivo:m.trim()},btn,'Título cancelado.');
}
function estornar(id,btn){
 const t=state.titulos.find(x=>x.baixas.some(b=>b.id===id&&!b.estornado_em));if(!t||!can(t.tipo,true)||!canOrigin(t.origem_tipo))return;
 const m=window.prompt('Motivo do estorno da baixa incorreta (5 a 400 caracteres):');if(m===null)return;if(m.trim().length<5||m.length>400){el('corpStatus').textContent='Informe motivo válido.';return;}
 if(window.confirm('Estornar o registro incorreto da baixa? Não use esta operação para ocultar um pagamento ou recebimento efetivo.'))void gravar('ew_fin_empresa_estornar_baixa',{p_baixa_id:id,p_motivo:m.trim()},btn,'Baixa estornada; histórico preservado.');
}
el('corpRefresh').addEventListener('click',abrir);
for(const id of ['corpInicio','corpFim'])el(id).addEventListener('change',abrir);
window.ewFinanceiroEmpresa=Object.freeze({abrir,limpar});
})();
