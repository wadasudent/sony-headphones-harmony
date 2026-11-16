import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { access, a2dp, connection, socket } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackgroundSession } from './BackgroundSession';
import { isSonyHeadphoneName } from '../protocol/DeviceNames';
import { WidgetSnapshot, publishWidget, widgetPreferences } from './WidgetStore';
import {
  MDR_UUID, MdrClock, MdrFrame, MdrLink, MdrTransport, HeadphoneSnapshot, BatteryPart,
  Xm6Protocol, NoiseMode, codecName
} from '../protocol/MdrCore';

export class PairedHeadphone {
  address: string;
  name: string;
  constructor(address: string, name: string) { this.address = address; this.name = name; }
}

@ObservedV2
export class HeadphoneState {
  @Trace devices: PairedHeadphone[] = [];
  @Trace discovering: boolean = false;
  @Trace connected: boolean = false;
  @Trace connecting: boolean = false;
  @Trace busy: boolean = false;
  @Trace message: string = '请先在系统蓝牙设置中配对索尼耳机';
  @Trace error: string = '';
  @Trace notice: string = '';
  @Trace model: string = '索尼耳机';
  @Trace firmware: string = '';
  @Trace battery: number = -1;
  @Trace charging: boolean = false;
  @Trace batteryParts: BatteryPart[] = [];
  @Trace codec: string = '未读取';
  @Trace noiseMode: NoiseMode = NoiseMode.Unknown;
  @Trace ambientLevel: number = -1;
  @Trace focusVoice: boolean = false;
  @Trace automaticAmbient: boolean = false;
  @Trace ambientSensitivity: number = 0;
  @Trace automaticAmbientAvailable: boolean = false;
  @Trace touchEnabled: boolean = false;
  @Trace touchAvailable: boolean = false;
  @Trace powerOffAvailable: boolean = false;
  @Trace cinemaEnabled: boolean = false;
  @Trace cinemaAvailable: boolean = false;
  @Trace poweringOff: boolean = false;
  @Trace priority: number = -1;
  @Trace noiseAvailable: boolean = false;
  @Trace priorityAvailable: boolean = false;
  @Trace logs: string[] = [];
  @Trace backgroundActive: boolean = false;
  @Trace eqAvailable: boolean = false;
  @Trace eqPreset: number = -1;
  @Trace eqPresets: number[] = [];
  @Trace eqBands: number[] = [];
  @Trace autoReconnect: boolean = false;
}

class NativeClock implements MdrClock {
  later(delayMs: number, task: () => void): number { return setTimeout(task, delayMs); }
  cancel(timer: number): void { if (timer >= 0) { clearTimeout(timer); } }
}

function describe(error: BusinessError): string {
  if (error.code === 201) { return '蓝牙权限未授予，请在系统设置中允许附近设备访问'; }
  if (error.code === 2900003) { return '蓝牙已关闭，请先打开系统蓝牙'; }
  if (error.code === 2900004) { return '当前设备或系统不支持此蓝牙控制连接'; }
  return `${error.message || '蓝牙操作失败'}${error.code ? '（' + error.code + '）' : ''}`;
}

// Writes are serialized because protocol ACKs may arrive while a request is being written.
class NativeTransport implements MdrTransport {
  private socketId: number = -1;
  private generation: number = 0;
  private writes: Promise<void> = Promise.resolve();
  private connecting: boolean = false;
  private cancelConnect?: () => void;
  private onReceive: (bytes: Uint8Array) => void;
  private onFailure: (message: string) => void;

  constructor(onReceive: (bytes: Uint8Array) => void, onFailure: (message: string) => void) {
    this.onReceive = onReceive;
    this.onFailure = onFailure;
  }

  open(address: string): Promise<void> {
    if (this.connecting || this.socketId >= 0) { return Promise.reject(new Error('已有控制连接')); }
    this.connecting = true;
    const generation: number = ++this.generation;
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (settled) { return; }
        settled = true;
        this.cancelConnect = undefined;
        this.connecting = false;
        ++this.generation;
        reject(new Error('连接超时。请确认耳机已开机，并退出其他耳机控制应用'));
      }, 20000);
      this.cancelConnect = () => {
        if (settled) { return; }
        settled = true;
        clearTimeout(timer);
        reject(new Error('已取消连接'));
      };
      try {
        const options: socket.SppOptions = { uuid: MDR_UUID, secure: true, type: socket.SppType.SPP_RFCOMM };
        socket.sppConnect(address, options, (error: BusinessError, id: number) => {
          if (generation !== this.generation || settled) {
            if (!error && id >= 0) { this.closeId(id); }
            return;
          }
          settled = true;
          clearTimeout(timer);
          this.cancelConnect = undefined;
          this.connecting = false;
          if (error) { reject(new Error(describe(error))); return; }
          this.socketId = id;
          this.readLoop(id, generation);
          resolve();
        });
      } catch (error) {
        settled = true;
        clearTimeout(timer);
        this.cancelConnect = undefined;
        this.connecting = false;
        reject(new Error(describe(error as BusinessError)));
      }
    });
  }

  write(bytes: Uint8Array): Promise<void> {
    const generation: number = this.generation;
    const id: number = this.socketId;
    const buffer: ArrayBuffer = new ArrayBuffer(bytes.length);
    new Uint8Array(buffer).set(bytes);
    const operation: Promise<void> = this.writes.then(async () => {
      if (id < 0 || id !== this.socketId || generation !== this.generation) { throw new Error('控制连接已断开'); }
      await socket.sppWriteAsync(id, buffer);
    });
    this.writes = operation.catch(() => {});
    return operation;
  }

  close(): void {
    ++this.generation;
    const cancel: (() => void) | undefined = this.cancelConnect;
    this.cancelConnect = undefined;
    if (cancel !== undefined) { cancel(); }
    this.connecting = false;
    const id: number = this.socketId;
    this.socketId = -1;
    this.writes = Promise.resolve();
    if (id >= 0) { this.closeId(id); }
  }

  private closeId(id: number): void {
    try { socket.sppCloseClientSocket(id); } catch (_) { /* Already closed by the stack. */ }
  }

  private async readLoop(id: number, generation: number): Promise<void> {
    try {
      while (generation === this.generation && id === this.socketId) {
        const buffer: ArrayBuffer = await socket.sppReadAsync(id);
        if (generation !== this.generation) { return; }
        if (buffer.byteLength === 0) { throw new Error('耳机已断开控制连接'); }
        this.onReceive(new Uint8Array(buffer));
      }
    } catch (error) {
      if (generation === this.generation) {
        this.close();
        this.onFailure(describe(error as BusinessError));
      }
    }
  }
}

export class HeadphoneController {
  state: HeadphoneState = new HeadphoneState();
  private protocol: Xm6Protocol = new Xm6Protocol();
  private link?: MdrLink;
  private transport?: NativeTransport;
  private generation: number = 0;
  private polling: number = -1;
  private context?: common.UIAbilityContext;
  private background: BackgroundSession = new BackgroundSession();
  private widgetWriting: boolean = false;
  private widgetPending?: WidgetSnapshot;
  private widgetTimer: number = -1;
  private widgetSignature: string = '';
  private widgetPublishedAt: number = 0;
  private widgetActionRunning: boolean = false;
  private foreground: boolean = true;
  private reconnectTimer: number = -1;
  private reconnectAttempts: number = 0;
  private reconnectPaused: boolean = false;
  private reconnectAfter: number = 0;
  private audioProfile?: a2dp.A2dpSourceProfile;
  private audioChanged: () => void = () => { this.scheduleReconnect(); };

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    try { this.state.autoReconnect = widgetPreferences(context).getSync('autoReconnect', false) === true; }
    catch (_) { this.state.autoReconnect = false; }
    this.background.initialize(context, () => {
      this.state.backgroundActive = false;
      if (!this.foreground) { this.disconnect(); }
      this.state.notice = '后台同步已停止，返回应用可重新连接。';
    });
  }

  onForeground(): void {
    this.foreground = true;
    if (this.state.connected) { this.restartPolling(); this.refreshStatus(); }
    this.watchAudio();
    this.scheduleReconnect();
  }

  destroy(): void { this.stopWatchingAudio(); this.disconnect(); this.background.destroy(); }

  onBackground(): void {
    this.foreground = false;
    this.cancelReconnect();
    this.stopWatchingAudio();
    if (!this.state.backgroundActive || this.state.connecting) { this.disconnect(false); }
    else if (this.state.connected) { this.restartPolling(); }
  }

  async setAutoReconnect(enabled: boolean): Promise<void> {
    if (this.context === undefined) { return; }
    try {
      const store = widgetPreferences(this.context);
      store.putSync('autoReconnect', enabled);
      await store.flush();
      this.state.autoReconnect = enabled;
      this.cancelReconnect();
      this.reconnectAttempts = 0;
      this.reconnectAfter = 0;
      this.reconnectPaused = false;
      if (enabled) { this.watchAudio(); this.scheduleReconnect(); }
      else { this.stopWatchingAudio(); }
    } catch (_) { this.showError('无法保存自动重连设置，请重试'); }
  }

  private watchAudio(): void {
    if (!this.foreground || !this.state.autoReconnect || this.audioProfile !== undefined) { return; }
    try {
      const profile = a2dp.createA2dpSrcProfile();
      profile.on('connectionStateChange', this.audioChanged);
      this.audioProfile = profile;
    } catch (_) { /* No permission prompt or background wakeup for auto reconnect. */ }
  }

  private stopWatchingAudio(): void {
    try { this.audioProfile?.off('connectionStateChange', this.audioChanged); } catch (_) {}
    this.audioProfile = undefined;
  }

  private cancelReconnect(): void {
    if (this.reconnectTimer >= 0) { clearTimeout(this.reconnectTimer); this.reconnectTimer = -1; }
  }

  private scheduleReconnect(): void {
    if (!this.foreground || !this.state.autoReconnect || this.reconnectPaused || this.state.connected ||
      this.state.connecting || this.state.busy || this.reconnectTimer >= 0) { return; }
    if (this.reconnectAttempts >= 3) {
      if (Date.now() < this.reconnectAfter) { return; }
      this.reconnectAttempts = 0;
    }
    const delays: number[] = [2000, 5000, 15000];
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.tryReconnect();
    }, delays[this.reconnectAttempts]);
  }

  private async tryReconnect(): Promise<void> {
    if (!this.foreground || !this.state.autoReconnect || this.reconnectPaused || this.state.connected ||
      this.state.connecting || this.state.busy || this.context === undefined) { return; }
    try {
      if (access.getState() !== access.BluetoothState.STATE_ON) { return; }
      const address = widgetPreferences(this.context).getSync('device', '') as string;
      // Only the saved, MDR-verified device already connected for system audio.
      const connected = a2dp.createA2dpSrcProfile().getConnectedDevices();
      if (!address || connected.indexOf(address) < 0 || connection.getPairedDevices().indexOf(address) < 0) { return; }
      ++this.reconnectAttempts;
      this.reconnectAfter = Date.now() + 60000;
      await this.connect(new PairedHeadphone(address, '索尼耳机'), true);
    } catch (_) { /* Permission revoked / unsupported profile: wait for user action. */ }
  }

  // Widget routing deliberately enters the foreground so permissions and connection
  // errors remain visible, and never sends a command using cached mode parameters.
  async handleWidgetAction(mode: number): Promise<void> {
    if (this.widgetActionRunning || this.state.busy || this.state.connecting || this.context === undefined) { return; }
    this.widgetActionRunning = true;
    try {
      if (!this.state.connected) {
        const store = widgetPreferences(this.context);
        const address = store.getSync('device', '') as string;
        if (!address) { this.state.notice = '请先在应用中选择并连接一次耳机，再使用桌面卡片。'; return; }
        await this.refreshDevices(this.context);
        if (this.state.error.length > 0) { return; }
        const device = this.state.devices.find((item: PairedHeadphone) => item.address === address);
        if (device === undefined) { this.state.notice = '未找到上次连接的耳机，请在应用中重新选择。'; return; }
        await this.connect(device);
      } else { await this.refreshStatus(); }
      if (this.state.connected && mode >= 0 && mode <= 2 && this.state.error.length === 0) {
        await this.setNoise(mode as NoiseMode, this.state.ambientLevel < 0 ? 10 : this.state.ambientLevel, this.state.focusVoice);
      }
    } catch (error) { this.showError((error as Error).message || '暂时无法读取卡片数据，请手动连接耳机'); }
    finally { this.widgetActionRunning = false; }
  }

  private widgetContentSignature(data: WidgetSnapshot): string {
    return JSON.stringify([data.connected, data.model, data.battery, data.charging, data.batteryParts, data.mode]);
  }

  private updateWidget(immediate: boolean = false): void {
    const context = this.context;
    if (context === undefined) { return; }
    const data = new WidgetSnapshot();
    data.connected = this.state.connected;
    if (data.connected) {
      data.battery = this.state.battery;
      data.batteryParts = this.state.batteryParts.slice();
      data.model = this.state.model;
      data.charging = this.state.charging;
      data.mode = this.state.noiseMode;
      data.updated = Date.now();
    }
    if (!immediate && !this.widgetWriting && this.widgetPending === undefined &&
      this.widgetContentSignature(data) === this.widgetSignature && Date.now() - this.widgetPublishedAt < 60000) { return; }
    this.widgetPending = data;
    if (immediate) {
      if (this.widgetTimer >= 0) { clearTimeout(this.widgetTimer); this.widgetTimer = -1; }
      this.flushWidget();
    } else if (this.widgetTimer < 0) {
      // A status round contains several MDR replies. Publish their combined result.
      this.widgetTimer = setTimeout(() => { this.widgetTimer = -1; this.flushWidget(); }, 1000);
    }
  }

  private async flushWidget(): Promise<void> {
    const context = this.context;
    if (context === undefined || this.widgetWriting) { return; }
    this.widgetWriting = true;
    try {
      while (this.widgetPending !== undefined) {
        const data = this.widgetPending;
        this.widgetPending = undefined;
        const signature = this.widgetContentSignature(data);
        if (signature === this.widgetSignature && Date.now() - this.widgetPublishedAt < 60000) { continue; }
        try {
          await publishWidget(context, data);
          this.widgetSignature = signature;
          this.widgetPublishedAt = Date.now();
        } catch (_) { this.log('桌面卡片更新失败，可点击卡片返回应用读取状态'); }
      }
    } finally { this.widgetWriting = false; }
  }

  async refreshDevices(context: common.UIAbilityContext): Promise<void> {
    if (this.state.connecting || this.state.busy || this.state.discovering) { return; }
    this.state.discovering = true;
    this.state.devices = [];
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, ['ohos.permission.ACCESS_BLUETOOTH']);
      if (result.authResults.length === 0 || result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        throw new Error('需要蓝牙权限才能查找已配对的耳机');
      }
      if (access.getState() !== access.BluetoothState.STATE_ON) { throw new Error('请先打开系统蓝牙'); }
      const devices: PairedHeadphone[] = [];
      let verifiedAddress: string = '';
      try { verifiedAddress = widgetPreferences(context).getSync('device', '') as string; }
      catch (_) { /* Default-name matching remains available if local storage fails. */ }
      const addresses: string[] = connection.getPairedDevices();
      for (let i: number = 0; i < addresses.length; i++) {
        let name: string = '';
        try { name = connection.getRemoteDeviceName(addresses[i]); } catch (_) { /* Name may not be cached. */ }
        // Paired-device names do not expose a reliable manufacturer field. Match Sony
        // branding and common model families, plus a previously verified device.
        // The saved address is written only after model validation in connect().
        if (isSonyHeadphoneName(name) || addresses[i] === verifiedAddress) {
          devices.push(new PairedHeadphone(addresses[i], name || '索尼耳机（已验证）'));
        }
      }
      this.state.devices = devices;
      this.state.error = '';
      this.state.message = devices.length > 0 ? '选择已配对的索尼耳机，功能以耳机实际支持为准' : '未找到已配对的索尼耳机，请先在系统蓝牙设置中配对';
    } catch (error) { this.showError(describe(error as BusinessError)); }
    finally { this.state.discovering = false; }
  }

  async connect(device: PairedHeadphone, automatic: boolean = false): Promise<void> {
    if (this.state.connecting || this.state.busy) { return; }
    this.disconnect(false);
    if (!automatic) { this.reconnectPaused = false; this.reconnectAttempts = 0; this.reconnectAfter = 0; }
    const generation: number = this.generation;
    this.state.connecting = true;
    this.state.error = '';
    this.state.notice = '';
    this.state.message = '正在连接耳机…';
    this.protocol = new Xm6Protocol();
    const transport: NativeTransport = new NativeTransport(
      (bytes: Uint8Array) => {
        if (generation !== this.generation) { return; }
        try { this.link?.receive(bytes); }
        catch (error) { this.failure((error as Error).message); }
      },
      (message: string) => { if (generation === this.generation) { this.failure(message); } }
    );
    const link: MdrLink = new MdrLink(transport, new NativeClock(), (frame: MdrFrame) => {
      if (generation === this.generation && this.protocol.consume(frame)) { this.adopt(this.protocol.snapshot); }
    }, (message: string) => { if (generation === this.generation) { this.failure(message); } });
    this.transport = transport;
    this.link = link;
    try {
      await transport.open(device.address);
      this.checkGeneration(generation);
      this.state.message = '正在读取耳机身份和功能…';
      await link.request([0, 0], 1, 0);
      if (this.protocol.snapshot.protocol === 0) { throw new Error('未识别的 MDR V2 握手响应'); }
      await link.request([2, 0], 3, 0);
      await link.request([4, 1], 5, 1);
      if (!isSonyHeadphoneName(this.protocol.snapshot.model)) {
        throw new Error('设备未返回可识别的索尼耳机型号，已停止连接');
      }
      await link.request([4, 2], 5, 2);
      await link.request([6, 0], 7, 0);
      const capabilities: number[][] = this.protocol.capabilityRequests();
      for (let i: number = 0; i < capabilities.length; i++) {
        const query: number[] = capabilities[i];
        await link.request(query, query[0] + 1, query[1]);
      }
      await this.readStatus(link);
      this.checkGeneration(generation);
      this.state.connected = true;
      this.state.connecting = false;
      this.state.message = '耳机已连接';
      if (this.context !== undefined) {
        try {
          const store = widgetPreferences(this.context);
          store.putSync('device', device.address);
          await store.flush();
        } catch (_) { this.log('未能保存重连设备，下次请手动选择耳机'); }
        try {
          await this.background.start();
          this.checkGeneration(generation);
          this.state.backgroundActive = true;
        } catch (_) {
          this.checkGeneration(generation);
          this.state.notice = '离开应用后系统将断开耳机控制连接，桌面卡片会显示断链。';
        }
      }
      this.checkGeneration(generation);
      this.updateWidget(true);
      if (this.state.model.toUpperCase() !== 'WH-1000XM6') {
        this.state.notice = '此型号尚未完成实机验证，已按耳机返回能力加载功能。' + this.state.notice;
      }
      this.log('连接并读取状态成功');
      this.reconnectAttempts = 0;
      this.startPolling();
    } catch (error) {
      if (generation === this.generation) { this.failure((error as Error).message); }
    }
  }

  disconnect(manual: boolean = true): void {
    this.cancelReconnect();
    if (manual) { this.reconnectPaused = true; }
    ++this.generation;
    this.background.stop();
    this.state.backgroundActive = false;
    if (this.polling >= 0) { clearInterval(this.polling); this.polling = -1; }
    this.link?.close();
    this.link = undefined;
    this.transport?.close();
    this.transport = undefined;
    this.state.connected = false;
    this.updateWidget(true);
    this.state.connecting = false;
    this.state.busy = false;
    this.state.battery = -1;
    this.state.charging = false;
    this.state.batteryParts = [];
    this.state.codec = '未读取';
    this.state.noiseMode = NoiseMode.Unknown;
    this.state.ambientLevel = -1;
    this.state.firmware = '';
    this.state.priority = -1;
    this.state.noiseAvailable = false;
    this.state.priorityAvailable = false;
    this.state.automaticAmbientAvailable = false;
    this.state.automaticAmbient = false;
    this.state.ambientSensitivity = 0;
    this.state.touchEnabled = false;
    this.state.touchAvailable = false;
    this.state.powerOffAvailable = false;
    this.state.cinemaEnabled = false;
    this.state.cinemaAvailable = false;
    this.state.poweringOff = false;
    this.state.message = '控制连接已断开';
    this.state.eqAvailable = false;
    this.state.eqPreset = -1;
    this.state.eqPresets = [];
    this.state.eqBands = [];
  }

  async refreshStatus(): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    this.state.busy = true;
    try {
      await this.readStatus(link);
      this.checkGeneration(generation);
      this.state.error = '';
      this.updateWidget();
    } catch (error) {
      if (generation === this.generation) { this.failure((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  async setNoise(mode: NoiseMode, level: number, voice: boolean): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    this.state.busy = true;
    try {
      const command: number[] = this.protocol.noiseCommand(mode, level, voice);
      await link.request(command);
      await link.request([0x66, this.protocol.snapshot.noiseType], 0x67, this.protocol.snapshot.noiseType);
      this.checkGeneration(generation);
      if (this.state.noiseMode !== mode || (mode === NoiseMode.Ambient &&
        (this.state.ambientLevel !== level || this.state.focusVoice !== voice))) {
        throw new Error('耳机返回的设置与请求不同，请确认是否受其他模式影响');
      }
      this.state.error = '';
      this.log('声音控制设置已由耳机确认');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  async setPriority(qualityFirst: boolean): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    this.state.busy = true;
    try {
      await link.request(this.protocol.priorityCommand(qualityFirst));
      await link.request([0xe6, 0], 0xe7, 0);
      if (this.protocol.supports(0x12)) { await link.request([0x12, 2], 0x13, 2); }
      this.checkGeneration(generation);
      if (this.state.priority !== (qualityFirst ? 0 : 1)) { throw new Error('耳机未确认音质模式切换'); }
      this.state.error = '';
      this.log('音质模式已由耳机确认');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  async setEqualizer(preset: number, bands: number[] = [], expectedBands: number[] = [], expectedPreset: number = -1): Promise<void> {
    const link = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation = this.generation;
    this.state.busy = true;
    try {
      const status = await link.request([0x52, 4], 0x53, 4);
      const current = await link.request([0x56, 4], 0x57, 4);
      this.checkGeneration(generation);
      if (!this.protocol.consume(status) || !this.protocol.consume(current)) { throw new Error('耳机返回了无法识别的均衡器状态'); }
      if (expectedBands.length > 0 && (expectedPreset !== this.state.eqPreset ||
        JSON.stringify(expectedBands) !== JSON.stringify(this.state.eqBands))) {
        throw new Error('耳机均衡器已在其他位置更改，请取消编辑后重新读取');
      }
      await link.request(this.protocol.equalizerCommand(preset, bands));
      const reply = await link.request([0x56, 4], 0x57, 4);
      this.checkGeneration(generation);
      if (!this.protocol.consume(reply) || this.protocol.snapshot.eqPreset !== preset ||
        (bands.length > 0 && JSON.stringify(this.protocol.snapshot.eqBands) !== JSON.stringify(bands))) {
        throw new Error('耳机未确认均衡器设置，请重新读取状态');
      }
      this.adopt(this.protocol.snapshot);
      this.state.error = '';
      this.log('均衡器设置已由耳机回读确认');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  private async readStatus(link: MdrLink): Promise<void> {
    const generation: number = this.generation;
    const requests: number[][] = this.protocol.statusRequests();
    for (let i: number = 0; i < requests.length; i++) {
      const request: number[] = requests[i];
      const partBattery: boolean = request[0] === 0x22 && request[1] !== 0 && request[1] !== 8;
      const response: MdrFrame = await link.request(request, request[0] + 1, request[1], partBattery);
      this.checkGeneration(generation);
      if (partBattery && !this.protocol.consume(response)) {
        this.protocol.clearBattery(request[1]);
        this.adopt(this.protocol.snapshot);
      }
    }
  }

  async setAutomaticAmbient(enabled: boolean, sensitivity: number): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    this.state.busy = true;
    try {
      await link.request(this.protocol.automaticAmbientCommand(enabled, sensitivity));
      await link.request([0x66, 0x19], 0x67, 0x19);
      this.checkGeneration(generation);
      if (this.state.automaticAmbient !== enabled || this.state.ambientSensitivity !== sensitivity) {
        throw new Error('耳机未确认自动环境声设置，请检查当前聆听模式');
      }
      this.state.error = '';
      this.log('自动环境声与检测灵敏度已由耳机确认');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  async setTouchEnabled(enabled: boolean): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    this.state.busy = true;
    try {
      await link.request(this.protocol.touchCommand(enabled));
      const type: number = this.protocol.snapshot.touchType;
      await link.request([0xd6, type], 0xd7, type);
      this.checkGeneration(generation);
      if (this.state.touchEnabled !== enabled) { throw new Error('耳机未确认触摸面板设置'); }
      this.state.error = '';
      this.log('触摸面板设置已由耳机确认');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  private async queryListening(link: MdrLink, type: number): Promise<void> {
    const frame: MdrFrame = await link.request([0xe6, type], 0xe7, type);
    const p: Uint8Array = frame.payload;
    if (p.length !== (type === 9 ? 4 : 3) || p[2] > 1 ||
      (type === 9 && p[3] > 2 && !(p[2] === 1 && p[3] === 0xff))) {
      throw new Error('耳机返回了无法识别的聆听音效状态');
    }
  }

  async setCinemaEnabled(enabled: boolean): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    const generation: number = this.generation;
    let changedOtherEffects: boolean = false;
    this.state.busy = true;
    try {
      if (!this.state.cinemaAvailable) { throw new Error('当前耳机未提供 Cinema 上混设置'); }
      if (enabled) {
        const queries: number[][] = this.protocol.listeningStatusRequests();
        for (let i: number = 0; i < queries.length; i++) { await this.queryListening(link, queries[i][1]); }
        this.checkGeneration(generation);
        const preparation: number[][] = this.protocol.cinemaPreparationCommands();
        for (let i: number = 0; i < preparation.length; i++) {
          const command: number[] = preparation[i];
          await link.request(command);
          changedOtherEffects = true;
          await this.queryListening(link, command[1]);
          this.checkGeneration(generation);
          if (this.protocol.listeningValue(command[1]) !== 1) { throw new Error('耳机未确认关闭互斥音效'); }
        }
      } else { await this.queryListening(link, 4); }
      await link.request(this.protocol.cinemaCommand(enabled));
      await this.queryListening(link, 4);
      if (enabled) {
        const verification: number[][] = this.protocol.listeningStatusRequests();
        for (let i: number = 1; i < verification.length; i++) {
          await this.queryListening(link, verification[i][1]);
        }
        if (this.protocol.cinemaPreparationCommands().length > 0) { throw new Error('耳机仍有其他聆听音效启用'); }
      }
      this.checkGeneration(generation);
      if (this.state.cinemaEnabled !== enabled) { throw new Error('耳机未确认 Cinema 上混设置'); }
      this.state.error = '';
      this.log('360 Upmix for Cinema 设置已由耳机确认');
    } catch (error) {
      if (generation === this.generation) {
        const message: string = (error as Error).message;
        this.showError(changedOtherEffects ? '音效切换未完成，部分其他音效可能已关闭。' + message : message);
      }
    } finally { if (generation === this.generation) { this.state.busy = false; } }
  }

  async powerOff(): Promise<void> {
    const link: MdrLink | undefined = this.link;
    if (!this.state.connected || this.state.busy || link === undefined) { return; }
    if (!this.state.powerOffAvailable) { this.showError('当前耳机未提供关机功能'); return; }
    const generation: number = this.generation;
    this.state.busy = true;
    this.state.poweringOff = true;
    this.reconnectPaused = true;
    this.cancelReconnect();
    this.state.error = '';
    this.state.notice = '';
    if (this.polling >= 0) { clearInterval(this.polling); this.polling = -1; }
    try {
      await link.request(this.protocol.powerOffCommand());
      this.checkGeneration(generation);
      // An ACK confirms receipt, not that the physical power-off has completed.
      this.disconnect();
      this.state.notice = '耳机已确认收到关机指令，请确认耳机已停止播放并关机。';
      this.log('关机指令已由耳机确认收到');
    } catch (error) {
      if (generation === this.generation) { this.showError((error as Error).message); }
    } finally {
      if (generation === this.generation) {
        this.state.poweringOff = false;
        this.state.busy = false;
        if (this.state.connected) { this.startPolling(); }
      }
    }
  }

  private startPolling(): void {
    if (this.polling < 0) {
      this.polling = setInterval(() => { this.refreshStatus(); }, this.foreground ? 15000 : 60000);
    }
  }

  private restartPolling(): void {
    if (this.polling >= 0) { clearInterval(this.polling); this.polling = -1; }
    this.startPolling();
  }

  private checkGeneration(generation: number): void {
    if (generation !== this.generation) { throw new Error('控制会话已结束'); }
  }

  private adopt(snapshot: HeadphoneSnapshot): void {
    this.state.eqAvailable = snapshot.eqCapability && snapshot.eqEnabled && snapshot.eqPreset >= 0;
    this.state.eqPreset = snapshot.eqPreset;
    this.state.eqPresets = snapshot.eqPresets.slice();
    this.state.eqBands = snapshot.eqBands.slice();
    this.state.model = snapshot.model || '索尼耳机';
    this.state.firmware = snapshot.firmware;
    this.state.battery = snapshot.battery;
    this.state.charging = snapshot.charging;
    this.state.batteryParts = this.protocol.batteryParts();
    this.state.codec = codecName(snapshot.codec);
    this.state.noiseMode = snapshot.noiseMode;
    this.state.ambientLevel = snapshot.ambientLevel;
    this.state.focusVoice = snapshot.focusVoice;
    this.state.automaticAmbient = snapshot.automaticAmbient === 1;
    this.state.ambientSensitivity = snapshot.sensitivity;
    this.state.automaticAmbientAvailable = this.protocol.supports(0x6d) && snapshot.noiseType === 0x19 && snapshot.noisePayload.length === 9;
    this.state.touchEnabled = snapshot.touchValue === 0;
    this.state.touchAvailable = snapshot.touchType >= 0 && snapshot.touchValue >= 0;
    this.state.powerOffAvailable = this.protocol.supports(0x23);
    this.state.cinemaEnabled = snapshot.cinemaValue === 0;
    this.state.cinemaAvailable = this.protocol.supports(0xe6) && this.protocol.supports(0xe5) && snapshot.cinemaValue >= 0;
    this.state.priority = snapshot.priority;
    this.state.noiseAvailable = snapshot.noisePayload.length >= 7;
    this.state.priorityAvailable = this.protocol.supports(0xe1) && snapshot.priority >= 0;
    if (this.state.connected) { this.updateWidget(); }
  }

  private failure(message: string): void {
    const requestedPowerOff: boolean = this.state.poweringOff;
    this.disconnect(false);
    if (requestedPowerOff) {
      this.state.notice = '关机期间控制连接已断开，未能确认指令结果。请检查耳机是否已关机。';
      this.log('关机期间连接断开，结果未确认：' + message);
    } else { this.showError(message); this.scheduleReconnect(); }
  }
  private showError(message: string): void { this.state.error = message; this.log(message); }
  private log(message: string): void {
    // No device addresses, audio content, or raw packets in the in-memory log.
    this.state.logs = [new Date().toLocaleTimeString() + '  ' + message].concat(this.state.logs).slice(0, 25);
  }
}

export const headphones: HeadphoneController = new HeadphoneController();
