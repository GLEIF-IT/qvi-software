import {readFileSync} from 'node:fs';

import {TestEnvironmentPreset} from "../resolve-env";
import {parseAidInfo} from '../create-aid.ts';
import {refreshGedaMultisigstate} from "../qvi-operations.ts";
import {
    validateThreeMemberOperationNames,
    type OperationEvidence,
} from '../operations.ts';
import type {NotificationReference} from '../notifications.ts';
import {
    completePersistedCoordinatedOperations,
} from '../coordinated-operation.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {QVI_INITIAL_SEQUENCE} from '../qvi-configuration.ts';
import {
    assertTerminalOperationEvidence,
    canonicalOperationEvidence,
} from '../workflow-contracts.ts';

type MemberScopedInceptionOperations = [
    qar1: string,
    qar2: string,
    qar3: string,
];

export interface MemberInceptionCoordination {
    memberPrefix: string;
    notifications: NotificationReference[];
}

interface InceptionCompletionArtifact {
    msPrefix: string;
    operationNames: string[];
    coordinationNotifications: MemberInceptionCoordination[];
}

export function validateMemberScopedInceptionOperations(
    operationNames: string[]
): MemberScopedInceptionOperations {
    return validateThreeMemberOperationNames(
        operationNames,
        'Delegated inception completion'
    );
}

/**
 * Finish KERIA+Signify multisig inception by refreshing keystate to discover the delegation seal and
 * then proving the delegator key state is available.
 * @param aidInfoArg
 * @param gedaPrefix
 * @param environment
 */
export async function completeMultisigIncept(
    aidInfoArg: string,
    gedaPrefix: string,
    environment: TestEnvironmentPreset,
    inceptionOperationNames: string[] = [],
    coordinationNotifications: MemberInceptionCoordination[] = []
): Promise<OperationEvidence[]> {

    const clients = await refreshGedaMultisigstate(
        aidInfoArg,
        gedaPrefix,
        environment
    );
    const noInceptionOperationsWereProvided =
        inceptionOperationNames.length === 0;
    if (noInceptionOperationsWereProvided) {
        return [];
    }
    const memberOperations =
        validateMemberScopedInceptionOperations(inceptionOperationNames);
    const memberClients = [
        clients.QAR1Client,
        clients.QAR2Client,
        clients.QAR3Client,
    ];
    const persistedCoordination: NotificationReference[][] =
        [[], [], []];

    const coordinationWasRecorded =
        coordinationNotifications.length > 0;
    if (coordinationWasRecorded) {
        const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfoArg);
        const memberAids = await Promise.all([
            clients.QAR1Client.identifiers().get(QAR1.name),
            clients.QAR2Client.identifiers().get(QAR2.name),
            clients.QAR3Client.identifiers().get(QAR3.name),
        ]);
        const expectedPrefixes = memberAids.map(
            (member) => member.prefix
        );
        const observedPrefixes = coordinationNotifications.map(
            (coordination) => coordination.memberPrefix
        );
        const exactMemberSetWasRecorded =
            coordinationNotifications.length === 3 &&
            new Set(observedPrefixes).size === 3 &&
            expectedPrefixes.every((prefix) =>
                observedPrefixes.includes(prefix)
            );
        if (exactMemberSetWasRecorded === false) {
            throw new Error(
                'Delegated inception coordination does not match the three QAR members'
            );
        }

        for (let index = 0; index < memberClients.length; index++) {
            const memberCoordination =
                coordinationNotifications.find(
                    ({memberPrefix}) =>
                        memberPrefix === expectedPrefixes[index]
                );
            if (memberCoordination === undefined) {
                throw new Error(
                    `Delegated inception coordination is missing ${expectedPrefixes[index]}`
                );
            }
            persistedCoordination[index] =
                memberCoordination.notifications;
        }
    }

    return completePersistedCoordinatedOperations(
        memberClients.map((client, index) => ({
            client,
            result: {
                operation: memberOperations[index],
                coordination: persistedCoordination[index],
            },
        }))
    );
}

function readInceptionCompletionArtifact(
    artifactPath: string | undefined
): InceptionCompletionArtifact {
    const artifactWasNotProvided = artifactPath === undefined;
    if (artifactWasNotProvided) {
        return {
            msPrefix: '',
            operationNames: [],
            coordinationNotifications: [],
        };
    }

    let artifact: unknown;
    try {
        artifact = JSON.parse(
            readFileSync(artifactPath, 'utf8')
        ) as unknown;
    } catch (error: unknown) {
        throw new Error(
            `Unable to read delegated inception artifact ${artifactPath}`,
            {cause: error}
        );
    }
    const artifactIsNotAnObject =
        typeof artifact !== 'object' || artifact === null;
    if (artifactIsNotAnObject) {
        throw new Error(
            'Delegated inception artifact must be a JSON object'
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
            'Delegated inception artifact has no valid operationNames array'
        );
    }
    const msPrefix = (
        artifact as Record<string, unknown>
    ).msPrefix;
    const multisigPrefixIsInvalid =
        typeof msPrefix !== 'string' || msPrefix.length === 0;
    if (multisigPrefixIsInvalid) {
        throw new Error(
            'Delegated inception artifact has no valid msPrefix'
        );
    }
    const coordinationNotifications = (
        artifact as Record<string, unknown>
    ).coordinationNotifications;
    const coordinationIsMissing =
        coordinationNotifications === undefined;
    if (coordinationIsMissing) {
        return {
            msPrefix,
            operationNames: operationNames as string[],
            coordinationNotifications: [],
        };
    }
    const coordinationIsInvalid =
        Array.isArray(coordinationNotifications) === false ||
        coordinationNotifications.some((entry) => {
            const entryIsInvalid =
                typeof entry !== 'object' ||
                entry === null;
            if (entryIsInvalid) {
                return true;
            }
            const record = entry as Record<string, unknown>;
            const notifications = record.notifications;
            const notificationsAreInvalid =
                Array.isArray(notifications) === false ||
                notifications.some((notification) => {
                    const notificationIsInvalid =
                        typeof notification !== 'object' ||
                        notification === null;
                    if (notificationIsInvalid) {
                        return true;
                    }
                    const notificationRecord =
                        notification as Record<string, unknown>;
                    const ids =
                        notificationRecord.notificationIds;
                    return (
                        Array.isArray(ids) === false ||
                        ids.length === 0 ||
                        ids.some(
                            (id) =>
                                typeof id !== 'string' ||
                                id.length === 0
                        ) ||
                        new Set(ids).size !== ids.length
                    );
                });
            return (
                typeof record.memberPrefix !== 'string' ||
                record.memberPrefix.length === 0 ||
                notificationsAreInvalid
            );
        });
    if (coordinationIsInvalid) {
        throw new Error(
            'Delegated inception artifact has invalid coordinationNotifications'
        );
    }
    return {
        msPrefix,
        operationNames: operationNames as string[],
        coordinationNotifications:
            coordinationNotifications as MemberInceptionCoordination[],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'geda-prefix', 'operation-artifact'],
            ['environment', 'participant-source', 'geda-prefix']
        );
        requireNamedArguments(parsed, ['geda-prefix']);
        const invocation = participantInvocationFromArguments(parsed);
        const inception = readInceptionCompletionArtifact(
            parsed['operation-artifact']
        );
        const operationEvidence = await completeMultisigIncept(
            invocation.participantSource,
            parsed['geda-prefix'],
            invocation.environment,
            inception.operationNames,
            inception.coordinationNotifications
        );
        const operationWasProvided =
            inception.operationNames.length > 0;
        if (operationWasProvided) {
            assertTerminalOperationEvidence(
                operationEvidence,
                Array.from({length: 3}, () => ({
                    name: `group.${inception.msPrefix}`,
                    result: {
                        kind: 'event',
                        said: inception.msPrefix,
                        prefix: inception.msPrefix,
                        sequence: QVI_INITIAL_SEQUENCE,
                    },
                })),
                'Delegated inception completion'
            );
        }
        return {
            status: 'completed',
            gedaPrefix: parsed['geda-prefix'],
            qviPrefix: inception.msPrefix,
            operationEvidence:
                canonicalOperationEvidence(operationEvidence),
        };
    });
}
