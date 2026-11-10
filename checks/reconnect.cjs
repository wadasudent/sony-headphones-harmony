const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('D:/HuaweiDevTools/DevEcoStudio26/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
let now = 100000, next = 0, attempts = 0, paired = ['saved'], audio = ['saved'], denied = false;
const timers = new Map(), values = new Map([['device', 'saved']]);
const profile = { getConnectedDevices: () => audio, on() {}, off() {} };
const store = { getSync: (k, d) => values.has(k) ? values.get(k) : d,
  putSync: (k, v) => values.set(k, v), flush: async () => {} };
const kits = {
  '@kit.AbilityKit': {}, '@kit.BasicServicesKit': {},
  '@kit.ConnectivityKit': {
    access: { BluetoothState: { STATE_ON: 2 }, getState: () => {
      if (denied) throw Error('denied'); return 2;
    }},
    connection: { getPairedDevices: () => paired }, a2dp: { createA2dpSrcProfile: () => profile }
  },
  './BackgroundSession': { BackgroundSession: class { initialize() {} stop() {} destroy() {} } },
  './WidgetStore': { widgetPreferences: () => store, WidgetSnapshot: class {}, publishWidget: async () => {} },
  '../protocol/DeviceNames': { isSonyHeadphoneName: () => true },
  '../protocol/MdrCore': { Xm6Protocol: class {}, NoiseMode: { Unknown: -1 } }
};
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/services/Headphones.ets'), 'utf8'), { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
}}).outputText, {
  exports: exportsObject, require: name => { assert.ok(name in kits, name); return kits[name]; },
  ObservedV2: c => c, Trace: () => {}, JSON, Math, Uint8Array,
  Date: class extends Date { static now() { return now; } },
  setTimeout: (fn, delay) => { const id = ++next; timers.set(id, { fn, delay }); return id; },
  clearTimeout: id => timers.delete(id), clearInterval() {}
});
async function tick(delay) {
  assert.equal(timers.size, 1);
  const [id, task] = [...timers][0];
  assert.equal(task.delay, delay);
  timers.delete(id); now += delay; task.fn();
  await new Promise(resolve => setImmediate(resolve));
}
async function main() {
  const c = new exportsObject.HeadphoneController();
  c.initialize({});
  assert.equal(c.state.autoReconnect, false, 'Opt-in by default');
  c.connect = async device => { assert.equal(device.address, 'saved'); attempts++; c.failure('test'); };
  await c.setAutoReconnect(true);
  await tick(2000); await tick(5000); await tick(15000);
  assert.equal(attempts, 3);
  c.audioChanged(); c.audioChanged();
  assert.equal(timers.size, 0, 'No event storm may bypass retry cap');
  now += 60000; c.onForeground();
  assert.equal(timers.size, 1);
  c.disconnect();
  assert.equal(timers.size, 0);
  c.onForeground(); c.audioChanged();
  assert.equal(timers.size, 0, 'Manual disconnect remains paused');
  await c.setAutoReconnect(true);
  c.onBackground();
  assert.equal(timers.size, 0, 'Background transition cancels waiting attempt');
  await c.tryReconnect();
  assert.equal(attempts, 3);
  c.onForeground();
  await c.setAutoReconnect(false);
  assert.equal(timers.size, 0);
  assert.equal(values.get('autoReconnect'), false);
  await c.setAutoReconnect(true);
  audio = ['unrelated']; await tick(2000);
  assert.equal(attempts, 3, 'Unrelated audio device must not trigger SPP');
  audio = ['saved']; paired = []; c.audioChanged(); await tick(2000);
  assert.equal(attempts, 3, 'Unpaired saved device must not reconnect');
  paired = ['saved']; denied = true; c.audioChanged(); await tick(2000);
  assert.equal(attempts, 3, 'Revoked permission stops silently without retries');
  assert.equal(timers.size, 0);
  c.destroy();
  console.log('PASS: opt-in, verified audio target, backoff/cap, event storms, manual pause, background cancellation, disable, unpair, revoked permission');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
