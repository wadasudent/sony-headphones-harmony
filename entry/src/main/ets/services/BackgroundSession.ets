import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

export class BackgroundSession {
  active: boolean = false;
  private context?: common.UIAbilityContext;
  private operations: Promise<void> = Promise.resolve();
  private onCancelled: () => void = () => {};
  private cancelled = (_info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (!this.active) { return; }
    this.active = false;
    this.onCancelled();
  };

  initialize(context: common.UIAbilityContext, onCancelled: () => void): void {
    this.context = context;
    this.onCancelled = onCancelled;
    try { backgroundTaskManager.on('continuousTaskCancel', this.cancelled); } catch (_) { /* Unsupported device. */ }
  }

  destroy(): void {
    this.stop();
    try { backgroundTaskManager.off('continuousTaskCancel', this.cancelled); } catch (_) { /* Not subscribed. */ }
  }

  start(): Promise<void> {
    const operation = this.operations.then(async () => {
      const context = this.context;
      if (context === undefined || this.active) { return; }
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.local.xm6harmony', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.BLUETOOTH_INTERACTION, agent);
      this.active = true;
    });
    this.operations = operation.catch(() => {});
    return operation;
  }

  stop(): void {
    this.operations = this.operations.then(async () => {
      if (this.context !== undefined && this.active) {
        this.active = false;
        await backgroundTaskManager.stopBackgroundRunning(this.context);
      }
    }).catch(() => { this.active = false; });
  }
}
