/* EWGEST | Núcleo determinístico da precificação por obra (fase 1).
 * Sem acessos à rede, banco ou DOM de formulários. Reutilizável na importação,
 * revisões e relatórios históricos. Todos os valores monetários internos são
 * CENTAVOS INTEIROS. Não registrar preços sem conferir o fechamento.
 *
 * Modelo:
 * - precoBaseCentavosM2 é um PESO comercial por categoria, não o valor final.
 * - Fabricação e instalação usam os mesmos pesos; mudar o percentual redistribui
 *   ambos automaticamente, sem alterar o valor combinado contratado.
 * - Os ajustes de centavos seguem o método dos maiores restos, estável pelo ID.
 * - Os valores individuais exatos prevalecem sobre valores/m² arredondados exibidos.
 */
(function(global){
 'use strict';
 const PRECISAO_MEDIDA=1000; // mm armazenados até 3 casas => micrômetros
 const DENOMINADOR_AREA_M2=1000000000000; // µm² por m²
 const erro=(m)=>{throw new Error(m);};
 const inteiro=(n,nome,min=0,max=Number.MAX_SAFE_INTEGER)=>{
  if(!Number.isSafeInteger(n)||n<min||n>max)erro(nome+' inválido.');
  return n;
 };
 function medidaEmMicrometros(n,nome){
  if(typeof n!=='number'||!Number.isFinite(n)||n<=0||n>100000||
   Math.abs(n*PRECISAO_MEDIDA-Math.round(n*PRECISAO_MEDIDA))>1e-6)
   erro(nome+' inválida: informe medida em milímetros com até três casas decimais.');
  return BigInt(Math.round(n*PRECISAO_MEDIDA));
 }
 function areaEmMicrometrosQuadrados(item){
  const largura=medidaEmMicrometros(item.largura_mm,'Largura'),
        altura=medidaEmMicrometros(item.altura_mm,'Altura');
  const quantidade=inteiro(item.quantidade,'Quantidade',1,100000);
  return largura*altura*BigInt(quantidade);
 }
 function sugerirCategoria(descricao){
  const d=String(descricao||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'')
   .toLocaleUpperCase('pt-BR');
  if(/\bGUARDA[\s-]*CORPO\b|\bSPLIT\b/.test(d))return 'GUARDA-CORPO';
  if(/\bGRADIL\b|\bGRADE\b/.test(d))return 'GRADIL';
  if(/\bFACHADA\b|\bUNITIZAD[AO]\b|\bSTICK\b|\bPELE\s+DE\s+VIDRO\b/.test(d))
   return 'FACHADAS';
  if(/\bJANELA\b|\bPORTA\b|\bMAXIM[\s-]*AR\b|\bFIXO\b/.test(d))return 'ESQUADRIAS';
  return 'OUTROS';
 }
 // Devolve o próprio total contratado, sem arredondar o percentual sugerido.
 // Se houver alteração explícita, percentual em centésimos de 1% (7000 = 70%).
 function totaisComDistribuicao(originalFabricacaoCentavos,originalInstalacaoCentavos,percentualBp=null){
  const fab=inteiro(originalFabricacaoCentavos,'Orçamento de fabricação',0,1e14);
  const inst=inteiro(originalInstalacaoCentavos,'Orçamento de instalação',0,1e14);
  const total=inteiro(fab+inst,'Total de fabricação e instalação',0,1e14);
  if(total===0)erro('O orçamento não possui valor para fabricação e instalação.');
  if(percentualBp===null||percentualBp===undefined)
   return {totalCentavos:total,fabricacaoCentavos:fab,instalacaoCentavos:inst,
    percentualSugeridoBp:Math.round(fab/total*10000),percentualAjustadoBp:null};
  const pct=inteiro(percentualBp,'Percentual de fabricação',0,10000);
  const fabricacao=Number((BigInt(total)*BigInt(pct)+5000n)/10000n);
  return {totalCentavos:total,fabricacaoCentavos:fabricacao,
   instalacaoCentavos:total-fabricacao,
   percentualSugeridoBp:Math.round(fab/total*10000),percentualAjustadoBp:pct};
 }
 function distribuirEmCentavos(total,linhas){
  inteiro(total,'Total para rateio',0,1e14);
  if(total===0)return new Map(linhas.map(x=>[x.id,0]));
  const pesoTotal=linhas.reduce((a,b)=>a+b.peso,0n);
  if(pesoTotal<=0n)erro('Não existem áreas com preços por m² válidos para ratear.');
  const t=BigInt(total);
  const partes=linhas.map(l=>{
   const produto=t*l.peso;
   return {id:l.id,inteiro:Number(produto/pesoTotal),resto:produto%pesoTotal};
  });
  const integral=partes.reduce((sum,p)=>sum+p.inteiro,0);
  const restante=total-integral;
  if(restante<0||restante>partes.length)
   erro('Falha de conciliação: distribuição fora da faixa.');
  // Identificadores persistentes garantem que trocar ordem visual não altera valores.
  partes.sort((a,b)=>a.resto===b.resto?
   a.id.localeCompare(b.id,'pt-BR'):(a.resto>b.resto?-1:1));
  for(let i=0;i<restante;i++)partes[i].inteiro++;
  return new Map(partes.map(p=>[p.id,p.inteiro]));
 }
 function precificar(dados){
  if(!dados||typeof dados!=='object')erro('Orçamento ausente.');
  const cats=Array.isArray(dados.categorias)?dados.categorias:[];
  const itens=Array.isArray(dados.itens)?dados.itens:[];
  if(!cats.length||!itens.length)erro('Cadastre categorias e esquadrias para precificar.');
  const mapaCategorias=new Map();
  for(const c of cats){
   const id=String(c.id||'').trim(),nome=String(c.nome||'').trim();
   if(!id||!nome||nome.length>120||mapaCategorias.has(id))
    erro('Categoria sem identificador válido ou duplicada.');
   const precoBase=inteiro(c.precoBaseCentavosM2,'Preço por m² de '+nome,0,100000000000);
   mapaCategorias.set(id,{id,nome,precoBase});
  }
  const linhas=[],ids=new Set();
  for(const x of itens){
   const id=String(x.id||'').trim(),categoriaId=String(x.categoriaId||'').trim(),
    cat=mapaCategorias.get(categoriaId);
   if(!id||ids.has(id))erro('Esquadria sem identificador único.');
   if(!cat)erro('Escolha uma categoria válida para a esquadria '+(x.codigo||id)+'.');
   ids.add(id);
   const areaMicros=areaEmMicrometrosQuadrados(x);
   const peso=areaMicros*BigInt(cat.precoBase);
   linhas.push({id,codigo:String(x.codigo||'').trim(),
    descricao:String(x.descricao||'').trim(),
    tipologiaId:x.tipologiaId||null,linha:x.linha||null,
    largura_mm:x.largura_mm,altura_mm:x.altura_mm,quantidade:x.quantidade,
    categoriaId,categoriaNome:cat.nome,areaMicros,peso});
  }
  const totais=totaisComDistribuicao(
   dados.fabricacaoOriginalCentavos,dados.instalacaoOriginalCentavos,
   dados.percentualFabricacaoBp
  );
  if(linhas.every(x=>x.peso===0n))
   erro('Informe ao menos um preço-base por m² positivo.');
  if(linhas.some(x=>x.peso===0n))
   erro('Todas as categorias com esquadrias devem ter preço por m² maior que zero.');
  const fab=distribuirEmCentavos(totais.fabricacaoCentavos,linhas);
  const inst=distribuirEmCentavos(totais.instalacaoCentavos,linhas);
  const resultado=linhas.map(x=>{
   const fabricacaoCentavos=fab.get(x.id),instalacaoCentavos=inst.get(x.id);
   return {id:x.id,codigo:x.codigo,descricao:x.descricao,tipologiaId:x.tipologiaId,
    linha:x.linha,largura_mm:x.largura_mm,altura_mm:x.altura_mm,
    quantidade:x.quantidade,categoriaId:x.categoriaId,categoriaNome:x.categoriaNome,
    areaM2:Number(x.areaMicros)/DENOMINADOR_AREA_M2,
    fabricacaoCentavos,instalacaoCentavos,
    valorTotalCentavos:fabricacaoCentavos+instalacaoCentavos};
  });
  const categoriasResultado=[...mapaCategorias.values()].map(c=>{
   const correspondentes=linhas.filter(x=>x.categoriaId===c.id),
    itensCat=resultado.filter(x=>x.categoriaId===c.id);
   const area=correspondentes.reduce((sum,x)=>sum+x.areaMicros,0n);
   const fabCent=itensCat.reduce((sum,x)=>sum+x.fabricacaoCentavos,0),
    instCent=itensCat.reduce((sum,x)=>sum+x.instalacaoCentavos,0);
   return {id:c.id,nome:c.nome,precoBaseCentavosM2:c.precoBase,
    areaM2:Number(area)/DENOMINADOR_AREA_M2,quantidadeItens:correspondentes.length,
    fabricacaoCentavos:fabCent,instalacaoCentavos:instCent,
    valorTotalCentavos:fabCent+instCent,
    // Preços ajustados por m² informativos; NÃO usar arredondamento como base de faturas.
    precoAjustadoFabricacaoM2:area>0n?fabCent*DENOMINADOR_AREA_M2/Number(area):null,
    precoAjustadoInstalacaoM2:area>0n?instCent*DENOMINADOR_AREA_M2/Number(area):null};
  });
  const somaFab=resultado.reduce((sum,x)=>sum+x.fabricacaoCentavos,0),
   somaInst=resultado.reduce((sum,x)=>sum+x.instalacaoCentavos,0);
  if(somaFab!==totais.fabricacaoCentavos||somaInst!==totais.instalacaoCentavos||
   somaFab+somaInst!==totais.totalCentavos)erro('Falha de fechamento: revise a distribuição.');
  // Snapshot imutável (sem datas inventadas); gerador de versão/usuário no backend.
  return {totais,categorias:categoriasResultado,itens:resultado,
   fechamento:{fabricacaoCentavos:somaFab,instalacaoCentavos:somaInst,
    valorTotalCentavos:somaFab+somaInst,diferencaCentavos:0}};
 }

 // Preço-base editável em centavos/m²; o rateio final continua sendo conferido
 // pelo servidor. Usar áreas inteiras para que o orçamento não derive em floats.
 function redistribuirPrecos(dados){
  const total=totaisComDistribuicao(dados.fabricacaoOriginalCentavos,dados.instalacaoOriginalCentavos).totalCentavos;
  const cats=dados.categorias.map(c=>({...c}));
  const areas=new Map(cats.map(c=>[c.id,0n]));
  if(areas.size!==cats.length)erro('Categorias duplicadas.');
  for(const x of dados.itens){
   if(!areas.has(x.categoriaId))erro('Categoria inválida.');
   areas.set(x.categoriaId,areas.get(x.categoriaId)+areaEmMicrometrosQuadrados(x));
  }
  const areaTotal=[...areas.values()].reduce((a,b)=>a+b,0n);
  if(areaTotal<=0n)erro('Não há área para calcular o preço médio.');
  const orcamento=BigInt(total)*BigInt(DENOMINADOR_AREA_M2);
  const arredondar=(num,den)=>Number((num+den/2n)/den);
  const precoMedio=Math.max(1,arredondar(orcamento,areaTotal));
  inteiro(precoMedio,'Preço médio por m²',1,100000000000);
  const ativos=cats.filter(c=>areas.get(c.id)>0n);
  const fixos=ativos.filter(c=>c.bloqueado), livres=ativos.filter(c=>!c.bloqueado);
  for(const c of cats)inteiro(c.precoBaseCentavosM2,'Preço por m² de '+c.nome,0,100000000000);
  if(fixos.some(c=>c.precoBaseCentavosM2<=0))erro('Categoria bloqueada com preço inválido.');
  const fixado=fixos.reduce((sum,c)=>sum+areas.get(c.id)*BigInt(c.precoBaseCentavosM2),0n);
  const saldo=orcamento-fixado;
  if(!livres.length){
   // Cada preço exibido é arredondado a 1 centavo/m². Uma diferença de até
   // meio centavo/m² pode ser fechada pelo rateio de centavos já existente.
   if((saldo<0n?-saldo:saldo)*2n>areaTotal)
    erro('Os preços bloqueados não fecham o orçamento. Desbloqueie uma categoria ou restaure os preços médios.');
  }else{
   if(saldo<=0n)erro('Os preços bloqueados esgotam o orçamento. Reduza um preço ou desbloqueie uma categoria.');
   const peso=c=>BigInt(c.precoBaseCentavosM2||precoMedio);
   const somaPesos=livres.reduce((sum,c)=>sum+areas.get(c.id)*peso(c),0n);
   const novos=livres.map(c=>[c,Math.max(1,arredondar(saldo*peso(c),somaPesos))]);
   for(const [c,v] of novos)inteiro(v,'Preço redistribuído de '+c.nome,1,100000000000);
   for(const [c,v] of novos)c.precoBaseCentavosM2=v;
   const minimo=livres.reduce((sum,c)=>sum+areas.get(c.id),0n);
   if(saldo<minimo&&fixos.length)erro('Saldo insuficiente para preços positivos nas demais categorias. Reduza um preço bloqueado.');
  }
  for(const c of cats)if(!c.bloqueado&&areas.get(c.id)===0n)c.precoBaseCentavosM2=precoMedio;
  return cats;
 }
 global.ewPrecificacaoCore=Object.freeze({
  sugerirCategoria,totaisComDistribuicao,precificar,redistribuirPrecos
 });
})(window);
