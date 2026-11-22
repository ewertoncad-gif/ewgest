/* EWGEST v46.9 | Etapa de categorias e preço por m², antes da importação. */
(function(){
'use strict';
const motor=window.ewPrecificacaoCore;
if(!motor)throw Error('Núcleo de precificação ausente.');
const $$=id=>document.getElementById(id);
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
 '<div class="ewPriceStep"><strong>2. Conferir cada esquadria</strong><span class="hint">Altere a categoria individualmente quando necessário</span></div>',
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
function abrir(r,values,onSave){
 if(!r||r.obraExistente||r.jaImportado||!r.esquadriasPayload?.length)
  throw Error('A precificação requer uma nova obra com esquadrias analisadas.');
 if(!values||!Array.isArray(values.niveis)||typeof onSave!=='function')
  throw Error('Orçamento ou confirmação não disponíveis.');
 const fab=totalNiveis(values,'fabricacao'),inst=totalNiveis(values,'instalacao');
 if(!Number.isSafeInteger(fab)||!Number.isSafeInteger(inst)||fab+inst<=0)
  throw Error('Cadastre níveis com valores de fabricação e/ou instalação.');
 const grupoNomes=['ESQUADRIAS','GUARDA-CORPO','GRADIL','FACHADAS','OUTROS'];
 const categorias=grupoNomes.map((n,i)=>({id:'categoria-'+i,nome:n,precoBaseCentavosM2:0}));
 const ids=new Map(categorias.map(x=>[x.nome,x.id]));
 const itens=r.esquadriasPayload.map((x,i)=>({
  id:'item-'+String(i).padStart(6,'0'),indiceImportacao:i,codigo:x.codigo,
  descricao:x.descricao,largura_mm:Number(x.largura_mm),altura_mm:Number(x.altura_mm),
  quantidade:Number(x.quantidade),categoriaId:ids.get(motor.sugerirCategoria(x.descricao))||ids.get('OUTROS')
 }));
 estado={r,values,fab,inst,categorias,itens,pctBp:null,proxima:5,calculado:null};
 salvar=onSave;gravando=false;
 $$('ewPriceWork').textContent=r.nomeObra+' · '+r.codigo+' · '+itens.length+' itens';
 $$('ewPricePercent').value=(fab/(fab+inst)*100).toFixed(2);
 $$('ewPricePercentHint').textContent='Sugerido a partir do orçamento.';
 $$('ewPriceNovaCategoria').value='';
 wrapper.classList.remove('hidden');
 renderizar();
}
function renderizar(){
 if(!estado)return;
 const s=estado;
 const ops=s.categorias.map(c=>'<option value="'+esc(c.id)+'">'+esc(c.nome)+'</option>').join('');
 $$('ewPriceCategorias').innerHTML=
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
 $$('ewPriceItens').innerHTML='<table><thead><tr><th>Código</th><th>Descrição</th><th>Qtd.</th><th>Área</th><th>Categoria</th><th>Fabricação</th><th>Instalação</th></tr></thead><tbody>'+
 s.itens.map(x=>{
  const options=ops.replace('value="'+esc(x.categoriaId)+'"','value="'+esc(x.categoriaId)+'" selected');
  return '<tr><td><strong>'+esc(x.codigo)+'</strong></td><td>'+esc(x.descricao)+'</td>'+
   '<td class="ewPriceNum">'+x.quantidade+'</td><td class="ewPriceNum">'+area(x.largura_mm*x.altura_mm*x.quantidade/1000000)+'</td>'+
   '<td><select aria-label="Categoria de '+esc(x.codigo)+'" data-item="'+esc(x.id)+'">'+options+'</select></td>'+
   '<td class="ewPriceNum" data-item-fab="'+esc(x.id)+'">—</td>'+
   '<td class="ewPriceNum" data-item-inst="'+esc(x.id)+'">—</td></tr>';
 }).join('')+'</tbody></table>';
 atualizar();
}
function atualizar(){
 if(!estado)return;
 const s=estado;
 s.calculado=null;
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
  $$('ewPriceResumo').innerHTML=[
   ['Total combinado',dinheiro(total.totalCentavos)],
   ['Fabricação recalculada',dinheiro(total.fabricacaoCentavos)],
   ['Instalação recalculada',dinheiro(total.instalacaoCentavos)],
   ['Diferença','R$ 0,00']
  ].map((v,i)=>'<div class="ewPriceKpi'+(i===3?' ewPriceHighlighted':'')+'"><small>'+v[0]+'</small><strong>'+v[1]+'</strong></div>').join('');
  $$('ewPriceFechamento').textContent='Orçamento original: fabricação '+dinheiro(s.fab)+
    ' e instalação '+dinheiro(s.inst)+'. Redistribuição: fabricação '+dinheiro(total.fabricacaoCentavos)+
    ' e instalação '+dinheiro(total.instalacaoCentavos)+
    '. Os preços/m² orientam a participação de cada categoria; os valores individuais em centavos são a referência exata.';
  $$('ewPriceFechamento').classList.remove('ewPriceError');
 }catch(err){
  $$('ewPriceResumo').innerHTML='<div class="ewPriceKpi"><small>Conferência</small><strong>Informe os preços por m²</strong></div>';
  $$('ewPriceFechamento').textContent=err.message;
  $$('ewPriceFechamento').classList.add('ewPriceError');
 }
 $$('ewPriceErro').textContent='';
 $$('ewPriceConfirmar').disabled=gravando||!s.calculado;
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
   largura_mm:x.largura_mm,altura_mm:x.altura_mm,quantidade:x.quantidade,
   area_m2:x.areaM2,fabricacao_centavos:x.fabricacaoCentavos,
   instalacao_centavos:x.instalacaoCentavos
  }))
 };
}
$$('ewPriceAdd').addEventListener('click',()=>{
 if(!estado||gravando)return;
 const novo=nome($$('ewPriceNovaCategoria').value);
 if(novo.length<2||novo.length>120||estado.categorias.some(c=>nome(c.nome)===novo)){
  $$('ewPriceErro').textContent='Nome de categoria inválido ou já existente.';return;
 }
 estado.categorias.push({id:'categoria-'+estado.proxima++,nome:novo,precoBaseCentavosM2:0});
 $$('ewPriceNovaCategoria').value='';renderizar();
});
$$('ewPriceCategorias').addEventListener('change',ev=>{
 if(!estado||gravando)return;
 const id=ev.target.dataset.price||ev.target.dataset.name;
 const cat=estado.categorias.find(x=>x.id===id);if(!cat)return;
 if(ev.target.dataset.price){
  const cents=lerDinheiro(ev.target.value);
  if(!Number.isSafeInteger(cents)||cents<0||cents>100000000000){
   $$('ewPriceErro').textContent='Preço inválido: use reais e até duas casas decimais.';return;
  }
  cat.precoBaseCentavosM2=cents;
 }else{
  const novo=nome(ev.target.value);
  if(novo.length<2||novo.length>120||estado.categorias.some(x=>x.id!==id&&nome(x.nome)===novo)){
   $$('ewPriceErro').textContent='Nome de categoria inválido ou duplicado.';return;
  }
  cat.nome=novo;
 }
 renderizar();
});
$$('ewPriceCategorias').addEventListener('click',ev=>{
 if(!estado||gravando)return;
 const id=ev.target.closest('[data-remove]')?.dataset.remove;if(!id)return;
 if(estado.itens.some(x=>x.categoriaId===id)){
  $$('ewPriceErro').textContent='Mova os itens desta categoria antes de excluí-la.';return;
 }
 if(estado.categorias.length<2)return;
 estado.categorias=estado.categorias.filter(x=>x.id!==id);renderizar();
});
$$('ewPriceItens').addEventListener('change',ev=>{
 if(!estado||gravando)return;
 const row=estado.itens.find(x=>x.id===ev.target.dataset.item);
 if(!row||!estado.categorias.some(c=>c.id===ev.target.value))return;
 row.categoriaId=ev.target.value;renderizar();
});
$$('ewPricePercent').addEventListener('change',ev=>{
 if(!estado||gravando)return;
 const v=String(ev.target.value).trim(),n=Number(v.replace(',','.'));
 if(!v||!Number.isFinite(n)||n<0||n>100||Math.abs(n*100-Math.round(n*100))>1e-7){
  $$('ewPriceErro').textContent='Percentual inválido; informe de 0 a 100 com até duas casas.';return;
 }
 estado.pctBp=Math.round(n*100);
 $$('ewPricePercentHint').textContent='Instalação: '+((10000-estado.pctBp)/100).toFixed(2)+'%';
 atualizar();
});
$$('ewPriceVoltar').addEventListener('click',()=>{
 if(!estado||gravando)return;
 const r=estado.r;
 r.precificacaoDraft=null;r.confirmacaoInicialFeita=false;
 fechar();
 $$('cemQuoteOverlay')?.classList.remove('hidden');
});
$$('ewPriceConfirmar').addEventListener('click',async()=>{
 if(!estado||gravando)return;
 let draft;
 try{draft=montarDraft();}catch(e){$$('ewPriceErro').textContent=e.message;return;}
 const r=estado.r,cb=salvar;
 if(!window.confirm('Confirmar importação de '+r.nomeObra+' ('+r.codigo+')?\n\n'+
   'Fabricação: '+dinheiro(draft.fabricacao_distribuida_centavos)+'\n'+
   'Instalação: '+dinheiro(draft.instalacao_distribuida_centavos)+'\n'+
   'Itens precificados: '+draft.itens.length+'\n\n'+
   'A obra e a precificação serão gravadas em uma única transação.'))return;
 gravando=true;$$('ewPriceConfirmar').disabled=true;
 $$('ewPriceErro').textContent='Gravando obra e precificação…';
 try{
  await cb(draft);
  if(!r.jaImportado)throw Error('Importação não confirmada. Consulte o histórico antes de repetir.');
  fechar();
 }catch(e){
  $$('ewPriceErro').textContent=e.message;gravando=false;$$('ewPriceConfirmar').disabled=false;
 }
});
window.ewPrecificacaoImportacao=Object.freeze({abrir,fechar,lerDinheiro});
})();