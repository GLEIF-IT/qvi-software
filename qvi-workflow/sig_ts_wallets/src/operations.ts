import type {
    CompletedOperation,
    FailedOperation,
    KeyState,
    Operation,
    PendingOperation,
    SignifyClient,
} from 'signify-ts';
import {
    LOCAL_OPERATION_POLLING,
    workflowTimeoutMs,
} from './retry.ts';

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

/**
 * Polls a KERIA operation until it completes.
 *
 * Operations remain available to KERIA until the demonstration tears down its
 * Compose volumes.
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
        .wait(resolvedOperation, {
            signal: waitSignal,
            ...LOCAL_OPERATION_POLLING,
        });
    return requireCompletedOperation(completed);
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
