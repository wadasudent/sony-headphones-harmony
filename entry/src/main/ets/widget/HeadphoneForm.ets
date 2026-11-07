import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { readWidget, widgetPreferences } from '../services/WidgetStore';

export default class HeadphoneForm extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    const dimension = want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number;
    try {
      const store = widgetPreferences(this.context);
      store.putSync('dimension_' + id, dimension);
      store.flushSync();
    } catch (_) { /* Initial display still uses the dimension from the system Want. */ }
    const view = readWidget(this.context, id);
    view.dimension = dimension === 3 ? 3 : 2;
    return formBindingData.createFormBindingData(view);
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, formBindingData.createFormBindingData(readWidget(this.context, formId)))
      .catch(() => {});
  }

  onRemoveForm(formId: string): void {
    try {
      const store = widgetPreferences(this.context);
      store.deleteSync('dimension_' + formId);
      store.flushSync();
    } catch (_) { /* No connection is owned by the form extension. */ }
  }
}
