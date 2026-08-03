(function () {
  'use strict';

  const scripts = Object.freeze({
    sandbox: 'https://app.sandbox.midtrans.com/snap/snap.js',
    production: 'https://app.midtrans.com/snap/snap.js',
  });
  const clientKeyPattern = /^Mid-client-[A-Za-z0-9_-]{8,128}$/;
  const tokenPattern = /^[A-Za-z0-9_-]{8,512}$/;
  let scriptPromise = null;
  let scriptIdentity = null;
  let active = null;

  function hideActive() {
    try {
      if (window.snap && typeof window.snap.hide === 'function') {
        window.snap.hide();
      }
    } catch (_) {
      // Closing an already-closed overlay is harmless.
    }
    active = null;
  }

  function loadSnap(clientKey, environment) {
    const src = scripts[environment];
    if (!src || !clientKeyPattern.test(clientKey)) {
      return Promise.reject(new Error('Invalid Midtrans client config'));
    }
    const identity = `${src}|${clientKey}`;
    if (scriptPromise && scriptIdentity === identity) return scriptPromise;
    if (scriptPromise && scriptIdentity !== identity) {
      return Promise.reject(new Error('Midtrans environment cannot change'));
    }

    scriptIdentity = identity;
    const candidate = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.setAttribute('data-client-key', clientKey);
      script.referrerPolicy = 'no-referrer';
      script.onload = () => {
        if (window.snap && typeof window.snap.pay === 'function') {
          resolve(window.snap);
        } else {
          reject(new Error('Snap.js did not initialize'));
        }
      };
      script.onerror = () => {
        script.remove();
        reject(new Error('Snap.js failed to load'));
      };
      document.head.appendChild(script);
    });
    scriptPromise = candidate.catch((error) => {
      // A transient network failure must remain retryable from the in-app
      // reload control; never pin a rejected Promise for the page lifetime.
      if (scriptIdentity === identity) {
        scriptPromise = null;
        scriptIdentity = null;
      }
      throw error;
    });
    return scriptPromise;
  }

  async function pay(token, clientKey, environment, sessionId, onResult) {
    if (!tokenPattern.test(token) || typeof onResult !== 'function') {
      throw new Error('Invalid Snap checkout session');
    }
    hideActive();
    const current = { sessionId, onResult, notified: false };
    active = current;
    const snap = await loadSnap(clientKey, environment);
    if (active !== current) return;

    const notify = (kind) => {
      if (active !== current || current.notified) return;
      current.notified = true;
      // Provider payloads are deliberately discarded. Dart only receives a
      // hint and asks the authenticated backend for authoritative state.
      current.onResult(kind);
    };
    snap.pay(token, {
      onSuccess: function () { notify('status'); },
      onPending: function () { notify('status'); },
      onError: function () { notify('status'); },
      onClose: function () { notify('closed'); },
    });
  }

  function hide(sessionId) {
    if (active && active.sessionId === sessionId) hideActive();
  }

  Object.defineProperty(window, 'SaveBiteSnap', {
    value: Object.freeze({ pay, hide }),
    configurable: false,
    enumerable: false,
    writable: false,
  });
})();
