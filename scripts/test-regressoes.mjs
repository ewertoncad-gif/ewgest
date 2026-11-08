import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const source=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const start=source.indexOf('function normalizarDescricaoTipologia(t){');
const end=source.indexOf('function refreshVariationManager(){',start);
assert.ok(start>=0&&end>start,'Funções de classificação foram localizadas');
const {classificarTipoTipologia,correspondeTipoTipologia}=
  new Function(source.slice(start,end)+'\nreturn {classificarTipoTipologia,correspondeTipoTipologia};')();
const cases=[
 ['FACHADA UNITIZADA COM MÓDULO MAXIM-AR','FACHADA UNITIZADA'],
 ['FACHADA STICK COM MAXIM-AR','FACHADA STICK'],
 ['FACHADA UNITIZADA MÓDULO FIXO','FACHADA UNITIZADA'],
 ['FACHADA STICK VIDRO FIXO','FACHADA STICK'],
 ['MAXIM-AR 1 FOLHA','MAXIM-AR'],
 ['MAXIM AR - LINHA INOVA','MAXIM-AR'],
 ['MAXIMAR - LINHA INOVA','MAXIM-AR'],
 ['JANELA MAXIM-AR','MAXIM-AR'],
 ['MAXIM-AR COM PEITORIL FIXO','MAXIM-AR'],
 ['JANELA DE CORRER - PEITORIL FIXO','JANELA'],
 ['JANELA DE CORRER','JANELA'],
 ['FIXO VENEZIANA - 2 FOLHAS','FIXO'],
 ['PAINEL FIXO','FIXO'],
 ['PORTA DE GIRO - FIXO LATERAL','PORTA DE GIRO'],
 ['GRADIL FIXO','GRADIL'],
 ['GUARDA CORPO','GUARDA CORPO'],
 ['SPLIT TUBULAR','SPLIT'],
];
for(const [descricao,expected] of cases){
  assert.equal(classificarTipoTipologia({descricao}),expected,descricao);
  assert.ok(correspondeTipoTipologia({descricao},expected),descricao);
  if(expected==='FACHADA UNITIZADA'||expected==='FACHADA STICK'){
    assert.equal(correspondeTipoTipologia({descricao},'FIXO'),false);
    assert.equal(correspondeTipoTipologia({descricao},'MAXIM-AR'),false);
  }
}
for(const token of [
 '<option value="MAXIM-AR">MAXIM-AR</option>',
 '<option value="FIXO">FIXO</option>',
 'id="systemRulesPanel"',
 'id="variationManager"',
 'id="variationForm"',
 'function saveVariationFamily(event)',
 'tipologia_principal_id,quantidade_modulos',
 'return classificarTipoTipologia(t)===tipo;',
 'famílias e regras v30.0'
]){
  assert.ok(source.includes(token),'Preservar: '+token);
}
console.log('OK: '+cases.length+' casos de classificação e estrutura de regras/famílias.');
