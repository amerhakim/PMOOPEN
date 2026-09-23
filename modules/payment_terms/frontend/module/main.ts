import { CUSTOM_ELEMENTS_SCHEMA, NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { OpenProjectPluginContext } from 'core-app/features/plugins/plugin-context';
import { WidgetPmoDashboardComponent } from './pmo-dashboard-widget/pmo-dashboard-widget.component';

// 'gridWidgets' is not one of PluginContext's known convenience hook names
// (see frontend/src/app/features/plugins/plugin-context.ts _knownHookNames),
// but the underlying HookService.register accepts any string id -- this is
// exactly the hook GridWidgetsService#buildWidgets calls, collecting every
// registration into the "+ Add widget" list on a project's Dashboard tab.
export function initializePaymentTermsPlugin() {
  window.OpenProject.getPluginContext().then((pluginContext:OpenProjectPluginContext) => {
    const title = pluginContext.services.i18n.t('js.grid.widgets.pmo_dashboard.title');

    pluginContext.services.hooks.register('gridWidgets', () => [
      {
        identifier: 'pmo_dashboard',
        component: WidgetPmoDashboardComponent,
        title,
        properties: {
          name: title,
        },
      },
    ]);
  });
}

@NgModule({
  imports: [CommonModule],
  declarations: [WidgetPmoDashboardComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
})
export class PluginModule {
  constructor() {
    initializePaymentTermsPlugin();
  }
}
