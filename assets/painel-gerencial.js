/* Painel gerencial EWGEST — somente leitura, valores documentais, não DRE. */
(()=>{
'use strict';
const el=id=>document.getElementById(id);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const brl=c=>(c/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const auth=()=>temPermissao('financeiro.consultar')&&temPermissao('relatorios.financeiros')&&temPermissao('compras.consultar_valores');
let seq=0;
function cents(v){
 const n=Number(v);
 if(v===null||v===''||!Number.isFinite(n)||n<0||!Number.isSafeInteger(Math.round(n*100)))throw Error('Valor financeiro inválido na origem.');
 return Math.round(n*100);
}
function integer(v){
 const n=Number(v);
 if(v===null||v===''||!Number.isSafeInteger(n)||n<0)throw Error('Valor em centavos inválido na origem.');
 return n;
}
function calc(faturas,despesas,notas,obras,inicio,fim){
 const dentro=d=>typeof d==='string'&&d.slice(0,10)>=inicio&&d.slice(0,10)<=fim;
 const grupos=new Map(),meses=new Map();
 const nomes=new Map(obras.map(w=>[w.id,w.nome+(w.codigo?' · '+w.codigo:'')]));
 const grupo=id=>{if(!grupos.has(id))grupos.set(id,{nome:nomes.get(id)||'Obra histórica ou indisponível',fab:0,inst:0,despesas:0});return grupos.get(id);};
 const mes=d=>{const k=d.slice(0,7);if(!meses.has(k))meses.set(k,{mes:k,faturado:0,comprasObras:0,comprasEmpresa:0});return meses.get(k);};
 let fab=0,inst=0,desp=0,empresa=0,pendentes=0,docs=0;
 for(const f of faturas){
  if(f.status!=='emitido'||!dentro(f.data_faturamento))continue;
  const v=cents(f.valor_total),g=grupo(f.obra_id);
  if(f.categoria==='fabricacao'){fab+=v;g.fab+=v;}
  else if(f.categoria==='instalacao'){inst+=v;g.inst+=v;}
  else throw Error('Categoria de faturamento não reconhecida.');
  docs++;mes(f.data_faturamento).faturado+=v;
 }
 for(const d of despesas){
  if(!dentro(d.data_documento))continue;
  if(d.status==='pendente'){pendentes++;continue;}
  if(d.status!=='aprovada')continue;
  const v=cents(d.valor);desp+=v;grupo(d.obra_id).despesas+=v;mes(d.data_documento).comprasObras+=v;
 }
 for(const n of notas){
  if(n.status!=='ATIVA'||!dentro(n.data_documento))continue;
  const v=integer(n.valor_centavos);empresa+=v;mes(n.data_documento).comprasEmpresa+=v;
 }
 return {fab,inst,desp,empresa,pendentes,docs,grupos:[...grupos.values()].sort((a,b)=>b.fab+b.inst-a.fab-a.inst||a.nome.localeCompare(b.nome,'pt-BR')),meses:[...meses.values()].sort((a,b)=>a.mes.localeCompare(b.mes))};
}
async function pages(table,params,valid){
 const result=[];
 for(let offset=0;offset<20000;offset+=1000){
  if(!valid())throw Error('Consulta substituída.');
  const p=await apiGet(table,{...params,order:'id.asc',limit:'1000',offset:String(offset)});
  if(!valid())throw Error('Consulta substituída.');
  if(!Array.isArray(p))throw Error('Consulta incompleta de '+table+'.');
  result.push(...p);if(p.length<1000)return result;
 }
 throw Error('Volume superior a 20 mil registros. Reduza o período.');
}
function table(headers,rows){
 return rows.length?'<div class="finTableWrap"><table class="finTable"><thead><tr>'+headers.map(h=>'<th>'+esc(h)+'</th>').join('')+'</tr></thead><tbody>'+rows.map(r=>'<tr>'+r.map(v=>'<td>'+esc(v)+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>':'<p class="hint">Nenhum registro ativo no período.</p>';
}
function renderEstoque(r){
 if(!r||!Array.isArray(r.galpoes))throw Error('Resposta de estoque valorizado incompleta.');
 const fisicas=integer(r.linhas_fisicas),conciliadas=integer(r.linhas_conciliadas),pend=integer(r.pendencias),semEvid=integer(r.fragmentos_sem_evidencia),provado=integer(r.valor_comprovado_centavos);
 const total=r.total_centavos===null?null:integer(r.total_centavos);
 const colunas=['Galpão','Local de estoque','Itens com saldo','Itens conciliados','Alertas','Valor comprovado'];
 const dados=r.galpoes.map(g=>{
  const f=integer(g.linhas_fisicas),c=integer(g.linhas_conciliadas),p=integer(g.pendencias),e=integer(g.fragmentos_sem_evidencia),v=integer(g.valor_comprovado_centavos);
  if(c>f||(!c&&v!==0)||!['OBRA','EMPRESA'].includes(g.tipo))throw Error('Dados de estoque inconsistentes.');
  return {f,c,p,e,v,row:[g.galpao,g.tipo==='OBRA'?'Obras':'Estoque próprio',String(f),String(c),String(p+e),c?brl(v):'—']};
 });
 const soma=k=>dados.reduce((a,g)=>a+g[k],0);
 if(soma('f')!==fisicas||soma('c')!==conciliadas||soma('p')!==pend||soma('e')!==semEvid||soma('v')!==provado||conciliadas>fisicas||
  (pend+semEvid===0?total!==provado:total!==null))throw Error('Totais de estoque não conciliam.');
 return '<div class="section" style="margin:18px 0"><h3>Estoque valorizado · posição atual</h3>'+
 '<div class="stats" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))">'+
 '<div class="stat"><div class="label">Valor total do estoque</div><div class="number" style="font-size:clamp(16px,2vw,23px)">'+(total===null?'A apurar':esc(brl(total)))+'</div></div>'+
 '<div class="stat"><div class="label">Subtotal comprovado</div><div class="number" style="font-size:clamp(16px,2vw,23px)">'+(conciliadas||total!==null?esc(brl(provado)):'—')+'</div></div>'+
 '<div class="stat"><div class="label">Itens com custo conciliado</div><div class="number">'+conciliadas+' / '+fisicas+'</div></div>'+
 '<div class="stat"><div class="label">Alertas de conciliação</div><div class="number">'+(pend+semEvid)+'</div></div></div>'+
 '<p class="hint">Saldo físico de agora, independente do período financeiro. O valor total só é mostrado quando quantidades e custos fiscais de aquisição estão conciliados. Transferências não são novas compras. Materiais já destinados à produção não integram este estoque.</p>'+
 table(colunas,dados.map(g=>g.row))+'</div>';
}
async function carregarEstoque(valid){
 if(!temPermissao('estoque.consultar'))return '';
 try{
  const r=await request('/rest/v1/rpc/ew_estoque_valorizado_resumo',{method:'POST',token:session.access_token,timeoutMs:30000,body:{p_empresa_id:currentCompany.id}});
  if(!valid()||!temPermissao('estoque.consultar'))return '';
  return renderEstoque(r);
 }catch(e){return valid()&&temPermissao('estoque.consultar')?'<h3>Estoque valorizado · posição atual</h3><p class="hint">Não foi possível conciliar o estoque agora. '+esc(e.message)+'</p>':'';}
}
function renderResultados(r){
 if(!r||!['fabrica','obras','itens','manuais'].every(k=>Array.isArray(r[k])))throw Error('Resultado gerencial incompleto.');
 const fab=integer(r.fabricacao_centavos),inst=integer(r.instalacao_centavos),material=integer(r.material_centavos),n=integer(r.consumos),pend=integer(r.consumos_pendentes);
 const manualP=integer(r.manuais_pagar_centavos),manualR=integer(r.manuais_receber_centavos),itensTotal=integer(r.itens_total),semItem=integer(r.material_sem_item_centavos);
 if(pend>n||semItem>material||itensTotal<r.itens.length)throw Error('Indicadores inconsistentes.');
 const soma=(arr,k)=>arr.reduce((a,x)=>a+integer(x[k]),0);
 if(soma(r.fabrica,'faturamento_centavos')!==fab||soma(r.obras,'faturamento_centavos')!==fab+inst||soma(r.fabrica,'material_centavos')!==material||soma(r.obras,'material_centavos')!==material||soma(r.fabrica,'consumos')!==n||soma(r.obras,'consumos')!==n||soma(r.fabrica,'consumos_pendentes')!==pend||soma(r.obras,'consumos_pendentes')!==pend||
 soma(r.manuais.filter(x=>x.tipo==='PAGAR'),'valor_centavos')!==manualP||soma(r.manuais.filter(x=>x.tipo==='RECEBER'),'valor_centavos')!==manualR)throw Error('Totais gerenciais não conciliam.');
 const mat=(v,total,pendentes)=>{v=integer(v);total=integer(total);pendentes=integer(pendentes);if(pendentes>total||(!total&&v))throw Error('Consumo inconsistente.');return total===0?'Sem registro':total===pendentes?'A apurar':brl(v)+(pendentes?' · parcial':'');};
 const area=v=>{const a=Number(v);if(!Number.isFinite(a)||a<0)throw Error('Área inválida.');return a.toLocaleString('pt-BR',{maximumFractionDigits:3});};
 const fabRows=[...r.fabrica].sort((a,b)=>Number(b.faturamento_centavos)-Number(a.faturamento_centavos)).map(g=>[g.fabrica||'A atribuir',brl(integer(g.faturamento_centavos)),area(g.area_expedida_m2)+(integer(g.areas_pendentes)?' · parcial':''),mat(g.material_centavos,g.consumos,g.consumos_pendentes),String(g.consumos_pendentes),'A apurar']);
 return '<div class="section" style="margin:18px 0"><h2>Resultados de fabricação e gestão</h2>'+
 '<h3>Desempenho por fábrica</h3><p class="hint">Receita de fabricação atribuída apenas quando os romaneios válidos anteriores ao faturamento identificam uma única fábrica e cobrem a área faturada. Histórico ambíguo fica em A atribuir. Instalação é separada. Área expedida e material entregue no período podem corresponder a receitas de outros períodos.</p>'+
 table(['Fábrica','Faturamento de fabricação','Área expedida (m²)','Material consumido comprovado','Consumos pendentes','Rentabilidade'],fabRows)+
 '<h3>Custos de materiais por obra</h3>'+table(['Obra','Faturamento total','Material consumido comprovado','Consumos pendentes','Rentabilidade'],r.obras.map(o=>[o.nome+' · '+o.codigo,brl(integer(o.faturamento_centavos)),mat(o.material_centavos,o.consumos,o.consumos_pendentes),String(o.consumos_pendentes),'A apurar']))+
 '<h3>Custos de materiais por código de esquadria</h3><p class="hint">Custo efetivo de materiais entregues à produção e conciliados com aquisição fiscal. Não é custo unitário completo nem custo da mercadoria vendida. Lotes sem vínculo individual permanecem separados, sem rateio arbitrário.</p>'+
 (itensTotal>r.itens.length?'<p class="hint">Mostrando até 500 códigos/grupos; totais incluem todos.</p>':'')+
 table(['Obra','Código','Material comprovado','Consumos pendentes'],r.itens.map(i=>[i.obra,i.codigo||'Lote / sem vínculo individual',mat(i.material_centavos,i.n,i.pendencias),String(i.pendencias)]))+
 '<p class="hint">Material comprovado sem vínculo individual: '+esc(brl(semItem))+'.</p>'+
 '<h3>DRE gerencial · base de apuração</h3><p class="notice">Resultado líquido e margens ainda não disponíveis: faltam classificação por competência, impostos, mão de obra, custos indiretos e apropriação dos custos aos itens efetivamente vendidos. Compras de estoque não são automaticamente despesas do resultado.</p>'+
 table(['Componente','Valor / situação'],[
 ['Receita de fabricação registrada',brl(fab)],['Receita de instalação registrada',brl(inst)],['Receita faturada total',brl(fab+inst)],
 ['Material entregue à produção (não deduzido automaticamente)',mat(material,n,pend)],
 ['Contas manuais a pagar por competência (a classificar)',brl(manualP)],['Contas manuais a receber por competência (a classificar)',brl(manualR)],
 ['Impostos e deduções','A apurar'],['Custo dos itens vendidos','A apurar'],['Mão de obra e custos indiretos','A apurar'],['Despesas administrativas','A classificar'],['Lucro / prejuízo e margem','A apurar']].map(x=>x))+
 '<h3>Contas manuais por categoria e centro de custo</h3>'+table(['Tipo','Categoria','Centro de custo','Valor por competência'],r.manuais.map(m=>[m.tipo==='PAGAR'?'A pagar':'A receber',m.categoria,m.centro_custo,brl(integer(m.valor_centavos))]))+'</div>';
}
async function carregarResultados(valid,inicio,fim){
 if(!temPermissao('estoque.consultar'))return '';
 try{
  const r=await request('/rest/v1/rpc/ew_resultados_gerenciais',{method:'POST',token:session.access_token,timeoutMs:45000,body:{p_empresa_id:currentCompany.id,p_inicio:inicio,p_fim:fim}});
  if(!valid()||!temPermissao('estoque.consultar'))return '';
  return renderResultados(r);
 }catch(e){return valid()&&temPermissao('estoque.consultar')?'<h3>Resultados de fabricação e gestão</h3><p class="hint">Não foi possível apurar os resultados: '+esc(e.message)+'</p>':'';}
}
function render(r){
 const kpi=(label,value)=>'<div class="stat"><div class="label">'+esc(label)+'</div><div class="number" style="font-size:clamp(16px,2vw,23px);overflow-wrap:anywhere">'+esc(value)+'</div></div>';
 return '<div class="stats" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))">'+
 kpi('Faturamento registrado',brl(r.fab+r.inst))+kpi('Fabricação',brl(r.fab))+kpi('Instalação',brl(r.inst))+
 kpi('Despesas aprovadas de obras',brl(r.desp))+kpi('Compras de estoque próprio',brl(r.empresa))+
 kpi('Notas de obras em conferência',String(r.pendentes))+'</div>'+
 '<p class="hint">Documentos ativos no período de emissão. Valores de compras e despesas são exibidos separadamente: podem representar estoque, não consumo. Faturamento não equivale a recebimento. Lucro, caixa e custos industriais ainda não são apurados integralmente. Consulte os indicadores de custos e a base da DRE abaixo.</p>'+
 '<h3>Evolução mensal</h3>'+table(['Mês','Faturamento','Despesas de obras','Compras estoque próprio'],r.meses.map(m=>[m.mes.split('-').reverse().join('/'),brl(m.faturado),brl(m.comprasObras),brl(m.comprasEmpresa)]))+
 '<h3>Desempenho documental por obra</h3>'+table(['Obra','Fabricação','Instalação','Total faturado','Despesas aprovadas'],r.grupos.map(g=>[g.nome,brl(g.fab),brl(g.inst),brl(g.fab+g.inst),brl(g.despesas)]))+
 '<div class="topactions"><button type="button" class="btn secondary" id="gerencialIrFinanceiro">Financeiro das obras</button><button type="button" class="btn secondary" id="gerencialIrEmpresa">Financeiro empresarial</button><button type="button" class="btn secondary" id="gerencialIrRelatorios">Relatórios</button><button type="button" class="btn secondary" id="gerencialIrEstoque">Estoque</button></div>';
}
function limpar(){seq++;el('gerencialPanel').classList.add('hidden');el('gerencialConteudo').replaceChildren();el('gerencialStatus').textContent='';}
async function abrir(){
 limpar();
 if(!auth()||!currentCompany||!session||el('dashboard').classList.contains('hidden'))return;
 el('gerencialPanel').classList.remove('hidden');
 const fim=el('gerencialFim'),inicio=el('gerencialInicio');
 if(!fim.value)fim.value=todayLocal();
 if(!inicio.value)inicio.value=fim.value.slice(0,7)+'-01';
 if(!inicio.value||!fim.value||inicio.value>fim.value){el('gerencialStatus').textContent='Informe um período válido.';return;}
 const id=currentCompany.id,uid=currentUser?.id,n=++seq,ini=inicio.value,end=fim.value;
 const valid=()=>n===seq&&session&&currentCompany?.id===id&&currentUser?.id===uid&&auth()&&!el('dashboard').classList.contains('hidden');
 const filter=(campo)=>({empresa_id:'eq.'+id,and:'('+campo+'.gte.'+ini+','+campo+'.lte.'+end+')'});
 el('gerencialStatus').textContent='Consultando documentos do período…';
 try{
  await ensureSession();if(!valid())return;
  const [f,d,c,o,estoque,resultados]=await Promise.all([
   pages('ew_obra_faturamentos',{...filter('data_faturamento'),select:'id,obra_id,categoria,data_faturamento,valor_total,status'},valid),
   pages('ew_obra_despesas',{...filter('data_documento'),select:'id,obra_id,data_documento,valor,status'},valid),
   pages('ew_compras_notas_empresa',{...filter('data_documento'),select:'id,data_documento,valor_centavos,status'},valid),
   pages('obras',{empresa_id:'eq.'+id,select:'id,nome,codigo'},valid),
   carregarEstoque(valid),carregarResultados(valid,ini,end)
  ]);
  if(!valid())return;
  const r=calc(f,d,c,o,ini,end);
  el('gerencialConteudo').innerHTML=render(r)+(temPermissao('estoque.consultar')?estoque+resultados:'');
  for(const [a,b] of [['gerencialIrFinanceiro','navFinanceiro'],['gerencialIrEmpresa','navFinanceiroEmpresa'],['gerencialIrRelatorios','navRelatorios'],['gerencialIrEstoque','navStock']]){
   const target=el(b),button=el(a);button.disabled=target.disabled;button.addEventListener('click',()=>target.click());
  }
  el('gerencialStatus').textContent=r.docs+' documento(s) de faturamento ativo(s) · Consulta concluída.';
 }catch(e){if(valid()){el('gerencialConteudo').replaceChildren();el('gerencialStatus').textContent='Não foi possível consolidar os dados: '+e.message;}}
}
el('gerencialAtualizar').addEventListener('click',abrir);
for(const id of ['gerencialInicio','gerencialFim'])el(id).addEventListener('change',abrir);
window.ewGerencial=Object.freeze({abrir,limpar});
if(!el('dashboard').classList.contains('hidden'))void abrir();
})();
