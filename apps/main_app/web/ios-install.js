(function () {
  'use strict';

  const banner = document.getElementById('ios-install-banner');
  if (!banner) return;

  const userAgent = navigator.userAgent;
  // iPadOS can request desktop sites using a Mac user agent.
  const isIOS = /iPad|iPhone|iPod/.test(userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!isIOS) return;

  const storageKey = 'aumazing.ios-install.dismissed';
  const standalone = window.matchMedia('(display-mode: standalone)');
  let dismissed = false;

  const isSafari = /Version\//.test(userAgent) && /Safari\//.test(userAgent) &&
    !/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|GSA\/|FBAN|FBAV|Instagram/i.test(userAgent);
  document.getElementById('ios-install-safari').hidden = isSafari;

  const update = () => {
    let savedDismissal = false;
    try {
      savedDismissal = window.localStorage.getItem(storageKey) === 'true';
    } catch (_) {
      // Storage may be blocked; dismissal still works for this page visit.
    }
    banner.hidden = dismissed || savedDismissal ||
      navigator.standalone === true || standalone.matches;
  };

  document.getElementById('ios-install-dismiss').addEventListener('click', () => {
    dismissed = true;
    try {
      window.localStorage.setItem(storageKey, 'true');
    } catch (_) {
      // Keep the in-memory dismissal when storage is unavailable.
    }
    update();
  });

  if (standalone.addEventListener) {
    standalone.addEventListener('change', update);
  } else {
    standalone.addListener(update);
  }
  window.addEventListener('pageshow', update);
  window.addEventListener('storage', update);
  window.addEventListener('appinstalled', () => {
    dismissed = true;
    update();
  });
  update();
})();
