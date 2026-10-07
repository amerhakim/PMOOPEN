import { DisplayField } from 'core-app/shared/components/fields/display/display-field.module';
import { WorkPackageResource } from 'core-app/features/hal/resources/work-package-resource';
import { WorkPackageRelationsService } from 'core-app/features/work-packages/components/wp-relations/wp-relations.service';
import { IFieldSchema } from 'core-app/shared/components/fields/field.base';
import { formatSuccessorsList } from './predecessors-format';

export class SuccessorsDisplayField extends DisplayField<WorkPackageResource> {
  private get wpRelations():WorkPackageRelationsService {
    return this.injector.get(WorkPackageRelationsService);
  }

  public apply(resource:WorkPackageResource, schema:IFieldSchema) {
    super.apply(resource, schema);

    // Relations may not be loaded yet for this row; kick off a fetch so
    // later renders (e.g. after the user scrolls back) show the value.
    // The current render intentionally does not await this: the fast-table
    // cell rendering is synchronous.
    void this.wpRelations.require(resource.id!);
  }

  protected get attribute() {
    const relations = this.wpRelations.state(this.resource.id!).value;
    return formatSuccessorsList(this.resource, relations);
  }
}
