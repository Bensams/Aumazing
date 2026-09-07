(function () {
  'use strict';

  const banner = document.getElementById('ios-install-banner');
  if (!banner) return;

  const guide = document.getElementById('ios-install-guide');
  const guideOpen = document.getElementById('ios-install-guide-open');
  const guideClose = document.getElementById('ios-install-guide-close');
  const guideImage = guide && guide.querySelector('[data-ios-install-guide-src]');

  const userAgent = navigator.userAgent;
  // iPadOS can request desktop sites using a Mac user agent.
  const isIOS = /iPad|iPhone|iPod/.test(userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!isIOS) return;

  const storageKey = 'aumazing.ios-install.dismissed';
  const standalone = window.matchMedia('(display-mode: standalone)');
  let dismissed = false;
  let guideOpener = null;

  const isSafari = /Version\//.test(userAgent) && /Safari\//.test(userAgent) &&
    !/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|GSA\/|FBAN|FBAV|Instagram/i.test(userAgent);
  const safariNote = document.getElementById('ios-install-safari');
  if (safariNote) safariNote.hidden = isSafari;

  const restoreGuideFocus = () => {
    const opener = guideOpener;
    guideOpener = null;
    if (opener && document.contains(opener) && !banner.hidden) {
      opener.focus({ preventScroll: true });
    }
  };

  const guideIsOpen = () => guide && guide.hasAttribute('open');

  const closeGuide = () => {
    if (!guide) return;
    if (guideIsOpen()) {
      if (typeof guide.close === 'function') {
        try {
          guide.close();
        } catch (_) {
          guide.removeAttribute('open');
        }
      } else {
        guide.removeAttribute('open');
      }
      guide.removeAttribute('aria-modal');
    }
    restoreGuideFocus();
  };

  const openGuide = () => {
    if (!guide || banner.hidden) return;
    guideOpener = guideOpen;
    if (guideImage && !guideImage.getAttribute('src')) {
      guideImage.setAttribute('src', guideImage.getAttribute('data-ios-install-guide-src'));
    }
    if (!guideIsOpen()) {
      if (typeof guide.showModal === 'function') {
        try {
          guide.showModal();
        } catch (_) {
          guide.setAttribute('open', '');
          guide.setAttribute('aria-modal', 'true');
        }
      } else {
        guide.setAttribute('open', '');
        guide.setAttribute('aria-modal', 'true');
      }
    }
    if (guideClose) {
      window.setTimeout(() => guideClose.focus(), 0);
    }
  };

  const update = () => {
    let savedDismissal = false;
    try {
      savedDismissal = window.localStorage.getItem(storageKey) === 'true';
    } catch (_) {
      // Storage may be blocked; dismissal still works for this page visit.
    }
    banner.hidden = dismissed || savedDismissal ||
      navigator.standalone === true || standalone.matches;
    if (banner.hidden) closeGuide();
  };

  if (guideOpen) guideOpen.addEventListener('click', openGuide);
  if (guideClose) guideClose.addEventListener('click', closeGuide);
  if (guide) {
    guide.addEventListener('close', restoreGuideFocus);
    guide.addEventListener('click', event => {
      if (event.target === guide) closeGuide();
    });
    guide.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        event.preventDefault();
        closeGuide();
        return;
      }
      if (event.key !== 'Tab') return;
      const focusable = Array.from(guide.querySelectorAll(
        'button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
      )).filter(element => !element.hidden && element.offsetParent !== null);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    });
  }

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
