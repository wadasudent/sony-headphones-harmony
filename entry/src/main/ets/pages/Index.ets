import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { HeadphoneState, PairedHeadphone, headphones } from '../services/Headphones';
import { NoiseMode, EQ_FREQUENCIES, eqPresetName } from '../protocol/MdrCore';

@Entry
@ComponentV2
struct Index {
  @Local state: HeadphoneState = headphones.state;
  @Local currentTab: number = 0;
  @Local showDevices: boolean = false;
  @Local showLogs: boolean = false;
  @Local wide: boolean = false;
  @Local editingEq: boolean = false;
  @Local eqDraft: number[] = [];
  @Local eqBase: number[] = [];
  @Local eqBasePreset: number = -1;

  private beginEqualizer(): void {
    this.eqDraft = this.state.eqBands.slice();
    this.eqBase = this.state.eqBands.slice();
    this.eqBasePreset = this.state.eqPreset;
    this.editingEq = true;
  }

  private async applyEqualizer(): Promise<void> {
    await headphones.setEqualizer(0xa0, this.eqDraft.slice(), this.eqBase.slice(), this.eqBasePreset);
    if (this.state.error.length === 0 && this.state.connected) { this.editingEq = false; }
  }

  private async refreshDevices(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context !== undefined) { await headphones.refreshDevices(context); }
  }

  private openDevices(): void { this.showDevices = true; this.refreshDevices(); }

  private setMode(mode: NoiseMode): void {
    headphones.setNoise(mode, this.state.ambientLevel < 0 ? 10 : this.state.ambientLevel, this.state.focusVoice);
  }

  private confirmPowerOff(): void {
    if (!this.state.connected || this.state.busy || !this.state.powerOffAvailable) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.power_off_title'),
        message: $r('app.string.power_off_message'),
        primaryButton: { value: $r('app.string.cancel'), defaultFocus: true, action: () => {} },
        secondaryButton: {
          value: $r('app.string.power_off_action'), fontColor: $r('app.color.error'),
          action: () => { this.currentTab = 0; headphones.powerOff(); }
        }
      });
    } catch (error) { this.state.error = (error as Error).message || '暂时无法显示关机确认'; }
  }

  @Builder
  Header() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.currentTab === 0 ? $r('app.string.home_title') : $r('app.string.more_title'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(this.currentTab === 0 ? $r('app.string.home_subtitle') : $r('app.string.more_subtitle'))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start)
      Blank()
      if (this.currentTab === 0) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_settings')).width(22).height(22).fillColor($r('app.color.text_primary'))
        }.width(44).height(44).backgroundColor($r('app.color.surface'))
          .accessibilityText($r('app.string.more_title')).onClick(() => { this.currentTab = 1; })
      } else {
        Text('0.5.0').fontSize(12).fontColor($r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.surface')).borderRadius(20)
      }
    }.width('100%').constraintSize({ maxWidth: 1080 })
      .padding({ left: 24, right: 24, top: 18, bottom: 18 })
  }

  @Builder
  StatusBadge() {
    Row({ space: 5 }) {
      Row().width(5).height(5).borderRadius(3)
        .backgroundColor(this.state.connected ? $r('app.color.success') : $r('app.color.text_tertiary'))
      Text(this.state.connected ? $r('app.string.connected') :
        (this.state.connecting ? $r('app.string.connecting') : $r('app.string.disconnected')))
        .fontSize(11).fontColor(this.state.connected ? $r('app.color.success') : $r('app.color.text_secondary'))
    }.padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface')).borderRadius(20)
  }

  @Builder
  StatusItem(icon: Resource, label: Resource, value: string) {
    Row({ space: 8 }) {
      Image(icon).width(19).height(19).fillColor($r('app.color.text_secondary'))
      Column({ space: 3 }) {
        Text(label).fontSize(10).fontColor($r('app.color.text_secondary'))
        Text(value).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).justifyContent(FlexAlign.Center)
  }

  @Builder
  DeviceHero() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text($r('app.string.headphone_category')).fontSize(11).fontColor($r('app.color.text_secondary'))
          Text(this.state.model).fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        this.StatusBadge()
      }.width('100%')
      Stack({ alignContent: Alignment.Center }) {
        Progress({ value: this.state.battery < 0 ? 0 : this.state.battery, total: 100, type: ProgressType.Ring })
          .width(184).height(184).color($r('app.color.accent'))
          .backgroundColor($r('app.color.hero_halo')).style({ strokeWidth: 5 })
          .accessibilityText(this.state.battery < 0 ? '电量未读取' : '耳机电量 ' + this.state.battery + '%')
        Image($r('app.media.headphones_hero')).width(208).height(152).objectFit(ImageFit.Contain)
          .accessibilityText($r('app.string.headphone_illustration'))
      }.height(200).width('100%')
      if (this.state.connected) {
        Row({ space: 12 }) {
          this.StatusItem($r('app.media.ic_battery'), $r('app.string.battery'),
            this.state.battery < 0 ? '—' : this.state.battery.toString() + '%')
          Divider().vertical(true).height(30).color($r('app.color.separator'))
          this.StatusItem($r('app.media.ic_noise'), $r('app.string.listening_mode'),
            this.state.noiseMode === NoiseMode.Cancel ? '降噪' : (this.state.noiseMode === NoiseMode.Ambient ? '环境声' :
              (this.state.noiseMode === NoiseMode.Off ? '关闭' : '未读取')))
        }.width('100%').padding({ top: 2, bottom: 8 })
        if (this.state.charging) {
          Text($r('app.string.charging')).fontSize(12).fontColor($r('app.color.success'))
        }
        Button(this.state.busy ? $r('app.string.syncing') : $r('app.string.refresh_status'))
          .width('100%').height(46).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
          .enabled(!this.state.busy).onClick(() => { headphones.refreshStatus(); })
      } else if (this.state.connecting) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color($r('app.color.accent'))
          Text(this.state.message).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        }.width('100%')
        Button($r('app.string.cancel_connection')).width('100%').height(46)
          .fontSize(15).fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
          .onClick(() => { headphones.disconnect(); })
      } else {
        Button() {
          Row({ space: 8 }) {
            Image($r('app.media.ic_bluetooth')).width(18).height(18).fillColor($r('app.color.on_accent'))
            Text($r('app.string.connect_headphones')).fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
          }
        }.width('100%').height(48).backgroundColor($r('app.color.accent'))
          .accessibilityText($r('app.string.connect_headphones')).onClick(() => { this.openDevices(); })
        Text($r('app.string.pair_first')).fontSize(11).fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center).width('100%')
      }
    }.width('100%').padding(20).backgroundColor($r('app.color.hero_background')).borderRadius(28)
  }

  @Builder
  ErrorBanner() {
    Row({ space: 10 }) {
      Image($r('app.media.ic_info')).width(20).height(20).fillColor($r('app.color.error'))
      Text(this.state.error).fontSize(13).lineHeight(19).fontColor($r('app.color.error')).layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_close')).width(16).height(16).fillColor($r('app.color.error'))
      }.width(32).height(32).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.dismiss_message')).onClick(() => { this.state.error = ''; })
    }.width('100%').padding(14).backgroundColor($r('app.color.error_surface')).borderRadius(18)
  }

  @Builder
  FeatureRow(icon: Resource, title: Resource, subtitle: Resource) {
    Row({ space: 13 }) {
      Image(icon).width(24).height(24).fillColor($r('app.color.accent'))
      Column({ space: 5 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(subtitle).fontSize(11).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Image($r('app.media.ic_lock')).width(16).height(16).fillColor($r('app.color.text_tertiary'))
    }.width('100%').padding({ top: 20, bottom: 20 })
  }

  @Builder
  NoticeBanner() {
    Row({ space: 10 }) {
      Image($r('app.media.ic_info')).width(20).height(20).fillColor($r('app.color.accent'))
      Text(this.state.notice).fontSize(13).lineHeight(20).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_close')).width(16).height(16).fillColor($r('app.color.text_secondary'))
      }.width(32).height(32).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.dismiss_message')).onClick(() => { this.state.notice = ''; })
    }.width('100%').padding(14).backgroundColor($r('app.color.accent_soft')).borderRadius(18)
  }

  // This switch only reflects confirmed device state; tapping never flips it locally.
  @Builder
  StateSwitch(label: Resource, value: boolean, available: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        if (value) { Blank() }
        Row().width(20).height(20).borderRadius(10).backgroundColor($r('app.color.on_accent'))
        if (!value) { Blank() }
      }.width(44).height(26).padding(3).borderRadius(13)
        .backgroundColor(value ? $r('app.color.accent') : $r('app.color.text_tertiary'))
    }.width(52).height(44).padding(0).borderRadius(22).backgroundColor(Color.Transparent)
      .enabled(available && !this.state.busy).accessibilityText(label)
      .accessibilityDescription(value ? $r('app.string.switch_on') : $r('app.string.switch_off'))
      .accessibilitySelected(value).onClick(action)
  }

  @Builder
  SensitivityOption(label: Resource, value: number) {
    Button(label).layoutWeight(1).height(36).fontSize(12)
      .fontColor(this.state.ambientSensitivity === value ? $r('app.color.accent') : $r('app.color.text_secondary'))
      .backgroundColor(this.state.ambientSensitivity === value ? $r('app.color.accent_soft') : $r('app.color.surface_secondary'))
      .enabled(this.state.automaticAmbient && !this.state.busy)
      .accessibilitySelected(this.state.ambientSensitivity === value)
      .onClick(() => { headphones.setAutomaticAmbient(this.state.automaticAmbient, value); })
  }

  @Builder
  FeatureOverview() {
    Column({ space: 12 }) {
      Text($r('app.string.ready_title')).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 4 })
      Column() {
        this.FeatureRow($r('app.media.ic_noise'), $r('app.string.listening_mode'), $r('app.string.listening_preview'))
        Divider().color($r('app.color.separator')).margin({ left: 54 })
        this.FeatureRow($r('app.media.ic_wave'), $r('app.string.connection_preference'), $r('app.string.quality_preview'))
      }.padding({ left: 18, right: 18 }).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      Row({ space: 7 }) {
        Image($r('app.media.ic_info')).width(14).height(14).fillColor($r('app.color.text_tertiary'))
        Text($r('app.string.offline_hint')).fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      }.width('100%').padding({ left: 4, right: 4 })
    }.width('100%')
  }

  @Builder
  ModeTile(label: Resource, icon: Resource, mode: NoiseMode) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Image(icon).width(25).height(25)
          .fillColor(this.state.noiseMode === mode ? $r('app.color.accent') : $r('app.color.text_secondary'))
        Text(label).fontSize(13).fontWeight(this.state.noiseMode === mode ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.state.noiseMode === mode ? $r('app.color.accent') : $r('app.color.text_primary'))
      }.width('100%').padding({ top: 17, bottom: 15 })
    }.layoutWeight(1).backgroundColor(this.state.noiseMode === mode ?
      $r('app.color.accent_soft') : Color.Transparent).borderRadius(18)
      .border({ width: 1, color: this.state.noiseMode === mode ? $r('app.color.accent_border') : Color.Transparent })
      .enabled(!this.state.busy && this.state.noiseAvailable)
      .accessibilityText(label).accessibilitySelected(this.state.noiseMode === mode)
      .onClick(() => { this.setMode(mode); })
  }

  @Builder
  ListeningCard() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.listening_mode')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.state.busy) { LoadingProgress().width(17).height(17).color($r('app.color.accent')) }
      }.width('100%')
      Row({ space: 4 }) {
        this.ModeTile($r('app.string.noise_cancel'), $r('app.media.ic_noise'), NoiseMode.Cancel)
        this.ModeTile($r('app.string.ambient'), $r('app.media.ic_ambient'), NoiseMode.Ambient)
        this.ModeTile($r('app.string.off'), $r('app.media.ic_off'), NoiseMode.Off)
      }.width('100%').padding(4).backgroundColor($r('app.color.surface_secondary')).borderRadius(22)
      if (!this.state.noiseAvailable) {
        Text($r('app.string.noise_unavailable')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.state.noiseAvailable && this.state.noiseMode === NoiseMode.Ambient) {
        Row() {
          Text($r('app.string.ambient_level')).fontSize(14).fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.state.ambientLevel.toString() + ' / 20').fontSize(12).fontColor($r('app.color.accent'))
        }.width('100%')
        Slider({ value: this.state.ambientLevel, min: 0, max: 20, step: 1 })
          .selectedColor($r('app.color.accent')).trackColor($r('app.color.surface_secondary'))
          .enabled(!this.state.busy).accessibilityText($r('app.string.ambient_level'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              headphones.setNoise(NoiseMode.Ambient, Math.round(value), this.state.focusVoice);
            }
          })
        if (this.state.automaticAmbientAvailable) {
          Divider().color($r('app.color.separator'))
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text($r('app.string.automatic_ambient')).fontSize(14).fontColor($r('app.color.text_primary'))
              Text($r('app.string.automatic_ambient_hint')).fontSize(11).fontColor($r('app.color.text_secondary'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            this.StateSwitch($r('app.string.automatic_ambient'), this.state.automaticAmbient, true, () => {
              headphones.setAutomaticAmbient(!this.state.automaticAmbient, this.state.ambientSensitivity);
            })
          }.width('100%')
          if (this.state.automaticAmbient) {
            Text($r('app.string.ambient_sensitivity')).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            Row({ space: 8 }) {
              this.SensitivityOption($r('app.string.sensitivity_low'), 2)
              this.SensitivityOption($r('app.string.sensitivity_standard'), 0)
              this.SensitivityOption($r('app.string.sensitivity_high'), 1)
            }.width('100%')
          }
        }
        Row() {
          Column({ space: 4 }) {
            Text($r('app.string.focus_voice')).fontSize(14).fontColor($r('app.color.text_primary'))
            Text($r('app.string.focus_voice_hint')).fontSize(11).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          this.StateSwitch($r('app.string.focus_voice'), this.state.focusVoice, this.state.noiseAvailable, () => {
            headphones.setNoise(NoiseMode.Ambient, this.state.ambientLevel, !this.state.focusVoice);
          })
        }.width('100%')
      }
    }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  QualityOption(title: Resource, subtitle: Resource, value: number) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(title).fontSize(14).fontColor($r('app.color.text_primary'))
          Text(subtitle).fontSize(11).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          Row().width(20).height(20).borderRadius(10).backgroundColor(Color.Transparent)
            .border({ width: 1.5, color: this.state.priority === value ? $r('app.color.accent') : $r('app.color.text_tertiary') })
          if (this.state.priority === value) {
            Row().width(10).height(10).borderRadius(5).backgroundColor($r('app.color.accent'))
          }
        }
      }.width('100%').padding({ top: 14, bottom: 14 })
    }.width('100%').backgroundColor(Color.Transparent).borderRadius(12)
      .enabled(!this.state.busy && this.state.priorityAvailable).accessibilityText(title)
      .accessibilitySelected(this.state.priority === value)
      .onClick(() => { headphones.setPriority(value === 0); })
  }

  @Builder
  QualityCard() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.connection_preference')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.state.codec).fontSize(11).fontColor($r('app.color.accent'))
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.accent_soft')).borderRadius(8)
      }.width('100%').margin({ bottom: 4 })
      if (this.state.priorityAvailable) {
        this.QualityOption($r('app.string.quality_first'), $r('app.string.quality_first_hint'), 0)
        Divider().color($r('app.color.separator'))
        this.QualityOption($r('app.string.stable_first'), $r('app.string.stable_first_hint'), 1)
      } else {
        Text($r('app.string.priority_unavailable')).fontSize(12).lineHeight(19)
          .fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 8, bottom: 6 })
      }
      Text($r('app.string.codec_hint')).fontSize(10).fontColor($r('app.color.text_tertiary')).width('100%')
    }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  CinemaCard() {
    Column({ space: 14 }) {
      Text($r('app.string.spatial_effect')).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        Text($r('app.string.cinema_title')).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
        this.StateSwitch($r('app.string.cinema_title'), this.state.cinemaEnabled, this.state.cinemaAvailable, () => {
          headphones.setCinemaEnabled(!this.state.cinemaEnabled);
        })
      }.width('100%')
      Text($r('app.string.cinema_description')).fontSize(12).lineHeight(20)
        .fontColor($r('app.color.text_secondary')).width('100%')
      Text($r('app.string.cinema_exclusive_hint')).fontSize(11).lineHeight(18)
        .fontColor($r('app.color.text_secondary')).width('100%')
      Text($r('app.string.cinema_persistence')).fontSize(10).fontColor($r('app.color.text_tertiary')).width('100%')
    }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  ControlCards() {
    Column({ space: 16 }) {
      if (this.state.connected) {
        this.ListeningCard()
        this.EqualizerCard()
        if (this.state.cinemaAvailable) { this.CinemaCard() }
        this.QualityCard()
      }
      else { this.FeatureOverview() }
    }.width('100%')
  }

  @Builder
  EqualizerCard() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text('均衡器 · 调整音色').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(eqPresetName(this.state.eqPreset)).fontSize(12).fontColor($r('app.color.accent'))
      }.width('100%')
      if (this.state.eqAvailable) {
        Text('耳机端 10 段 EQ · 从低频到高频').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        if (!this.editingEq) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.state.eqPresets, (preset: number) => {
              Button(eqPresetName(preset)).fontSize(12).height(36).margin({ right: 8, bottom: 8 })
                .fontColor(this.state.eqPreset === preset ? $r('app.color.on_accent') : $r('app.color.accent'))
                .backgroundColor(this.state.eqPreset === preset ? $r('app.color.accent') : $r('app.color.accent_soft'))
                .enabled(!this.state.busy).accessibilitySelected(this.state.eqPreset === preset)
                .onClick(() => { headphones.setEqualizer(preset); })
            }, (preset: number) => preset.toString())
          }.width('100%')
          if (this.state.eqBands.length === 10 && this.state.eqPresets.indexOf(0xa0) >= 0) {
            Button('调整 10 段均衡器').width('100%').height(42).fontSize(14)
              .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
              .enabled(!this.state.busy).onClick(() => { this.beginEqualizer(); })
          }
        } else {
          ForEach(EQ_FREQUENCIES, (label: string, index: number) => {
            Row({ space: 8 }) {
              Text(label).width(58).fontSize(12).fontColor($r('app.color.text_secondary'))
              Slider({ value: this.eqDraft[index], min: 0, max: 12, step: 1 }).layoutWeight(1)
                .selectedColor($r('app.color.accent')).enabled(!this.state.busy)
                .accessibilityText(label + ' 均衡器档位')
                .onChange((value: number) => {
                  const next = this.eqDraft.slice();
                  next[index] = Math.round(value);
                  this.eqDraft = next;
                })
              Text(this.eqDraft[index].toString()).width(22).fontSize(12).fontColor($r('app.color.accent'))
            }.width('100%')
          }, (label: string) => label)
          Text('档位 0–12；这里只显示调整档位，不作为实测频响曲线或 dB 标定。点击应用后由耳机确认。')
            .fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 10 }) {
            Button('取消').layoutWeight(1).height(42).fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.accent_soft')).enabled(!this.state.busy)
              .onClick(() => { this.editingEq = false; })
            Button(this.state.busy ? '正在确认…' : '应用到耳机').layoutWeight(1).height(42)
              .fontColor($r('app.color.on_accent')).backgroundColor($r('app.color.accent'))
              .enabled(!this.state.busy).onClick(() => { this.applyEqualizer(); })
          }.width('100%')
        }
      } else {
        Text('连接后读取耳机均衡器能力。若当前音效或连接模式使 EQ 不可用，将暂停设置。')
          .fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  InfoRow(label: Resource, value: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value).fontSize(13).fontColor($r('app.color.text_primary')).textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '65%' })
    }.width('100%').padding({ top: 13, bottom: 13 })
  }

  @Builder
  DeviceControls() {
    Column({ space: 14 }) {
      Text($r('app.string.device_controls')).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.state.touchAvailable) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text($r('app.string.touch_panel')).fontSize(14).fontColor($r('app.color.text_primary'))
            Text($r('app.string.touch_panel_hint')).fontSize(11).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          this.StateSwitch($r('app.string.touch_panel'), this.state.touchEnabled, this.state.touchAvailable, () => {
            headphones.setTouchEnabled(!this.state.touchEnabled);
          })
        }.width('100%')
      }
      if (this.state.powerOffAvailable) {
        Button(this.state.poweringOff ? $r('app.string.powering_off') : $r('app.string.power_off_action'))
          .width('100%').height(44).fontSize(14).fontColor($r('app.color.error'))
          .backgroundColor($r('app.color.error_surface')).enabled(!this.state.busy)
          .onClick(() => { this.confirmPowerOff(); })
      }
    }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(24)
  }

  @Builder
  MorePage() {
    Column({ space: 16 }) {
      if (this.state.connected && (this.state.touchAvailable || this.state.powerOffAvailable)) { this.DeviceControls() }
      Column({ space: 10 }) {
        Text($r('app.string.widget_guide_title')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text($r('app.string.widget_guide_body')).fontSize(13).lineHeight(21)
          .fontColor($r('app.color.text_secondary')).width('100%')
        Text(this.state.backgroundActive ? $r('app.string.background_on') : $r('app.string.background_off'))
          .fontSize(12).fontColor($r('app.color.accent')).width('100%')
      }.padding(20).width('100%').backgroundColor($r('app.color.accent_soft')).borderRadius(24)
      Column({ space: 5 }) {
        Text($r('app.string.device_information')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).width('100%').margin({ bottom: 6 })
        this.InfoRow($r('app.string.model'), this.state.model)
        Divider().color($r('app.color.separator'))
        this.InfoRow($r('app.string.firmware'), this.state.firmware || '—')
        Divider().color($r('app.color.separator'))
        this.InfoRow($r('app.string.codec'), this.state.codec)
        if (this.state.connected || this.state.connecting) {
          Button($r('app.string.disconnect_control')).width('100%').height(44)
            .fontSize(14).fontColor($r('app.color.error')).backgroundColor($r('app.color.error_surface'))
            .margin({ top: 12 }).onClick(() => { headphones.disconnect(); })
        } else {
          Button($r('app.string.connect_headphones')).width('100%').height(44)
            .fontSize(14).fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
            .margin({ top: 12 }).onClick(() => { this.openDevices(); })
        }
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      Column({ space: 14 }) {
        Text($r('app.string.connection_notes')).fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).width('100%')
        Text($r('app.string.connection_notes_body')).fontSize(13).lineHeight(21)
          .fontColor($r('app.color.text_secondary')).width('100%')
        Divider().color($r('app.color.separator'))
        Row({ space: 10 }) {
          Image($r('app.media.ic_lock')).width(18).height(18).fillColor($r('app.color.accent'))
          Text($r('app.string.privacy_title')).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }.width('100%')
        Text($r('app.string.privacy_body')).fontSize(12).lineHeight(20)
          .fontColor($r('app.color.text_secondary')).width('100%')
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      Column({ space: 10 }) {
        Button({ type: ButtonType.Normal }) {
          Row() {
            Text($r('app.string.connection_logs')).fontSize(15).fontColor($r('app.color.text_primary'))
            Blank()
            Image($r('app.media.ic_chevron')).width(18).height(18).fillColor($r('app.color.text_secondary'))
              .rotate({ angle: this.showLogs ? 90 : 0 })
          }.width('100%').padding({ top: 6, bottom: 6 })
        }.backgroundColor(Color.Transparent).width('100%').borderRadius(8)
          .accessibilityText($r('app.string.connection_logs')).onClick(() => { this.showLogs = !this.showLogs; })
        if (this.showLogs) {
          if (this.state.logs.length === 0) {
            Text($r('app.string.no_logs')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
          ForEach(this.state.logs, (line: string, index: number) => {
            Text(line).fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary')).width('100%')
          }, (line: string, index: number) => index.toString() + line)
        }
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      Column({ space: 6 }) {
        Text($r('app.string.app_name')).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
        Text($r('app.string.community_notice')).fontSize(10).lineHeight(17).textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_tertiary'))
      }.width('100%').padding({ top: 8, bottom: 8 })
    }.width('100%').constraintSize({ maxWidth: 680 })
  }

  @Builder
  DeviceSheet() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.select_device')).fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }.width('100%').padding({ right: 56 })
      Text($r('app.string.device_sheet_hint')).fontSize(12).lineHeight(20)
        .fontColor($r('app.color.text_secondary')).width('100%')
      Row() {
        Button($r('app.string.refresh_devices')).fontSize(13).height(44)
          .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
          .enabled(!this.state.discovering).onClick(() => { this.refreshDevices(); })
      }.width('100%')
      if (this.state.error.length > 0) { this.ErrorBanner() }
      Scroll() {
        Column({ space: 10 }) {
          if (this.state.discovering) {
            LoadingProgress().width(30).height(30).color($r('app.color.accent')).margin({ top: 30 })
            Text($r('app.string.reading_devices')).fontSize(13).fontColor($r('app.color.text_secondary'))
          } else if (this.state.devices.length === 0) {
            Image($r('app.media.ic_bluetooth')).width(36).height(36)
              .fillColor($r('app.color.text_tertiary')).margin({ top: 24 })
            Text($r('app.string.no_devices')).fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.no_devices_hint')).fontSize(12).lineHeight(20)
              .textAlign(TextAlign.Center).fontColor($r('app.color.text_secondary'))
          } else {
            ForEach(this.state.devices, (device: PairedHeadphone) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Image($r('app.media.ic_headphones')).width(26).height(26).fillColor($r('app.color.accent'))
                  Column({ space: 5 }) {
                    Text(device.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                    Text($r('app.string.paired_device')).fontSize(11).fontColor($r('app.color.text_secondary'))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Image($r('app.media.ic_chevron')).width(18).height(18).fillColor($r('app.color.text_tertiary'))
                }.padding(18).width('100%')
              }.width('100%').backgroundColor($r('app.color.surface_secondary')).borderRadius(18)
                .onClick(() => { this.showDevices = false; this.currentTab = 0; headphones.connect(device); })
            }, (device: PairedHeadphone) => device.address)
          }
        }.width('100%').padding({ bottom: 24 })
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 24, bottom: 12 })
  }

  @Builder
  NavItem(label: Resource, icon: Resource, tab: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Image(icon).width(23).height(23)
          .fillColor(this.currentTab === tab ? $r('app.color.accent') : $r('app.color.text_tertiary'))
        Text(label).fontSize(11).fontWeight(this.currentTab === tab ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.currentTab === tab ? $r('app.color.accent') : $r('app.color.text_secondary'))
      }.width('100%')
    }.height(52).layoutWeight(1).backgroundColor(Color.Transparent).borderRadius(16)
      .accessibilityText(label).accessibilitySelected(this.currentTab === tab)
      .onClick(() => { this.currentTab = tab; })
  }

  @Builder
  NativePage(tab: number) {
    HdsNavigation() {
      if (this.wide && tab === 0) {
        Row({ space: 24 }) {
          Scroll() {
            Column({ space: 16 }) {
              this.DeviceHero()
              if (this.state.notice.length > 0) { this.NoticeBanner() }
              if (this.state.error.length > 0) { this.ErrorBanner() }
            }.width('100%').padding({ bottom: 100 })
          }.width(300).height('100%').align(Alignment.Top).scrollBar(BarState.Off)
          Scroll() {
            Column() { this.ControlCards() }.width('100%').padding({ bottom: 100 })
          }.layoutWeight(1).height('100%').align(Alignment.Top).scrollBar(BarState.Off)
        }.width('100%').constraintSize({ maxWidth: 1200 }).height('100%')
          .padding({ left: 24, right: 24, top: 16 })
      } else {
      Scroll() {
        Column({ space: 16 }) {
          if (this.state.notice.length > 0) { this.NoticeBanner() }
          if (this.state.error.length > 0) { this.ErrorBanner() }
          if (tab === 0) {
            if (this.wide) {
              Row({ space: 20 }) {
                Column() { this.DeviceHero() }.layoutWeight(1)
                Column() { this.ControlCards() }.layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
            } else { this.DeviceHero(); this.ControlCards() }
          } else { this.MorePage() }
        }.width('100%').constraintSize({ maxWidth: 1080 })
          .padding({ left: 20, right: 20, top: 12, bottom: 100 })
      }.width('100%').height('100%').scrollBar(BarState.Off)
      }
    }.mode(NavigationMode.Stack).hideBackButton(true).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        enableComponentSafeArea: true,
        content: {
          title: { mainTitle: tab === 0 ? $r('app.string.home_title') : $r('app.string.more_title'),
            subTitle: tab === 0 ? $r('app.string.home_subtitle') : '索尼耳机助手 · 0.5.0' },
          menu: { value: [{ content: { icon: $r('app.media.ic_bluetooth'), label: '选择耳机',
            action: () => { this.openDevices(); } } }] }
        },
        style: { systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE } }
      }).width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  NativeLayout() {
    HdsTabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() { this.NativePage(0) }
        .tabBar(BottomTabBarStyle.of($r('app.media.ic_headphones'), $r('app.string.tab_headphones')))
      TabContent() { this.NativePage(1) }
        .tabBar(BottomTabBarStyle.of($r('app.media.ic_settings'), $r('app.string.more_title')))
    }.width('100%').height('100%').scrollable(false).animationDuration(250).barOverlap(true)
      .barFloatingStyle({ barSideMargin: 24, barBottomMargin: 12, adaptToHandedness: true,
        thermoCtrl: true, systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE } })
      .onChange((index: number) => { this.currentTab = index; })
      .backgroundColor($r('app.color.page_background'))
      .onAreaChange((_oldArea: Area, newArea: Area) => { this.wide = Number(newArea.width) >= 720; })
      .bindSheet($$this.showDevices, this.DeviceSheet(), {
        width: this.wide ? 480 : undefined,
        height: SheetSize.MEDIUM, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: this.wide ? SheetType.CENTER : SheetType.BOTTOM, showClose: true,
        backgroundColor: $r('app.color.surface'), dragBar: true
      })
  }

  build() {
    if (deviceInfo.sdkApiVersion >= 26 && canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
      this.NativeLayout()
    } else { this.LegacyLayout() }
  }

  @Builder
  LegacyLayout() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 16 }) {
          if (this.state.notice.length > 0) { this.NoticeBanner() }
          if (this.currentTab === 0) {
            if (this.state.error.length > 0) { this.ErrorBanner() }
            if (this.wide) {
              Row({ space: 20 }) {
                Column() { this.DeviceHero() }.layoutWeight(1)
                Column() { this.ControlCards() }.layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
            } else { this.DeviceHero(); this.ControlCards() }
          } else {
            if (this.state.error.length > 0) { this.ErrorBanner() }
            this.MorePage()
          }
        }.width('100%').constraintSize({ maxWidth: 1080 }).padding({ left: 20, right: 20, bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      Row() {
        Row({ space: 16 }) {
          this.NavItem($r('app.string.tab_headphones'), $r('app.media.ic_headphones'), 0)
          this.NavItem($r('app.string.more_title'), $r('app.media.ic_settings'), 1)
        }.width('100%').constraintSize({ maxWidth: 480 })
      }.width('90%').constraintSize({ maxWidth: 480 }).justifyContent(FlexAlign.Center)
        .padding({ top: 5, bottom: 5, left: 16, right: 16 }).margin({ bottom: 12 })
        .backgroundColor($r('app.color.surface')).backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(32).border({ width: 0.5, color: $r('app.color.separator') })
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const next: boolean = Number(newArea.width) >= 720;
        if (next !== this.wide) { this.wide = next; }
      })
      .bindSheet($$this.showDevices, this.DeviceSheet(), {
        width: this.wide ? 480 : undefined,
        height: SheetSize.MEDIUM, detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: this.wide ? SheetType.CENTER : SheetType.BOTTOM, showClose: true,
        backgroundColor: $r('app.color.surface'), dragBar: true
      })
  }
}
