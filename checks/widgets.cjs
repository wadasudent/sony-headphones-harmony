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
  const core = load('../protocol/MdrCore.ts', {});
  const store = { getSync: (key, value) => data.has(key) ? data.get(key) : value,
    putSync: (key, value) => data.set(key, value), flush: async () => {} };
  const widget = load('WidgetStore.ets', {
    '../protocol/MdrCore': core,
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
  assert.equal(restored.batteryParts.length, 0, 'Old single-battery snapshots retain their layout');
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

  // Recorded Table 1 frames 000015, 000022, 000131 and 000135 from the upstream WF-1000XM5 6.1.0 fixture.
  const decoder = new core.FrameDecoder();
  function replay(hex) {
    const frames = decoder.feed(Buffer.from(hex, 'hex'));
    assert.equal(frames.length, 1);
    assert.equal(controller.protocol.consume(frames[0]), true);
    controller.adopt(controller.protocol.snapshot);
  }
  controller.state.connected = true;
  replay('3e0c000000000d05010a57462d31303030584d358e3c');
  replay('3e0c000000005f07002e10ff12ff13ff14ff15ff16ff17ff23ff253611ff27ff29ff2aff92ff50116b08700190ffa112c1ffc2ffe21bf138fc0d93fff633f941d13b94ff402e423a44ffff2d19fff326e71ad220fd2bb61db042b243b81fb715343ff423f524293c');
  const batteryQueries = protocol => Array.from(protocol.statusRequests(), q => Array.from(q)).filter(q => q[0] === 0x22);
  assert.deepEqual(batteryQueries(controller.protocol), [[0x22, 9], [0x22, 10]]);
  replay('3e0c000000000823090000640064646c3c');
  replay('3e0c0100000005230a35001e923c');
  controller.updateWidget(true);
  await new Promise(resolve => setImmediate(resolve));
  const parts = snapshot => Array.from(snapshot.batteryParts, p => [p.label, p.level, p.charging]);
  const recorded = [['左耳', 0, false], ['右耳', 100, false], ['充电盒', 53, false]];
  assert.deepEqual(parts(controller.state), recorded);
  assert.equal(controller.state.battery, -1, 'No made-up combined percentage');
  await widget.publishWidget({}, writes.at(-1));
  for (const { value } of published.slice(-2)) {
    assert.equal(value.model, 'WF-1000XM5');
    assert.deepEqual(parts(value), recorded);
  }

  // Synthetic variants cover partial availability, independent notifications and formats not in the capture.
  const consume = (protocol, bytes) => protocol.consume(new core.MdrFrame(core.TABLE1, 0, Uint8Array.from(bytes)));
  const notify = bytes => { assert.equal(consume(controller.protocol, bytes), true); controller.adopt(controller.protocol.snapshot); };
  notify([0x25, 9, 255, 255, 71, 1, 30, 30]);
  notify([0x25, 10, 255, 2, 30]);
  assert.equal(timers.size, 1, 'Several part changes share one widget refresh');
  fire();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(parts(writes.at(-1)), [['左耳', -1, false], ['右耳', 71, true], ['充电盒', -1, false]]);
  await widget.publishWidget({}, writes.at(-1));
  assert.deepEqual(parts(widget.readWidget({})), parts(writes.at(-1)));
  const count = writes.length;
  notify([0x25, 9, 255, 255, 71, 1, 30, 30]);
  assert.equal(timers.size, 0, 'Unchanged multipart readings respect the throttle');
  notify([0x25, 10, 55, 0, 30]);
  notify([0x25, 10, 255, 2, 30]);
  fire();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(writes.length, count, 'A transient change returning to the published value cannot leave a stale card');
  assert.equal(consume(controller.protocol, [0x25, 9, 99, 0]), false);
  assert.equal(consume(controller.protocol, [0x25, 2, 55, 0]), false, 'Unadvertised basic case format');
  controller.disconnect();
  await new Promise(resolve => setImmediate(resolve));
  await widget.publishWidget({}, writes.at(-1));
  assert.deepEqual(parts(controller.state), []);
  for (const { value } of published.slice(-2)) {
    assert.equal(value.connected, false);
    assert.deepEqual(parts(value), []);
    assert.equal(value.batteryText, '—');
  }

  const basic = new core.Xm6Protocol();
  basic.snapshot.functions = [0x20, 0x21, 0x22, 0x29, 0x2a];
  assert.deepEqual(batteryQueries(basic), [[0x22, 1], [0x22, 2]], 'One supported query per source');
  assert.equal(consume(basic, [0x25, 2, 0, 1]), true);
  assert.equal(consume(basic, [0x23, 1, 20, 0, 60, 0]), true);
  assert.deepEqual(Array.from(basic.batteryParts(), p => p.level), [20, 60, 0]);
  assert.equal(consume(basic, [0x25, 1, 50, 1, 255, 255]), true);
  assert.deepEqual(Array.from(basic.batteryParts(), p => p.level), [50, -1, 0]);
  basic.snapshot.functions = [0x21];
  assert.equal(basic.batteryParts().length, 2, 'Case-less headsets do not gain a case reading');
  basic.snapshot.functions = [0x22];
  assert.deepEqual(batteryQueries(basic), [[0x22, 2]]);
  assert.equal(basic.batteryParts().length, 1);

  // An acknowledged query may omit a case report, while the next query keeps the correct sequence.
  const linkTimers = new Map(), failures = [], outbound = [];
  const linkClock = {
    later: (delay, fn) => { const id = ++nextTimer; linkTimers.set(id, { delay, fn }); return id; },
    cancel: id => linkTimers.delete(id)
  };
  const tickLink = () => {
    assert.equal(linkTimers.size, 1);
    const [id, timer] = [...linkTimers][0];
    linkTimers.delete(id); timer.fn();
    return timer.delay;
  };
  const linkProtocol = new core.Xm6Protocol();
  linkProtocol.snapshot.functions = [0x29, 0x2a, 0x12];
  const link = new core.MdrLink({ write: async bytes => { outbound.push(bytes); } }, linkClock,
    f => linkProtocol.consume(f), message => failures.push(message));
  const receive = (sequence, payload, type = core.TABLE1) =>
    link.receive(core.encodeFrame(type, sequence, Uint8Array.from(payload)));
  const missingCase = link.request([0x22, 10], 0x23, 10, true);
  const nextCodec = link.request([0x12, 2], 0x13, 2);
  receive(1, [], 1);
  assert.equal(tickLink(), 4000);
  assert.equal((await missingCase).type, 1);
  assert.equal(failures.length, 0);
  receive(0, [0x25, 10, 53, 0, 30]);
  assert.equal(linkProtocol.snapshot.caseBattery.level, 53, 'Late battery updates remain usable');
  receive(1, [0x13, 2, 2]);
  receive(0, [], 1);
  assert.equal((await nextCodec).payload[2], 2);
  assert.equal(linkTimers.size, 0);
  assert.equal(new core.FrameDecoder().feed(outbound[1])[0].sequence, 1, 'ACK advances the queued query sequence');

  const notifiedBattery = link.request([0x22, 9], 0x23, 9, true);
  receive(0, [0x25, 9, 82, 0, 78, 0, 30, 30]);
  receive(1, [], 1);
  assert.equal((await notifiedBattery).payload[0], 0x25);
  assert.equal(linkTimers.size, 0, 'A matching notification can satisfy the acknowledged battery query');
  const required = assert.rejects(link.request([0x12, 2], 0x13, 2), /未返回查询结果/);
  receive(0, [], 1);
  assert.equal(tickLink(), 4000);
  await required;
  assert.equal(failures.length, 1, 'Required queries still fail on a missing reply');

  const ackFailures = [];
  const noAckLink = new core.MdrLink({ write: async () => {} }, linkClock, () => {}, message => ackFailures.push(message));
  const noAck = assert.rejects(noAckLink.request([0x22, 10], 0x23, 10, true), /应答超时/);
  tickLink(); tickLink(); tickLink();
  await noAck;
  assert.equal(ackFailures.length, 1, 'A transport failure still ends an optional battery query');

  const partial = new service.HeadphoneController();
  partial.protocol = linkProtocol;
  partial.adopt(partial.protocol.snapshot);
  partial.state.connected = true;
  const queries = [];
  await partial.readStatus({ request: async (bytes, command, type, optional) => {
    queries.push({ bytes: Array.from(bytes), optional });
    const payload = type === 9 ? [0x23, 9, 81, 0, 78, 0, 30, 30] : [0x13, 2, 2];
    const response = type === 10 ? new core.MdrFrame(1, 0, new Uint8Array()) :
      new core.MdrFrame(core.TABLE1, 0, Uint8Array.from(payload));
    if (partial.protocol.consume(response)) { partial.adopt(partial.protocol.snapshot); }
    return response;
  }});
  assert.deepEqual(parts(partial.state), [['左耳', 81, false], ['右耳', 78, false], ['充电盒', -1, false]]);
  assert.equal(partial.state.connected, true, 'An unavailable case leaves the headset connected');
  assert.deepEqual(queries.map(q => q.optional), [true, true, false]);

  controller.protocol = new core.Xm6Protocol();
  controller.protocol.snapshot.functions = [0x28];
  assert.deepEqual(batteryQueries(controller.protocol), [[0x22, 8]]);
  assert.equal(consume(controller.protocol, [0x25, 1, 90, 0, 88, 0]), false);
  assert.equal(consume(controller.protocol, [0x23, 8, 86, 1, 30]), true);
  controller.state.connected = true;
  controller.adopt(controller.protocol.snapshot);
  controller.updateWidget(true);
  await new Promise(resolve => setImmediate(resolve));
  await widget.publishWidget({}, writes.at(-1));
  assert.equal(widget.readWidget({}).batteryText, '86%');
  assert.deepEqual(parts(widget.readWidget({})), [], 'A different model never inherits earbud readings');
  console.log('PASS: WF-1000XM5 capture (L 0%, R 100%, case 53%), battery variants, compact/wide card data, cache, disconnect, throttle and lifecycle');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
