/* EWGEST — instalação web app no Android, iPhone e computadores. */
(function () {
  'use strict';
  const button = document.getElementById('installEwgest');
  const hint = document.getElementById('installHelp');
  if (!button || !hint) return;
  let pendingInstall = null;
  const ua = navigator.userAgent || '';
  const isIOS = /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isAndroid = /Android/i.test(ua);
  const installed = () => (
    window.matchMedia('(display-mode: standalone)').matches ||
    navigator.standalone === true
  );
  function say(message) {
    hint.textContent = message;
    hint.hidden = !message;
  }
  function fallbackSteps() {
    if (isIOS) return 'No iPhone, abra o menu Compartilhar do navegador e toque em Adicionar à Tela de Início. Confirme Adicionar.';
    if (isAndroid) return 'No Android, abra o menu ⋮ do Chrome e escolha Instalar aplicativo ou Adicionar à tela inicial.';
    return 'No computador, use o menu do Chrome/Edge e escolha Instalar aplicativo (ou Instalar esta página como app), se disponível.';
  }
  if (installed()) {
    button.disabled = true;
    button.textContent = 'Aplicativo instalado';
    return;
  }
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    pendingInstall = event;
    button.textContent = 'Baixe para seu celular';
  });
  window.addEventListener('appinstalled', () => {
    pendingInstall = null;
    button.disabled = true;
    button.textContent = 'Aplicativo instalado';
    say('EWGEST instalada! Abra pelo ícone da tela inicial.');
  });
  button.addEventListener('click', async () => {
    if (installed()) {
      say('EWGEST já está instalada neste aparelho.');
      return;
    }
    if (pendingInstall) {
      const prompt = pendingInstall;
      pendingInstall = null;
      try {
        await prompt.prompt();
        const choice = await prompt.userChoice;
        if (choice && choice.outcome === 'accepted') {
          say('Instalação aceita. Confira o ícone na tela inicial.');
        } else {
          say('Se quiser instalar depois: ' + fallbackSteps());
        }
      } catch (_) {
        say(fallbackSteps());
      }
    } else {
      say(fallbackSteps());
    }
  });
  if ('serviceWorker' in navigator && window.isSecureContext) {
    navigator.serviceWorker.register('/sw.js', {scope:'/'}).catch(() => {
      // O acesso normal pelo navegador continua funcionando.
    });
  }
})();
