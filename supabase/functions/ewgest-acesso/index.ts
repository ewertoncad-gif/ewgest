import { createClient } from 'npm:@supabase/supabase-js@2.119.0';

const URL_BASE = Deno.env.get('SUPABASE_URL');
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
if (!URL_BASE || !SERVICE_KEY || !ANON_KEY) {
  throw new Error('Supabase environment variables not configured');
}
const admin = createClient(URL_BASE, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const allowedOrigins = new Set(['https://ewgest.com.br', 'https://www.ewgest.com.br']);
function cors(origin) {
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://ewgest.com.br',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
    'Cache-Control': 'no-store, private',
    'Content-Type': 'application/json; charset=utf-8',
    'X-Content-Type-Options': 'nosniff',
  };
}
function reply(status, value, origin) {
  return new Response(JSON.stringify(value), { status, headers: cors(origin) });
}
function normalizeLogin(input) {
  if (typeof input !== 'string') throw new Error('Informe o nome de usuário.');
  const login = input.normalize('NFKC').trim().replace(/\s+/g, ' ');
  if (login.length < 3 || login.length > 100 || !/^[\p{L}\p{N} ._@-]+$/u.test(login)) {
    throw new Error('Login: use de 3 a 100 caracteres, letras, números, espaço, ponto, hífen ou sublinhado.');
  }
  return login;
}
function validName(input) {
  const name = String(input ?? '').normalize('NFKC').trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 100) throw new Error('Informe um nome de 2 a 100 caracteres.');
  return name;
}
function validPassword(input) {
  if (typeof input !== 'string' || input.length < 6 || input.length > 128)
    throw new Error('A senha precisa ter pelo menos 6 caracteres (regra do Supabase Auth).');
  return input;
}
function normalizeProfile(value) {
  const role = String(value || '');
  if (!['administrador', 'tecnico', 'consulta'].includes(role))
    throw new Error('Perfil de usuário inválido.');
  return role;
}
function publicAccount(a) {
  return {
    usuario_id: a.usuario_id, login: a.login, nome: a.nome,
    perfil: a.perfil, ativo: a.ativo, criado_em: a.criado_em,
  };
}
async function accountForToken(req) {
  const header = req.headers.get('authorization') || '';
  if (!header.startsWith('Bearer ')) throw new Error('Acesse sua conta novamente.');
  const token = header.slice(7);
  const { data: { user }, error } = await admin.auth.getUser(token);
  if (error || !user) throw new Error('Sessão inválida. Entre novamente.');
  const { data: account, error: readError } = await admin.from('usuarios_login')
    .select('usuario_id,empresa_id,login,nome,perfil,ativo,criado_em')
    .eq('usuario_id', user.id).maybeSingle();
  if (readError || !account || !account.ativo) throw new Error('Usuário sem acesso ativo.');
  const { data: member, error: membershipError } = await admin.from('usuarios_empresas')
    .select('empresa_id,perfil').eq('usuario_id', user.id)
    .eq('empresa_id', account.empresa_id).maybeSingle();
  if (membershipError || !member) throw new Error('Acesso à empresa não autorizado.');
  return { user, account, member };
}
function requireAdmin(caller) {
  if (caller.member.perfil !== 'administrador' || caller.account.perfil !== 'administrador') {
    throw new Error('Apenas o administrador pode gerenciar usuários.');
  }
}
async function targetAccount(caller, id) {
  if (typeof id !== 'string' || !/^[a-f0-9-]{36}$/i.test(id))
    throw new Error('Usuário inválido.');
  const { data, error } = await admin.from('usuarios_login')
    .select('usuario_id,empresa_id,login,nome,perfil,ativo,criado_em')
    .eq('usuario_id', id).eq('empresa_id', caller.account.empresa_id).maybeSingle();
  if (error || !data) throw new Error('Usuário não encontrado nesta empresa.');
  return data;
}
async function accountLogin(payload, origin) {
  const login = normalizeLogin(payload.login);
  if (typeof payload.senha !== 'string' || payload.senha.length > 128) {
    return reply(401, { error: 'Usuário ou senha inválidos.' }, origin);
  }
  const normalized = login.toLocaleLowerCase('pt-BR');
  const { data: account } = await admin.from('usuarios_login')
    .select('usuario_id,ativo').eq('login_chave', normalized).maybeSingle();
  if (!account || !account.ativo) return reply(401, { error: 'Usuário ou senha inválidos.' }, origin);
  const { data: userRecord, error: userError } = await admin.auth.admin.getUserById(account.usuario_id);
  if (userError || !userRecord?.user?.email) return reply(401, { error: 'Usuário ou senha inválidos.' }, origin);
  const publicClient = createClient(URL_BASE, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await publicClient.auth.signInWithPassword({
    email: userRecord.user.email, password: payload.senha,
  });
  if (error || !data?.session?.access_token)
    return reply(401, { error: 'Usuário ou senha inválidos.' }, origin);
  const ss = data.session;
  return reply(200, {
    access_token: ss.access_token, refresh_token: ss.refresh_token,
    expires_in: ss.expires_in, token_type: ss.token_type, user: ss.user,
  }, origin);
}
Deno.serve(async (req) => {
  const origin = req.headers.get('origin') || '';
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors(origin) });
  }
  if (req.method !== 'POST') return reply(405, { error: 'Método não permitido.' }, origin);
  if (origin && !allowedOrigins.has(origin)) return reply(403, { error: 'Origem não autorizada.' }, origin);
  let payload;
  try {
    const raw = await req.text();
    if (raw.length > 18000) return reply(413, { error: 'Requisição muito grande.' }, origin);
    payload = JSON.parse(raw);
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error();
  } catch {
    return reply(400, { error: 'Requisição inválida.' }, origin);
  }
  try {
    const action = payload.acao;
    if (action === 'entrar') return await accountLogin(payload, origin);
    const caller = await accountForToken(req);
    if (action === 'meu_perfil') {
      return reply(200, { usuario: publicAccount(caller.account) }, origin);
    }
    if (action === 'alterar_minha_senha') {
      const current = String(payload.senha_atual || '');
      const next = validPassword(payload.nova_senha);
      if (current === next) throw new Error('A nova senha precisa ser diferente da atual.');
      const publicClient = createClient(URL_BASE, ANON_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: verifyError } = await publicClient.auth.signInWithPassword({
        email: caller.user.email, password: current,
      });
      if (verifyError) throw new Error('A senha atual está incorreta.');
      const { error } = await admin.auth.admin.updateUserById(caller.user.id, { password: next });
      if (error) throw new Error('Não foi possível atualizar a senha.');
      return reply(200, { ok: true }, origin);
    }
    requireAdmin(caller);
    if (action === 'listar') {
      const { data, error } = await admin.from('usuarios_login')
        .select('usuario_id,empresa_id,login,nome,perfil,ativo,criado_em')
        .eq('empresa_id', caller.account.empresa_id).order('login');
      if (error) throw new Error('Falha ao consultar usuários.');
      return reply(200, { usuarios: (data || []).map(publicAccount) }, origin);
    }
    if (action === 'criar') {
      const login = normalizeLogin(payload.login);
      if (login.includes('@')) throw new Error('Para novos usuários, informe um nome de login, sem e-mail.');
      const nome = validName(payload.nome);
      const perfil = normalizeProfile(payload.perfil);
      const senha = validPassword(payload.senha);
      const { data: existing } = await admin.from('usuarios_login')
        .select('usuario_id').eq('login_chave', login.toLocaleLowerCase('pt-BR')).maybeSingle();
      if (existing) throw new Error('Este login já está cadastrado. Escolha outro.');
      const email = crypto.randomUUID() + '@usuarios.ewgest.com.br';
      const { data: created, error: authError } = await admin.auth.admin.createUser({
        email, password: senha, email_confirm: true,
        user_metadata: { nome, sistema: 'EWGEST' },
      });
      if (authError || !created?.user) throw new Error('O Supabase não aceitou o cadastro. Verifique a senha ou tente novamente.');
      const id = created.user.id;
      try {
        const { error: accountError } = await admin.from('usuarios_login').insert({
          usuario_id: id, empresa_id: caller.account.empresa_id,
          login, nome, perfil, ativo: true,
        });
        if (accountError) throw new Error('Não foi possível cadastrar o login. Verifique se já existe.');
        const { error: memberError } = await admin.from('usuarios_empresas').insert({
          usuario_id: id, empresa_id: caller.account.empresa_id, perfil,
        });
        if (memberError) throw new Error('Não foi possível vincular o usuário à empresa.');
      } catch (error) {
        await admin.from('usuarios_empresas').delete().eq('usuario_id', id)
          .eq('empresa_id', caller.account.empresa_id);
        await admin.from('usuarios_login').delete().eq('usuario_id', id);
        await admin.auth.admin.deleteUser(id);
        throw error;
      }
      return reply(201, { ok: true, usuario_id: id }, origin);
    }
    if (action === 'editar') {
      const target = await targetAccount(caller, payload.usuario_id);
      const login = normalizeLogin(payload.login);
      const nome = validName(payload.nome);
      let perfil = normalizeProfile(payload.perfil);
      if (target.usuario_id === caller.user.id) perfil = 'administrador';
      const { data: collision } = await admin.from('usuarios_login')
        .select('usuario_id').eq('login_chave', login.toLocaleLowerCase('pt-BR'))
        .neq('usuario_id', target.usuario_id).maybeSingle();
      if (collision) throw new Error('Este login já pertence a outro usuário.');
      const { error } = await admin.from('usuarios_login')
        .update({ login, nome, perfil, atualizado_em: new Date().toISOString() })
        .eq('usuario_id', target.usuario_id).eq('empresa_id', caller.account.empresa_id);
      if (error) throw new Error('Não foi possível salvar o nome e o login.');
      if (target.ativo) {
        const { error: roleError } = await admin.from('usuarios_empresas')
          .update({ perfil }).eq('empresa_id', caller.account.empresa_id)
          .eq('usuario_id', target.usuario_id);
        if (roleError) throw new Error('Nome salvo, mas não foi possível atualizar as permissões.');
      }
      return reply(200, { ok: true }, origin);
    }
    if (action === 'redefinir_senha') {
      const target = await targetAccount(caller, payload.usuario_id);
      const senha = validPassword(payload.nova_senha);
      const { error } = await admin.auth.admin.updateUserById(target.usuario_id, { password: senha });
      if (error) throw new Error('Não foi possível definir a nova senha.');
      return reply(200, { ok: true }, origin);
    }
    if (action === 'desativar') {
      const target = await targetAccount(caller, payload.usuario_id);
      if (target.usuario_id === caller.user.id) throw new Error('Não é permitido desativar sua própria conta de administrador.');
      if (!target.ativo) return reply(200, { ok: true }, origin);
      const { error: banError } = await admin.auth.admin.updateUserById(target.usuario_id,
        { ban_duration: '876000h' });
      if (banError) throw new Error('Não foi possível bloquear o acesso no Supabase Auth.');
      const { error: unlinkError } = await admin.from('usuarios_empresas').delete()
        .eq('empresa_id', caller.account.empresa_id).eq('usuario_id', target.usuario_id);
      if (unlinkError) throw new Error('Conta bloqueada no Auth, mas não foi possível retirar as permissões.');
      const { error } = await admin.from('usuarios_login')
        .update({ ativo: false, atualizado_em: new Date().toISOString() })
        .eq('usuario_id', target.usuario_id);
      if (error) throw new Error('Permissões retiradas, mas não foi possível atualizar o cadastro.');
      return reply(200, { ok: true }, origin);
    }
    if (action === 'reativar') {
      const target = await targetAccount(caller, payload.usuario_id);
      if (target.ativo) return reply(200, { ok: true }, origin);
      const { error: unbanError } = await admin.auth.admin.updateUserById(target.usuario_id,
        { ban_duration: 'none' });
      if (unbanError) throw new Error('Não foi possível desbloquear o usuário.');
      const { error: memberError } = await admin.from('usuarios_empresas').upsert({
        empresa_id: caller.account.empresa_id, usuario_id: target.usuario_id, perfil: target.perfil,
      }, { onConflict: 'empresa_id,usuario_id' });
      if (memberError) throw new Error('Usuário desbloqueado, mas não foi possível restaurar o vínculo.');
      const { error } = await admin.from('usuarios_login')
        .update({ ativo: true, atualizado_em: new Date().toISOString() })
        .eq('usuario_id', target.usuario_id);
      if (error) throw new Error('Usuário vinculado, mas não foi possível reativar o login.');
      return reply(200, { ok: true }, origin);
    }
    return reply(400, { error: 'Operação não reconhecida.' }, origin);
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Falha inesperada.';
    const unauthorized = /Acesse sua conta|Sessão inválida|sem acesso ativo|não autorizado/.test(message);
    return reply(unauthorized ? 401 : 400, { error: message }, origin);
  }
});