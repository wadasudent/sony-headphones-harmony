const storage = new LocalStorage();

@Entry(storage)
@Component
struct HeadphoneCard {
  @LocalStorageProp('connected') connected: boolean = false;
  @LocalStorageProp('connectionText') connectionText: string = '未连接';
  @LocalStorageProp('model') model: string = '索尼耳机助手';
  @LocalStorageProp('batteryText') batteryText: string = '—';
  @LocalStorageProp('modeText') modeText: string = '未读取';
  @LocalStorageProp('updateText') updateText: string = '点击连接耳机';
  @LocalStorageProp('charging') charging: boolean = false;
  @LocalStorageProp('mode') mode: number = -1;
  @LocalStorageProp('battery') battery: number = 0;
  @LocalStorageProp('dimension') dimension: number = 2;

  private open(mode: number = -1): void {
    postCardAction(this, {
      action: 'router', abilityName: 'EntryAbility',
      params: { widgetAction: mode < 0 ? 'refresh' : 'mode', noiseMode: mode }
    });
  }

  @Builder
  ModeButton(title: string, value: number) {
    Text(title).fontSize(12).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
      .fontColor(this.mode === value ? $r('app.color.accent') : $r('app.color.text_secondary'))
      .backgroundColor(this.mode === value ? $r('app.color.accent_soft') : $r('app.color.surface_secondary'))
      .borderRadius(18).height(36).layoutWeight(1)
      .accessibilityText('打开耳机控制并切换到' + title)
      .onClick(() => { this.open(value); })
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_headphones')).width(20).height(20).fillColor($r('app.color.accent'))
        Text(this.model).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).maxLines(1).layoutWeight(1)
      }.width('100%')
      if (this.connected) {
      Text(this.connectionText).fontSize(10).fontColor($r('app.color.text_secondary'))
        .width('100%').maxLines(1)
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.batteryText).fontSize(this.dimension === 3 ? 28 : 32).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text((this.charging ? '充电中 · ' : '') + this.modeText).fontSize(12)
            .fontColor($r('app.color.text_secondary')).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Image($r('app.media.headphones_hero')).width(this.dimension === 3 ? 100 : 48).height(46)
          .objectFit(ImageFit.Contain)
      }.width('100%').layoutWeight(1)
      if (this.dimension === 3) {
        Row({ space: 8 }) {
          this.ModeButton('降噪', 1)
          this.ModeButton('环境声', 2)
          this.ModeButton('关闭', 0)
        }.width('100%')
      }
      Text(this.updateText).fontSize(10).fontColor($r('app.color.text_secondary')).maxLines(1).width('100%')
      } else {
        Column({ space: 8 }) {
          Image($r('app.media.ic_bluetooth')).width(28).height(28).fillColor($r('app.color.text_tertiary'))
          Text('连接已断开').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text('点击重新连接').fontSize(11).fontColor($r('app.color.text_secondary'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }.padding(this.dimension === 3 ? 12 : 16).width('100%').height('100%').backgroundColor($r('app.color.surface'))
      .onClick(() => { this.open(); })
  }
}
