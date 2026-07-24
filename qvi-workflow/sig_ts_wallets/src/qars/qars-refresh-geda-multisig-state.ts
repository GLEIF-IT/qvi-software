import {readFileSync} from 'node:fs';

import type {SignifyClient} from 'signify-ts';

import {refreshGedaMultisigstate} from "../qvi-operations.ts";
import {
    completePersistedCoordinatedOperationsWithValidation,
} from '../coordinated-operation.ts';
import type {NotificationReference} from '../notifications.ts';
import {
    validateThreeMemberOperationNames,
    type OperationEvidence,
} from '../operations.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

interface RotationMemberClients {
    QAR1Client: SignifyClient;
    QAR2Client: SignifyClient;
    QAR3Client: SignifyClient;
}

interface RotationNotificationReferences {
    qar2: NotificationReference;
    qar3: NotificationReference;
}

export interface RotationGroupStateEvidence {
    prefix: string;
    sequence: '1';
    establishmentDigest: string;
    observerCount: 3;
}

export interface MemberRotationCompletionEvidence {
    operationEvidence: OperationEvidence[];
    groupState: RotationGroupStateEvidence;
}

export interface CompleteMemberRotationRequest {
    clients: RotationMemberClients;
    operationNames: readonly string[];
    references: RotationNotificationReferences;
    groupName: string;
    expectedQviPrefix: string;
}

interface RotationSubmissionEvidence {
    operationNames: string[];
    notificationReferences: RotationNotificationReferences;
}

function assertRotationOperationEvidence(
    operationEvidence: readonly OperationEvidence[],
    expectedQviPrefix: string
): string {
    const hasOneResultPerMember =
        operationEvidence.length === 3;
    const everyResultIsTheExpectedRotation =
        operationEvidence.every((evidence) => {
            const result = evidence.result;
            const resultHasSaid =
                typeof result.said === 'string' &&
                result.said.length > 0;
            const resultMatchesExpectedEvent =
                result.kind === 'event' &&
                result.prefix === expectedQviPrefix &&
                result.sequence === '1' &&
                resultHasSaid;
            const operationMatchesEvent =
                resultHasSaid &&
                evidence.name === `group.${result.said}`;
            return (
                evidence.done === true &&
                resultMatchesExpectedEvent &&
                operationMatchesEvent
            );
        });
    const resultSaids = operationEvidence
        .map((evidence) => evidence.result.said)
        .filter((said): said is string => said !== undefined);
    const everyMemberObservedTheSameEvent =
        resultSaids.length === 3 &&
        new Set(resultSaids).size === 1;
    const rotationEvidenceIsValid =
        hasOneResultPerMember &&
        everyResultIsTheExpectedRotation &&
        everyMemberObservedTheSameEvent;
    if (rotationEvidenceIsValid === false) {
        throw new Error(
            'Delegated rotation requires three matching QVI event results ' +
            `for prefix ${expectedQviPrefix} at sequence 1`
        );
    }

    return resultSaids[0];
}

async function readConvergedRotationGroupState(
    clients: RotationMemberClients,
    groupName: string,
    expectedQviPrefix: string,
    expectedEventSaid: string
): Promise<RotationGroupStateEvidence> {
    const memberGroups = await Promise.all([
        clients.QAR1Client.identifiers().get(groupName),
        clients.QAR2Client.identifiers().get(groupName),
        clients.QAR3Client.identifiers().get(groupName),
    ]);
    const everyMemberObservedExpectedState =
        memberGroups.every((group) => {
            const establishmentDigest = group.state.ee.d;
            return (
                group.prefix === expectedQviPrefix &&
                group.state.s === '1' &&
                establishmentDigest === expectedEventSaid
            );
        });
    if (everyMemberObservedExpectedState === false) {
        throw new Error(
            'Delegated rotation group state does not converge on ' +
            `${expectedQviPrefix} sequence 1 event ${expectedEventSaid}`
        );
    }

    return {
        prefix: expectedQviPrefix,
        sequence: '1',
        establishmentDigest: expectedEventSaid,
        observerCount: 3,
    };
}

export async function completeMemberRotationOperations(
    request: CompleteMemberRotationRequest
): Promise<MemberRotationCompletionEvidence> {
    const {
        clients,
        operationNames,
        references,
        groupName,
        expectedQviPrefix,
    } = request;
    const memberOperations = validateThreeMemberOperationNames(
        operationNames,
        'Delegated rotation completion'
    );

    const completion =
        await completePersistedCoordinatedOperationsWithValidation(
            [
                {
                    client: clients.QAR1Client,
                    result: {
                        operation: memberOperations[0],
                        coordination: [],
                    },
                },
                {
                    client: clients.QAR2Client,
                    result: {
                        operation: memberOperations[1],
                        coordination: [references.qar2],
                    },
                },
                {
                    client: clients.QAR3Client,
                    result: {
                        operation: memberOperations[2],
                        coordination: [references.qar3],
                    },
                },
            ],
            async (operationEvidence) => {
                const eventSaid =
                    assertRotationOperationEvidence(
                        operationEvidence,
                        expectedQviPrefix
                    );
                return readConvergedRotationGroupState(
                    clients,
                    groupName,
                    expectedQviPrefix,
                    eventSaid
                );
            },
        );

    return {
        operationEvidence: completion.operationEvidence,
        groupState: completion.validatedState,
    };
}

function notificationReferenceFromArtifact(
    value: unknown,
    member: 'qar2' | 'qar3'
): NotificationReference {
    const referenceIsNotAnObject =
        typeof value !== 'object' || value === null;
    if (referenceIsNotAnObject) {
        throw new Error(
            `Delegated rotation artifact has no ${member} notification reference`
        );
    }

    const notificationIds = (
        value as Record<string, unknown>
    ).notificationIds;
    const notificationIdsAreInvalid =
        Array.isArray(notificationIds) === false ||
        notificationIds.length === 0 ||
        notificationIds.some(
            (id) => typeof id !== 'string' || id.length === 0
        ) ||
        new Set(notificationIds).size !== notificationIds.length;
    if (notificationIdsAreInvalid) {
        throw new Error(
            `Delegated rotation artifact has invalid ${member} notification IDs`
        );
    }

    return {
        notificationIds: notificationIds as string[],
    };
}

function readRotationSubmissionEvidence(
    artifactPath: string | undefined
): RotationSubmissionEvidence | undefined {
    const artifactWasNotProvided = artifactPath === undefined;
    if (artifactWasNotProvided) {
        return undefined;
    }

    let artifact: unknown;
    try {
        artifact = JSON.parse(
            readFileSync(artifactPath, 'utf8')
        ) as unknown;
    } catch (error: unknown) {
        throw new Error(
            `Unable to read delegated rotation artifact ${artifactPath}`,
            {cause: error}
        );
    }

    const artifactIsNotAnObject =
        typeof artifact !== 'object' || artifact === null;
    if (artifactIsNotAnObject) {
        throw new Error(
            'Delegated rotation artifact must be a JSON object'
        );
    }

    const operationNames = (
        artifact as Record<string, unknown>
    ).operationNames;
    const operationNamesAreInvalid =
        Array.isArray(operationNames) === false ||
        operationNames.some(
            (name) =>
                typeof name !== 'string' ||
                name.length === 0
        );
    if (operationNamesAreInvalid) {
        throw new Error(
            'Delegated rotation artifact has no valid operationNames array'
        );
    }

    const notificationReferences = (
        artifact as Record<string, unknown>
    ).notificationReferences;
    const referencesAreNotAnObject =
        typeof notificationReferences !== 'object' ||
        notificationReferences === null;
    if (referencesAreNotAnObject) {
        throw new Error(
            'Delegated rotation artifact has no notification references'
        );
    }
    const references =
        notificationReferences as Record<string, unknown>;

    return {
        operationNames: operationNames as string[],
        notificationReferences: {
            qar2: notificationReferenceFromArtifact(
                references.qar2,
                'qar2'
            ),
            qar3: notificationReferenceFromArtifact(
                references.qar3,
                'qar3'
            ),
        },
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            [
                'config',
                'geda-prefix',
                'operation-artifact',
                'group-name',
                'qvi-prefix',
            ],
            ['environment', 'participant-source', 'geda-prefix']
        );
        requireNamedArguments(parsed, ['geda-prefix']);
        const invocation = participantInvocationFromArguments(parsed);
        const clients = await refreshGedaMultisigstate(
            invocation.participantSource,
            parsed['geda-prefix'],
            invocation.environment
        );
        const rotationSubmission = readRotationSubmissionEvidence(
            parsed['operation-artifact']
        );
        const hasRotationSubmission =
            rotationSubmission !== undefined;
        if (hasRotationSubmission) {
            requireNamedArguments(parsed, [
                'group-name',
                'qvi-prefix',
            ]);
        }
        const rotationCompletion = hasRotationSubmission
            ? await completeMemberRotationOperations(
                {
                    clients,
                    operationNames:
                        rotationSubmission.operationNames,
                    references:
                        rotationSubmission.notificationReferences,
                    groupName: parsed['group-name'],
                    expectedQviPrefix: parsed['qvi-prefix'],
                }
            )
            : undefined;
        return {
            status: 'refreshed',
            gedaPrefix: parsed['geda-prefix'],
            operationEvidence:
                rotationCompletion?.operationEvidence ?? [],
            ...(rotationCompletion === undefined
                ? {}
                : {groupState: rotationCompletion.groupState}),
        };
    });
}
