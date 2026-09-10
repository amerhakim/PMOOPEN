import { WorkPackageResource } from 'core-app/features/hal/resources/work-package-resource';
import { RelationResource } from 'core-app/features/hal/resources/relation-resource';
import { RelationsStateValue } from 'core-app/features/work-packages/components/wp-relations/wp-relations.service';

export const SCHEDULE_RELATION_TYPES = ['FS', 'SS', 'FF', 'SF'];

export interface ParsedPredecessor {
  id:string;
  scheduleRelationType:string;
  lag:number;
}

/**
 * Parses MS-Project-style predecessor text, e.g. "3, 7SS-1, 12FF+2d"
 * into a list of { id, scheduleRelationType, lag }.
 * Throws with a human-readable message on malformed input.
 */
export function parsePredecessorsText(text:string):ParsedPredecessor[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const tokenPattern = /^(\d+)\s*(FS|SS|FF|SF)?\s*([+-]\s*\d+)\s*d?$/i;
  const simplePattern = /^(\d+)\s*(FS|SS|FF|SF)?$/i;

  return trimmed.split(',').map((rawToken) => {
    const token = rawToken.trim();
    if (token.length === 0) {
      throw new Error(`Empty predecessor entry`);
    }

    const withLag = token.match(tokenPattern);
    const withoutLag = token.match(simplePattern);
    const match = withLag || withoutLag;

    if (!match) {
      throw new Error(`"${token}" is not a valid predecessor (expected e.g. "3", "7SS", "12FF+2")`);
    }

    const id = match[1];
    const scheduleRelationType = (match[2] || 'FS').toUpperCase();
    const lagRaw = withLag ? match[3] : undefined;
    const lag = lagRaw ? parseInt(lagRaw.replace(/\s/g, ''), 10) : 0;

    return { id, scheduleRelationType, lag };
  });
}

/**
 * Formats a single predecessor for display/editing, e.g. "7SS-1" or plain "3"
 * for a default FS relation with no lag. Appends the predecessor's project
 * name in parentheses when it differs from the current work package's
 * project, so cross-project predecessors are never ambiguous.
 */
export function formatPredecessor(
  targetId:string,
  scheduleRelationType:string,
  lag:number,
  targetProjectName:string|undefined,
  currentProjectName:string|undefined,
):string {
  let text = targetId;

  if (scheduleRelationType && scheduleRelationType !== 'FS') {
    text += scheduleRelationType;
  }

  if (lag) {
    text += lag > 0 ? `+${lag}` : `${lag}`;
  }

  if (targetProjectName && currentProjectName && targetProjectName !== currentProjectName) {
    text += ` (${targetProjectName})`;
  }

  return text;
}

/**
 * Returns the current `follows` relations of `workPackage` (i.e., its
 * predecessors) from an already-loaded RelationsStateValue.
 */
export function predecessorRelationsOf(
  workPackage:WorkPackageResource,
  relations:RelationsStateValue|undefined,
):RelationResource[] {
  if (!relations) {
    return [];
  }

  return Object.values(relations).filter(
    (relation:RelationResource) => relation.denormalized(workPackage).relationType === 'follows',
  );
}

export function formatPredecessorsList(
  workPackage:WorkPackageResource,
  relations:RelationsStateValue|undefined,
):string {
  const currentProjectName = workPackage.project?.name as string|undefined;

  return predecessorRelationsOf(workPackage, relations)
    .map((relation) => {
      const denormalized = relation.denormalized(workPackage);
      const target = denormalized.target;
      const targetProjectName = target?.project?.name as string|undefined;

      return formatPredecessor(
        denormalized.targetId,
        (relation as any).scheduleRelationType || 'FS',
        (relation as any).lag || 0,
        targetProjectName,
        currentProjectName,
      );
    })
    .join(', ');
}

/**
 * Returns the current `precedes` relations of `workPackage` (i.e., its
 * successors) from an already-loaded RelationsStateValue.
 */
export function successorRelationsOf(
  workPackage:WorkPackageResource,
  relations:RelationsStateValue|undefined,
):RelationResource[] {
  if (!relations) {
    return [];
  }

  return Object.values(relations).filter(
    (relation:RelationResource) => relation.denormalized(workPackage).relationType === 'precedes',
  );
}

export function formatSuccessorsList(
  workPackage:WorkPackageResource,
  relations:RelationsStateValue|undefined,
):string {
  const currentProjectName = workPackage.project?.name as string|undefined;

  return successorRelationsOf(workPackage, relations)
    .map((relation) => {
      const denormalized = relation.denormalized(workPackage);
      const target = denormalized.target;
      const targetProjectName = target?.project?.name as string|undefined;

      return formatPredecessor(
        denormalized.targetId,
        (relation as any).scheduleRelationType || 'FS',
        (relation as any).lag || 0,
        targetProjectName,
        currentProjectName,
      );
    })
    .join(', ');
}
