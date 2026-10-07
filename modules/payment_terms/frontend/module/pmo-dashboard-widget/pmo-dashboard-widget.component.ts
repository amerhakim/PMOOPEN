import { ChangeDetectionStrategy, Component } from '@angular/core';
import { AbstractTurboWidgetComponent } from 'core-app/shared/components/grids/widgets/abstract-turbo-widget.component';

// The widget's actual content (progress ring, hours bars, severity bars,
// invoice counts) is rendered entirely server-side -- see
// Grids::Widgets::PmoDashboard / PmoDashboardHelper -- and fetched into the
// <turbo-frame> below by its [src], same as every other Rails-rendered
// widget (project-status, description, ...). No chart logic lives here.
@Component({
  selector: 'op-pmo-dashboard-widget',
  templateUrl: './pmo-dashboard-widget.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
  standalone: false,
})
export class WidgetPmoDashboardComponent extends AbstractTurboWidgetComponent {
  override frameId = 'grids-widgets-pmo-dashboard';

  override name = 'pmo_dashboard';
}
