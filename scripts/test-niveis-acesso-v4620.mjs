import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const read=p=>readFileSync(fileURLToPath(new URL(p,import.meta.url)),'utf8');
const app=read('../app.html');
const ui=read('../assets/niveis-acesso.js');
const css=read('../assets/niveis-acesso.css');
const edge=read('../supabase/functions/ewgest-acesso/index.ts');
const base=read('../database/proposals/20261122_niveis_acesso_v4620.sql');
const guards=read('../database/proposals/20261122_niveis_guardas_rpc_v4620.sql');
const rls=read('../database/proposals/20261122_niveis_rls_v4620.sql');
const reports=read('../assets/relatorios-obras.js');
assert.doesNotThrow(()=>new Function(ui),'Editor de flags deve compilar');
assert.doesNotThrow(()=>new Function(reports),'Relatórios devem compilar');
assert.match(app,/EWGEST <strong>· v46\.23<\/strong>/);
assert.match(app,/niveis-acesso\.js\?v=20261124c/);
assert.match(app,/niveis-acesso\.css\?v=20261124c/);
for(const token of ['id="createUserLevel"','id="userEditLevel"','id="userLevelsPanel"',
 'id="userLevelsSave"','id="userLevelsGroups"','id="userLevelsTabs"']){
 assert.ok(app.includes(token),'Falta o controle '+token);
}
for(let n=1;n<=8;n++)assert.ok(app.includes('<option value="'+n+'"'),
 'Nível '+String(n).padStart(2,'0')+' ausente nos formulários');
for(const group of ['Financeiro','Estoque','Liberação','Romaneios','Obras','Cadastros','Administração','Navegação']){
 assert.ok(base.includes("'"+group+"'"),'Grupo não registrado: '+group);
}
assert.match(base,/CREATE TABLE IF NOT EXISTS public\.ew_niveis_auditoria/);
assert.match(base,/CREATE OR REPLACE FUNCTION public\.ew_salvar_nivel/);
assert.match(base,/p_nivel NOT BETWEEN 2 AND 8/,'Impedir edição do nível 01');
assert.match(base,/nivel_acesso=ul\.nivel_acesso/,'Vínculo precisa seguir o nível do login');
assert.match(base,/ul\.nivel_acesso=ue\.nivel_acesso/,'Impedir divergência de nível');
assert.match(base,/ul\.ativo AND ul\.excluido_em IS NULL/,'Conta inativa sem permissão');
assert.match(base,/public\.ew_sessao_eh_atual\(\)/,'Verificar sessão ativa no servidor');
assert.ok(ui.includes("window.nivelAcessoPreparar=nivelAcessoPreparar")&&
 ui.includes("'/rest/v1/rpc/ew_salvar_nivel'")&&ui.includes('userLevelsGroups'));
assert.ok(ui.includes("nivel===1?")&&ui.includes("'Nível 01 protegido"));
assert.match(app,/request\('\/rest\/v1\/rpc\/ew_meu_nivel'/);
assert.match(app,/temPermissao\('financeiro\.consultar'\)/);
assert.match(reports,/temPermissao\('relatorios\.financeiros'\)/);
assert.match(reports,/el\('reportType'\)\.value='estoque'/,'Nível 07 nunca vê relatório financeiro');
assert.match(guards,/PERFORM public\.ew_exigir_permissao\('estoque\.estornar'\)/);
assert.match(guards,/PERFORM public\.ew_exigir_permissao\('financeiro\.faturar'\)/);
assert.match(guards,/PERFORM public\.ew_exigir_permissao\('obras\.estornar'\)/);
assert.match(guards,/PERFORM public\.ew_exigir_permissao\('romaneios\.emitir'\)/);
assert.match(guards,/PERFORM public\.ew_exigir_permissao\('liberacoes\.criar'\)/);
assert.match(rls,/CREATE POLICY ew_nivel_select_restrito/);
assert.match(rls,/public\.ew_pode\(empresa_id,'relatorios\.financeiros'\)/);
assert.match(rls,/CREATE POLICY ew_flags_update/);
assert.match(edge,/normalizeLevel\(payload\.nivel_acesso,payload\.perfil\)/);
assert.match(edge,/caller\.flags\.has\('usuarios\.gerenciar'\)/);
assert.match(edge,/nivel_acesso:target\.nivel_acesso/);
assert.match(app,/nivel_acesso,senha/);
assert.match(app,/nivel_acesso\}/);
assert.ok(!app.includes("EWGEST <strong>· v46.19</strong>"));
console.log('OK v46.20: oito níveis, 28 flags, permissões no banco, relatórios 06/07, nível 01 protegido.');

const landing=read('../index.html');
assert.match(landing,/location\.replace\('\/app'\)/);
assert.ok(!landing.includes('Primeiros módulos'));
assert.match(app,/id="navAccessLevels"/);
assert.match(app,/section id="accessLevels"/);
assert.match(app,/if\(view==='accessLevels'\)return currentAccessLevel===1&&temPermissao\('niveis.gerenciar'\)/);
assert.ok(app.includes('id="userLevelsSearch"')&&app.includes('id="userLevelsAll"')&&app.includes('id="userLevelsNone"'));
assert.ok(!app.includes('class="btn secondary loginBackHome"'));
assert.ok(app.includes('id="installEwgest"')&&app.includes('/pwa-install.js?v=25'));
assert.ok(ui.includes('p_nivel:nivel')&&ui.includes('p_empresa_id:company')&&ui.includes('dirty()'));
console.log('OK: entrada direta, menu exclusivo de níveis e ações de edição protegidas.');
