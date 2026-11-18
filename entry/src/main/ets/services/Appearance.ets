import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export type ColorMode = ConfigurationConstant.ColorMode;

export class AccentPalette {
  readonly id: string;
  readonly label: Resource;
  readonly color: Resource;
  readonly soft: Resource;
  readonly border: Resource;

  constructor(id: string, label: Resource, color: Resource, soft: Resource, border: Resource) {
    this.id = id;
    this.label = label;
    this.color = color;
    this.soft = soft;
    this.border = border;
  }
}

export const accentPalettes: AccentPalette[] = [
  new AccentPalette('blue', $r('app.string.accent_blue'), $r('app.color.accent'),
    $r('app.color.accent_soft'), $r('app.color.accent_border')),
  new AccentPalette('teal', $r('app.string.accent_teal'), $r('app.color.accent_teal'),
    $r('app.color.accent_teal_soft'), $r('app.color.accent_teal_border')),
  new AccentPalette('purple', $r('app.string.accent_purple'), $r('app.color.accent_purple'),
    $r('app.color.accent_purple_soft'), $r('app.color.accent_purple_border')),
  new AccentPalette('amber', $r('app.string.accent_amber'), $r('app.color.accent_amber'),
    $r('app.color.accent_amber_soft'), $r('app.color.accent_amber_border'))
];

const systemMode: ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
const storeName: string = 'ui_appearance';

@ObservedV2
export class Appearance {
  @Trace mode: ColorMode = systemMode;
  @Trace palette: AccentPalette = accentPalettes[0];
  @Trace saving: boolean = false;
  @Trace error?: Resource;

  load(context: common.UIAbilityContext): void {
    try {
      const store = preferences.getPreferencesSync(context, { name: storeName });
      const savedMode = store.getSync('colorMode', systemMode);
      const accent = store.getSync('accent', accentPalettes[0].id);
      this.palette = accentPalettes.find((palette: AccentPalette) => palette.id === accent) || accentPalettes[0];
      const mode: ColorMode = savedMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ||
        savedMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? savedMode : systemMode;
      if (mode !== systemMode || this.mode !== systemMode) {
        context.getApplicationContext().setColorMode(mode);
      }
      this.mode = mode;
      this.error = undefined;
    } catch (_) { this.error = $r('app.string.theme_load_failed'); }
  }

  async update(context: common.UIAbilityContext, mode: ColorMode, palette: AccentPalette): Promise<void> {
    if (this.saving) { return; }
    this.error = undefined;
    try {
      if (mode !== this.mode) { context.getApplicationContext().setColorMode(mode); }
    } catch (_) {
      this.error = $r('app.string.theme_apply_failed');
      return;
    }
    this.mode = mode;
    this.palette = palette;
    this.saving = true;
    try {
      const store = preferences.getPreferencesSync(context, { name: storeName });
      store.putSync('colorMode', mode);
      store.putSync('accent', palette.id);
      await store.flush();
    } catch (_) { this.error = $r('app.string.theme_save_failed'); }
    finally { this.saving = false; }
  }
}

export const appearance = new Appearance();
