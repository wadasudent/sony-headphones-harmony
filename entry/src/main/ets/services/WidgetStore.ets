import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';

export class WidgetSnapshot {
  connected: boolean = false;
  model: string = '索尼耳机';
  battery: number = -1;
  charging: boolean = false;
  mode: number = -1;
  updated: number = 0;
}

export class WidgetView {
  connected: boolean = false;
  connectionText: string = '未连接';
  model: string = '索尼耳机助手';
  dimension: number = 2;
  batteryText: string = '—';
  modeText: string = '未读取';
  updateText: string = '点击连接耳机';
  mode: number = -1;
  battery: number = 0;
  charging: boolean = false;
}

// Only confirmed readings are persisted. A widget always identifies them as history,
// including after the UIAbility has been killed without a lifecycle callback.
export function widgetPreferences(context: common.Context): preferences.Preferences {
  preferences.removePreferencesFromCacheSync(context, 'xm6_widget');
  return preferences.getPreferencesSync(context, { name: 'xm6_widget' });
}

export function readWidget(context: common.Context, formId: string = ''): WidgetView {
  const view = new WidgetView();
  try {
    const store = widgetPreferences(context);
    view.dimension = store.getSync('dimension_' + formId, 2) as number;
    const data = JSON.parse(store.getSync('snapshot', '{}') as string) as WidgetSnapshot;
    if (!data.updated) { return view; }
    view.connected = data.connected === true;
    view.model = data.model || '索尼耳机';
    if (!view.connected) {
      view.connectionText = '连接已断开';
      view.updateText = '点击重新连接';
      return view;
    }
    // Persisted connection state is a historical observation, never a live lease.
    view.connectionText = data.connected ? '最近已连接' : '未连接';
    view.model = data.model || '索尼耳机';
    view.batteryText = data.battery >= 0 ? data.battery + '%' : '—';
    view.battery = Math.max(0, data.battery);
    view.charging = data.charging;
    view.mode = data.mode;
    view.modeText = data.mode === 1 ? '降噪' : (data.mode === 2 ? '环境声' : (data.mode === 0 ? '关闭' : '未读取'));
    const time = new Date(data.updated);
    view.updateText = '上次读取 ' + (time.getMonth() + 1) + '/' + time.getDate() + ' ' +
      time.getHours().toString().padStart(2, '0') + ':' + time.getMinutes().toString().padStart(2, '0');
  } catch (_) { /* An empty/corrupt cache never fabricates a reading. */ }
  return view;
}

export async function publishWidget(context: common.Context, data: WidgetSnapshot): Promise<void> {
  const store = widgetPreferences(context);
  if (!data.connected && data.updated === 0) {
    // Disconnect must not erase the last confirmed reading or make it look newer.
    try {
      const previous = JSON.parse(store.getSync('snapshot', '{}') as string) as WidgetSnapshot;
      if (previous.updated > 0) {
        data.model = previous.model || '索尼耳机';
        data.battery = previous.battery;
        data.mode = previous.mode;
        data.charging = previous.charging;
        data.updated = previous.updated;
      }
    } catch (_) { /* A disconnect without history keeps the empty state. */ }
  }
  store.putSync('snapshot', JSON.stringify(data));
  await store.flush();
  const forms = await formProvider.getPublishedRunningFormInfos();
  for (let i: number = 0; i < forms.length; i++) {
    try { await formProvider.updateForm(forms[i].formId,
      formBindingData.createFormBindingData(readWidget(context, forms[i].formId))); }
    catch (_) { /* A card may be removed while a reading is being published. */ }
  }
}
