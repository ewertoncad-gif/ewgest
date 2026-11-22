/* EWGEST v46.9 | Etapa de categorias e preço por m², antes da importação. */
(function(){
'use strict';
const motor=window.ewPrecificacaoCore;
if(!motor)throw Error('Núcleo de precificação ausente.');
const priceNode=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const nome=v=>String(v||'').trim().toLocaleUpperCase('pt-BR');
const real=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const dinheiro=v=>real(Number(v)/100);
const area=v=>Number(v).toLocaleString('pt-BR',{minimumFractionDigits:3,maximumFractionDigits:6})+' m²';
function lerDinheiro(valor){
 const s=String(valor??'').trim().replace(/^R\$\s*/i,'').replace(/\s/g,'');
 if(!s)return 0;
 let n;
 if(/^\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?$/.test(s))n=Number(s.replace(/\./g,'').replace(',','.'));
 else if(/^\d+(?:,\d{1,2})?$/.test(s))n=Number(s.replace(',','.'));
 else if(/^\d+\.\d{1,2}$/.test(s))n=Number(s);
 else return NaN;
 const cents=Math.round(n*100);
 return Number.isSafeInteger(cents)&&cents>=0?cents:NaN;
}
const wrapper=document.createElement('div');
wrapper.id='ewPriceOverlay';wrapper.className='modaloverlay hidden';
wrapper.setAttribute('role','presentation');
wrapper.innerHTML=[
 '<div class="panel modalbox ewPriceDialog" role="dialog" aria-modal="true" aria-labelledby="ewPriceTitle">',
 '<div class="ewPriceStep"><h2 id="ewPriceTitle">Categorias e precificação por m²</h2><span class="ewPriceBadge">Etapa 3 · Antes da importação</span></div>',
 '<p class="ewPriceIntro">Confira as categorias e o preço-base do m². Os valores finais serão distribuídos entre fabricação e instalação, sem alterar os totais originais do orçamento.</p>',
 '<p id="ewPriceWork" class="hint"></p>',
 '<div id="ewPriceResumo" class="ewPriceGrid" aria-live="polite"></div>',
 '<div class="ewPriceStep"><strong>1. Categorias e preços por m²</strong><span class="hint">Preços-base indicam o peso de cada categoria</span></div>',
 '<div id="ewPriceCategorias" class="ewPriceTableWrap"></div>',
 '<div class="ewPriceActions"><input id="ewPriceNovaCategoria" maxlength="120" placeholder="Nova categoria">',
 '<button class="btn secondary" type="button" id="ewPriceAdd">+ Criar categoria</button>',
 '<label>Fabricação <input type="number" id="ewPricePercent" min="0" max="100" step="0.01" inputmode="decimal"> %</label>',
 '<span class="hint" id="ewPricePercentHint"></span></div>',
 '<div class="ewPriceStep"><strong>2. Conferir cada esquadria</strong><span class="hint">Altere a categoria individualmente. Marque Padrão para repetir a escolha nas próximas obras.</span></div>',
 '<div id="ewPriceItens" class="ewPriceItems"></div>',
 '<div id="ewPriceFechamento" class="ewPriceInfo" aria-live="polite"></div>',
 '<p id="ewPriceErro" class="feedback" role="alert"></p>',
 '<div class="ewPriceButtons"><button class="btn secondary" type="button" id="ewPriceVoltar">Voltar ao orçamento</button>',
 '<button class="btn primary" type="button" id="ewPriceConfirmar">Conferir e importar obra</button></div></div>'
].join('');
document.body.appendChild(wrapper);
let estado=null,salvar=null,gravando=false;
function fechar(){wrapper.classList.add('hidden');estado=null;salvar=null;gravando=false;}
function totalNiveis(v,grupo){
 return v.niveis.filter(x=>x.categoria_base===grupo)
 .reduce((sum,x)=>sum+Math.round(Number(x.valor||0)*100),0);
}
async function abrir(r,values,onSave){
 if(!r||r.obraExistente||r.jaImportado||!r.esquadriasPayload?.length)
  throw Error('A precificação requer uma nova obra com esquadrias analisadas.');
 if(!values||!Array.isArray(values.niveis)||typeof onSave!=='function')
  throw Error('Orçamento ou confirmação não disponíveis.');
 if(values.niveis.some(x=>['fabricacao','instalacao'].includes(x.categoria_base)&&
    Math.round(Number(x.valor||0)*100)>0&&!x.faturar))
  throw Error('Para precificar, marque os níveis de fabricação e instalação como faturáveis no orçamento. Use Outros para gastos que não serão faturados.');
 const fab=totalNiveis(values,'fabricacao'),inst=totalNiveis(values,'instalacao');
 if(!Number.isSafeInteger(fab)||!Number.isSafeInteger(inst)||fab+inst<=0)
  throw Error('Cadastre níveis com valores de fabricação e/ou instalação.');
 const grupoNomes=['ESQUADRIAS','GUARDA-CORPO','GRADIL','FACHADAS','OUTROS'];
 const categorias=grupoNomes.map((n,i)=>({id:'categoria-'+i,nome:n,precoBaseCentavosM2:0}));
 const ids=new Map(categorias.map(x=>[x.nome,x.id]));
 const emp=currentCompany?.id;
 if(!emp)throw Error('Empresa da sessão não identificada.');
 priceNode('ewPriceWork').textContent='Carregando categorias do cadastro…';
 wrapper.classList.remove('hidden');
 priceNode('ewPriceConfirmar').disabled=true;
 try{
  await ensureSession();
  // Catálogo da empresa é reutilizado, mas o vínculo de cada esquadria é
  // específico desta obra. O nome de categoria fica congelado na revisão.
  const empresa='eq.'+emp;
  const [salvas,tipos,padroes]=await Promise.all([
   apiGet('ew_precificacao_categorias',{select:'id,nome,ativo',empresa_id:empresa,ativo:'eq.true',limit:'500'}),
   apiGet('tipologias',{select:'id,codigo',empresa_id:empresa,limit:'5000'}),
   apiGet('ew_precificacao_tipologias_padrao',{select:'tipologia_id,categoria_id',empresa_id:empresa,limit:'5000'})
  ]);
  if(cemParsed!==r||currentCompany?.id!==emp)throw Error('A obra ou a empresa foi alterada durante a conferência.');
  const porUuid=new Map();
  for(const c of salvas||[]){
   const n=nome(c.nome);if(!n)continue;
   let grupo=categorias.find(x=>x.nome===n);
   if(!grupo){
    grupo={id:'catalogo-'+c.id,nome:n,precoBaseCentavosM2:0};
    categorias.push(grupo);
   }
   porUuid.set(c.id,grupo.id);
  }
  const codigoTipo=new Map(),duplicados=new Set();
  for(const t of tipos||[]){
   const cod=nome(t.codigo);
   if(codigoTipo.has(cod))duplicados.add(cod);
   else codigoTipo.set(cod,t.id);
  }
  const padraoPorTipo=new Map((padroes||[]).map(x=>[x.tipologia_id,porUuid.get(x.categoria_id)]));
  const itens=r.esquadriasPayload.map((x,i)=>{
   const codigoReferencia=nome(x.referencia_tipologia);
   const tipoId=duplicados.has(codigoReferencia)?null:codigoTipo.get(codigoReferencia);
   return {
    id:'item-'+String(i).padStart(6,'0'),indiceImportacao:i,codigo:x.codigo,
    descricao:x.descricao,referencia_tipologia:String(x.referencia_tipologia||''),
    largura_mm:Number(x.largura_mm),altura_mm:Number(x.altura_mm),
    quantidade:Number(x.quantidade),tipologiaId:tipoId||null,padrao:false,
    categoriaId:(tipoId&&padraoPorTipo.get(tipoId))||
     ids.get(motor.sugerirCategoria(x.descricao))||ids.get('OUTROS')
   };
  });
  estado={r,values,fab,inst,categorias,itens,pctBp:null,proxima:5,calculado:null};
  salvar=onSave;gravando=false;
  priceNode('ewPriceWork').textContent=r.nomeObra+' · '+r.codigo+' · '+itens.length+' itens';
  priceNode('ewPricePercent').value=(fab/(fab+inst)*100).toFixed(2);
  priceNode('ewPricePercentHint').textContent='Sugerido a partir do orçamento.';
  priceNode('ewPriceNovaCategoria').value='';
  renderizar();
 }catch(e){
  fechar();
  throw e;
 }
}
function renderizar(){
 if(!estado)return;
 const s=estado;
 const ops=s.categorias.map(c=>'<option value="'+esc(c.id)+'">'+esc(c.nome)+'</option>').join('');
 priceNode('ewPriceCategorias').innerHTML=
  '<table><thead><tr><th>Categoria</th><th>Área</th><th>Preço-base/m²</th><th>Fabricação</th><th>Instalação</th><th>Fab. R$/m²</th><th>Inst. R$/m²</th><th>Ações</th></tr></thead><tbody>'+
  s.categorias.map(c=>{
   const a=s.itens.filter(x=>x.categoriaId===c.id)
    .reduce((sum,x)=>sum+x.largura_mm*x.altura_mm*x.quantidade/1000000,0);
   const temItens=s.itens.some(x=>x.categoriaId===c.id);
   return '<tr><td><input data-name="'+esc(c.id)+'" value="'+esc(c.nome)+'" maxlength="120" aria-label="Nome da categoria"></td>'+
    '<td class="ewPriceNum">'+area(a)+'</td>'+
    '<td><input data-price="'+esc(c.id)+'" inputmode="decimal" placeholder="R$ 0,00" aria-label="Preço por metro quadrado" value="'+
    (c.precoBaseCentavosM2?esc(dinheiro(c.precoBaseCentavosM2)):'')+'"></td>'+
    '<td class="ewPriceNum" data-fab="'+esc(c.id)+'">—</td>'+
    '<td class="ewPriceNum" data-inst="'+esc(c.id)+'">—</td>'+
    '<td class="ewPriceNum" data-fab-m2="'+esc(c.id)+'">—</td>'+
    '<td class="ewPriceNum" data-inst-m2="'+esc(c.id)+'">—</td>'+
    '<td><button type="button" class="btn secondary" data-remove="'+esc(c.id)+'"'+
    (temItens?' disabled title="Mova as esquadrias antes de excluir"':'')+'>Excluir</button></td></tr>';
  }).join('')+'</tbody></table>';
 // Exibir esquadrias agrupadas por categoria, com possibilidade de mover cada item.
 priceNode('ewPriceItens').innerHTML='<table><thead><tr><th>Código</th><th>Descrição</th><th>Qtd.</th><th>Área</th><th>Categoria</th><th>Padrão</th><th>Fabricação</th><th>Instalação</th></tr></thead><tbody>'+
 s.categorias.map(cat=>{
  const porGrupo=s.itens.filter(x=>x.categoriaId===cat.id).sort((a,b)=>a.codigo.localeCompare(b.codigo,'pt-BR'));
  if(!porGrupo.length)return '';
  const areaGrupo=porGrupo.reduce((sum,x)=>sum+x.largura_mm*x.altura_mm*x.quantidade/1000000,0);
  return '<tr class="ewPriceGroupRow"><td colspan="8"><strong>'+esc(cat.nome)+'</strong> · '+
   porGrupo.length+' linhas · '+area(areaGrupo)+'</td></tr>'+
  porGrupo.map(x=>{
   const options=ops.replace('value="'+esc(x.categoriaId)+'"','value="'+esc(x.categoriaId)+'" selected');
   return '<tr><td><strong>'+esc(x.codigo)+'</strong></td><td>'+esc(x.descricao)+'</td>'+
    '<td class="ewPriceNum">'+x.quantidade+'</td><td class="ewPriceNum">'+area(x.largura_mm*x.altura_mm*x.quantidade/1000000)+'</td>'+
    '<td><select aria-label="Categoria de '+esc(x.codigo)+'" data-item="'+esc(x.id)+'">'+options+'</select></td>'+
    '<td><label class="ewPriceDefault"><input type="checkbox" data-default="'+esc(x.id)+'"'+
      (x.padrao?' checked':'')+(x.tipologiaId?'':' disabled title="Tipologia não identificada de forma única no catálogo"')+
     '> Usar depois</label></td>'+
    '<td class="ewPriceNum" data-item-fab="'+esc(x.id)+'">—</td>'+
    '<td class="ewPriceNum" data-item-inst="'+esc(x.id)+'">—</td></tr>';
  }).join('');
 }).join('')+'</tbody></table>';
 atualizar();
}
function lerPercentualBp(){
 const v=String(priceNode('ewPricePercent').value).trim(),n=Number(v.replace(',','.'));
 if(!v||!Number.isFinite(n)||n<0||n>100||
    Math.abs(n*100-Math.round(n*100))>1e-7)return null;
 return Math.round(n*100);
}
function atualizar(){
 if(!estado)return;
 const s=estado;
 s.calculado=null;
 // Não reabilitar confirmação com o último percentual válido quando o campo
 // exibe atualmente um valor inválido (ex.: 110% ou campo vazio).
 if(lerPercentualBp()===null){
  priceNode('ewPriceResumo').innerHTML='<div class="ewPriceKpi"><small>Conferência</small><strong>Percentual inválido</strong></div>';
  priceNode('ewPriceFechamento').textContent='Informe fabricação de 0 a 100% com até duas casas decimais.';
  priceNode('ewPriceFechamento').classList.add('ewPriceError');
  priceNode('ewPriceConfirmar').disabled=true;
  return;
 }
 try{
  const resultado=motor.precificar({
   fabricacaoOriginalCentavos:s.fab,instalacaoOriginalCentavos:s.inst,
   percentualFabricacaoBp:s.pctBp,categorias:s.categorias,itens:s.itens
  });
  s.calculado=resultado;
  for(const c of resultado.categorias){
   const f=wrapper.querySelector('[data-fab="'+c.id+'"]');
   const i=wrapper.querySelector('[data-inst="'+c.id+'"]');
   if(f)f.textContent=dinheiro(c.fabricacaoCentavos);
   if(i)i.textContent=dinheiro(c.instalacaoCentavos);
   const fm=wrapper.querySelector('[data-fab-m2="'+c.id+'"]');
   const im=wrapper.querySelector('[data-inst-m2="'+c.id+'"]');
   if(fm)fm.textContent=c.precoAjustadoFabricacaoM2===null?'—':real(c.precoAjustadoFabricacaoM2/100);
   if(im)im.textContent=c.precoAjustadoInstalacaoM2===null?'—':real(c.precoAjustadoInstalacaoM2/100);
  }
  for(const x of resultado.itens){
   const f=wrapper.querySelector('[data-item-fab="'+x.id+'"]');
   const i=wrapper.querySelector('[data-item-inst="'+x.id+'"]');
   if(f)f.textContent=dinheiro(x.fabricacaoCentavos);
   if(i)i.textContent=dinheiro(x.instalacaoCentavos);
  }
  const total=resultado.totais;
  priceNode('ewPriceResumo').innerHTML=[
   ['Total combinado',dinheiro(total.totalCentavos)],
   ['Fabricação recalculada',dinheiro(total.fabricacaoCentavos)],
   ['Instalação recalculada',dinheiro(total.instalacaoCentavos)],
   ['Diferença','R$ 0,00']
  ].map((v,i)=>'<div class="ewPriceKpi'+(i===3?' ewPriceHighlighted':'')+'"><small>'+v[0]+'</small><strong>'+v[1]+'</strong></div>').join('');
  priceNode('ewPriceFechamento').textContent='Orçamento original: fabricação '+dinheiro(s.fab)+
    ' e instalação '+dinheiro(s.inst)+'. Redistribuição: fabricação '+dinheiro(total.fabricacaoCentavos)+
    ' e instalação '+dinheiro(total.instalacaoCentavos)+
    '. Os preços/m² orientam a participação de cada categoria; os valores individuais em centavos são a referência exata.';
  priceNode('ewPriceFechamento').classList.remove('ewPriceError');
 }catch(err){
  priceNode('ewPriceResumo').innerHTML='<div class="ewPriceKpi"><small>Conferência</small><strong>Informe os preços por m²</strong></div>';
  priceNode('ewPriceFechamento').textContent=err.message;
  priceNode('ewPriceFechamento').classList.add('ewPriceError');
 }
 priceNode('ewPriceErro').textContent='';
 priceNode('ewPriceConfirmar').disabled=gravando||!s.calculado;
}
function invalidar(msg){
 if(estado)estado.calculado=null;
 priceNode('ewPriceErro').textContent=msg;
 priceNode('ewPriceConfirmar').disabled=true;
}
function montarDraft(){
 const s=estado,r=s?.calculado;
 if(!r||r.fechamento.diferencaCentavos!==0)throw Error('Não há fechamento válido.');
 return {
  versao:1,percentual_fabricacao_bp:s.pctBp===null?r.totais.percentualSugeridoBp:s.pctBp,
  percentual_ajustado:s.pctBp!==null,
  fabricacao_original_centavos:s.fab,instalacao_original_centavos:s.inst,
  fabricacao_distribuida_centavos:r.totais.fabricacaoCentavos,
  instalacao_distribuida_centavos:r.totais.instalacaoCentavos,
  categorias:r.categorias.map(c=>({id_local:c.id,nome:c.nome,area_m2:c.areaM2,
   preco_base_m2_centavos:c.precoBaseCentavosM2,
   fabricacao_centavos:c.fabricacaoCentavos,instalacao_centavos:c.instalacaoCentavos})),
  itens:r.itens.map(x=>({
   indice_importacao:s.itens.find(y=>y.id===x.id).indiceImportacao,
   categoria_id_local:x.categoriaId,codigo:x.codigo,descricao:x.descricao,
   referencia_tipologia:s.itens.find(y=>y.id===x.id).referencia_tipologia,
   definir_padrao_tipologia:Boolean(s.itens.find(y=>y.id===x.id).padrao),
   largura_mm:x.largura_mm,altura_mm:x.altura_mm,quantidade:x.quantidade,
   area_m2:x.areaM2,fabricacao_centavos:x.fabricacaoCentavos,
   instalacao_centavos:x.instalacaoCentavos
  }))
 };
}
priceNode('ewPriceAdd').addEventListener('click',()=>{
 if(!estado||gravando)return;
 const novo=nome(priceNode('ewPriceNovaCategoria').value);
 if(novo.length<2||novo.length>120||estado.categorias.some(c=>nome(c.nome)===novo)){
  invalidar('Nome de categoria inválido ou já existente.');return;
 }
 estado.categorias.push({id:'categoria-'+estado.proxima++,nome:novo,precoBaseCentavosM2:0});
 priceNode('ewPriceNovaCategoria').value='';renderizar();
});
priceNode('ewPriceCategorias').addEventListener('change',ev=>{
 if(!estado||gravando)return;
 const id=ev.target.dataset.price||ev.target.dataset.name;
 const cat=estado.categorias.find(x=>x.id===id);if(!cat)return;
 if(ev.target.dataset.price){
  const cents=lerDinheiro(ev.target.value);
  if(!Number.isSafeInteger(cents)||cents<0||cents>100000000000){
   invalidar('Preço inválido: use reais e até duas casas decimais.');return;
  }
  cat.precoBaseCentavosM2=cents;
 }else{
  const novo=nome(ev.target.value);
  if(novo.length<2||novo.length>120||estado.categorias.some(x=>x.id!==id&&nome(x.nome)===novo)){
   invalidar('Nome de categoria inválido ou duplicado.');return;
  }
  cat.nome=novo;
 }
 renderizar();
});
priceNode('ewPriceCategorias').addEventListener('click',ev=>{
 if(!estado||gravando)return;
 const id=ev.target.closest('[data-remove]')?.dataset.remove;if(!id)return;
 if(estado.itens.some(x=>x.categoriaId===id)){
  priceNode('ewPriceErro').textContent='Mova os itens desta categoria antes de excluí-la.';return;
 }
 if(estado.categorias.length<2)return;
 estado.categorias=estado.categorias.filter(x=>x.id!==id);renderizar();
});
priceNode('ewPriceItens').addEventListener('change',ev=>{
 if(!estado||gravando)return;
 if(ev.target.dataset.default){
  const linha=estado.itens.find(x=>x.id===ev.target.dataset.default);
  if(!linha||!linha.tipologiaId)return;
  linha.padrao=Boolean(ev.target.checked);
  return;
 }
 const row=estado.itens.find(x=>x.id===ev.target.dataset.item);
 if(!row||!estado.categorias.some(c=>c.id===ev.target.value))return;
 row.categoriaId=ev.target.value;renderizar();
});
function percentualAlterado(){
 if(!estado||gravando)return;
 const pct=lerPercentualBp();
 if(pct===null){
  priceNode('ewPricePercentHint').textContent='Percentual inválido';
  invalidar('Percentual inválido; informe de 0 a 100 com até duas casas.');
  atualizar();
  return;
 }
 estado.pctBp=pct;
 priceNode('ewPricePercentHint').textContent='Instalação: '+((10000-pct)/100).toFixed(2)+'%';
 atualizar();
}
// Input recalcula sem perder foco; change cobre colagem/seleção final.
priceNode('ewPricePercent').addEventListener('input',percentualAlterado);
priceNode('ewPricePercent').addEventListener('change',percentualAlterado);
priceNode('ewPriceVoltar').addEventListener('click',()=>{
 if(!estado||gravando)return;
 const r=estado.r;
 r.precificacaoDraft=null;r.confirmacaoInicialFeita=false;
 fechar();
 priceNode('cemQuoteOverlay')?.classList.remove('hidden');
});
priceNode('ewPriceConfirmar').addEventListener('click',async()=>{
 if(!estado||gravando)return;
 let draft;
 try{draft=montarDraft();}catch(e){priceNode('ewPriceErro').textContent=e.message;return;}
 const r=estado.r,cb=salvar;
 if(!window.confirm('Confirmar importação de '+r.nomeObra+' ('+r.codigo+')?\n\n'+
   'Fabricação: '+dinheiro(draft.fabricacao_distribuida_centavos)+'\n'+
   'Instalação: '+dinheiro(draft.instalacao_distribuida_centavos)+'\n'+
   'Itens precificados: '+draft.itens.length+'\n\n'+
   'A obra e a precificação serão gravadas em uma única transação.'))return;
 gravando=true;priceNode('ewPriceConfirmar').disabled=true;
 priceNode('ewPriceErro').textContent='Gravando obra e precificação…';
 try{
  await cb(draft);
  if(!r.jaImportado)throw Error('Importação não confirmada. Consulte o histórico antes de repetir.');
  fechar();
 }catch(e){
  priceNode('ewPriceErro').textContent=e.message;gravando=false;priceNode('ewPriceConfirmar').disabled=false;
 }
});
window.ewPrecificacaoImportacao=Object.freeze({abrir,fechar,lerDinheiro});
})();