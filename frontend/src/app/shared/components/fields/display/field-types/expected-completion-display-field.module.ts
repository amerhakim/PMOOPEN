import { DisplayField } from 'core-app/shared/components/fields/display/display-field.module';

export class ExpectedCompletionDisplayField extends DisplayField {
  protected get attribute() {
    const raw = this.resource[this.name];

    if (raw === null || raw === undefined) {
      return null;
    }

    return `${raw}%`;
  }
}
