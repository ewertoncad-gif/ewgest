/* EWGEST v46.16 — relatórios de consulta. Sem RPC de escrita, sem mutação de estoque. */
(function(){
'use strict';
const el=id=>document.getElementById(id);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const brl=n=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const qtd=n=>Number(n||0).toLocaleString('pt-BR',{maximumFractionDigits:3});
const stamp=d=>{if(!d)return '—';const t=new Date(d);return Number.isFinite(t.getTime())?t.toLocaleString('pt-BR'):'—';};
let rows=[],headers=[],reportTitle='',running=false,summaryCsv=[],summaryHeaders=[];
let obras=[],nomeObras=new Map(),nomeUsuarios=new Map();
// O encerramento não aparece em relatórios operacionais, nem em seus totais.
let obraAtivaIds=new Set();
const tipos={
 ABERTURA:'Abertura manual de estoque',AJUSTE:'Ajuste de estoque',
 COMPRA:'Recebimento físico / compra',IMPORTACAO_CEM:'Importação técnica CEM',
 PLANO_CORTE:'Baixa de produção',PLANO_CORTE_LOTE:'Baixa de lote de corte',
 SAIDA_MANUAL:'Baixa manual',TRANSFERENCIA:'Transferência',ESTORNO:'Estorno'
};
async function listarTudo(table,extra={},limit=1000,max=20000){
 const dados=[];
 for(let offset=0;offset<max;offset+=limit){
  const pagina=await apiGet(table,{...extra,limit:String(limit),offset:String(offset)});
  if(!Array.isArray(pagina))throw new Error('A consulta de '+table+' não retornou uma lista.');
  dados.push(...pagina);
  if(pagina.length<limit)return dados;
 }
 throw new Error('O relatório excedeu '+max+' registros. Reduza o período para evitar um arquivo incompleto.');
}
function selectObras(){
 const selecao=el('reportWork').value;
 el('reportWork').replaceChildren(new Option('Todas as obras',''));
 for(const o of obras){
  const label=o.nome+(o.codigo?' · '+o.codigo:'');
  el('reportWork').add(new Option(label,o.id));
 }
 el('reportWork').value=obras.some(o=>o.id===selecao)?selecao:'';
}
async function carregarCatalogos(){
 if(!currentCompany)throw new Error('Selecione uma empresa.');
 const empresa='eq.'+currentCompany.id;
 const [ob,users]=await Promise.all([
  listarTudo('obras',{select:'id,nome,codigo',empresa_id:empresa,arquivada_em:'is.null',order:'nome.asc'}),
  listarTudo('usuarios_login',{select:'usuario_id,nome,login',empresa_id:empresa,order:'nome.asc'})
 ]);
 obras=ob;obraAtivaIds=new Set(ob.map(o=>o.id));nomeObras=new Map(ob.map(o=>[o.id,o.nome+(o.codigo?' · '+o.codigo:'')]));
 nomeUsuarios=new Map(users.map(u=>[u.usuario_id,u.nome||u.login||String(u.usuario_id).slice(0,8)]));
 selectObras();
 const multi=el('reportWorkChecks');
 const checked=new Set([...multi.querySelectorAll('input:checked')].map(x=>x.value));
 multi.replaceChildren();
 for(const o of obras){
  const lbl=document.createElement('label'),cb=document.createElement('input');
  cb.type='checkbox';cb.value=o.id;cb.checked=checked.has(o.id);
  lbl.append(cb,document.createTextNode(' '+o.nome+(o.codigo?' · '+o.codigo:'')));
  multi.append(lbl);
 }
}
function obra(id){return nomeObras.get(id)||'Obra indisponível';}
function usuario(id){return nomeUsuarios.get(id)||'Usuário '+String(id||'').slice(0,8);}
function dentro(d){
 if(!d)return false;
 if(el('reportFullPeriod').checked)return true;
 const dia=String(d).slice(0,10),ini=el('reportStart').value,fim=el('reportEnd').value;
 return (!ini||dia>=ini)&&(!fim||dia<=fim);
}
function contexto(){
 const ini=el('reportStart').value,fim=el('reportEnd').value;
 if(!el('reportFullPeriod').checked&&ini&&fim&&ini>fim)
  throw new Error('A data inicial não pode ser posterior à data final.');
 const modo=el('reportType').value;
 let obraIds=null;
 if(modo==='faturamento'&&el('reportWorkScope').value==='selected'){
  obraIds=new Set([...el('reportWorkChecks').querySelectorAll('input:checked')].map(x=>x.value));
  if(!obraIds.size)throw new Error('Marque pelo menos uma obra para consolidar o faturamento.');
 }
 return {empresa:'eq.'+currentCompany.id,obraId:['faturamento','custos_empresa','precos_fornecedores'].includes(modo)?'':el('reportWork').value,obraIds,ativas:obraAtivaIds};
}
function tabela(cabecalhos,linhas){
 if(!linhas.length)return '<p class="reportsEmpty">Nenhum registro encontrado nos filtros selecionados.</p>';
 return '<table class="reportsTable"><thead><tr>'+cabecalhos.map(h=>'<th>'+esc(h)+'</th>').join('')+
 '</tr></thead><tbody>'+linhas.map(l=>'<tr>'+l.map(c=>'<td>'+esc(c)+'</td>').join('')+'</tr>').join('')+'</tbody></table>';
}
function agruparPorObra(faturas){
 const mapa=new Map();
 for(const f of faturas){
  const k=f.obra_id;
  if(!mapa.has(k))mapa.set(k,{obra:obra(k),fab:0,inst:0,documentos:0});
  const v=mapa.get(k);const valor=Number(f.valor_total)||0;
  if(f.categoria==='fabricacao')v.fab+=valor;
  else if(f.categoria==='instalacao')v.inst+=valor;
  v.documentos++;
 }
 return [...mapa.values()].sort((a,b)=>a.obra.localeCompare(b.obra,'pt-BR'));
}
async function faturamento(ctx){
 const base={empresa_id:ctx.empresa,select:'id,obra_id,categoria,data_faturamento,numero_documento,valor_total,status,cancelado_em,criado_por,criado_em,observacoes',order:'criado_em.asc'};
 const [faturas,itens,esq]=await Promise.all([
  listarTudo('ew_obra_faturamentos',base),
  listarTudo('ew_obra_faturamentos_itens',{empresa_id:ctx.empresa,select:'faturamento_id,esquadria_id,quantidade,valor_unitario,valor_total'}),
  listarTudo('esquadrias',{empresa_id:ctx.empresa,select:'id,codigo,descricao,obra_id'})
 ]);
 const codes=new Map(esq.map(e=>[e.id,e]));
 const linhasPorFat=new Map();
 for(const item of itens){if(!linhasPorFat.has(item.faturamento_id))linhasPorFat.set(item.faturamento_id,[]);linhasPorFat.get(item.faturamento_id).push(item);}
 const filtro=faturas.filter(f=>ctx.ativas.has(f.obra_id)&&(!ctx.obraIds||ctx.obraIds.has(f.obra_id))&&dentro(f.data_faturamento));
 const ativos=filtro.filter(f=>!f.cancelado_em&&String(f.status).toLowerCase()!=='cancelado');
 const exibidos=el('reportCancelled').checked?filtro:ativos;
 const resumo=agruparPorObra(ativos);
 const totalFab=resumo.reduce((n,x)=>n+x.fab,0),totalInst=resumo.reduce((n,x)=>n+x.inst,0);
 summaryHeaders=['Obra','Documentos','Fabricação','Instalação','Total'];
 summaryCsv=[...resumo.map(x=>[x.obra,x.documentos,brl(x.fab),brl(x.inst),brl(x.fab+x.inst)]),
  ['TOTAL GERAL',ativos.length,brl(totalFab),brl(totalInst),brl(totalFab+totalInst)]];
 let sum='<div class="reportsKpis"><div><span>Faturado ativo</span><strong>'+brl(totalFab+totalInst)+'</strong></div>'+
 '<div><span>Fabricação</span><strong>'+brl(totalFab)+'</strong></div>'+
 '<div><span>Instalação</span><strong>'+brl(totalInst)+'</strong></div>'+
 '<div><span>Documentos ativos</span><strong>'+ativos.length+'</strong></div></div>';
 sum+='<h3>Totais por obra</h3>'+tabela(['Obra','Documentos','Fabricação','Instalação','Total'],
  summaryCsv);
 el('reportSummary').innerHTML=sum;
 headers=['Obra','Data','Documento','Categoria','Situação','Esquadria','Descrição','Quantidade','Valor unitário','Valor item','Valor documento','Registrado por','Observações'];
 rows=[];
 for(const f of exibidos){
  const lista=linhasPorFat.get(f.id)||[null];
  for(const i of lista){
   const e=i?codes.get(i.esquadria_id):null;
   rows.push([
    obra(f.obra_id),String(f.data_faturamento).slice(0,10),f.numero_documento,
    f.categoria==='fabricacao'?'Fabricação':f.categoria==='instalacao'?'Instalação':f.categoria,
    f.cancelado_em||String(f.status).toLowerCase()==='cancelado'?'CANCELADO':String(f.status).toUpperCase(),
    e?.codigo||'',e?.descricao||'',i?qtd(i.quantidade):'',i?brl(i.valor_unitario):'',
    i?brl(i.valor_total):'',brl(f.valor_total),usuario(f.criado_por),f.observacoes||''
   ]);
  }
 }
 reportTitle='Faturamentos por obra';
 el('reportTable').innerHTML='<h3>Documentos e itens faturados</h3>'+
 tabela(headers,rows)+'<p class="hint">Valores de documentos cancelados não entram nos totais. O valor do documento pode repetir nas linhas de seus itens; não some essa coluna.</p>';
 return {contagem:filtro.length,visiveis:exibidos.length};
}
function materialIndex(vars,perfis,acess){
 const p=new Map(perfis.map(x=>[x.id,x])),a=new Map(acess.map(x=>[x.id,x]));
 return new Map(vars.map(v=>{
  const item=v.perfil_id?p.get(v.perfil_id):a.get(v.acessorio_id);
  return [v.id,{codigo:item?.codigo||'Sem código',
    descricao:item?.descricao||'Material histórico',cor:v.cor||v.acabamento||''}];
 }));
}
function rotuloMovimento(m,porTransferencia,nfeMap){
 if(m.origem!=='TRANSFERENCIA'){
  const original=m.estorno_de_id?' · Referência '+String(m.estorno_de_id).slice(0,8):'';
  const nfe=nfeMap.get(m.id);
  return (tipos[m.origem]||m.origem)+original+(nfe?' · Recebimento físico NF-e':'');
 }
 const outros=(porTransferencia.get(m.transferencia_id)||[]).filter(x=>x.id!==m.id);
 const par=outros.find(x=>Number(x.quantidade_delta)===-Number(m.quantidade_delta) &&
  x.variacao_id===m.variacao_id && x.unidade===m.unidade);
 if(!par)return 'Transferência sem par identificado — conferir';
 if(par.obra_id!==m.obra_id)
  return Number(m.quantidade_delta)<0?'Enviado para '+obra(par.obra_id):'Recebido de '+obra(par.obra_id);
 return Number(m.quantidade_delta)<0?'Saída para galpão '+par.local_estoque:
  'Recebido do galpão '+par.local_estoque;
}
async function estoque(ctx){
 const [movs,vars,perfis,acess,nfes]=await Promise.all([
  listarTudo('ew_estoque_obras_movimentos',{empresa_id:ctx.empresa,
   select:'id,empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,criado_em,local_estoque,estorno_de_id,transferencia_id,observacao,usuario_id',order:'criado_em.asc'}),
  listarTudo('ew_materiais_variacoes',{empresa_id:ctx.empresa,select:'id,perfil_id,acessorio_id,cor,acabamento'}),
  listarTudo('ew_perfis',{empresa_id:ctx.empresa,select:'id,codigo,descricao'}),
  listarTudo('ew_acessorios',{empresa_id:ctx.empresa,select:'id,codigo,descricao'}),
  listarTudo('ew_nfe_recebimentos',{empresa_id:ctx.empresa,select:'movimento_id,estornado_em'})
 ]);
 const materiais=materialIndex(vars,perfis,acess);
 const nfeMap=new Map(nfes.map(x=>[x.movimento_id,x]));
 const transfers=new Map(),saldos=new Map();
 for(const m of movs)if(m.transferencia_id){
  if(!transfers.has(m.transferencia_id))transfers.set(m.transferencia_id,[]);
  transfers.get(m.transferencia_id).push(m);
 }
 const linhaMov=movs.map(m=>{
  const mat=materiais.get(m.variacao_id)||{codigo:'Sem código',descricao:'Cadastro histórico',cor:''};
  const chave=JSON.stringify([m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque]);
  const atual=(saldos.get(chave)||0)+Number(m.quantidade_delta);
  saldos.set(chave,atual);
  const delta=Number(m.quantidade_delta);
  return {m,linha:[obra(m.obra_id),stamp(m.criado_em),mat.codigo,mat.descricao,mat.cor,
   m.comprimento_mm?String(Number(m.comprimento_mm)/1000).replace('.',',')+' m':'—',
   m.local_estoque||'—',rotuloMovimento(m,transfers,nfeMap),
   (delta>0?'+':'')+qtd(delta),m.unidade,qtd(atual),usuario(m.usuario_id),
   m.observacao||'',String(m.id)]};
 });
 const filtros=new Set([...document.querySelectorAll('[data-report-stock]:checked')].map(x=>x.dataset.reportStock));
 if(!filtros.size)throw new Error('Marque pelo menos um tipo de movimentação.');
 const classificacao=m=>{
  if(m.origem==='TRANSFERENCIA'){
   const par=(transfers.get(m.transferencia_id)||[]).find(p=>p.id!==m.id);
   return par&&par.obra_id!==m.obra_id?'obras':'galpoes';
  }
  if(m.origem==='COMPRA'||m.origem==='ABERTURA')return 'recebimento';
  if(m.origem==='PLANO_CORTE'||m.origem==='PLANO_CORTE_LOTE'||m.origem==='SAIDA_MANUAL')return 'producao';
  if(m.origem==='SAIDA_OBRA')return 'direto';
  return 'outros';
 };
 const filtradas=linhaMov.filter(({m})=>ctx.ativas.has(m.obra_id)&&(!ctx.obraId||m.obra_id===ctx.obraId)&&
  dentro(m.criado_em)&&filtros.has(classificacao(m)))
  .reverse();
 headers=['Obra','Data/hora','Código','Material','Cor','Barra','Galpão','Operação',
  'Movimento','Unidade','Saldo após movimento','Responsável','Observações','ID movimento'];
 rows=filtradas.map(x=>x.linha);
 const entradas=filtradas.filter(x=>Number(x.m.quantidade_delta)>0).length;
 const saidas=filtradas.filter(x=>Number(x.m.quantidade_delta)<0).length;
 el('reportSummary').innerHTML='<div class="reportsKpis">'+
 '<div><span>Movimentações</span><strong>'+rows.length+'</strong></div>'+
 '<div><span>Entradas / contrapartidas positivas</span><strong>'+entradas+'</strong></div>'+
 '<div><span>Saídas / contrapartidas negativas</span><strong>'+saidas+'</strong></div></div>'+
 '<p class="hint">A quantidade é mostrada na unidade original de cada material; não se somam barras, peças e metros. '+
 'Os saldos são por material, comprimento, obra e galpão e incluem movimentos anteriores ao período selecionado.</p>';
 reportTitle='Movimentações de estoque por obra';
 el('reportTable').innerHTML='<h3>Histórico de movimentações</h3>'+tabela(headers,rows);
 return {contagem:rows.length};
}
function resumoKpi(pares){
 return '<div class="reportsKpis">'+pares.map(([a,b])=>'<div><span>'+esc(a)+'</span><strong>'+esc(b)+'</strong></div>').join('')+'</div>';
}
async function liberacoes(ctx){
 const [releases,esqs,batches]=await Promise.all([
  listarTudo('liberacoes_corte',{select:'id,esquadria_id,quantidade,data_liberacao,usuario_id,registrada_em,fabrica,cancelado_em,tipo_componente',order:'registrada_em.asc'}),
  listarTudo('esquadrias',{empresa_id:ctx.empresa,select:'id,codigo,descricao,obra_id'}),
  listarTudo('ew_liberacoes_lotes',{empresa_id:ctx.empresa,select:'id,obra_id,data_liberacao,fabrica,arquivo_nome,itens_confirmados,criado_por,criado_em,cancelado_em,entregue_em'})
 ]);
 const esq=new Map(esqs.map(x=>[x.id,x]));
 const incluirCancelados=el('reportCancelled').checked;
 const eventos=releases.map(x=>({...x,elemento:esq.get(x.esquadria_id)}))
  .filter(x=>x.elemento&&ctx.ativas.has(x.elemento.obra_id)&&(!ctx.obraId||x.elemento.obra_id===ctx.obraId)&&
    dentro(x.data_liberacao)&&(!x.cancelado_em||incluirCancelados));
 const lotes=batches.filter(x=>ctx.ativas.has(x.obra_id)&&(!ctx.obraId||x.obra_id===ctx.obraId)&&
  dentro(x.data_liberacao)&&(!x.cancelado_em||incluirCancelados));
 const validas=eventos.filter(x=>!x.cancelado_em);
 headers=['Obra','Data','Tipo','Esquadria / Lote','Descrição','Parte liberada','Quantidade',
  'Fábrica','Situação','Material entregue à produção','Responsável','ID'];
 rows=eventos.map(x=>[obra(x.elemento.obra_id),String(x.data_liberacao), 'Liberação',
  x.elemento.codigo,x.elemento.descricao||'',x.tipo_componente||'completo',qtd(x.quantidade),
  x.fabrica||'Não informada',x.cancelado_em?'CANCELADA':'ATIVA','Ver documento de entrega',
  usuario(x.usuario_id),x.id]);
 rows.push(...lotes.map(x=>[obra(x.obra_id),String(x.data_liberacao),'Lote técnico',
  x.arquivo_nome||'Lote CEM','Itens vinculados: '+(Array.isArray(x.itens_confirmados)?x.itens_confirmados.length:'—'),
  'Lote','—',x.fabrica||'—',x.cancelado_em?'CANCELADO':'ATIVO',
  x.entregue_em?'Entregue em '+stamp(x.entregue_em):'Aguardando entrega',usuario(x.criado_por),x.id]));
 reportTitle='Liberações para fabricação';
 el('reportSummary').innerHTML=resumoKpi([
  ['Liberações ativas',String(validas.length)],['Quantidades liberadas',qtd(validas.reduce((n,x)=>n+Number(x.quantidade||0),0))],
  ['Lotes técnicos ativos',String(lotes.filter(x=>!x.cancelado_em).length)],
  ['Registros no filtro',String(rows.length)]])+
 '<p class="hint">As quantidades de marcos e folhas não são somadas como unidades completas. '+
 'O lote técnico é apresentado em separado; não some sua quantidade com liberações de esquadrias.</p>';
 el('reportTable').innerHTML=tabela(headers,rows);
 return {contagem:rows.length};
}
// Reconstitui área histórica apenas quando o romaneio não a armazenou.
function areaLinha(item,folhasConfig){
 if(item.natureza!=='esquadria')return null;
 const salvo=Number(item.area_m2);
 if(!item.composicao_revisao_id&&item.area_m2!==null&&item.area_m2!==undefined&&Number.isFinite(salvo)&&salvo>0)return salvo;
 const raw=String(item.medida||'').trim();
 const match=raw.match(/^(\\d[\\d.,]*)\\s*[x×]\\s*(\\d[\\d.,]*)\\s*mm$/i);
 if(!match)return null;
 const valor=s=>{
  let text=s;
  if(text.includes(','))text=text.replace(/\\./g,'').replace(',','.');
  else if(/^\\d{1,3}(?:\\.\\d{3})+$/.test(text))text=text.replace(/\\./g,'');
  return Number(text);
 };
 const largura=valor(match[1]),altura=valor(match[2]),q=Number(item.quantidade);
 if(!(largura>0&&altura>0&&Number.isInteger(q)&&q>0))return null;
 if(item.composicao_revisao_id){const eq=Number(item.equivalente_expedido);return Number.isFinite(eq)&&eq>0?largura*altura*eq/1000000:null;}
 let fracao=1;
 if(item.tipo_saida==='marco')fracao=.5;
 else if(item.tipo_saida==='folha'){
  const folhas=Number(folhasConfig.get(item.esquadria_id));
  if(!Number.isSafeInteger(folhas)||folhas<1)return null;
  fracao=.5/folhas;
 }else if(item.tipo_saida&&item.tipo_saida!=='completo')return null;
 return Math.round(largura*altura*q*fracao/1000)/1000;
}
async function expedicao(ctx){
 const [docs,itens,composicoes]=await Promise.all([
  listarTudo('romaneios',{empresa_id:ctx.empresa,
   select:'id,obra_id,numero,data_saida,motorista,placa,status,cancelado_em,criado_por,observacoes',order:'data_saida.asc'}),
  listarTudo('romaneios_itens',{select:'id,romaneio_id,natureza,esquadria_id,codigo,descricao,tipo_saida,quantidade,unidade,area_m2,fabrica,medida,localizacao,componente_nome,composicao_revisao_id,equivalente_expedido',order:'sequencia.asc'}),
  listarTudo('esquadrias_saida_config',{select:'esquadria_id,folhas_por_unidade'})
 ]);
 const porDoc=new Map(docs.map(x=>[x.id,x]));
 const partes=new Map(composicoes.map(x=>[x.esquadria_id,x.folhas_por_unidade]));
 const incluirCancelados=el('reportCancelled').checked;
 const filtrados=itens.map(i=>({i,doc:porDoc.get(i.romaneio_id)}))
 .filter(x=>x.doc&&ctx.ativas.has(x.doc.obra_id)&&(!ctx.obraId||x.doc.obra_id===ctx.obraId)&&dentro(x.doc.data_saida)&&
 (incluirCancelados||(!x.doc.cancelado_em&&String(x.doc.status).toLowerCase()!=='cancelado')));
 const ativos=filtrados.filter(x=>!x.doc.cancelado_em&&String(x.doc.status).toLowerCase()!=='cancelado');
 const codDocs=new Set(ativos.map(x=>x.doc.id)),area=ativos.reduce((n,x)=>n+Number(areaLinha(x.i,partes)||0),0);
 const semArea=ativos.filter(x=>x.i.natureza==='esquadria'&&areaLinha(x.i,partes)===null).length;
 headers=['Obra','Data de saída','Romaneio','Status','Tipo','Código','Descrição',
 'Componente / natureza','Medida','Quantidade','Unidade','Área expedida m²','Fábrica',
 'Motorista','Placa','Emitido por','ID item'];
 rows=filtrados.map(({doc,i})=>[obra(doc.obra_id),String(doc.data_saida),doc.numero,
  doc.cancelado_em||String(doc.status).toLowerCase()==='cancelado'?'CANCELADO':doc.status,
  i.natureza==='esquadria'?'Esquadria':'Material',i.codigo,i.descricao,
  i.componente_nome||i.tipo_saida||i.natureza,i.medida||'',qtd(i.quantidade),i.unidade,
  areaLinha(i,partes)===null?'':qtd(areaLinha(i,partes)),i.fabrica||'',doc.motorista,doc.placa,
  usuario(doc.criado_por),i.id]);
 reportTitle='Romaneios de expedição fábrica → obra';
 el('reportSummary').innerHTML=resumoKpi([
 ['Romaneios ativos',String(codDocs.size)],['Área expedida',qtd(area)+' m²'],
 ['Itens de esquadrias',String(ativos.filter(x=>x.i.natureza==='esquadria').length)],
 ['Itens de materiais',String(ativos.filter(x=>x.i.natureza==='material').length)]])+
 '<p class="hint">O total considera apenas documentos ativos. Área de marco e folhas é parcial. '+
 'Perfis e acessórios expedidos separadamente não acrescentam m² de esquadrias.'+
 (semArea?' <strong>Atenção: '+semArea+' linha(s) de esquadria sem área calculável.</strong>':'')+'</p>';
 el('reportTable').innerHTML=tabela(headers,rows);
 return {contagem:rows.length};
}
async function aluminio(ctx){
 const [docs,itens,movs,vars,perfis,composicoes]=await Promise.all([
  listarTudo('romaneios',{empresa_id:ctx.empresa,select:'id,obra_id,data_saida,status,cancelado_em'}),
  listarTudo('romaneios_itens',{select:'romaneio_id,natureza,area_m2,esquadria_id,tipo_saida,medida,quantidade,composicao_revisao_id,equivalente_expedido'}),
  listarTudo('ew_estoque_obras_movimentos',{empresa_id:ctx.empresa,
    select:'id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,criado_em,estorno_de_id'}),
  listarTudo('ew_materiais_variacoes',{empresa_id:ctx.empresa,select:'id,perfil_id,tipo'}),
  listarTudo('ew_perfis',{empresa_id:ctx.empresa,select:'id,codigo,peso_kg_m'}),
  listarTudo('esquadrias_saida_config',{select:'esquadria_id,folhas_por_unidade'})
 ]);
 const porDoc=new Map(docs.map(d=>[d.id,d]));
 const partes=new Map(composicoes.map(x=>[x.esquadria_id,x.folhas_por_unidade]));
 const areaPorObra=new Map(),kgPorObra=new Map(),faltaPeso=new Map(),faltaArea=new Map();
 for(const i of itens){
  const d=porDoc.get(i.romaneio_id);
  if(!d||!ctx.ativas.has(d.obra_id)||d.cancelado_em||String(d.status).toLowerCase()==='cancelado'||
    (ctx.obraId&&d.obra_id!==ctx.obraId)||!dentro(d.data_saida)||i.natureza!=='esquadria')continue;
  const m2=areaLinha(i,partes);
  if(m2===null){faltaArea.set(d.obra_id,(faltaArea.get(d.obra_id)||0)+1);continue;}
  areaPorObra.set(d.obra_id,(areaPorObra.get(d.obra_id)||0)+m2);
 }
 const variacoes=new Map(vars.map(x=>[x.id,x])),catalogo=new Map(perfis.map(x=>[x.id,x]));
 const estornados=new Set(movs.filter(x=>x.estorno_de_id).map(x=>x.estorno_de_id));
 const elegiveis=movs.filter(x=>['PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_OBRA'].includes(x.origem)&&
  Number(x.quantidade_delta)<0);
 for(const m of elegiveis){
  if(!ctx.ativas.has(m.obra_id)||(ctx.obraId&&m.obra_id!==ctx.obraId)||!dentro(m.criado_em)||estornados.has(m.id))continue;
  const v=variacoes.get(m.variacao_id);
  if(v?.tipo!=='perfil')continue;
  const p=catalogo.get(v.perfil_id),peso=Number(p?.peso_kg_m);
  if(!(peso>0)||!(Number(m.comprimento_mm)>0)||m.unidade!=='BARRA'){
   faltaPeso.set(m.obra_id,(faltaPeso.get(m.obra_id)||0)+1);continue;
  }
  const kg=Math.abs(Number(m.quantidade_delta))*Number(m.comprimento_mm)/1000*peso;
  kgPorObra.set(m.obra_id,(kgPorObra.get(m.obra_id)||0)+kg);
 }
 const obrasRel=new Set([...areaPorObra.keys(),...kgPorObra.keys(),...faltaPeso.keys(),...faltaArea.keys()]);
 if(ctx.obraId)obrasRel.add(ctx.obraId);
 const rel=[...obrasRel].map(id=>({id,area:areaPorObra.get(id)||0,
  kg:kgPorObra.get(id)||0,naoPesados:faltaPeso.get(id)||0,semArea:faltaArea.get(id)||0}))
  .sort((a,b)=>obra(a.id).localeCompare(obra(b.id),'pt-BR'));
 const somaArea=rel.reduce((n,x)=>n+x.area,0),somaKg=rel.reduce((n,x)=>n+x.kg,0),
 naoPesados=rel.reduce((n,x)=>n+x.naoPesados,0),semArea=rel.reduce((n,x)=>n+x.semArea,0);
 headers=['Obra','m² expedidos (parcial + completo)','Alumínio destinado kg',
  'Alumínio destinado t','kg por m² expedido','Linhas sem peso/tamanho','Linhas sem área','Qualidade do dado'];
 rows=rel.map(x=>[obra(x.id),qtd(x.area),qtd(x.kg),qtd(x.kg/1000),
  x.area>0?qtd(x.kg/x.area):'—',x.naoPesados,x.semArea,
  x.naoPesados?'Peso incompleto / não conclusivo':'Indicador de expedição + fornecimento']);
 rows.push(['TOTAL DAS OBRAS',qtd(somaArea),qtd(somaKg),qtd(somaKg/1000),
  somaArea>0?qtd(somaKg/somaArea):'—',naoPesados,semArea,
  naoPesados||semArea?'Índice parcial':'Indicador']);
 reportTitle='m² expedidos versus alumínio destinado';
 el('reportSummary').innerHTML=resumoKpi([
  ['m² expedidos',qtd(somaArea)+' m²'],
  ['Alumínio destinado',qtd(somaKg/1000)+' t'],
  ['Consumo específico indicativo',somaArea?qtd(somaKg/somaArea)+' kg/m²':'—'],
  ['Linhas sem peso/área',String(naoPesados+semArea)]
 ])+
 '<p class="hint"><strong>Limitação:</strong> o EWGEST ainda não registra conclusão física de fabricação nem '+
 'pesagem real de sucata. O m² corresponde à esquadria <strong>expedida</strong> (marcos/folhas proporcionais); '+
 'o alumínio corresponde a barras entregues à produção ou enviadas diretamente à obra. '+
 'Transferências entre galpões/obras NÃO contam como consumo. Estornos de consumo integral vinculados '+
 'são desconsiderados. O peso utiliza o cadastro técnico atualmente disponível, e pode mudar se os pesos forem revisados. '+
 'Não representa rendimento exato, perda nem índice definitivo até reconciliar '+
 'estornos parciais e pesos faltantes.</p>';
 el('reportTable').innerHTML=tabela(headers,rows);
 return {contagem:rows.length};
}
async function precos_fornecedores(ctx){
 const dados=[];
 for(let offset=0;offset<=100000;offset+=500){
  const page=await request('/rest/v1/rpc/ew_compras_historico_precos',{method:'POST',token:session.access_token,body:{p_empresa_id:currentCompany.id,p_fornecedor_id:null,p_variacao_id:null,p_offset:offset}});
  if(!Array.isArray(page))throw Error('Histórico indisponível.');
  dados.push(...page);if(page.length<500)break;
  if(offset===100000)throw Error('Histórico acima do limite de consulta.');
 }
 const seen=new Set();const filtered=dados.filter(x=>dentro(x.criado_em));
 headers=['Fornecedor','Código','Descrição','Cor','Acabamento','Comprimento mm','Unidade','Preço unitário','Quantidade cotada','Data da cotação','Situação','Pedido aprovado','Referência'];
 rows=filtered.map(x=>{
  const key=[x.fornecedor_id,x.variacao_id,x.unidade,x.comprimento_mm].join('|');
  const latest=!seen.has(key)&&x.status!=='CANCELADA';if(latest)seen.add(key);
  return [x.fornecedor,x.codigo||'',x.descricao||'',x.cor||'',x.acabamento||'',x.comprimento_mm??'',x.unidade,brl(Number(x.preco_unitario_centavos)/100),qtd(x.quantidade),stamp(x.criado_em),x.status==='CANCELADA'?'Cancelada':latest?'Última válida no período':'Histórica',x.pedido_aprovado?'Sim':'Não',x.cotacao_id];
 });
 reportTitle='Histórico de preços por fornecedor';
 el('reportSummary').innerHTML='<p class="hint">Preços das cotações, inclusive histórico cancelado identificado. Não alteram orçamento ou preço-base das esquadrias. Descrições seguem o catálogo atual; a variação e o preço são os da cotação.</p>';
 el('reportTable').innerHTML=tabela(headers,rows);return {contagem:rows.length};
}
async function gerar(){
 if(running||!podeVerRelatorios()||!currentCompany)return;
 rows=[];headers=[];summaryCsv=[];summaryHeaders=[];el('reportCsv').disabled=true;el('reportPrint').disabled=true;
 el('reportTable').replaceChildren();el('reportSummary').replaceChildren();
 const tipo=el('reportType').value;
 if(tipo==='precos_fornecedores'&&!(temPermissao('compras.historico_precos')&&temPermissao('compras.consultar_valores'))){el('reportStatus').textContent='Sem permissão para consultar preços de fornecedores.';return;}
 if((tipo==='faturamento'&&!temPermissao('relatorios.financeiros'))||
   (tipo==='custos_empresa'&&!(temPermissao('relatorios.financeiros')&&temPermissao('compras.consultar_valores')&&temPermissao('financeiro.consultar')))){
  el('reportStatus').textContent='Seu nível não permite consultar relatórios financeiros.';return;
 }
 running=true;el('reportGenerate').disabled=true;
 el('reportStatus').textContent=tipo==='custos_empresa'?'Consultando notas do estoque da empresa…':'Consultando registros das obras em andamento…';
 try{
  await ensureSession();
  await carregarCatalogos();
  const ctx=contexto();
  if(ctx.obraId && !obras.some(o=>o.id===ctx.obraId))throw new Error('A obra não está mais disponível para consulta.');
  el('reportWork').value=ctx.obraId;
  if(tipo==='custos_empresa'){
   if(!window.ewCustosEmpresa)throw new Error('Módulo financeiro de estoque não foi carregado.');
   const res=await window.ewCustosEmpresa.gerar({
    empresaId:currentCompany.id,
    localId:el('reportCompanyLocal').value,
    fornecedorId:el('reportCompanySupplier').value,
    inicio:el('reportFullPeriod').checked?'':el('reportStart').value,
    fim:el('reportFullPeriod').checked?'':el('reportEnd').value,
    incluirCanceladas:el('reportCancelled').checked
   });
   reportTitle=res.title;headers=res.headers;rows=res.rows;
   summaryHeaders=res.summaryHeaders;summaryCsv=res.summaryCsv;
   el('reportSummary').innerHTML=res.summaryHtml;
   el('reportTable').innerHTML='<h3>Notas e custos do estoque da empresa</h3>'+tabela(headers,rows)+
    '<p class="hint">Cada nota aparece uma vez; o total de custos ativos está no resumo. Valores cancelados não entram na soma. Não misturar com despesas das obras.</p>';
   el('reportStatus').textContent='Relatório concluído: '+res.notesCount+' nota(s) encontrada(s), '+res.shown+
    ' apresentada(s). Valores ativos sem notas canceladas; consulta sem movimentações.';
  }else{
   const geradores={faturamento,estoque,liberacoes,expedicao,aluminio,precos_fornecedores};
   if(!geradores[tipo])throw new Error('Relatório inexistente.');
   const res=await geradores[tipo](ctx);
   el('reportStatus').textContent='Relatório concluído: '+res.contagem+' registro(s) consultado(s). '+
    (tipo==='faturamento'?'Totais excluem documentos cancelados.':'Consulta sem alteração dos registros.');
  }
  el('reportCsv').disabled=!rows.length;el('reportPrint').disabled=!rows.length;
 }catch(e){el('reportStatus').textContent='Não foi possível gerar: '+e.message;}
 finally{running=false;el('reportGenerate').disabled=false;}
}
function csv(){
 if(!rows.length)return;
 const enc=v=>{
  const texto=String(v??'');
  // Impede que códigos, descrições ou observações virem fórmulas ao abrir no Excel.
  const seguro=/^[\\s\\r\\n]*[=+@-]/.test(texto)?"'"+texto:texto;
  return '"'+seguro.replace(/"/g,'""')+'"';
 };
 const tabelaPrincipal=[headers,...rows].map(r=>r.map(enc).join(';')).join('\r\n');
 const resumo=summaryHeaders.length?[
  (el('reportType').value==='custos_empresa'?'RESUMO DOS CUSTOS POR LOCAL DA EMPRESA':'RESUMO POR OBRA'),summaryHeaders.map(enc).join(';'),
  ...summaryCsv.map(r=>r.map(enc).join(';')),'','DETALHAMENTO',''
 ].join('\r\n'):'';
 const text='\ufeff'+resumo+tabelaPrincipal;
 const url=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8;'}));
 const a=document.createElement('a');a.href=url;
 a.download=el('reportType').value+
  '_ewgest_'+new Date().toISOString().slice(0,10)+'.csv';
 document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function imprimir(){
 if(!rows.length)return;
 const w=window.open('about:blank','_blank');
 if(!w){el('reportStatus').textContent='Permita a abertura de guias para imprimir o relatório.';return;}
 const html='<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>'+
  esc(reportTitle)+' · EWGEST</title><style>body{font:11px Arial,sans-serif;color:#14243a;margin:20px}'+
  'h1{font-size:18px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #cbd5e1;padding:5px;text-align:left;vertical-align:top}'+
  'th{background:#edf3fa}thead{display:table-header-group}@page{size:landscape;margin:12mm}</style></head><body>'+
  '<h1>EWGEST · '+esc(reportTitle)+'</h1><p>Gerado em '+esc(stamp(new Date().toISOString()))+
  (el('reportType').value==='custos_empresa'?' · Relatório de locais próprios da empresa':
   ' · Obra: '+esc(el('reportWork').selectedOptions[0]?.text||'Todas as obras'))+'</p>'+
  el('reportSummary').innerHTML+tabela(headers,rows)+'</body></html>';
 w.document.open();w.document.write(html);w.document.close();w.focus();w.print();
}
el('navRelatorios').addEventListener('click',async()=>{
 if(!podeVerRelatorios())return;
 setView('relatorios');
 exibirFiltros();
 el('reportStatus').textContent='Consulta sem movimentação de estoque. Clique em Gerar relatório.';
 el('reportTable').replaceChildren();el('reportSummary').replaceChildren();
 el('reportCsv').disabled=true;el('reportPrint').disabled=true;rows=[];
 try{
  await ensureSession();await carregarCatalogos();
  if(el('reportType').value==='custos_empresa'&&window.ewCustosEmpresa)
   await window.ewCustosEmpresa.carregarFiltros(currentCompany.id);
 }catch(e){el('reportStatus').textContent='Erro ao preparar filtros dos relatórios: '+e.message;}
});
function exibirFiltros(){
 const finance=temPermissao('relatorios.financeiros');
 const pricesAllowed=temPermissao('compras.historico_precos')&&temPermissao('compras.consultar_valores');
 const priceOption=el('reportType').querySelector('[value="precos_fornecedores"]');
 if(priceOption){priceOption.disabled=!pricesAllowed;priceOption.hidden=!pricesAllowed;}
 if(!pricesAllowed&&el('reportType').value==='precos_fornecedores')el('reportType').value='estoque';
 const option=el('reportType').querySelector('[value="faturamento"]');
 if(option){option.disabled=!finance;option.hidden=!finance;}
 const corpAllowed=finance&&temPermissao('financeiro.consultar')&&temPermissao('compras.consultar_valores');
 const companyOption=el('reportType').querySelector('[value="custos_empresa"]');
 if(companyOption){companyOption.disabled=!corpAllowed;companyOption.hidden=!corpAllowed;}
 if((!finance&&el('reportType').value==='faturamento')||
    (!corpAllowed&&el('reportType').value==='custos_empresa'))el('reportType').value='estoque';
 const tipo=el('reportType').value,isBilling=tipo==='faturamento',stock=tipo==='estoque';
 const company=tipo==='custos_empresa';
 el('reportMultiple').classList.toggle('hidden',!isBilling);
 el('reportWork').closest('label').classList.toggle('hidden',isBilling||company||tipo==='precos_fornecedores');
 el('reportCompanyLocalWrap').classList.toggle('hidden',!company);
 el('reportCompanySupplierWrap').classList.toggle('hidden',!company);
 el('reportStockOptions').classList.toggle('hidden',!stock);
 el('reportCancelledWrap').classList.toggle('hidden',!['faturamento','liberacoes','expedicao','custos_empresa'].includes(tipo));
 el('reportWorkChecks').classList.toggle('hidden',el('reportWorkScope').value!=='selected'||!isBilling);
}
function periodo(){
 const todo=el('reportFullPeriod').checked;
 el('reportStart').disabled=todo;el('reportEnd').disabled=todo;
}
el('reportFullPeriod').addEventListener('change',periodo);
el('reportWorkScope').addEventListener('change',exibirFiltros);
el('reportType').addEventListener('change',()=>{
 exibirFiltros();
 el('reportSummary').replaceChildren();el('reportTable').replaceChildren();
 el('reportCsv').disabled=true;el('reportPrint').disabled=true;rows=[];
 if(el('reportType').value==='custos_empresa'&&window.ewCustosEmpresa&&currentCompany?.id)
  void window.ewCustosEmpresa.carregarFiltros(currentCompany.id)
   .catch(e=>{el('reportStatus').textContent='Falha ao carregar locais/fornecedores: '+e.message;});
});
periodo();exibirFiltros();
el('reportGenerate').addEventListener('click',gerar);
el('reportCsv').addEventListener('click',csv);
el('reportPrint').addEventListener('click',imprimir);
})();