(function () {
  'use strict';

  // Registers the offline service worker (offline_sw.js, AUM-334) and, once it
  // controls the page, quietly downloads the rest of the games' files so a
  // child can later play any game with no connection. Exposes
  // window.aumazingOffline for the app: status() and downloadAll(onProgress).

  if (!('serviceWorker' in navigator)) return;

  // Give the app time to start before competing with it for bandwidth.
  const BACKGROUND_DELAY_MS = 20000;
  const RETRY_DELAY_MS = 60000;

  function send(message, onProgress) {
    return navigator.serviceWorker.ready.then((reg) => new Promise((resolve, reject) => {
      const worker = navigator.serviceWorker.controller || reg.active;
      if (!worker) {
        reject(new Error('offline worker is not active'));
        return;
      }
      const channel = new MessageChannel();
      channel.port1.onmessage = (event) => {
        const data = event.data || {};
        if (data.type === 'progress') {
          if (onProgress) onProgress(data);
        } else if (data.type === 'result') {
          resolve(data);
        } else if (data.type === 'error') {
          reject(new Error(data.message));
        }
      };
      worker.postMessage(message, [channel.port2]);
    }));
  }

  let downloading = null;

  // Browsers cut a service worker's task short after a few minutes, so keep
  // asking until nothing is missing. Each round resumes where the last ended.
  function downloadAll(onProgress) {
    if (!downloading) {
      downloading = (async () => {
        for (;;) {
          const result = await send({ type: 'cache-all' }, onProgress);
          if (result.total === 0 || (result.done === result.total && result.failed === 0)) {
            return send({ type: 'status' });
          }
          if (result.failed > 0 && result.failed === result.total) {
            throw new Error('could not download offline files');
          }
        }
      })().finally(() => { downloading = null; });
    }
    return downloading;
  }

  function prefersSavingData() {
    const connection = navigator.connection;
    return !!(connection && connection.saveData);
  }

  function backgroundDownload() {
    if (!navigator.onLine || prefersSavingData()) return;
    downloadAll().catch((e) => {
      console.warn('[offline] background download stopped:', e.message);
      setTimeout(backgroundDownload, RETRY_DELAY_MS);
    });
  }

  window.aumazingOffline = {
    status: () => send({ type: 'status' }),
    downloadAll: downloadAll,
  };

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('offline_sw.js').then(() => {
      // Ask the browser not to evict the cache under storage pressure.
      if (navigator.storage && navigator.storage.persist) {
        navigator.storage.persist().catch(() => {});
      }
      return navigator.serviceWorker.ready;
    }).then(() => {
      setTimeout(backgroundDownload, BACKGROUND_DELAY_MS);
    }).catch((e) => {
      console.warn('[offline] service worker unavailable:', e.message);
    });
  });

  window.addEventListener('online', () => setTimeout(backgroundDownload, BACKGROUND_DELAY_MS));
})();
