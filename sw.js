/* EWGEST PWA v1: não guarda senhas, tokens, dados de obras ou respostas do Supabase.
 * A autenticação e o trabalho sempre exigem conexão à internet. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || event.request.mode !== 'navigate') return;
  if (new URL(event.request.url).origin !== self.location.origin) return;
  // Navegação sempre pela rede, sem cache persistente das informações privadas.
  event.respondWith(fetch(event.request).catch(() => new Response(
    '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>EWGEST | Sem conexão</title><body style="font:17px system-ui;background:#0c1727;color:#eaf2fc;padding:30px"><h1>EWGEST</h1><p>Você está sem conexão. Conecte-se à internet para acessar as obras e os lançamentos.</p><a style="color:#62d9b3" href="/app">Tentar novamente</a></body></html>',
    {status:503,headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}}
  )));
});
