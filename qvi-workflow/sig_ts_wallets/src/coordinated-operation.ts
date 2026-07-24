import type {Operation, SignifyClient} from 'signify-ts';

import {
    consumeNotificationReference,
    notificationReference,
    type MatchedNotification,
    type NotificationReference,
} from './notifications.ts';
import {
    waitOperationEvidence,
    type OperationEvidence,
} from './operations.ts';

export interface CoordinatedOperation {
    operation: Operation | string;
    coordination: MatchedNotification[];
}

export interface MemberCoordinatedOperation {
    client: SignifyClient;
    result: CoordinatedOperation;
}

export interface PersistedCoordinatedOperation {
    operation: Operation | string;
    coordination: NotificationReference[];
}

export interface MemberPersistedCoordinatedOperation {
    client: SignifyClient;
    result: PersistedCoordinatedOperation;
}

export interface CoordinatedCompletion<TValidatedState> {
    operationEvidence: OperationEvidence[];
    validatedState: TValidatedState;
}

export type DependentStateValidator<TValidatedState> = (
    operationEvidence: OperationEvidence[]
) => Promise<TValidatedState>;

/**
 * Completes a batch of member-scoped operations before consuming any of the
 * notifications that coordinated them.
 *
 * Waiting is deliberately a separate phase from consumption. If any member
 * operation fails or times out, every coordination notice remains available
 * for diagnosis and a safe retry.
 */
export async function completeCoordinatedOperations(
    members: MemberCoordinatedOperation[]
): Promise<OperationEvidence[]> {
    const completion =
        await completeCoordinatedOperationsWithValidation(
            members,
            async () => undefined
        );
    return completion.operationEvidence;
}

/**
 * Completes all member operations, validates their dependent protocol state,
 * and only then consumes the notifications that coordinated the operations.
 *
 * The validation callback is part of the success boundary. If an operation
 * fails, a dependent result does not materialize, or validation rejects
 * divergent state, no coordination notice is consumed.
 */
export async function completeCoordinatedOperationsWithValidation<
    TValidatedState,
>(
    members: MemberCoordinatedOperation[],
    validateDependentState: DependentStateValidator<TValidatedState>
): Promise<CoordinatedCompletion<TValidatedState>> {
    return completePersistedCoordinatedOperationsWithValidation(
        members.map(({client, result}) => ({
            client,
            result: {
                operation: result.operation,
                coordination: result.coordination.map(
                    notificationReference
                ),
            },
        })),
        validateDependentState
    );
}

/**
 * Completes operations whose minimal notification references crossed a
 * process boundary, such as delegated inception or rotation.
 */
export async function completePersistedCoordinatedOperations(
    members: MemberPersistedCoordinatedOperation[]
): Promise<OperationEvidence[]> {
    const completion =
        await completePersistedCoordinatedOperationsWithValidation(
            members,
            async () => undefined
        );
    return completion.operationEvidence;
}

export async function completePersistedCoordinatedOperationsWithValidation<
    TValidatedState,
>(
    members: MemberPersistedCoordinatedOperation[],
    validateDependentState: DependentStateValidator<TValidatedState>
): Promise<CoordinatedCompletion<TValidatedState>> {
    const operationEvidence = await Promise.all(
        members.map(({client, result}) =>
            waitOperationEvidence(client, result.operation)
        )
    );
    const validatedState = await validateDependentState(
        operationEvidence
    );

    for (const {client, result} of members) {
        for (const notification of result.coordination) {
            await consumeNotificationReference(client, notification);
        }
    }

    return {
        operationEvidence,
        validatedState,
    };
}
