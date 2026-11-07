// MDR protocol port based on mos9527/SonyHeadphonesClient (MIT).
// Upstream attribution and license are in THIRD_PARTY_NOTICES.md.
// This file has no platform dependencies.

export const MDR_UUID: string = '956C7B26-D49A-4BA8-B03F-B17D393CB6E2';
export const TABLE1: number = 0x0c;

export class MdrFrame {
  type: number;
  sequence: number;
  payload: Uint8Array;
  constructor(type: number, sequence: number, payload: Uint8Array) {
    this.type = type;
    this.sequence = sequence;
    this.payload = payload;
  }
}

export function encodeFrame(type: number, sequence: number, payload: Uint8Array): Uint8Array {
  if ((sequence !== 0 && sequence !== 1) || payload.length > 4096) {
    throw new Error('Invalid MDR frame size or sequence');
  }
  const body: number[] = [type, sequence, 0, 0, (payload.length >>> 8) & 255, payload.length & 255];
  for (let i: number = 0; i < payload.length; i++) { body.push(payload[i]); }
  let checksum: number = 0;
  for (let i: number = 0; i < body.length; i++) { checksum = (checksum + body[i]) & 255; }
  body.push(checksum);
  const result: number[] = [0x3e];
  for (let i: number = 0; i < body.length; i++) {
    const byte: number = body[i];
    if (byte >= 0x3c && byte <= 0x3e) { result.push(0x3d, byte - 0x10); }
    else { result.push(byte); }
  }
  result.push(0x3c);
  return new Uint8Array(result);
}

export class FrameDecoder {
  private body: number[] = [];
  private started: boolean = false;
  private escaped: boolean = false;
  rejected: number = 0;

  reset(): void {
    this.body = [];
    this.started = false;
    this.escaped = false;
    this.rejected = 0;
  }

  feed(bytes: Uint8Array): MdrFrame[] {
    const frames: MdrFrame[] = [];
    for (let i: number = 0; i < bytes.length; i++) {
      const byte: number = bytes[i];
      if (byte === 0x3e) {
        if (this.started && this.body.length > 0) { this.rejected++; }
        this.started = true;
        this.body = [];
        this.escaped = false;
        continue;
      }
      if (!this.started) { continue; }
      if (byte === 0x3c) {
        const frame: MdrFrame | undefined = this.finish();
        if (frame !== undefined) { frames.push(frame); }
        else { this.rejected++; }
        this.started = false;
        this.body = [];
        this.escaped = false;
        continue;
      }
      if (this.escaped) {
        if (byte < 0x2c || byte > 0x2e) {
          this.rejected++;
          this.started = false;
          this.body = [];
          this.escaped = false;
          continue;
        }
        this.body.push(byte + 0x10);
        this.escaped = false;
      } else if (byte === 0x3d) { this.escaped = true; }
      else { this.body.push(byte); }
      if (this.body.length > 4103) {
        this.rejected++;
        this.started = false;
        this.body = [];
        this.escaped = false;
      }
    }
    return frames;
  }

  private finish(): MdrFrame | undefined {
    const b: number[] = this.body;
    if (this.escaped || b.length < 7 || (b[1] !== 0 && b[1] !== 1)) { return undefined; }
    const length: number = b[2] * 16777216 + b[3] * 65536 + b[4] * 256 + b[5];
    if (length > 4096 || b.length !== length + 7) { return undefined; }
    let checksum: number = 0;
    for (let i: number = 0; i < b.length - 1; i++) { checksum = (checksum + b[i]) & 255; }
    if (checksum !== b[b.length - 1] || (b[0] === 1 && length !== 0)) { return undefined; }
    return new MdrFrame(b[0], b[1], new Uint8Array(b.slice(6, 6 + length)));
  }
}

export interface MdrTransport {
  write(bytes: Uint8Array): Promise<void>;
}

export interface MdrClock {
  later(delayMs: number, task: () => void): number;
  cancel(timer: number): void;
}

class Request {
  payload: Uint8Array;
  replyCommand: number;
  replyType: number;
  resolve: (frame: MdrFrame) => void;
  reject: (error: Error) => void;
  acked: boolean = false;
  reply?: MdrFrame;
  attempts: number = 0;
  timer: number = -1;
  constructor(payload: Uint8Array, replyCommand: number, replyType: number,
    resolve: (frame: MdrFrame) => void, reject: (error: Error) => void) {
    this.payload = payload;
    this.replyCommand = replyCommand;
    this.replyType = replyType;
    this.resolve = resolve;
    this.reject = reject;
  }
}

// One request in flight. A reply can arrive before its ACK. ACKs and notifications
// share the transport but never consume another request's sequence number.
export class MdrLink {
  private transport: MdrTransport;
  private clock: MdrClock;
  private decoder: FrameDecoder = new FrameDecoder();
  private sequence: number = 0;
  private pending?: Request;
  private queue: Request[] = [];
  private closed: boolean = false;
  private onData: (frame: MdrFrame) => void;
  private onFailure: (message: string) => void;

  constructor(transport: MdrTransport, clock: MdrClock, onData: (frame: MdrFrame) => void,
    onFailure: (message: string) => void) {
    this.transport = transport;
    this.clock = clock;
    this.onData = onData;
    this.onFailure = onFailure;
  }

  request(payload: number[], replyCommand: number = -1, replyType: number = -1): Promise<MdrFrame> {
    return new Promise<MdrFrame>((resolve: (frame: MdrFrame) => void, reject: (error: Error) => void) => {
      if (this.closed) { reject(new Error('控制连接已关闭')); return; }
      if (this.queue.length >= 32) { reject(new Error('操作过于频繁，请稍后再试')); return; }
      this.queue.push(new Request(new Uint8Array(payload), replyCommand, replyType, resolve, reject));
      this.pump();
    });
  }

  receive(bytes: Uint8Array): void {
    if (this.closed) { return; }
    const frames: MdrFrame[] = this.decoder.feed(bytes);
    for (let i: number = 0; i < frames.length; i++) {
      const frame: MdrFrame = frames[i];
      const pending: Request | undefined = this.pending;
      if (frame.type === 1) {
        if (pending !== undefined && !pending.acked && frame.sequence === 1 - this.sequence) {
          pending.acked = true;
          this.sequence = 1 - this.sequence;
          this.clock.cancel(pending.timer);
          if (pending.replyCommand < 0) { this.complete(frame); }
          else if (pending.reply !== undefined) { this.complete(pending.reply); }
          else {
            pending.timer = this.clock.later(4000, () => { this.fail('耳机确认收到指令，但未返回查询结果，请重新连接'); });
          }
        }
        continue;
      }
      if (frame.type !== TABLE1 && frame.type !== 0x0e) { continue; }
      this.write(encodeFrame(1, 1 - frame.sequence, new Uint8Array(0)));
      if (frame.type === TABLE1) {
        this.onData(frame);
        if (pending !== undefined && pending.replyCommand >= 0 &&
          frame.payload.length > 0 && frame.payload[0] === pending.replyCommand &&
          (pending.replyType < 0 || (frame.payload.length > 1 && frame.payload[1] === pending.replyType))) {
          pending.reply = frame;
          if (pending.acked) { this.complete(frame); }
        }
      }
    }
  }

  close(message: string = '控制连接已关闭'): void {
    if (this.closed) { return; }
    this.closed = true;
    const pending: Request | undefined = this.pending;
    this.pending = undefined;
    if (pending !== undefined) {
      this.clock.cancel(pending.timer);
      pending.reject(new Error(message));
    }
    const queue: Request[] = this.queue;
    this.queue = [];
    for (let i: number = 0; i < queue.length; i++) { queue[i].reject(new Error(message)); }
    this.decoder.reset();
  }

  private pump(): void {
    if (this.closed || this.pending !== undefined || this.queue.length === 0) { return; }
    this.pending = this.queue.shift();
    this.transmit();
  }

  private transmit(): void {
    const pending: Request | undefined = this.pending;
    if (pending === undefined || this.closed) { return; }
    pending.attempts++;
    pending.timer = this.clock.later(1500, () => {
      if (this.pending !== pending || this.closed) { return; }
      if (pending.attempts < 3) { this.transmit(); }
      else { this.fail('耳机控制应答超时，请关闭其他控制应用后重新连接'); }
    });
    this.write(encodeFrame(TABLE1, this.sequence, pending.payload));
  }

  private write(bytes: Uint8Array): void {
    this.transport.write(bytes).catch((error: Error) => { this.fail(error.message); });
  }

  private complete(frame: MdrFrame): void {
    const pending: Request | undefined = this.pending;
    if (pending === undefined) { return; }
    this.clock.cancel(pending.timer);
    this.pending = undefined;
    pending.resolve(frame);
    this.pump();
  }

  private fail(message: string): void {
    if (this.closed) { return; }
    this.close(message);
    this.onFailure(message);
  }
}

export enum NoiseMode { Unknown = -1, Off = 0, Cancel = 1, Ambient = 2 }

export const EQ_FREQUENCIES: string[] = ['31 Hz', '63 Hz', '125 Hz', '250 Hz', '500 Hz',
  '1 kHz', '2 kHz', '4 kHz', '8 kHz', '16 kHz'];

export function eqPresetName(id: number): string {
  switch (id) {
    case 0: return '关闭';
    case 0x30: return '浑厚 Heavy';
    case 0x31: return '清晰 Clear';
    case 0x32: return '硬朗 Hard';
    case 0x33: return '柔和 Soft';
    case 0xa0: return '自定义';
    case 0xa1: return '用户设置 1';
    case 0xa2: return '用户设置 2';
    default: return id < 0 ? '未读取' : '预设 0x' + id.toString(16).toUpperCase();
  }
}

export class HeadphoneSnapshot {
  eqCapability: boolean = false;
  eqEnabled: boolean = false;
  eqPresets: number[] = [];
  eqPreset: number = -1;
  eqBands: number[] = [];
  model: string = '';
  firmware: string = '';
  protocol: number = 0;
  functions: number[] = [];
  battery: number = -1;
  charging: boolean = false;
  codec: number = -1;
  noiseType: number = -1;
  noiseMode: NoiseMode = NoiseMode.Unknown;
  ambientLevel: number = -1;
  focusVoice: boolean = false;
  automaticAmbient: number = 0;
  sensitivity: number = 0;
  touchType: number = -1;
  touchValue: number = -1;
  cinemaValue: number = -1;
  backgroundValue: number = -1;
  backgroundRoom: number = -1;
  voiceContentsValue: number = -1;
  leakageValue: number = -1;
  priority: number = -1;
  noisePayload: number[] = [];
}

export function codecName(value: number): string {
  switch (value) {
    case 0: return '尚未协商';
    case 1: return 'SBC';
    case 2: return 'AAC';
    case 0x10: return 'LDAC';
    case 0x20: return 'aptX';
    case 0x21: return 'aptX HD';
    case 0x30: return 'LC3';
    case -1: return '未读取';
    default: return '其他编码';
  }
}

function asciiField(payload: Uint8Array): string {
  if (payload.length < 3 || payload.length !== payload[2] + 3) { throw new Error('设备信息长度异常'); }
  let result: string = '';
  for (let i: number = 3; i < payload.length; i++) {
    if (payload[i] < 0x20 || payload[i] > 0x7e) { throw new Error('设备信息包含非预期字符'); }
    result += String.fromCharCode(payload[i]);
  }
  return result;
}

export class Xm6Protocol {
  snapshot: HeadphoneSnapshot = new HeadphoneSnapshot();
  private generalSettingNames: string[] = ['', '', '', ''];

  consume(frame: MdrFrame): boolean {
    if (frame.type !== TABLE1 || frame.payload.length < 2) { return false; }
    const p: Uint8Array = frame.payload;
    if (this.supports(0x57) && p[1] === 4) {
      if (p[0] === 0x51) {
        // XM6 PRESET_EQ_AND_ERRORCODE: band, step, count, [preset, nameLength, name...].
        if (p.length < 5 || p[2] !== 10 || p[3] < 12 || p[3] > 13) { return false; }
        const presets: number[] = [];
        let offset: number = 5;
        for (let i: number = 0; i < p[4]; i++) {
          if (offset + 2 > p.length) { return false; }
          const id: number = p[offset];
          const length: number = p[offset + 1];
          offset += 2 + length;
          if (offset > p.length || presets.indexOf(id) >= 0) { return false; }
          presets.push(id);
        }
        if (offset !== p.length) { return false; }
        this.snapshot.eqCapability = true;
        this.snapshot.eqPresets = presets;
        return true;
      }
      if (p[0] === 0x53 || p[0] === 0x55) {
        if (p.length < 4 || p[2] > 1 || p.length !== 4 + p[3]) { return false; }
        // A nonempty error list disables writes even when the status byte says enabled.
        this.snapshot.eqEnabled = p[2] === 0 && p[3] === 0;
        return true;
      }
      if (p[0] === 0x57 || p[0] === 0x59) {
        if (p.length < 4 || (p[3] !== 0 && p[3] !== 10) || p.length !== 4 + p[3]) { return false; }
        const bands: number[] = [];
        for (let i: number = 4; i < p.length; i++) {
          if (p[i] > 12) { return false; }
          bands.push(p[i]);
        }
        this.snapshot.eqPreset = p[2];
        this.snapshot.eqBands = bands;
        return true;
      }
    }
    if (p[0] === 0x01 && p[1] === 0 && p.length === 8) {
      if (p[6] !== 0) { throw new Error('耳机未提供 MDR Table 1'); }
      this.snapshot.protocol = p[2] * 16777216 + p[3] * 65536 + p[4] * 256 + p[5];
      return true;
    }
    if (p[0] === 0x05 && (p[1] === 1 || p[1] === 2)) {
      const text: string = asciiField(p);
      if (p[1] === 1) { this.snapshot.model = text; }
      else { this.snapshot.firmware = text; }
      return true;
    }
    if (p[0] === 0x07 && p[1] === 0) {
      if (p.length < 3 || p.length !== 3 + p[2] * 2) { throw new Error('功能表长度异常'); }
      const functions: number[] = [];
      for (let i: number = 0; i < p[2]; i++) { functions.push(p[3 + i * 2]); }
      this.snapshot.functions = functions;
      this.snapshot.noiseType = functions.indexOf(0x6d) >= 0 ? 0x19 :
        (functions.indexOf(0x6b) >= 0 ? 0x17 : -1);
      return true;
    }
    if ((p[0] === 0x13 || p[0] === 0x15) && p[1] === 2 && p.length === 3) {
      this.snapshot.codec = p[2];
      return true;
    }
    if ((p[0] === 0x23 || p[0] === 0x25) &&
      ((p[1] === 0 && p.length === 4) || (p[1] === 8 && p.length === 5))) {
      if (p[2] > 100 || p[3] > 3) { return false; }
      this.snapshot.battery = p[2];
      this.snapshot.charging = p[3] === 1;
      return true;
    }
    if ((p[0] === 0x67 || p[0] === 0x69) && p[1] === this.snapshot.noiseType &&
      ((p[1] === 0x19 && p.length === 9) || (p[1] === 0x17 && p.length === 7))) {
      if (p[2] > 1 || p[3] > 1 || p[4] > 1 || p[5] > 1 || p[6] > 20 ||
        (p[1] === 0x19 && (p[7] > 1 || p[8] > 2))) { return false; }
      const raw: number[] = [];
      for (let i: number = 0; i < p.length; i++) { raw.push(p[i]); }
      this.snapshot.noisePayload = raw;
      this.snapshot.noiseMode = p[3] === 0 ? NoiseMode.Off : (p[4] === 0 ? NoiseMode.Cancel : NoiseMode.Ambient);
      this.snapshot.ambientLevel = p[6];
      this.snapshot.focusVoice = p[5] === 1;
      if (p[1] === 0x19) {
        this.snapshot.automaticAmbient = p[7];
        this.snapshot.sensitivity = p[8];
      }
      return true;
    }
    if (p[0] === 0xd1 && p[1] >= 0xd1 && p[1] <= 0xd4 && this.supports(p[1])) {
      return this.consumeGeneralCapability(p);
    }
    if ((p[0] === 0xd7 || p[0] === 0xd9) && p[1] === this.snapshot.touchType &&
      p.length === 4 && p[2] === 0 && p[3] <= 1) {
      this.snapshot.touchValue = p[3];
      return true;
    }
    if ((p[0] === 0xe7 || p[0] === 0xe9) && this.supports(0xe6)) {
      if (p[1] === 4 && this.supports(0xe5) && p.length === 3 && p[2] <= 1) {
        this.snapshot.cinemaValue = p[2];
        return true;
      }
      if ((p[1] === 3 || p[1] === 9) && this.supportsBackgroundEffect() &&
        p.length === 4 && p[2] <= 1 && (p[3] <= 2 || (p[2] === 1 && p[3] === 0xff))) {
        this.snapshot.backgroundValue = p[2];
        this.snapshot.backgroundRoom = p[3] <= 2 ? p[3] : -1;
        return true;
      }
      if (p[1] === 6 && this.supports(0xe8) && p.length === 3 && p[2] <= 1) {
        this.snapshot.voiceContentsValue = p[2];
        return true;
      }
      if (p[1] === 7 && this.supports(0xe9) && p.length === 3 && p[2] <= 1) {
        this.snapshot.leakageValue = p[2];
        return true;
      }
    }
    if ((p[0] === 0xe7 || p[0] === 0xe9) && p[1] === 0 && p.length === 3 && p[2] <= 2) {
      this.snapshot.priority = p[2];
      return true;
    }
    return false;
  }

  supports(functionId: number): boolean { return this.snapshot.functions.indexOf(functionId) >= 0; }

  capabilityRequests(): number[][] {
    const requests: number[][] = [];
    if (this.supports(0x57)) { requests.push([0x50, 4, 1]); }
    for (let type: number = 0xd1; type <= 0xd4; type++) {
      // Ask for English capability identifiers; never assume a setting's slot.
      if (this.supports(type)) { requests.push([0xd0, type, 1]); }
    }
    return requests;
  }

  private consumeGeneralCapability(p: Uint8Array): boolean {
    if (p.length < 6) { return false; }
    const summaryOffset: number = 5 + p[4];
    if (summaryOffset >= p.length) { return false; }
    // Require a Boolean capability and an exact known subject identifier.
    // RAW_NAME and ENUM_NAME share this layout; translated/unknown names never match.
    let name: string = '';
    if (p[2] === 0 && p[3] <= 1) {
      if (summaryOffset + 1 + p[summaryOffset] !== p.length) { return false; }
      for (let i: number = 5; i < summaryOffset; i++) {
        if (p[i] < 0x20 || p[i] > 0x7e) { return false; }
        name += String.fromCharCode(p[i]);
      }
    }
    this.generalSettingNames[p[1] - 0xd1] = name;
    let touchType: number = -1;
    let matches: number = 0;
    for (let i: number = 0; i < this.generalSettingNames.length; i++) {
      if (this.generalSettingNames[i] === 'TOUCH_PANEL_SETTING') { touchType = 0xd1 + i; matches++; }
    }
    if (matches !== 1) { touchType = -1; }
    if (touchType !== this.snapshot.touchType) { this.snapshot.touchValue = -1; }
    this.snapshot.touchType = touchType;
    return true;
  }

  statusRequests(): number[][] {
    const requests: number[][] = [];
    if (this.supports(0x57) && this.snapshot.eqCapability) {
      requests.push([0x52, 4], [0x56, 4]);
    }
    if (this.supports(0x20)) { requests.push([0x22, 0]); }
    else if (this.supports(0x28)) { requests.push([0x22, 8]); }
    if (this.supports(0x12)) { requests.push([0x12, 2]); }
    if (this.snapshot.noiseType >= 0) { requests.push([0x66, this.snapshot.noiseType]); }
    // E1 is verified in upstream's query/set implementation. Do not guess E3/E7 layouts.
    if (this.supports(0xe1)) { requests.push([0xe6, 0]); }
    if (this.snapshot.touchType >= 0) { requests.push([0xd6, this.snapshot.touchType]); }
    return requests.concat(this.listeningStatusRequests());
  }

  private supportsBackgroundEffect(): boolean {
    return this.supports(0xe4) || this.supports(0xeb) || this.supports(0x45);
  }

  listeningStatusRequests(): number[][] {
    const requests: number[][] = [];
    if (!this.supports(0xe6) || !this.supports(0xe5)) { return requests; }
    requests.push([0xe6, 4]);
    // The upstream grouped-listening implementation queries BGM with type 9.
    if (this.supportsBackgroundEffect()) { requests.push([0xe6, 9]); }
    if (this.supports(0xe8)) { requests.push([0xe6, 6]); }
    if (this.supports(0xe9)) { requests.push([0xe6, 7]); }
    return requests;
  }

  listeningValue(type: number): number {
    if (type === 4) { return this.snapshot.cinemaValue; }
    if (type === 9) { return this.snapshot.backgroundValue; }
    if (type === 6) { return this.snapshot.voiceContentsValue; }
    if (type === 7) { return this.snapshot.leakageValue; }
    return -1;
  }

  cinemaPreparationCommands(): number[][] {
    const commands: number[][] = [];
    const requests: number[][] = this.listeningStatusRequests();
    if (requests.length === 0 || this.snapshot.cinemaValue < 0) { throw new Error('请先读取空间音效能力与状态'); }
    for (let i: number = 1; i < requests.length; i++) {
      const type: number = requests[i][1];
      const value: number = this.listeningValue(type);
      if (value < 0) { throw new Error('其他聆听音效状态未知，暂不能启用 Cinema'); }
      if (value === 0) {
        const command: number[] = [0xe8, type, 1];
        if (type === 9) {
          if (this.snapshot.backgroundRoom < 0) { throw new Error('背景音乐参数未读取'); }
          command.push(this.snapshot.backgroundRoom);
        }
        commands.push(command);
      }
    }
    return commands;
  }

  cinemaCommand(enabled: boolean): number[] {
    if (!this.supports(0xe6) || !this.supports(0xe5) || this.snapshot.cinemaValue < 0) {
      throw new Error('当前耳机未提供已读取的 Cinema 上混设置');
    }
    if (enabled && this.cinemaPreparationCommands().length > 0) { throw new Error('请先关闭其他互斥聆听音效'); }
    return [0xe8, 4, enabled ? 0 : 1];
  }

  noiseCommand(mode: NoiseMode, level: number, voice: boolean): number[] {
    const current: number[] = this.snapshot.noisePayload;
    if (current.length < 7 || this.snapshot.noiseType < 0) { throw new Error('请先读取耳机的降噪状态'); }
    if (mode !== NoiseMode.Off && mode !== NoiseMode.Cancel && mode !== NoiseMode.Ambient) {
      throw new Error('无效的降噪模式');
    }
    if (!Number.isInteger(level) || level < 0 || level > 20) { throw new Error('环境声等级应为 0–20'); }
    const command: number[] = current.slice();
    command[0] = 0x68;
    command[2] = 1;
    command[3] = mode === NoiseMode.Off ? 0 : 1;
    command[4] = mode === NoiseMode.Ambient ? 1 : 0;
    command[5] = voice ? 1 : 0;
    command[6] = level;
    // Preserve auto ambient and sensitivity fields read from the device.
    return command;
  }

  equalizerCommand(preset: number, bands: number[] = []): number[] {
    if (!this.snapshot.eqCapability || !this.snapshot.eqEnabled || this.snapshot.eqPreset < 0) {
      throw new Error('请先读取可用的 XM6 均衡器状态');
    }
    if (this.snapshot.eqPresets.indexOf(preset) < 0) { throw new Error('耳机未公布此均衡器预设'); }
    if (bands.length > 0 && (preset !== 0xa0 || bands.length !== 10 ||
      bands.some((value: number) => !Number.isInteger(value) || value < 0 || value > 12))) {
      throw new Error('自定义均衡器需要完整的 10 段设置，每段为 0–12');
    }
    return [0x58, 4, preset, bands.length].concat(bands);
  }

  priorityCommand(qualityFirst: boolean): number[] {
    if (!this.supports(0xe1) || this.snapshot.priority < 0) { throw new Error('当前耳机未提供已验证的音质模式接口'); }
    return [0xe8, 0, qualityFirst ? 0 : 1];
  }

  automaticAmbientCommand(enabled: boolean, sensitivity: number): number[] {
    if (!this.supports(0x6d) || this.snapshot.noiseType !== 0x19 || this.snapshot.noisePayload.length !== 9) {
      throw new Error('当前耳机未提供已验证的自动环境声接口');
    }
    if (this.snapshot.noiseMode !== NoiseMode.Ambient) { throw new Error('请先切换到环境声模式'); }
    // Raw enum: standard=0, high=1, low=2 (not the C API's public enum).
    if (!Number.isInteger(sensitivity) || sensitivity < 0 || sensitivity > 2) { throw new Error('无效的检测灵敏度'); }
    const command: number[] = this.noiseCommand(this.snapshot.noiseMode, this.snapshot.ambientLevel, this.snapshot.focusVoice);
    command[7] = enabled ? 1 : 0;
    command[8] = sensitivity;
    return command;
  }

  touchCommand(enabled: boolean): number[] {
    if (this.snapshot.touchType < 0 || !this.supports(this.snapshot.touchType) || this.snapshot.touchValue < 0) {
      throw new Error('请先读取耳机的触摸面板能力和状态');
    }
    // General settings use ON=0/OFF=1, unlike NC/ASM's ON=1/OFF=0.
    return [0xd8, this.snapshot.touchType, 0, enabled ? 0 : 1];
  }

  powerOffCommand(): number[] {
    if (!this.supports(0x23)) { throw new Error('当前耳机未提供关机功能'); }
    return [0x24, 3, 1];
  }
}
