const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('./sdk-typescript.cjs');
let now = 100000, next = 0, attempts = 0, paired = ['saved'], audio = ['saved'], denied = false;
let bluetoothOn = true, activeController;
const names = new Map([['saved', '我的耳机'], ['new', 'WH-1000XM6'], ['otherSony', 'WF-1000XM5'],
  ['unrelated', 'HUAWEI FreeBuds']]);
const timers = new Map(), values = new Map([['device', 'saved']]);
const profile = { getConnectedDevices: () => audio, on() {}, off() {} };
const store = { getSync: (k, d) => values.has(k) ? values.get(k) : d,
  putSync: (k, v) => values.set(k, v), flush: async () => {} };
const kits = {
  '@kit.AbilityKit': {}, '@kit.BasicServicesKit': {},
  '@kit.ConnectivityKit': {
    access: { BluetoothState: { STATE_ON: 2 }, getState: () => {
      if (denied) throw Error('denied'); return bluetoothOn ? 2 : 0;
    }},
    connection: { getPairedDevices: () => paired, getRemoteDeviceName: id => names.get(id) || '' },
    a2dp: { createA2dpSrcProfile: () => profile }
  },
  './BackgroundSession': { BackgroundSession: class { initialize() {} stop() {} destroy() {} } },
  './WidgetStore': { widgetPreferences: () => store, WidgetSnapshot: class {}, publishWidget: async () => {} },
  '../protocol/DeviceNames': { isSonyHeadphoneName: name => name === 'WH-1000XM6' || name === 'WF-1000XM5' },
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
const entryExports = {};
const entryKits = {
  '@kit.AbilityKit': { UIAbility: class {} }, '@kit.ArkUI': {}, '@kit.BasicServicesKit': {},
  '@kit.PerformanceAnalysisKit': {}, '../services/Appearance': { appearance: { load() {} } },
  '../services/Headphones': { get headphones() { return activeController; } }
};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8'), { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS
}}).outputText, {
  exports: entryExports, require: name => { assert.ok(name in entryKits, name); return entryKits[name]; }
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
  activeController = c;
  const entry = new entryExports.default();
  entry.context = {};
  c.connect = async device => { assert.equal(device.address, 'saved'); attempts++; c.failure('test'); };
  entry.onCreate({});
  assert.equal(c.state.autoReconnect, true, 'First launch enables automatic connection');
  entry.onForeground();
  await tick(0); await tick(5000); await tick(15000);
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
  audio = ['unrelated']; await tick(0);
  assert.equal(attempts, 3, 'Unrelated audio device must not trigger SPP');
  audio = ['saved']; paired = []; c.audioChanged(); await tick(0);
  assert.equal(attempts, 3, 'Unpaired saved device must not reconnect');
  paired = ['saved']; denied = true; c.audioChanged(); await tick(0);
  assert.equal(attempts, 3, 'Revoked permission stops silently without retries');
  assert.equal(timers.size, 0);
  c.destroy();
  denied = false;
  const choose = new exportsObject.HeadphoneController();
  choose.initialize({});
  choose.connect = async (device, automatic) => {
    assert.equal(automatic, true);
    selected.push(device.address);
    choose.reconnectAttempts = 0;
  };
  let selected = [];
  values.delete('device');
  values.delete('autoReconnect');
  choose.onForeground();
  paired = ['new', 'unrelated']; audio = ['unrelated', 'new'];
  await tick(0);
  assert.deepEqual(selected, ['new'], 'A first-time launch recognizes the sole connected Sony headset');
  selected = [];
  paired = ['new', 'unrelated']; audio = ['unrelated']; choose.audioChanged(); await tick(0);
  assert.equal(selected.length, 0, 'A paired but disconnected Sony headset is ignored');
  paired = ['new', 'otherSony']; audio = ['otherSony', 'new']; choose.audioChanged(); await tick(0);
  assert.equal(selected.length, 0, 'Several connected headsets require a choice');
  assert.match(choose.state.notice, /多副/);
  values.set('device', 'new'); choose.audioChanged(); await tick(0);
  assert.deepEqual(selected, ['new'], 'Last-used connected Sony headset has priority');
  selected = [];
  audio = ['otherSony']; choose.audioChanged(); await tick(0);
  assert.deepEqual(selected, ['otherSony'], 'An unavailable saved headset does not prevent using the connected one');
  selected = [];
  choose.widgetActionRunning = true; choose.audioChanged(); await tick(0);
  assert.equal(selected.length, 0, 'Card actions retain control of their own connection');
  choose.widgetActionRunning = false;
  choose.audioChanged(); bluetoothOn = false; await tick(0);
  assert.equal(selected.length, 0, 'Bluetooth-off state never attempts a connection');
  bluetoothOn = true;
  choose.disconnect();
  choose.onForeground();
  assert.equal(timers.size, 0, 'Manual disconnect stays paused until a fresh ability is created');
  activeController = choose;
  const relaunched = new entryExports.default(); relaunched.context = {};
  relaunched.onCreate({}); relaunched.onForeground(); await tick(0);
  assert.deepEqual(selected, ['otherSony'], 'Recreating the ability restores automatic connection');
  choose.destroy();

  values.set('autoReconnect', false);
  activeController = new exportsObject.HeadphoneController();
  const disabledEntry = new entryExports.default(); disabledEntry.context = {};
  disabledEntry.onCreate({}); disabledEntry.onForeground();
  assert.equal(activeController.state.autoReconnect, false);
  assert.equal(timers.size, 0, 'A saved user opt-out survives app relaunch');
  activeController.destroy();
  console.log('PASS: launch lifecycle, default auto-connect, first headset, saved preference, multiple devices, backoff/cap, manual pause, background, disable and permission');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
