import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { headphones } from '../services/Headphones';

export default class EntryAbility extends UIAbility {
  private pendingWidgetMode: number = -2;
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    headphones.initialize(this.context);
    this.captureWidget(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.captureWidget(want); }

  private captureWidget(want: Want): void {
    const action = want.parameters?.['widgetAction'];
    if (action === 'refresh' || action === 'mode') {
      const mode = want.parameters?.['noiseMode'];
      this.pendingWidgetMode = action === 'mode' && typeof mode === 'number' &&
        Number.isInteger(mode) && mode >= 0 && mode <= 2 ? mode : -1;
    }
  }

  onForeground(): void {
    headphones.onForeground();
    if (this.pendingWidgetMode >= -1) {
      const mode = this.pendingWidgetMode;
      this.pendingWidgetMode = -2;
      headphones.handleWidgetAction(mode);
    }
  }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      windowStage.loadContent('pages/Index', (error: BusinessError) => {
        if (error.code) { hilog.error(0x0000, 'Headphones', 'Page load failed: %{public}d', error.code); }
      });
    } catch (error) {
      hilog.error(0x0000, 'Headphones', 'Window initialization failed: %{public}d', (error as BusinessError).code);
    }
  }

  onBackground(): void { headphones.onBackground(); }
  onDestroy(): void { headphones.destroy(); }
}
