// Run with the official SDK TypeScript runtime, without a device or Bluetooth.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || 'D:/HuaweiDevTools/DevEcoStudio26/sdk',
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
function load(file, kits, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services', file), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
  }}).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => {
    assert.ok(name in kits, 'Unexpected platform dependency: ' + name);
    return kits[name];
  }, Date, Math, JSON, Uint8Array, ObservedV2: value => value, Trace: () => {}, ...globals });
  return exports;
}

async function main() {
  let cancel, releaseAgent, starts = 0, stops = 0, cancelled = 0;
  const manager = {
    BackgroundMode: { BLUETOOTH_INTERACTION: 5 },
    on: (_, fn) => { cancel = fn; }, off: () => {},
    startBackgroundRunning: async () => { starts++; },
    stopBackgroundRunning: async () => { stops++; cancel({}); }
  };
  let agent = new Promise(resolve => { releaseAgent = resolve; });
  const { BackgroundSession } = load('BackgroundSession.ets', {
    '@kit.AbilityKit': { wantAgent: {
      getWantAgent: () => agent, OperationType: { START_ABILITY: 1 },
      WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 }
    }}, '@kit.BackgroundTasksKit': { backgroundTaskManager: manager }
  });
  const session = new BackgroundSession();
  session.initialize({}, () => { cancelled++; });
  const pending = session.start();
  session.stop(); // Disconnect while the start operation is still awaiting its WantAgent.
  releaseAgent({});
  await pending;
  await session.operations;
  assert.equal(starts, 1);
  assert.equal(stops, 1);
  assert.equal(session.active, false);
  assert.equal(cancelled, 0, 'A user disconnect must not be reported as system cancellation');
  manager.startBackgroundRunning = async () => { throw new Error('system denied'); };
  await assert.rejects(session.start(), /system denied/);
  assert.equal(session.active, false);
  manager.startBackgroundRunning = async () => { starts++; };
  await session.start();
  cancel({}); cancel({});
  assert.equal(session.active, false);
  assert.equal(cancelled, 1);
  session.destroy();
  await session.operations;

  const data = new Map();
  const published = [];
  const store = { getSync: (key, value) => data.has(key) ? data.get(key) : value,
    putSync: (key, value) => data.set(key, value), flush: async () => {} };
  const widget = load('WidgetStore.ets', {
    '@kit.ArkData': { preferences: { removePreferencesFromCacheSync: () => {}, getPreferencesSync: () => store } },
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      getPublishedRunningFormInfos: async () => [{ formId: 'small' }, { formId: 'wide' }],
      updateForm: async (id, value) => { published.push({ id, value }); }
    }}
  });
  assert.equal(widget.readWidget({}).batteryText, '—');
  data.set('snapshot', '{corrupt');
  assert.equal(widget.readWidget({}).modeText, '未读取');
  data.set('dimension_wide', 3);
  const readingTime = Date.now() - 86400000;
  await widget.publishWidget({}, { connected: true, model: 'WH-1000XM6', battery: 75, charging: true, mode: 2, updated: readingTime });
  assert.equal(published.length, 2);
  assert.equal(published[1].value.dimension, 3);
  const restored = widget.readWidget({});
  assert.equal(restored.batteryText, '75%');
  assert.equal(restored.modeText, '环境声');
  assert.match(restored.updateText, /^上次读取 /, 'Cached data must never claim a live connection');
  assert.equal(restored.connectionText, '最近已连接');
  await widget.publishWidget({}, new widget.WidgetSnapshot());
  const disconnected = widget.readWidget({});
  assert.equal(disconnected.connectionText, '连接已断开');
  assert.equal(disconnected.connected, false);
  assert.equal(disconnected.batteryText, '—');
  assert.equal(disconnected.modeText, '未读取');
  assert.equal(disconnected.battery, 0);
  assert.equal(disconnected.charging, false);
  assert.equal(disconnected.updateText, '点击重新连接');
  assert.equal(disconnected.model, 'WH-1000XM6');
  assert.equal(JSON.parse(data.get('snapshot')).updated, readingTime, 'Disconnect must preserve reading time');

  // Deterministic clock: many MDR replies coalesce, stable readings throttle,
  // and disconnect wins over an in-flight publication without parallel writes.
  let now = 100000, nextTimer = 0, releaseWrite;
  const timers = new Map(), intervals = new Map(), writes = [];
  const core = load('../protocol/MdrCore.ts', {});
  const names = load('../protocol/DeviceNames.ts', {});
  const service = load('Headphones.ets', {
    '@kit.AbilityKit': {}, '@kit.ConnectivityKit': {}, '@kit.BasicServicesKit': {},
    '../protocol/MdrCore': core, '../protocol/DeviceNames': names,
    './BackgroundSession': { BackgroundSession: class { stop() {} } },
    './WidgetStore': { WidgetSnapshot: widget.WidgetSnapshot, publishWidget: async (_, value) => {
      writes.push(value);
      if (writes.length === 1) { await new Promise(resolve => { releaseWrite = resolve; }); }
    }}
  }, {
    Date: class extends Date { static now() { return now; } },
    setTimeout: fn => { const id = ++nextTimer; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id),
    setInterval: (fn, delay) => { const id = ++nextTimer; intervals.set(id, delay); return id; },
    clearInterval: id => intervals.delete(id)
  });
  const controller = new service.HeadphoneController();
  controller.context = {};
  controller.state.connected = true;
  controller.state.battery = 75;
  for (let i = 0; i < 10; i++) { controller.updateWidget(); }
  assert.equal(timers.size, 1);
  const fire = () => { const fns = [...timers.values()]; timers.clear(); fns.forEach(fn => fn()); };
  fire();
  assert.equal(writes.length, 1);
  controller.state.battery = 74;
  controller.updateWidget();
  controller.disconnect();
  assert.equal(timers.size, 0, 'Disconnect cancels pending connected display');
  assert.equal(writes.length, 1, 'Only one update may run at a time');
  releaseWrite();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(writes.length, 2);
  assert.equal(writes[1].connected, false, 'Disconnect is published after in-flight reading');
  controller.state.connected = true;
  controller.updateWidget(true);
  await new Promise(resolve => setImmediate(resolve));
  controller.updateWidget();
  assert.equal(timers.size, 0, 'Stable readings do not continually rewrite cards');
  now += 60000;
  controller.updateWidget();
  assert.equal(timers.size, 1, 'Stable readings publish a timestamp heartbeat after a minute');
  fire();
  await new Promise(resolve => setImmediate(resolve));
  controller.state.battery = 73;
  controller.updateWidget();
  assert.equal(timers.size, 1, 'Changed battery bypasses the stable-data throttle');
  controller.startPolling();
  assert.deepEqual([...intervals.values()], [15000]);
  controller.state.backgroundActive = true;
  controller.onBackground();
  assert.deepEqual([...intervals.values()], [60000]);
  controller.refreshStatus = async () => {};
  controller.onForeground();
  assert.deepEqual([...intervals.values()], [15000]);
  controller.disconnect();
  assert.equal(intervals.size, 0);
  console.log('PASS: background lifecycle, cache recovery, disconnect history, coalescing, throttle, in-flight disconnect, foreground/background polling');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
