import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const bridgeSource = readFileSync(
  new URL('../web/snap_bridge.js', import.meta.url),
  'utf8',
);

function createHarness() {
  const scripts = [];
  const timers = [];
  const window = {};
  const document = {
    createElement() {
      return {
        async: false,
        onerror: null,
        onload: null,
        referrerPolicy: '',
        removed: false,
        setAttribute() {},
        remove() {
          this.removed = true;
        },
      };
    },
    head: {
      appendChild(script) {
        scripts.push(script);
        return script;
      },
    },
  };
  const context = {
    Error,
    Object,
    Promise,
    RegExp,
    String,
    clearTimeout(timer) {
      timer.cleared = true;
    },
    document,
    setTimeout(callback, delay) {
      const timer = { callback, cleared: false, delay };
      timers.push(timer);
      return timer;
    },
    window,
  };

  vm.runInNewContext(bridgeSource, context, {
    filename: 'web/snap_bridge.js',
  });
  return { scripts, timers, window };
}

test('Snap.js load times out after 20 seconds and can be retried', async () => {
  const harness = createHarness();
  const { SaveBiteSnap } = harness.window;
  const token = 'sandboxToken_123456789';
  const clientKey = 'Mid-client-sandboxPublic123';

  const firstAttempt = SaveBiteSnap.pay(
    token,
    clientKey,
    'sandbox',
    'first-session',
    () => {},
  );
  assert.equal(harness.scripts.length, 1);
  assert.equal(harness.timers.length, 1);
  assert.equal(harness.timers[0].delay, 20_000);

  harness.timers[0].callback();
  await assert.rejects(firstAttempt, /Snap\.js load timed out/);
  assert.equal(harness.scripts[0].removed, true);

  harness.window.snap = { pay() {} };
  const retry = SaveBiteSnap.pay(
    token,
    clientKey,
    'sandbox',
    'second-session',
    () => {},
  );
  assert.equal(harness.scripts.length, 2);
  harness.scripts[1].onload();
  await retry;
  assert.equal(harness.timers[1].cleared, true);
});
