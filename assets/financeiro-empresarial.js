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
function distribuirRateioPorQuantidade(total,liberacoes){
 const t=cents(total);if(t<=0||!liberacoes.length||new Set(liberacoes.map(l=>l.id)).size!==liberacoes.length)throw Error('Selecione liberações distintas e saldo positivo.');
 const rows=liberacoes.map(l=>{const q=Number(l.quantidade);if(!Number.isSafeInteger(q)||q<=0)throw Error('Quantidade de liberação inválida.');return {id:l.id,q:BigInt(q)};});
 const sum=rows.reduce((a,r)=>a+r.q,0n),value=BigInt(t);
 for(const r of rows){r.centavos=value*r.q/sum;r.resto=value*r.q%sum;}
 let extra=value-rows.reduce((a,r)=>a+r.centavos,0n);
 const rank=[...rows].sort((a,b)=>a.resto>b.resto?-1:a.resto<b.resto?1:String(a.id).localeCompare(String(b.id)));
 for(const r of rank){if(extra===0n)break;r.centavos++;extra--;}
 return rows.map(r=>({id:r.id,centavos:Number(r.centavos)}));
}
function indicadorFabrica(x){
 const receita=cents(x.receita_centavos),material=cents(x.material_centavos),rateio=cents(x.rateio_centavos),custo=material+rateio,contribuicao=receita-custo;
 const area=x.area_m2===null?null:Number(x.area_m2);
 if(!Number.isSafeInteger(custo)||!Number.isSafeInteger(contribuicao)||(area!==null&&(!Number.isFinite(area)||area<=0)))throw Error('Indicadores não conciliados.');
 return {receita,custo,contribuicao,area,custoM2:area?custo/area:null,margem:receita?100*contribuicao/receita:null};
}
function renderIndicadores(r){
 if(!r||!Array.isArray(r.fabrica))return '<div class="panel section"><h2>Indicadores industriais por fábrica</h2><p class="hint">Consulta indisponível.</p></div>';
 try{const fmt=n=>Number(n).toLocaleString('pt-BR',{maximumFractionDigits:3});
 const rows=r.fabrica.map(x=>{const d=indicadorFabrica(x),kg=Number(x.kg_registrado),estimado=Number(x.kg_estimado),historico=Number(x.kg_historico),pend=cents(x.peso_pendente),base=cents(x.peso_com_base);
 if(!Number.isFinite(kg)||kg<0||!Number.isFinite(estimado)||estimado<0||!Number.isFinite(historico)||historico<0)throw Error('Peso inválido.');
 return cells([x.fabrica||'A atribuir',money(d.receita),d.area===null?'—':fmt(d.area),money(d.custo),d.custoM2===null?'—':money(d.custoM2),signed(d.contribuicao),d.margem===null?'—':fmt(d.margem)+'%',base?fmt(kg):'—',base?fmt(historico):'—',base?fmt(estimado):'—',String(pend)]);
 });
 return '<div class="panel section"><h2>Indicadores industriais por fábrica</h2><p class="notice">Custo reconhecido/m² faturado e margem de contribuição são parciais, não custo integral de fabricação nem lucro líquido. A área exige atribuição conciliada à receita da fábrica. Peso em kg registrado refere-se a movimentos em kg; peso histórico congela o peso linear no momento do consumo; estimativa retroativa usa o cadastro atual. Não equivale a pesagem nem a peso líquido da esquadria. Movimentos de lote não são divididos entre itens.</p>'+
 table(['Fábrica','Receita fabricação','Área faturada (m²)','Custo reconhecido','Custo parcial/m²','Contribuição parcial','Margem parcial','Kg registrados','Kg históricos','Kg estimados retroativos','Pendências peso'],rows)+'</div>';
 }catch(e){return '<div class="panel section"><h2>Indicadores industriais por fábrica</h2><p class="hint">Dados não conciliados: '+esc(e.message)+'</p></div>';}
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
 (edit&&titles.length?'<form id="rateioForm"><div class="finFormRows"><label>Título de custo<select id="rateioTitulo">'+option('','Selecione')+titles.map(t=>option(t.id,t.descricao+' · '+t.centro_custo+' · '+t.competencia+' · saldo '+money(cents(t.valor_centavos)-cents(t.usado_centavos)))).join('')+'</select></label><label>Liberação<select id="rateioLiberacao" required><option value="">Selecione o título</option></select></label><label>Valor (R$)<input id="rateioValor" inputmode="decimal" required></label><label>Critério / justificativa<input id="rateioMotivo" minlength="5" maxlength="400" required placeholder="Ex.: horas trabalhadas nesta liberação"></label></div><button id="rateioSubmit" class="btn primary" type="submit">Registrar rateio</button></form><details><summary>Rateio proporcional em lote</summary><p class="hint">Escolha até 100 liberações completas. Área = largura × altura × unidades liberadas. Peso informado = kg totais de cada liberação, conferidos pelo operador; não é peso apurado pelo estoque. Peso histórico consumido utiliza registros novos de consumo individual; sem base completa, o lote é recusado. A prévia não grava valores.</p><label>Critério<select id="rateioSimCriterio"><option value="QUANTIDADE">Quantidade de esquadrias</option><option value="AREA">Área liberada (m²)</option><option value="PESO_INFORMADO">Peso informado (kg)</option><option value="PESO_CONSUMO">Peso histórico consumido (kg)</option></select></label><label>Justificativa do lote<input id="rateioSimMotivo" maxlength="300" minlength="5"></label><div id="rateioSimLista"></div><button type="button" id="rateioSimular" class="btn secondary">Calcular prévia do saldo</button><div id="rateioSimResultado" role="status"></div><button type="button" id="rateioSimConfirmar" class="btn primary" disabled>Registrar lote</button></details>':'<p class="hint">Nenhum título com saldo disponível para rateio, ou acesso somente consulta.</p>')+
 '<h3>Histórico de rateios ativos</h3>'+table(['Obra','Esquadria','Fábrica','Competência','Classe','Valor','Situação / critério','Ação'],r.rateios.map(x=>'<tr>'+[x.obra||'Histórico',x.codigo||'Histórico',x.fabrica,x.competencia,dreClasses[x.classe]||x.classe,money(x.valor_centavos),(x.valido?'Apropriado':'Em conferência')+' · '+x.motivo].map(v=>'<td>'+esc(v)+'</td>').join('')+'<td>'+(temPermissao('financeiro.cancelar_despesas')?'<button type="button" class="btn secondary" data-rateio-reverse="'+esc(x.id)+'">Estornar</button>':'')+'</td></tr>'))+'</div>';
}
function bindRateio(){
 if(!state?.rateio||!el('corpRateio'))return;
 const r=state.rateio;
 if(el('rateioForm')){
  let previa=null,previewSeq=0;
  const limparPrevia=()=>{previewSeq++;previa=null;el('rateioSimResultado').replaceChildren();el('rateioSimConfirmar').disabled=true;};
  const elegiveis=t=>r.liberacoes.filter(l=>(!t.galpao_id||t.centro_custo.trim()===l.fabrica.trim())&&l.data_liberacao.slice(0,7)<=t.competencia.slice(0,7));
  el('rateioTitulo').addEventListener('change',()=>{
   const t=r.titulos.find(x=>x.id===el('rateioTitulo').value);
   el('rateioLiberacao').innerHTML=option('','Selecione')+(t?elegiveis(t).map(l=>option(l.id,l.obra+' · '+l.codigo+' · '+l.fabrica+' · '+l.quantidade+' un. · '+l.data_liberacao)).join(''):'');
   el('rateioValor').value='';
   limparPrevia();el('rateioSimLista').innerHTML=t?elegiveis(t).map(l=>'<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><label><input type="checkbox" data-rateio-sim="'+esc(l.id)+'" style="width:16px;height:16px"> '+esc(l.obra+' · '+l.codigo+' · '+l.fabrica+' · '+l.quantidade+' un.')+'</label><label data-peso-label hidden>Peso total (kg)<input type="number" min="0.001" max="1000000" step="0.001" data-rateio-peso="'+esc(l.id)+'"></label></div>').join(''):'Escolha um título acima.';atualizarPeso();
  });
  const atualizarPeso=()=>el('rateioSimLista').querySelectorAll('[data-peso-label]').forEach(x=>x.hidden=el('rateioSimCriterio').value!=='PESO_INFORMADO');
  el('rateioSimCriterio').addEventListener('change',()=>{limparPrevia();atualizarPeso();});
  el('rateioSimMotivo').addEventListener('input',limparPrevia);
  el('rateioSimLista').addEventListener('change',limparPrevia);el('rateioSimLista').addEventListener('input',limparPrevia);
  el('rateioSimular').addEventListener('click',async()=>{
   limparPrevia();const n=previewSeq,btn=el('rateioSimular'),out=el('rateioSimResultado'),ctx=scope;
   try{const t=r.titulos.find(x=>x.id===el('rateioTitulo').value),criterio=el('rateioSimCriterio').value,motivo=el('rateioSimMotivo').value.trim();
    if(!dreEditar()||!t||!ctx||!valid(ctx.n,ctx.id,ctx.uid)||motivo.length<5||motivo.length>300)throw Error('Escolha um título e informe justificativa válida.');
    const ids=new Set([...el('rateioSimLista').querySelectorAll('[data-rateio-sim]:checked')].map(b=>b.dataset.rateioSim));
    const pesos=new Map([...el('rateioSimLista').querySelectorAll('[data-rateio-peso]')].map(b=>[b.dataset.rateioPeso,Number(b.value)]));
    const ls=elegiveis(t).filter(l=>ids.has(l.id));if(!ls.length||ls.length>100)throw Error('Selecione de 1 a 100 liberações.');
    const selecao=ls.map(l=>({id:l.id,peso_kg:criterio==='PESO_INFORMADO'?pesos.get(l.id):null}));
    if(criterio==='PESO_INFORMADO'&&selecao.some(x=>!Number.isFinite(x.peso_kg)||x.peso_kg<=0||x.peso_kg>1000000))throw Error('Informe o peso total de cada liberação.');
    const body={p_titulo_id:t.id,p_versao:t.versao,p_criterio:criterio,p_selecao:selecao,p_motivo:motivo};
    btn.disabled=true;out.textContent='Calculando no servidor…';await ensureSession();if(!valid(ctx.n,ctx.id,ctx.uid)||n!==previewSeq)return;
    const p=await request('/rest/v1/rpc/ew_rateio_industrial_lote',{method:'POST',token:session.access_token,timeoutMs:45000,body:{p_empresa_id:ctx.id,p_operacao_id:crypto.randomUUID(),...body,p_confirmar:false,p_previa:null}});
    if(!valid(ctx.n,ctx.id,ctx.uid)||n!==previewSeq||!out.isConnected)return;
    if(!p||p.criterio!==criterio||!Array.isArray(p.linhas)||p.linhas.length!==ls.length||new Set(p.linhas.map(x=>x.id)).size!==ls.length||p.linhas.some(x=>!ids.has(x.id)||!Number.isFinite(Number(x.peso))||Number(x.peso)<=0)||p.linhas.reduce((sum,x)=>sum+cents(x.centavos),0)!==cents(p.saldo_centavos)||cents(p.saldo_centavos)!==cents(t.valor_centavos)-cents(t.usado_centavos))throw Error('Prévia não conciliada. Atualize o financeiro.');
    previa={...body,p_confirmar:true,p_previa:p.linhas};
    out.innerHTML=table(['Obra','Código','Fábrica','Base do rateio','Valor sugerido'],p.linhas.map(x=>{const l=ls.find(y=>y.id===x.id);return cells([l.obra,l.codigo,l.fabrica,Number(x.peso).toLocaleString('pt-BR',{maximumFractionDigits:6}),money(x.centavos)]);}))+'<p class="hint">Total: '+esc(money(p.saldo_centavos))+'</p>';
    el('rateioSimConfirmar').disabled=false;
   }catch(e){if(n===previewSeq&&out.isConnected)out.textContent=e.message;}finally{if(btn.isConnected)btn.disabled=false;}
  });
  el('rateioSimConfirmar').addEventListener('click',()=>{if(!previa||!dreEditar())return;if(window.confirm('Registrar todos os rateios da prévia em uma única operação? Não cria nova despesa na DRE.'))void gravar('ew_rateio_industrial_lote',previa,el('rateioSimConfirmar'),'Lote registrado.');});
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
function previsaoTitulos(r){
 const map=new Map();let pagar=0,receber=0;
 for(const t of r.titulos){
  if(t.cancelado_em||!t.origem_valida)continue;
  const n=cents(t.saldo_centavos);if(!n)continue;
  const data=String(t.vencimento||'');if(!/^\d{4}-\d{2}-\d{2}$/.test(data))throw Error('Vencimento inválido.');
  const mes=data.slice(0,7),x=map.get(mes)||{mes,pagar:0,receber:0};
  if(t.tipo==='PAGAR'){x.pagar+=n;pagar+=n;}else{x.receber+=n;receber+=n;}map.set(mes,x);
 }
 if(!Number.isSafeInteger(pagar)||!Number.isSafeInteger(receber)||pagar>cents(r.a_pagar_centavos)||receber>cents(r.a_receber_centavos))throw Error('Previsão não conciliada.');
 const completa=r.titulos.length===cents(r.titulos_total);
 if(completa&&(pagar!==cents(r.a_pagar_centavos)||receber!==cents(r.a_receber_centavos)))throw Error('Saldos não conciliados.');
 return {linhas:[...map.values()].sort((a,b)=>a.mes.localeCompare(b.mes)),pagar,receber,completa};
}
function renderPrevisaoTitulos(r){
 try{const p=previsaoTitulos(r);
 return '<div class="section panel"><h2>Previsão de pagamentos e recebimentos</h2><p class="hint">Por vencimento dos títulos programados e ativos, descontadas as baixas. Valores vencidos permanecem no mês original. Não inclui compromissos sem título, frete sem documento ou saldo bancário. '+(p.completa?'':'Lista parcial de títulos; confira os indicadores globais. ') +(!r.escopo_completo?'Visão restrita pelas permissões.':'')+'</p>'+
 table(['Mês de vencimento','A pagar','A receber','Fluxo previsto líquido'],p.linhas.map(x=>cells([x.mes,money(x.pagar),money(x.receber),signed(x.receber-x.pagar)])))+'</div>';
 }catch(e){return '<div class="section panel"><h2>Previsão de pagamentos e recebimentos</h2><p class="hint">Consulta não conciliada: '+esc(e.message)+'</p></div>';}
}
function renderCoberturaIndustrial(r){
 if(!r.dre||!r.rateio)return '';
 try{const dre=dreCalcular(r.dre),d=rateioValidar(r.rateio);
 return '<div class="section panel"><h2>Cobertura dos custos de fabricação</h2><p class="hint">Os custos reconhecidos não são necessariamente integrais. Antes de considerar o resultado definitivo, confira as pendências e os custos sem atribuição, inclusive frete não incluído no preço dos materiais. Não somar novamente despesas já reconhecidas na DRE.</p>'+
 table(['Verificação','Posição'],[cells(['Custos industriais classificados',money(d.industrial)]),cells(['Custos industriais rateados',money(d.rateado)]),cells(['Custos industriais ainda sem rateio',money(d.saldo)]),cells(['Títulos manuais sem classificação',String(dre.p)]),cells(['Reconhecimentos de material pendentes',String(dre.pend)]),cells(['Rateios industriais em conferência',String(d.pend)])])+'</div>';
 }catch(e){return '<p class="hint">Cobertura de custos não conciliada.</p>';}
}
const comprasFinanceiro=()=>auth()&&temPermissao('compras.consultar')&&temPermissao('compras.consultar_valores');
function renderComprasFinanceiro(r){
 if(!r||!['linhas','pedidos','fretes_disponiveis'].every(k=>Array.isArray(r[k])))return '<div class="section panel"><h2>Previsão financeira de compras</h2><p class="hint">Consulta indisponível.</p></div>';
 try{
 const total=cents(r.total),saldo=cents(r.saldo_programado_centavos),sem=cents(r.sem_programacao_centavos),pend=cents(r.pendencias);
 const ids=new Set();let s=0,n=0,p=0;
 for(const x of r.linhas){const key=x.origem_tipo+'|'+x.origem_id;if(ids.has(key)||!Array.isArray(x.pedidos))throw Error('Documento duplicado ou inválido.');ids.add(key);
 if(x.situacao==='PROGRAMADO')s+=cents(x.saldo_centavos);else if(x.situacao==='SEM_PROGRAMACAO')n+=cents(x.valor_centavos);else p++;}
 if(r.linhas.length>total||s>saldo||n>sem||p>pend||(r.linhas.length===total&&(s!==saldo||n!==sem||p!==pend)))throw Error('Previsão não conciliada.');
 const form=can('PAGAR')&&r.pedidos.length&&r.fretes_disponiveis.length?'<h3>Vincular frete externo já programado</h3><form id="corpFreteForm"><div class="finFormRows"><label>Conta de frete existente<select id="corpFreteTitulo" required>'+option('','Selecione')+r.fretes_disponiveis.map(t=>option(t.id,t.descricao+' · '+t.numero_documento+' · '+money(t.valor_centavos))).join('')+'</select></label><label>Pedido<select id="corpFretePedido" required>'+option('','Selecione')+r.pedidos.map(t=>option(t.id,'Pedido #'+t.numero)).join('')+'</select></label></div><label>Justificativa<input id="corpFreteMotivo" required minlength="5" maxlength="300"></label><p class="hint">Vincule somente frete cobrado em documento separado, não incluído no preço da nota de materiais. Não cria conta ou baixa adicional, nem altera a valorização do estoque. Vínculo único por título.</p><button type="submit" class="btn primary">Vincular frete</button></form>':'';
 return '<div class="section panel"><h2>Previsão financeira de compras</h2><p class="hint">Documentos fiscais já ligados aos pedidos e fretes externos vinculados. Documento compartilhado aparece uma única vez. Valores são parte das contas empresariais, não somar novamente. Pedido sem documento não gera vencimento automaticamente. '+(r.linhas.length<total?'Lista limitada aos primeiros 500 documentos.':'')+'</p><p><strong>Saldo programado: '+money(saldo)+' · Documentos sem programação: '+money(sem)+' · Pendências: '+pend+'</strong></p>'+
 table(['Pedido(s)','Natureza','Documento','Fornecedor','Vencimento','Saldo','Situação'],r.linhas.map(x=>cells([x.pedidos.map(n=>'#'+n).join(', '),x.natureza==='FRETE_EXTERNO'?'Frete externo':'Documento de compra',x.numero_documento||'—',x.contraparte||'—',x.vencimento||'—',x.saldo_centavos===null?'—':money(x.saldo_centavos),x.situacao])))+form+'</div>';
 }catch(e){return '<div class="section panel"><h2>Previsão financeira de compras</h2><p class="hint">Dados não conciliados: '+esc(e.message)+'</p></div>';}
}
function bindFrete(){
 const form=el('corpFreteForm');if(!form)return;
 form.onsubmit=ev=>{ev.preventDefault();const r=state?.comprasFinanceiro,t=el('corpFreteTitulo').value,p=el('corpFretePedido').value,m=el('corpFreteMotivo').value.trim();if(!comprasFinanceiro()||!can('PAGAR')||!r?.fretes_disponiveis.some(x=>x.id===t)||!r.pedidos.some(x=>x.id===p)||m.length<5||m.length>300)return;
 if(window.confirm('Vincular o título de frete existente ao pedido? Confirme que o frete não está incluído na nota dos materiais. Não será criada outra conta a pagar.'))void gravar('ew_fin_vincular_frete',{p_titulo_id:t,p_pedido_id:p,p_motivo:m},form.querySelector('button[type=submit]'),'Frete vinculado ao pedido.');};
}
function renderProdutividade(r){
 if(!r||!Array.isArray(r.fabrica))return '<div class="section panel"><h2>Produtividade industrial</h2><p class="hint">Consulta indisponível.</p></div>';
 try{const dias=cents(r.dias);if(!dias||dias>367)throw Error('Período inválido.');
 const fmt=x=>{const n=Number(x);if(x==null||!Number.isFinite(n)||n<0)throw Error('Área inválida.');return n.toLocaleString('pt-BR',{maximumFractionDigits:3});};
 return '<div class="section panel"><h2>Produtividade industrial</h2><p class="hint">Liberações completas e expedições ativas no período. São etapas distintas; a expedição pode corresponder a liberações de outros meses. Área expedida/dia corrido não representa horas trabalhadas nem produção concluída.</p>'+table(['Fábrica','Un. liberadas','m² liberados','m² expedidos','m² expedidos/dia corrido','Pendências de área'],r.fabrica.map(x=>cells([x.fabrica||'A atribuir',String(cents(x.unidades_liberadas)),fmt(x.area_liberada),fmt(x.area_expedida),fmt(Number(x.area_expedida)/dias),String(cents(x.pendencias_liberacao)+cents(x.pendencias_expedicao))])))+'</div>';
 }catch(e){return '<div class="section panel"><h2>Produtividade industrial</h2><p class="hint">Dados inválidos: '+esc(e.message)+'</p></div>';}
}
function renderFretesHistorico(r){
 if(!Array.isArray(r))return '<p class="hint">Histórico de fretes indisponível.</p>';
 return '<div class="section panel"><h2>Histórico de vínculos de frete</h2><p class="hint">Estornar desvincula o pedido, mas não cancela o título nem suas baixas. Até 500 registros.</p>'+table(['Pedido','Documento','Valor','Justificativa','Situação','Ação'],r.map(x=>'<tr>'+[x.numero,x.numero_documento,money(x.valor_centavos),x.justificativa,x.estornado_em?'Estornado: '+x.estorno_motivo:'Ativo'].map(v=>'<td>'+esc(v)+'</td>').join('')+'<td>'+(!x.estornado_em?'<button type="button" class="btn secondary" data-frete-previa="'+esc(x.operacao_id)+'">Simular rateio</button> ':'')+(!x.estornado_em&&can('PAGAR',true)?'<button type="button" class="btn secondary" data-frete-estorno="'+esc(x.operacao_id)+'">Estornar vínculo</button>':'')+'</td></tr>'))+'</div>';
}
function bindEstornos(){
 for(const b of el('corpConteudo').querySelectorAll('[data-frete-previa]'))b.onclick=async()=>{const ctx=scope,x=state?.fretesHistorico?.find(v=>v.operacao_id===b.dataset.fretePrevia&&!v.estornado_em);if(!x||!ctx||!comprasFinanceiro())return;const row=b.closest('tr');const old=row.nextElementSibling;if(old?.dataset.freteResultado==='1')old.remove();const tr=document.createElement('tr');tr.dataset.freteResultado='1';const td=document.createElement('td');td.colSpan=6;td.textContent='Calculando…';tr.append(td);row.after(tr);b.disabled=true;
 try{await ensureSession();if(!valid(ctx.n,ctx.id,ctx.uid))return;const r=await request('/rest/v1/rpc/ew_fin_frete_previa',{method:'POST',token:session.access_token,timeoutMs:45000,body:{p_empresa_id:ctx.id,p_vinculo_id:x.operacao_id}});if(!valid(ctx.n,ctx.id,ctx.uid)||!td.isConnected)return;if(!r?.consultivo||!Array.isArray(r.itens)||r.itens.reduce((a,i)=>a+cents(i.frete_centavos),0)!==cents(r.frete_centavos)||r.itens.reduce((a,i)=>a+cents(i.material_centavos),0)!==cents(r.material_centavos))throw Error('Prévia não conciliada.');td.innerHTML='<p class="hint">Simulação pelo valor contratado de cada item. Não altera estoque, DRE, nota ou título.</p>'+table(['Item do pedido','Quantidade','Material','Frete sugerido','Total simulado'],r.itens.map(i=>cells([i.chave,i.quantidade,money(i.material_centavos),money(i.frete_centavos),money(cents(i.material_centavos)+cents(i.frete_centavos))])));}catch(e){if(td.isConnected)td.textContent=e.message;}finally{if(b.isConnected)b.disabled=false;}};

 for(const b of el('corpConteudo').querySelectorAll('[data-frete-estorno]'))b.onclick=()=>{const x=state?.fretesHistorico?.find(v=>v.operacao_id===b.dataset.freteEstorno&&!v.estornado_em);if(!x||!comprasFinanceiro()||!can('PAGAR',true))return;const m=window.prompt('Justificativa do estorno do vínculo (a conta e suas baixas serão preservadas):')?.trim();if(m&&m.length>=5&&m.length<=300)void gravar('ew_fin_estornar_vinculo_frete',{p_titulo_id:x.titulo_id,p_vinculo_id:x.operacao_id,p_motivo:m},b,'Vínculo estornado.');};
 for(const b of el('corpConteudo').querySelectorAll('[data-horas-estorno]'))b.onclick=()=>{const x=state?.horas?.registros?.find(v=>v.operacao_id===b.dataset.horasEstorno&&!v.estornado_em);if(!x||!dreEditar()||!can('PAGAR',true))return;const m=window.prompt('Justificativa para estornar o registro de horas:')?.trim();if(m&&m.length>=5&&m.length<=300)void gravar('ew_industrial_estornar_horas',{p_registro_id:x.operacao_id,p_motivo:m},b,'Horas estornadas.');};
}
function renderHoras(r,prod,centros){
 if(!r||!Array.isArray(r.registros)||!Array.isArray(r.totais))return '<div class="section panel"><h2>Horas de mão de obra industrial</h2><p class="hint">Consulta indisponível.</p></div>';
 const fmt=n=>Number(n).toLocaleString('pt-BR',{maximumFractionDigits:3});
 const form=dreEditar()?'<form id="corpHorasForm"><div class="finFormRows"><label>Fábrica / local<select id="corpHorasLocal" required>'+option('','Selecione')+centros.map(c=>option(c.id,c.nome)).join('')+'</select></label><label>Data<input type="date" id="corpHorasData" max="'+esc(todayLocal())+'" value="'+esc(todayLocal())+'" required></label><label>Total de horas-homem<input type="number" id="corpHorasValor" min="0" max="166666" step="0.01" required></label></div><label>Fonte / justificativa<input id="corpHorasMotivo" minlength="5" maxlength="300" required></label><button type="submit" class="btn primary">Registrar horas</button></form>':'';
 return '<div class="section panel"><h2>Horas de mão de obra industrial</h2><p class="hint">Total diário agregado por local (soma de horas dos trabalhadores, não duração do turno). Um registro ativo por dia. Informe zero quando não houve trabalho. Não cria folha ou despesa. A relação área expedida/hora só é exibida se houver registro para todos os dias do período; não é produtividade individual.</p>'+
 table(['Local','Horas-homem','Dias informados','m² expedidos/hora-homem'],r.totais.map(x=>{const p=prod?.fabrica?.filter(v=>v.fabrica===x.nome)||[],h=cents(x.minutos)/60,d=cents(x.dias_informados);return cells([x.nome||'Local histórico',fmt(h),String(d),p.length===1&&d===prod.dias&&h>0?fmt(Number(p[0].area_expedida)/h):'—']);}))+form+
 (r.registros.length<cents(r.total)?'<p class="hint">Histórico limitado a 500 registros.</p>':'')+
 table(['Local','Data','Horas-homem','Fonte','Situação','Ação'],r.registros.map(x=>'<tr>'+[x.nome,x.data_trabalho,fmt(cents(x.minutos)/60),x.motivo,x.estornado_em?'Estornado: '+x.estorno_motivo:'Ativo'].map(v=>'<td>'+esc(v)+'</td>').join('')+'<td>'+(!x.estornado_em&&dreEditar()&&can('PAGAR',true)?'<button type="button" class="btn secondary" data-horas-estorno="'+esc(x.operacao_id)+'">Estornar</button>':'')+'</td></tr>'))+'</div>';
}
function bindHoras(){
 const f=el('corpHorasForm');if(!f)return;
 f.onsubmit=ev=>{ev.preventDefault();if(!dreEditar())return;const id=el('corpHorasLocal').value,d=el('corpHorasData').value,h=Number(el('corpHorasValor').value),m=el('corpHorasMotivo').value.trim(),min=Math.round(h*60);if(!state?.centros.some(c=>c.id===id)||!d||d>todayLocal()||el('corpHorasValor').value===''||!Number.isSafeInteger(min)||min<0||min>10000000||m.length<5||m.length>300)return;void gravar('ew_industrial_registrar_horas',{p_galpao_id:id,p_data:d,p_minutos:min,p_motivo:m},f.querySelector('button[type=submit]'),'Horas registradas.');};
}
function simularCustoIntegral(d){
 const vals=['materiais','folha','encargos','beneficios','energia','manutencao','frete','outros','ativo','residual'].map(k=>cents(d[k]));
 const [materiais,folha,encargos,beneficios,energia,manutencao,frete,outros,ativo,residual]=vals,vida=Number(d.vida),area=Number(d.area),horas=Number(d.horas);
 if(residual>ativo||!Number.isSafeInteger(vida)||vida<1||vida>1200||!Number.isFinite(area)||area<=0||!Number.isFinite(horas)||horas<0)throw Error('Confira área, horas, vida útil e valor residual.');
 const depreciacao=Math.round((ativo-residual)/vida),pessoal=folha+encargos+beneficios,total=materiais+pessoal+energia+manutencao+frete+outros+depreciacao;
 if(!Number.isSafeInteger(total)||!Number.isSafeInteger(pessoal))throw Error('Total fora do limite.');
 return {depreciacao,pessoal,total,porM2:Math.round(total/area),porHora:horas>0?Math.round(total/horas):null};
}
function renderSimCusto(){
 const campos=[['materiais','Materiais consumidos'],['folha','Salários brutos'],['encargos','Encargos e provisões'],['beneficios','Benefícios'],['energia','Água e energia'],['manutencao','Manutenção'],['frete','Frete ainda não incluído nos materiais'],['outros','Outros custos industriais'],['ativo','Valor de aquisição do ativo'],['residual','Valor residual']];
 return '<div class="section panel"><h2>Simulação mensal de custo integral</h2><p class="notice">Simulação não persistida de uma fábrica e um mês, com valores informados pelo operador. Não é folha de pagamento, cálculo trabalhista ou escrituração contábil. Não incluir novamente frete ou custos já considerados em outra linha. Depreciação linear gerencial, sem lançamento financeiro.</p><form id="corpSimCusto"><div class="finFormRows">'+campos.map(([id,l])=>'<label>'+esc(l)+' (R$)<input id="simCusto_'+id+'" type="number" min="0" step="0.01" value="0" required></label>').join('')+
 '<label>Vida útil restante da base (meses)<input id="simCusto_vida" type="number" min="1" max="1200" step="1" value="60" required></label><label>Área de referência (m²)<input id="simCusto_area" type="number" min="0.001" step="0.001" required></label><label>Horas-homem<input id="simCusto_horas" type="number" min="0" step="0.01" value="0" required></label></div><button type="submit" class="btn secondary">Simular custo</button></form><div id="corpSimResultado" role="status"></div></div>';
}
function bindSimCusto(){
 const f=el('corpSimCusto');if(!f)return;
 f.addEventListener('input',()=>el('corpSimResultado').replaceChildren());
 f.onsubmit=e=>{e.preventDefault();if(!drePermitido())return;try{const d={};for(const k of ['materiais','folha','encargos','beneficios','energia','manutencao','frete','outros','ativo','residual']){const v=el('simCusto_'+k).value;if(!/^\d{1,12}(?:\.\d{1,2})?$/.test(v))throw Error('Valor inválido.');const [a,b='']=v.split('.');d[k]=Number(a)*100+Number(b.padEnd(2,'0'));}for(const k of ['vida','area','horas'])d[k]=Number(el('simCusto_'+k).value);
 const r=simularCustoIntegral(d);el('corpSimResultado').innerHTML=table(['Componente','Simulação'],[cells(['Mão de obra total',money(r.pessoal)]),cells(['Depreciação mensal',money(r.depreciacao)]),cells(['Custo mensal simulado',money(r.total)]),cells(['Custo/m²',money(r.porM2)]),cells(['Custo/hora-homem',r.porHora===null?'—':money(r.porHora)])]);}catch(e){el('corpSimResultado').textContent=e.message;}};
}
const pessoalPermitido=()=>drePermitido()&&temPermissao('usuarios.gerenciar');
function industrialValor(id){const v=el(id).value;if(!/^\d{1,12}(?:\.\d{1,2})?$/.test(v))throw Error('Valor inválido.');const [a,b='']=v.split('.');return cents(Number(a)*100+Number(b.padEnd(2,'0')));}
function renderCadIndustrial(r,centros){
 if(!r||!['funcionarios','folhas','ativos','depreciacoes'].every(k=>Array.isArray(r[k])))return '<div class="panel section"><h2>Pessoal e patrimônio industrial</h2><p class="hint">Consulta indisponível.</p></div>';
 const locais=option('','Selecione')+centros.map(c=>option(c.id,c.nome)).join(''),local=id=>'<label>Fábrica / local<select id="'+id+'" required>'+locais+'</select></label>',input=(id,l,type='text',extra='')=>'<label>'+esc(l)+'<input id="'+id+'" type="'+type+'" '+extra+' required></label>',valor=(id,l)=>input(id,l,'number','min="0" step="0.01" value="0"');
 const mes=todayLocal().slice(0,7),edit=dreEditar();
 const pessoal=pessoalPermitido()&&r.pessoal_permitido?'<details class="panel section"><summary>Funcionários e folha gerencial por fábrica</summary><p class="hint">Cadastro mínimo, sem CPF ou dados bancários. Folha agregada por competência, não gera contas a pagar, folha legal, eSocial ou DRE. Não some estes valores aos títulos já classificados.</p>'+
 (edit?'<form id="corpFuncionario"><div class="finFormRows">'+local('indFuncLocal')+input('indFuncCodigo','Matrícula','text','maxlength="50"')+input('indFuncNome','Nome','text','maxlength="150"')+input('indFuncFuncao','Função','text','maxlength="100"')+input('indFuncData','Admissão','date','max="'+esc(todayLocal())+'"')+'</div><button class="btn primary" type="submit">Cadastrar funcionário</button></form>':'')+
 table(['Matrícula','Nome','Função','Local','Admissão'],r.funcionarios.map(x=>cells([x.matricula,x.nome,x.funcao,x.local||'Local histórico',x.admissao])))+
 (edit?'<form id="corpFolha"><div class="finFormRows">'+local('indFolhaLocal')+input('indFolhaMes','Competência','month','max="'+esc(mes)+'" value="'+esc(mes)+'"')+valor('indFolhaSal','Salários (R$)')+valor('indFolhaEnc','Encargos e provisões (R$)')+valor('indFolhaBen','Benefícios (R$)')+input('indFolhaRef','Referência da folha','text','minlength="5" maxlength="300"')+'</div><button class="btn primary" type="submit">Registrar folha gerencial</button></form>':'')+
 table(['Competência','Local','Salários','Encargos','Benefícios','Total','Referência','Situação','Ação'],r.folhas.map(x=>'<tr>'+[x.competencia,x.local,money(x.salarios),money(x.encargos),money(x.beneficios),money(cents(x.salarios)+cents(x.encargos)+cents(x.beneficios)),x.referencia,x.estornado_em?'Estornada: '+x.estorno_motivo:'Ativa'].map(v=>'<td>'+esc(v)+'</td>').join('')+'<td>'+(!x.estornado_em&&edit&&can('PAGAR',true)?'<button class="btn secondary" type="button" data-folha-estorno="'+esc(x.id)+'">Estornar</button>':'')+'</td></tr>'))+'</details>':'';
 return pessoal+'<details class="panel section"><summary>Máquinas, patrimônio e depreciação gerencial</summary><p class="hint">Cadastro inicial de ativos com base congelada e depreciação linear mensal. Não gera despesa, pagamento ou escrituração. Registre as competências em sequência; não há alteração da base nem baixa patrimonial nesta etapa.</p>'+
 (edit?'<form id="corpAtivo"><div class="finFormRows">'+local('indAtivoLocal')+input('indAtivoCodigo','Código patrimonial','text','maxlength="50"')+input('indAtivoNome','Descrição','text','maxlength="150"')+input('indAtivoMes','Início da depreciação','month','max="'+esc(mes)+'"')+valor('indAtivoValor','Base de aquisição (R$)')+valor('indAtivoResidual','Residual (R$)')+input('indAtivoVida','Vida útil (meses)','number','min="1" max="1200" step="1"')+'</div><button class="btn primary" type="submit">Cadastrar ativo</button></form>':'')+
 table(['Código','Descrição','Local','Base','Residual','Vida (meses)','Depreciado acumulado','Saldo gerencial','Meses registrados'],r.ativos.map(x=>cells([x.codigo,x.descricao,x.local,money(x.valor_centavos),money(x.residual_centavos),String(cents(x.vida_meses)),money(x.depreciado_centavos),money(cents(x.valor_centavos)-cents(x.depreciado_centavos)),String(cents(x.meses))])))+
 (edit&&r.ativos.length?'<form id="corpDepreciar"><div class="finFormRows"><label>Ativo<select id="indDepAtivo" required>'+option('','Selecione')+r.ativos.map(x=>option(x.id,x.codigo+' · '+x.descricao)).join('')+'</select></label>'+input('indDepMes','Competência','month','max="'+esc(mes)+'" value="'+esc(mes)+'"')+'</div><button class="btn primary" type="submit">Registrar depreciação mensal</button></form>':'')+
 table(['Competência','Ativo','Local','Depreciação'],r.depreciacoes.map(x=>cells([x.competencia,x.codigo,x.local,money(x.valor_centavos)])))+'</details>';
}
function bindCadIndustrial(){
 for(const b of el('corpConteudo').querySelectorAll('[data-folha-estorno]'))b.onclick=()=>{const x=state?.cadIndustrial?.folhas.find(v=>v.id===b.dataset.folhaEstorno&&!v.estornado_em);if(!x||!pessoalPermitido()||!dreEditar()||!can('PAGAR',true))return;const m=window.prompt('Justificativa para estornar a folha gerencial:')?.trim();if(m&&m.length>=5&&m.length<=300)void gravar('ew_industrial_estornar_folha',{p_folha_id:x.id,p_motivo:m},b,'Folha gerencial estornada.');};
 const val=id=>el(id).value.trim(),mes=id=>val(id)+'-01';
 const bind=(id,tipo,fn)=>{const form=el(id);if(!form)return;form.onsubmit=ev=>{ev.preventDefault();if(!dreEditar()||(tipo!=='ATIVO'&&!pessoalPermitido()))return;try{const d=fn();if(!state.centros.some(x=>x.id===d.galpao_id))throw Error('Local inválido.');void gravar('ew_industrial_cadastrar',{p_tipo:tipo,p_dados:d},form.querySelector('button[type=submit]'),'Cadastro registrado.');}catch(e){el('corpStatus').textContent=e.message;}};};
 bind('corpFuncionario','FUNCIONARIO',()=>({galpao_id:val('indFuncLocal'),codigo:val('indFuncCodigo'),nome:val('indFuncNome'),funcao:val('indFuncFuncao'),data:val('indFuncData')}));
 bind('corpFolha','FOLHA',()=>({galpao_id:val('indFolhaLocal'),data:mes('indFolhaMes'),salarios:industrialValor('indFolhaSal'),encargos:industrialValor('indFolhaEnc'),beneficios:industrialValor('indFolhaBen'),referencia:val('indFolhaRef')}));
 bind('corpAtivo','ATIVO',()=>({galpao_id:val('indAtivoLocal'),codigo:val('indAtivoCodigo'),nome:val('indAtivoNome'),data:mes('indAtivoMes'),valor:industrialValor('indAtivoValor'),residual:industrialValor('indAtivoResidual'),vida:Number(val('indAtivoVida'))}));
 const f=el('corpDepreciar');if(f)f.onsubmit=ev=>{ev.preventDefault();if(!dreEditar()||!state?.cadIndustrial?.ativos.some(x=>x.id===val('indDepAtivo')))return;void gravar('ew_industrial_depreciar',{p_ativo_id:val('indDepAtivo'),p_competencia:mes('indDepMes')},f.querySelector('button[type=submit]'),'Depreciação histórica registrada.');};
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
 '<label>Categoria<input id="corpCat" maxlength="80" required list="corpCats" placeholder="Selecione ou digite"><datalist id="corpCats">'+['Folha de pagamento','Energia elétrica','Água','Aluguel','Combustível','Impostos','Manutenção','Serviços','Frete','Outras despesas','Outras receitas'].map(v=>option(v,v)).join('')+'</datalist></label>'+
 '<label>Centro de custo<select id="corpCentro">'+option('GERAL','Geral')+option('ADMINISTRATIVO','Administrativo')+r.centros.map(g=>option(g.id,g.nome)).join('')+'</select></label>'+
 '<label>Competência<input id="corpComp" type="date" required value="'+esc(todayLocal())+'"></label></div>'+
 '<label>Valor (R$)<input id="corpValor" inputmode="decimal" required placeholder="0,00"></label><p id="corpOrigemHint" class="hint">Use lançamento manual somente para uma conta sem documento já registrado no EWGEST.</p>'+
 '<button id="corpCriar" type="submit" class="btn primary">Programar conta</button></form></div>':'')+
 '<div class="section panel"><h2>Contas programadas</h2><div class="finFormRows"><label>Tipo<select id="corpFiltroTipo">'+option('','Todas')+option('PAGAR','A pagar')+option('RECEBER','A receber')+'</select></label><label>Situação<select id="corpFiltroSituacao">'+option('ativas','Abertas, parciais e pendentes')+option('','Todas')+option('LIQUIDADO','Liquidadas')+option('CANCELADO','Canceladas')+'</select></label></div>'+
 (r.titulos_total>r.titulos.length?'<p class="hint">Lista limitada aos primeiros 500 registros; indicadores consideram todos os registros autorizados.</p>':'')+
 '<div id="corpTabela"></div><div id="corpBaixaForm"></div></div>'+
 renderPrevisaoTitulos(r)+
 '<div class="section panel"><h2>Movimentos de caixa por centro de custo</h2>'+table(['Centro','Recebimentos','Pagamentos'],r.caixa_centros.map(c=>cells([c.centro_custo,money(c.entradas_centavos),money(c.saidas_centavos)])))+
 '<p class="hint">Movimentos pagos/recebidos, não rentabilidade nem custo industrial. Documentos de obra são inicialmente classificados no centro Geral.</p></div>'+
 (comprasFinanceiro()?renderComprasFinanceiro(r.comprasFinanceiro)+renderFretesHistorico(r.fretesHistorico):'')+
 (drePermitido()?'<div id="corpDre">'+renderDre(r.dre)+'</div><div id="corpRateio">'+renderRateio(r.rateio)+'</div>'+renderIndicadores(r.indicadores)+renderCoberturaIndustrial(r)+renderProdutividade(r.produtividade)+renderHoras(r.horas,r.produtividade,r.centros)+renderSimCusto()+renderCadIndustrial(r.cadIndustrial,r.centros):'');
 if(el('corpForm')){
  el('corpOrigem').addEventListener('change',mudarOrigem);
  el('corpForm').addEventListener('submit',criar);
 }
 for(const id of ['corpFiltroTipo','corpFiltroSituacao'])el(id).addEventListener('change',renderTitulos);
 renderTitulos();if(comprasFinanceiro())bindFrete();if(drePermitido()){bindDre();bindRateio();bindHoras();bindSimCusto();bindCadIndustrial();}bindEstornos();
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
  const [r,dre,rateio,indicadores,compras,produtividade,fretes,horas,cadIndustrial]=await Promise.all([request('/rest/v1/rpc/ew_fin_empresa_consultar',args),drePermitido()?request('/rest/v1/rpc/ew_dre_consultar',args).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_rateio_industrial_consultar',args).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_indicadores_industriais',args).catch(()=>null):null,comprasFinanceiro()?request('/rest/v1/rpc/ew_fin_compras_previsao',{...args,body:{p_empresa_id:id}}).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_industrial_produtividade',args).catch(()=>null):null,comprasFinanceiro()?request('/rest/v1/rpc/ew_fin_fretes_historico',{...args,body:{p_empresa_id:id}}).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_industrial_horas_consultar',args).catch(()=>null):null,drePermitido()?request('/rest/v1/rpc/ew_industrial_cadastros_consultar',args).catch(()=>null):null]);
  if(!valid(n,id,uid))return;state=validate(r);state.dre=drePermitido()?dre:null;
  if(state.dre){try{dreCalcular(state.dre);}catch(e){state.dre=null;}}
  state.cadIndustrial=drePermitido()?cadIndustrial:null;state.fretesHistorico=comprasFinanceiro()?fretes:null;state.horas=drePermitido()?horas:null;state.comprasFinanceiro=comprasFinanceiro()?compras:null;state.produtividade=drePermitido()?produtividade:null;state.indicadores=drePermitido()?indicadores:null;state.rateio=drePermitido()?rateio:null;if(state.rateio){try{rateioValidar(state.rateio);}catch(e){state.rateio=null;}}
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
