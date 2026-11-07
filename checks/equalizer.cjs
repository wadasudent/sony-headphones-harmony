const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || 'D:/HuaweiDevTools/DevEcoStudio26/sdk',
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, kits = {}) {
  const exports = {};
  const js = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(js, { exports, require: name => {
    assert.ok(name in kits, 'Unexpected dependency: ' + name); return kits[name];
  }, Date, Math, JSON, Uint8Array, setTimeout, clearTimeout, setInterval, clearInterval,
    ObservedV2: value => value, Trace: () => {} });
  return exports;
}
const core = load('protocol/MdrCore.ts');
const deviceNames = load('protocol/DeviceNames.ts');
const frame = bytes => new core.MdrFrame(core.TABLE1, 0, new Uint8Array(bytes));
function ready() {
  const p = new core.Xm6Protocol();
  p.snapshot.functions = [0x57];
  assert.equal(p.consume(frame([0x51, 4, 10, 13, 3, 0, 0, 0x30, 0, 0xa0, 0])), true);
  assert.equal(p.consume(frame([0x53, 4, 0, 0])), true);
  // Sound Connect capture documented in sony-device-center PR #44, offset 22375.
  assert.equal(p.consume(frame([0x57, 4, 0xa0, 10, 7, 7, 7, 7, 6, 6, 7, 8, 8, 8])), true);
  return p;
}
async function main() {
  for (const name of ['WH-1000XM6', 'WH-1000XM5', 'WF-1000XM5', 'WI-C100', 'MDR-1ABT', 'LinkBuds S', 'ULT WEAR', 'Sony WH-CH720N']) {
    assert.equal(deviceNames.isSonyHeadphoneName(name), true, name);
  }
  for (const name of ['HUAWEI FreeBuds', 'AirPods Pro', 'SRS-XB100', 'SONY TV', 'ULT FIELD 1', 'WHATEVER', '', 'LE_WH-1000XM6']) {
    assert.equal(deviceNames.isSonyHeadphoneName(name), false, name);
  }
  const p = ready();
  assert.equal(JSON.stringify(p.snapshot.eqBands), '[7,7,7,7,6,6,7,8,8,8]');
  const curve = [7,7,7,7,6,6,3,7,3,8];
  assert.equal(JSON.stringify(p.equalizerCommand(0xa0, curve)), '[88,4,160,10,7,7,7,7,6,6,3,7,3,8]');
  assert.equal(JSON.stringify(p.equalizerCommand(0x30)), '[88,4,48,0]');
  for (const bad of [curve.slice(1), [...curve.slice(0,9), 13], [...curve.slice(0,9), 1.5]]) {
    assert.throws(() => p.equalizerCommand(0xa0, bad));
  }
  assert.throws(() => p.equalizerCommand(0x16)); // Legacy preset not advertised.
  assert.throws(() => new core.Xm6Protocol().equalizerCommand(0xa0, curve));
  const before = JSON.stringify(p.snapshot.eqBands);
  for (const bytes of [[0x57,0,0xa0,10,...curve], [0x57,4,0xa0,10,1], [0x59,4,0xa0,10,...curve.slice(0,9),255]]) {
    assert.equal(p.consume(frame(bytes)), false);
    assert.equal(JSON.stringify(p.snapshot.eqBands), before);
  }
  p.consume(frame([0x55,4,0,1,1]));
  assert.throws(() => p.equalizerCommand(0xa0, curve), /状态/);
  p.consume(frame([0x53,4,0,0]));
  const service = load('services/Headphones.ets', {
    '@kit.AbilityKit': {}, '@kit.ConnectivityKit': {}, '@kit.BasicServicesKit': {},
    './BackgroundSession': { BackgroundSession: class {} }, './WidgetStore': {}, '../protocol/MdrCore': core,
    '../protocol/DeviceNames': deviceNames
  });
  const controller = new service.HeadphoneController();
  controller.protocol = ready();
  controller.adopt(controller.protocol.snapshot);
  controller.state.connected = true;
  let commands = [], wrongReadback = true, conflict = false;
  controller.link = { request: async command => {
    commands.push(command);
    if (command[0] === 0x52) return frame([0x53,4,0,0]);
    if (command[0] === 0x58) return frame([]); // ACK alone must never confirm the write.
    const result = frame([0x57,4, conflict ? 0x30 : (wrongReadback ? 0xa0 : 0x30),10,...curve]);
    controller.protocol.consume(result);
    controller.adopt(controller.protocol.snapshot);
    return result;
  }};
  await controller.setEqualizer(0x30);
  assert.match(controller.state.error, /未确认/);
  wrongReadback = false;
  await controller.setEqualizer(0x30);
  assert.equal(controller.state.error, '');
  assert.equal(controller.state.busy, false);
  commands = []; conflict = true;
  await controller.setEqualizer(0xa0, curve, curve, 0xa0);
  assert.match(controller.state.error, /其他位置/);
  assert.equal(commands.some(c => c[0] === 0x58), false);
  // NC/ASM mode switching preserves the full XM6 auto-ambient state.
  const noise = new core.Xm6Protocol(); noise.snapshot.noiseType = 0x19;
  noise.consume(frame([0x67,0x19,1,1,1,0,5,1,2]));
  const command = noise.noiseCommand(core.NoiseMode.Cancel,5,false);
  assert.equal(command[4], 0);
  assert.equal(command[7], 1); assert.equal(command[8], 2);
  console.log('PASS: XM6 capture, strict band validation, status/error gating, readback mismatch, external-edit conflict, NC/ASM fields');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
