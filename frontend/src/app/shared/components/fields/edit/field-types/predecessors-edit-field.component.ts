import { ChangeDetectionStrategy, Component } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { EditFieldComponent } from 'core-app/shared/components/fields/edit/edit-field.component';
import { WorkPackageResource } from 'core-app/features/hal/resources/work-package-resource';
import { WorkPackageRelationsService } from 'core-app/features/work-packages/components/wp-relations/wp-relations.service';
import { ApiV3Service } from 'core-app/core/apiv3/api-v3.service';
import { HalResourceService } from 'core-app/features/hal/services/hal-resource.service';
import { RelationResource } from 'core-app/features/hal/resources/relation-resource';
import isNewResource from 'core-app/features/hal/helpers/is-new-resource';
import {
  formatPredecessorsList,
  parsePredecessorsText,
  predecessorRelationsOf,
} from 'core-app/shared/components/fields/display/field-types/predecessors-format';

@Component({
  templateUrl: './predecessors-edit-field.component.html',
  standalone: false,
  // eslint-disable-next-line @angular-eslint/prefer-on-push-component-change-detection
  changeDetection: ChangeDetectionStrategy.Eager,
})
export class PredecessorsEditFieldComponent extends EditFieldComponent {
  public text = '';

  public errorMessage:string|null = null;

  private get wpRelations():WorkPackageRelationsService {
    return this.injector.get(WorkPackageRelationsService);
  }

  private get apiV3Service():ApiV3Service {
    return this.injector.get(ApiV3Service);
  }

  private get halResource():HalResourceService {
    return this.injector.get(HalResourceService);
  }

  private get workPackage():WorkPackageResource {
    return this.resource as WorkPackageResource;
  }

  protected initialize():void {
    this.handler.registerOnSubmit(() => this.save());

    // A not-yet-saved work package has no relations to fetch, and the API
    // rejects a non-integer "involved" filter (its placeholder id is the
    // literal string 'new') -- skip the request rather than leaving this
    // field (and the surrounding form) stuck waiting on the failed load.
    if (isNewResource(this.workPackage)) {
      return;
    }

    void this.wpRelations.require(this.workPackage.id!).then((relations) => {
      this.text = formatPredecessorsList(this.workPackage, relations);
    });
  }

  public async onEnter(event:Event):Promise<void> {
    event.preventDefault();
    event.stopPropagation();

    try {
      await this.save();
      this.handler.deactivate(true);
    } catch {
      // Error already surfaced via handler.setErrors(); keep editing open
      // so the user can fix the input.
    }
  }

  private async save():Promise<void> {
    this.errorMessage = null;

    let desired;
    try {
      desired = parsePredecessorsText(this.text);
    } catch (error) {
      const message = (error as Error).message;
      this.errorMessage = message;
      this.handler.setErrors([message]);
      return Promise.reject(error);
    }

    // A not-yet-saved work package has no id to create/fetch relations
    // against yet, so there is nothing this field can persist as part of
    // the initial creation. Predecessors typed here before the work
    // package exists can't be linked -- surface that rather than silently
    // dropping them or failing the whole form on the "involved" lookup
    // below (which requires a real, integer work package id).
    if (isNewResource(this.workPackage)) {
      if (desired.length > 0) {
        const message = 'Predecessors can only be added after the work package has been created.';
        this.errorMessage = message;
        this.handler.setErrors([message]);
        return Promise.reject(new Error(message));
      }
      return;
    }

    const relations = await this.wpRelations.require(this.workPackage.id!, true);
    const current = predecessorRelationsOf(this.workPackage, relations);

    const currentById = new Map(
      current.map((relation) => [relation.denormalized(this.workPackage).targetId, relation]),
    );
    const desiredById = new Map(desired.map((entry) => [entry.id, entry]));

    const toRemove = current.filter(
      (relation) => !desiredById.has(relation.denormalized(this.workPackage).targetId),
    );
    const toCreate = desired.filter((entry) => !currentById.has(entry.id));
    const toUpdate = desired
      .filter((entry) => currentById.has(entry.id))
      .map((entry) => ({ entry, relation: currentById.get(entry.id) as RelationResource }))
      .filter(({ entry, relation }) => (
        entry.scheduleRelationType !== ((relation as any).scheduleRelationType || 'FS')
        || entry.lag !== ((relation as any).lag || 0)
      ));

    try {
      // Creates/updates run first, and removals only after those succeed:
      // if a create is rejected (e.g. an invalid parent/child pairing), we
      // must not have already deleted a perfectly valid existing relation
      // as a side effect of running everything concurrently.
      await Promise.all([
        ...toUpdate.map(({ entry, relation }) => this.wpRelations.updateRelation(relation, {
          scheduleRelationType: entry.scheduleRelationType,
          lag: entry.lag,
        })),
        ...toCreate.map((entry) => this.createPredecessor(entry.id, entry.scheduleRelationType, entry.lag)),
      ]);
      await Promise.all(toRemove.map((relation) => this.wpRelations.removeRelation(relation)));
    } catch (error:any) {
      const message:string = error?.message || this.I18n.t('js.error.internal');
      this.errorMessage = message;
      this.handler.setErrors([message]);
      throw error;
    }

    const refreshed = await this.wpRelations.require(this.workPackage.id!, true);
    this.text = formatPredecessorsList(this.workPackage, refreshed);
  }

  private createPredecessor(predecessorId:string, scheduleRelationType:string, lag:number):Promise<RelationResource> {
    const params = {
      _links: {
        from: { href: this.apiV3Service.work_packages.id(this.workPackage.id!).toString() },
        to: { href: this.apiV3Service.work_packages.id(predecessorId).toString() },
      },
      type: 'follows',
      scheduleRelationType,
      lag,
    };

    const path = this.apiV3Service.work_packages.id(this.workPackage.id!).relations.toString();
    return firstValueFrom(this.halResource.post<RelationResource>(path, params));
  }
}
