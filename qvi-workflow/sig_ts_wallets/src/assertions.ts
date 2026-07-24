import {
    connectClient,
    connectParticipants,
    getAid,
    type WorkflowConfig,
    type ParticipantRole,
} from './client.ts';
import {
    credentialSnapshot,
    getCredential,
    type CredentialSnapshot,
} from './credential-state.ts';
import {
    readGroupObservation,
    type GroupStateSnapshot,
} from './group-state.ts';
import {
    assertCredentialConvergence,
    assertGroupStateConvergence,
} from './workflow-assertions.ts';

export interface ExpectedCredentialState {
    credentialSaid: string;
    issuerPrefix: string;
    schema: string;
    issueePrefix: string;
    statusSequence: string;
}

/** Assert exact QVI KEL, signing-roster, next-roster, and observer convergence. */
export async function assertGroupConvergence(
    config: WorkflowConfig,
    options: {
        groupPrefix: string;
        delegatorPrefix: string;
        sequence: string;
        observerRoles: ParticipantRole[];
        signingRoles: ParticipantRole[];
        rotationRoles: ParticipantRole[];
        eventSaid?: string;
    }
): Promise<GroupStateSnapshot> {
    const allRoles = [
        ...new Set([
            ...options.observerRoles,
            ...options.signingRoles,
            ...options.rotationRoles,
        ]),
    ];
    const clients = await connectParticipants(config, allRoles);
    const aids = new Map(
        await Promise.all(
            allRoles.map(async (role) => [
                role,
                await getAid(
                    clients.get(role)!,
                    config.participants[role].name
                ),
            ] as const)
        )
    );
    const observations = await Promise.all(
        options.observerRoles.map((role) =>
            readGroupObservation(
                clients.get(role)!,
                aids.get(role)!.prefix,
                config.qvi.name
            )
        )
    );
    const snapshot = assertGroupStateConvergence(observations, {
        prefix: options.groupPrefix,
        delegator: options.delegatorPrefix,
        sequence: options.sequence,
        signingThreshold: config.qvi.signingThreshold,
        nextThreshold: config.qvi.nextThreshold,
        members: options.observerRoles.map(
            (role) => aids.get(role)!.prefix
        ),
        signingMembers: options.signingRoles.map(
            (role) => aids.get(role)!.prefix
        ),
        rotationMembers: options.rotationRoles.map(
            (role) => aids.get(role)!.prefix
        ),
    });
    if (
        options.eventSaid !== undefined &&
        snapshot.establishmentDigest !== options.eventSaid
    ) {
        throw new Error(
            `Group establishment digest ${snapshot.establishmentDigest} does not match ${options.eventSaid}`
        );
    }
    return snapshot;
}

/** Assert credential and TEL convergence across the final QVI member roster. */
export async function assertQviCredentialConvergence(
    config: WorkflowConfig,
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const roles = config.qvi.finalMembers;
    const clients = await connectParticipants(config, roles);
    const snapshots = await Promise.all(
        roles.map(async (role) => {
            const client = clients.get(role)!;
            const aid = await getAid(
                client,
                config.participants[role].name
            );
            return credentialSnapshot(
                await getCredential(client, expected.credentialSaid),
                aid.prefix
            );
        })
    );
    return assertCredentialConvergence(
        snapshots,
        snapshots.map(({observerAid}) => observerAid),
        {
            said: expected.credentialSaid,
            issuer: expected.issuerPrefix,
            schema: expected.schema,
            issuee: expected.issueePrefix,
            statusSequence: expected.statusSequence,
        }
    );
}

/** Assert the holder observes the expected credential and TEL state. */
export async function assertPersonCredentialState(
    config: WorkflowConfig,
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const person = config.participants.person;
    const client = await connectClient(person);
    const aid = await getAid(client, person.name);
    const snapshot = credentialSnapshot(
        await getCredential(client, expected.credentialSaid),
        aid.prefix
    );
    const actual = {
        credentialSaid: snapshot.said,
        issuerPrefix: snapshot.issuer,
        schema: snapshot.schema,
        issueePrefix: snapshot.issuee,
        statusSequence: snapshot.statusSequence,
    };
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        throw new Error(
            `Person credential state ${JSON.stringify(actual)} does not match ${JSON.stringify(expected)}`
        );
    }
    return snapshot;
}
