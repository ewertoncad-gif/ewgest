import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const start=html.indexOf('function renderGerenciamentoObras(){');
const end=html.indexOf('function abrirGerenciamentoObras(){',start);
assert.ok(start>0&&end>start,'Localizar renderizador de gerenciamento de obras');
const render=html.slice(start,end);

assert.match(html,/cancelado_em:'is.null'/,'O histórico é carregado somente com liberações ativas');
assert.match(render,/const liberacoesAtivas=releaseHistory\.filter\(h=>ids\.has\(h\.esquadria_id\)\)\.length/);
assert.match(render,/const podeCancelarLiberacoes=liberacoesAtivas>0/);
assert.match(render,/disabled title="Esta obra não possui liberações ativas para cancelar/);

const root={
 innerHTML:'',
 querySelectorAll:()=>[],
};
const context={
 works:[
  {id:'obra-zero',nome:'OBRA SEM LIBERAÇÕES',codigo:'CEM-ZERO'},
  {id:'obra-uma',nome:'OBRA UMA LIBERAÇÃO',codigo:'CEM-UM'},
  {id:'obra-duas',nome:'OBRA DUAS LIBERAÇÕES',codigo:'CEM-DOIS'},
 ],
 elements:[
  {id:'ea-zero',obra_id:'obra-zero'},
  {id:'ea-uma',obra_id:'obra-uma'},
  {id:'ea-duas-a',obra_id:'obra-duas'},
  {id:'ea-duas-b',obra_id:'obra-duas'},
 ],
 releaseHistory:[
  {esquadria_id:'ea-uma',quantidade:1},
  {esquadria_id:'ea-duas-a',quantidade:2},
  {esquadria_id:'ea-duas-b',quantidade:1},
 ],
 node:()=>root,
 escapeHTML:x=>String(x),
};
vm.createContext(context);
vm.runInContext(render,context);
context.renderGerenciamentoObras();

function inspect(nome){
 const parts=root.innerHTML.split('<div class="manufacturerLine" style="gap:14px">').slice(1);
 assert.equal(parts.length,3,'Cada obra deve ocupar uma linha');
 const row=parts.find(x=>x.includes('<strong>'+nome+'</strong>'));
 assert.ok(row,'Obra não encontrada: '+nome);
 const btn=row.match(/<button type="button" class="btn secondary releaseCancellationButton" data-work-cancel-releases="([^"]+)"([^>]*)>([^<]+)<\/button>/);
 assert.ok(btn,'Botão não encontrado: '+nome);
 assert.match(row,/data-work-review="[^"]+"/,'Verificar exclusão deve continuar disponível');
 return {html:row,id:btn[1],attrs:btn[2],label:btn[3]};
}

let zero=inspect('OBRA SEM LIBERAÇÕES');
assert.equal(zero.id,'obra-zero');
assert.match(zero.html,/Liberações ativas: 0/);
assert.equal(zero.label,'Cancelar liberações (0)');
assert.match(zero.attrs,/\bdisabled\b/);
assert.match(zero.attrs,/não possui liberações ativas/);

let uma=inspect('OBRA UMA LIBERAÇÃO');
assert.equal(uma.id,'obra-uma');
assert.match(uma.html,/Liberações ativas: 1/);
assert.equal(uma.label,'Cancelar liberações (1)');
assert.doesNotMatch(uma.attrs,/\bdisabled\b/);

let duas=inspect('OBRA DUAS LIBERAÇÕES');
assert.equal(duas.id,'obra-duas');
assert.match(duas.html,/Liberações ativas: 2/);
assert.equal(duas.label,'Cancelar liberações (2)');
assert.doesNotMatch(duas.attrs,/\bdisabled\b/);

// Ao cancelar ou criar uma liberação e recarregar o painel, o botão
// precisa refletir a contagem atual, sem exigir mudança de tela.
context.releaseHistory=[];
context.renderGerenciamentoObras();
for(const nome of context.works.map(w=>w.nome)){
 const b=inspect(nome);
 assert.equal(b.label,'Cancelar liberações (0)');
 assert.match(b.attrs,/\bdisabled\b/);
}
context.releaseHistory=[{esquadria_id:'ea-zero',quantidade:1}];
context.renderGerenciamentoObras();
zero=inspect('OBRA SEM LIBERAÇÕES');
assert.equal(zero.label,'Cancelar liberações (1)');
assert.doesNotMatch(zero.attrs,/\bdisabled\b/);
assert.equal(inspect('OBRA UMA LIBERAÇÃO').label,'Cancelar liberações (0)');

console.log('OK v46.12: contador 0/1/2 por obra, disabled somente com zero e recálculo após refresh.');
