import type {
    CompletedOperation,
    FailedOperation,
    KeyState,
    Operation,
    PendingOperation,
    SignifyClient,
} from 'signify-ts';
import {workflowTimeoutMs} from './retry.ts';

const MAX_EVIDENCE_STRING_LENGTH = 512;

export interface OperationResultIdentity {
    kind:
        | 'event'
        | 'credential'
        | 'registry-anchor'
        | 'text'
        | 'object'
        | 'array'
        | 'null'
        | 'scalar';
    said?: string;
    prefix?: string;
    sequence?: string;
    schema?: string;
    route?: string;
}

export interface OperationEvidence {
    name: string;
    done: true;
    result: OperationResultIdentity;
}

export type ThreeMemberOperationNames = [
    firstMember: string,
    secondMember: string,
    thirdMember: string,
];

export function validateThreeMemberOperationNames(
    operationNames: readonly string[],
    operationDescription: string
): ThreeMemberOperationNames {
    const hasOneOperationPerMember = operationNames.length === 3;
    const everyOperationHasAName = operationNames.every(
        (name) => name.length > 0
    );
    const operationsNameTheSameGroupEvent =
        new Set(operationNames).size === 1;
    const operationSetIsValid =
        hasOneOperationPerMember &&
        everyOperationHasAName &&
        operationsNameTheSameGroupEvent;
    if (operationSetIsValid === false) {
        throw new Error(
            `${operationDescription} requires three matching ` +
            'member-scoped operation names'
        );
    }

    return [
        operationNames[0],
        operationNames[1],
        operationNames[2],
    ];
}

export function isPendingOperation(
    operation: Operation
): operation is PendingOperation {
    return operation.done === false;
}

export function isFailedOperation(
    operation: Operation
): operation is FailedOperation {
    const operationIsDone = operation.done === true;
    const operationHasError =
        'error' in operation && operation.error !== null;
    return operationIsDone && operationHasError;
}

export function isCompletedOperation(
    operation: Operation
): operation is CompletedOperation {
    const operationIsDone = operation.done === true;
    const operationHasResponse = 'response' in operation;
    const operationFailed = isFailedOperation(operation);
    return (
        operationIsDone &&
        operationHasResponse &&
        operationFailed === false
    );
}

function failedOperationError(operation: FailedOperation): Error {
    const detailsArePresent =
        operation.error.details !== undefined &&
        operation.error.details !== null;
    const details = detailsArePresent
        ? ` Details: ${JSON.stringify(operation.error.details)}`
        : '';
    return new Error(
        `Operation '${operation.name}' failed [Code ${operation.error.code}]: ${operation.error.message}${details}`
    );
}

function requireCompletedOperation(
    operation: Operation
): CompletedOperation {
    const operationFailed = isFailedOperation(operation);
    if (operationFailed) {
        throw failedOperationError(operation);
    }

    const operationCompleted = isCompletedOperation(operation);
    if (operationCompleted === false) {
        throw new Error(
            `Operation '${operation.name}' returned without reaching a completed state`
        );
    }
    return operation;
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function nonemptyString(value: unknown): string | undefined {
    const valueIsUsable =
        typeof value === 'string' &&
        value.length > 0 &&
        value.length <= MAX_EVIDENCE_STRING_LENGTH;
    return valueIsUsable ? value : undefined;
}

function sequenceString(value: unknown): string | undefined {
    const valueIsString =
        typeof value === 'string' &&
        value.length > 0 &&
        value.length <= MAX_EVIDENCE_STRING_LENGTH;
    if (valueIsString) {
        return value;
    }
    const valueIsNumber =
        typeof value === 'number' && Number.isSafeInteger(value);
    return valueIsNumber ? String(value) : undefined;
}

function eventIdentity(
    event: Record<string, unknown>,
    kind: 'event' | 'credential'
): OperationResultIdentity | undefined {
    const said = nonemptyString(event.d);
    const eventHasNoSaid = said === undefined;
    if (eventHasNoSaid) {
        return undefined;
    }

    const identity: OperationResultIdentity = {kind, said};
    const prefix = nonemptyString(event.i);
    const sequenceOrSchema = sequenceString(event.s);
    const route = nonemptyString(event.r);
    if (prefix !== undefined) {
        identity.prefix = prefix;
    }
    if (sequenceOrSchema !== undefined) {
        if (kind === 'credential') {
            identity.schema = sequenceOrSchema;
        } else {
            identity.sequence = sequenceOrSchema;
        }
    }
    if (route !== undefined) {
        identity.route = route;
    }
    return identity;
}

/**
 * Projects a completed operation response onto a small protocol identity.
 *
 * KERIA operation responses can contain complete events and credentials.
 * Proof output needs enough identity to correlate the terminal result, not a
 * copy of the full response. In particular, operation metadata is excluded
 * because some operation types contain challenge words.
 */
export function operationResultIdentity(
    response: unknown
): OperationResultIdentity {
    if (response === null) {
        return {kind: 'null'};
    }
    if (Array.isArray(response)) {
        return {kind: 'array'};
    }
    const responseIsRecord = isRecord(response);
    if (responseIsRecord) {
        const directEvent = eventIdentity(response, 'event');
        if (directEvent !== undefined) {
            return directEvent;
        }

        const credential = response.ced;
        if (isRecord(credential)) {
            const credentialIdentity =
                eventIdentity(credential, 'credential');
            if (credentialIdentity !== undefined) {
                return credentialIdentity;
            }
        }

        const exchange = response.exn;
        if (isRecord(exchange)) {
            const exchangeIdentity =
                eventIdentity(exchange, 'event');
            if (exchangeIdentity !== undefined) {
                return exchangeIdentity;
            }
        }

        const anchor = response.anchor;
        if (isRecord(anchor)) {
            const said = nonemptyString(anchor.d);
            const prefix =
                nonemptyString(anchor.pre) ??
                nonemptyString(anchor.i);
            const sequence =
                sequenceString(anchor.sn) ??
                sequenceString(anchor.s);
            const anchorIsComplete =
                said !== undefined &&
                prefix !== undefined &&
                sequence !== undefined;
            if (anchorIsComplete) {
                return {
                    kind: 'registry-anchor',
                    said,
                    prefix,
                    sequence,
                };
            }
        }
        return {kind: 'object'};
    }
    if (typeof response === 'string') {
        return {kind: 'text'};
    }
    return {kind: 'scalar'};
}

export function completedOperationEvidence(
    operation: Operation
): OperationEvidence {
    const completed = requireCompletedOperation(operation);
    const operationNameIsMissing =
        typeof completed.name !== 'string' ||
        completed.name.length === 0 ||
        completed.name.length > MAX_EVIDENCE_STRING_LENGTH;
    if (operationNameIsMissing) {
        throw new Error('Completed operation has no name');
    }
    return {
        name: completed.name,
        done: true,
        result: operationResultIdentity(completed.response),
    };
}

/**
 * Polls a KERIA operation until it completes.
 *
 * Operations are intentionally retained. The workflow records their
 * structured result before its private runtime volume is removed.
 */
export async function waitOperation(
    client: SignifyClient,
    operation: Operation | string,
    signal?: AbortSignal
): Promise<CompletedOperation> {
    const resolvedOperation =
        typeof operation === 'string'
            ? await client.operations().get(operation)
            : operation;
    const operationName = resolvedOperation.name;

    const operationFailed = isFailedOperation(resolvedOperation);
    if (operationFailed) {
        throw failedOperationError(resolvedOperation);
    }

    const operationCompleted =
        isCompletedOperation(resolvedOperation);
    if (operationCompleted) {
        return resolvedOperation;
    }

    const operationPending = isPendingOperation(resolvedOperation);
    if (operationPending === false) {
        throw new Error(
            `Operation '${operationName}' has an unrecognized state`
        );
    }

    const waitSignal =
        signal ?? AbortSignal.timeout(workflowTimeoutMs());
    waitSignal.throwIfAborted();

    const completed = await client
        .operations()
        .wait(resolvedOperation, {signal: waitSignal});
    return requireCompletedOperation(completed);
}

export async function waitOperationEvidence(
    client: SignifyClient,
    operation: Operation | string,
    signal?: AbortSignal
): Promise<OperationEvidence> {
    const completed = await waitOperation(client, operation, signal);
    return completedOperationEvidence(completed);
}

function isKeyState(value: unknown): value is KeyState {
    if (typeof value !== 'object' || value === null) {
        return false;
    }
    const candidate = value as Record<string, unknown>;
    return (
        typeof candidate.i === 'string' &&
        typeof candidate.s === 'string' &&
        typeof candidate.d === 'string'
    );
}

export async function waitKeyStateOperation(
    client: SignifyClient,
    operation: Operation | string,
    signal?: AbortSignal
): Promise<KeyState> {
    const completed = await waitOperation(client, operation, signal);
    return requireOperationResponse(
        completed,
        isKeyState,
        'Key-state query'
    );
}

export function requireOperationResponse<T>(
    operation: CompletedOperation,
    isExpectedResponse: (value: unknown) => value is T,
    operationDescription: string
): T {
    const operationHasResponse = 'response' in operation;
    if (operationHasResponse === false) {
        throw new Error(
            `${operationDescription} completed without a response`
        );
    }

    const response = operation.response;
    const responseHasExpectedShape = isExpectedResponse(response);
    if (responseHasExpectedShape === false) {
        throw new Error(
            `${operationDescription} returned an unexpected response`
        );
    }

    return response;
}
