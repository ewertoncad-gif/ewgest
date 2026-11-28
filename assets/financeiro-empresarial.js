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
 '<p class="hint">Movimentos pagos/recebidos, não rentabilidade nem custo industrial. Documentos de obra são inicialmente classificados no centro Geral.</p></div>';
 if(el('corpForm')){
  el('corpOrigem').addEventListener('change',mudarOrigem);
  el('corpForm').addEventListener('submit',criar);
 }
 for(const id of ['corpFiltroTipo','corpFiltroSituacao'])el(id).addEventListener('change',renderTitulos);
 renderTitulos();
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
  const r=await request('/rest/v1/rpc/ew_fin_empresa_consultar',{method:'POST',token:session.access_token,timeoutMs:45000,body:{p_empresa_id:id,p_inicio:i.value,p_fim:f.value}});
  if(!valid(n,id,uid))return;state=validate(r);render();el('corpStatus').textContent='Consulta concluída.';
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
