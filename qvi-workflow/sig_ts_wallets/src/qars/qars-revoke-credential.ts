import {createTimestamp} from '../create-aid.ts';
import {
    credentialSnapshot,
    getCredential,
    type CredentialSnapshot,
} from '../credential-state.ts';
import {revokeCredentialMultisig} from '../credentials.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import type {QviMember} from './qvi-context.ts';

export interface RevokeCredentialOptions {
    members: QviMember[];
    groupName: string;
    credentialSaid: string;
}

export interface RevocationResult {
    status: 'already-revoked' | 'revoked';
    credentialSaid: string;
    qviPrefix: string;
    revocationTelDigest: string;
    revocationTimestamp: string;
}

/** Require one value to agree across all QVI members. */
function commonValue(
    values: string[],
    description: string
): string {
    const first = values[0];
    const valuesAgree =
        first !== undefined &&
        values.every((value) => value === first);
    if (valuesAgree === false) {
        throw new Error(
            `${description} diverged: ${values.join(', ')}`
        );
    }
    return first;
}

/** Require one credential status sequence across all QVI members. */
function commonCredentialStatus(
    snapshots: CredentialSnapshot[]
): string {
    return commonValue(
        snapshots.map(({statusSequence}) => statusSequence),
        'Credential status'
    );
}

/** Revoke one credential and require the new TEL state to converge. */
export async function runRevocation(
    options: RevokeCredentialOptions
): Promise<RevocationResult> {
    const members = options.members;
    const qviPrefix = commonValue(
        members.map(({groupAid}) => groupAid.prefix),
        'QVI prefix'
    );
    const credentials = await Promise.all(
        members.map(({client}) =>
            getCredential(client, options.credentialSaid)
        )
    );
    const before = credentials.map((credential, index) =>
        credentialSnapshot(
            credential,
            members[index].memberAid.prefix
        )
    );
    const beforeStatus = commonCredentialStatus(before);
    if (beforeStatus === '1') {
        return {
            status: 'already-revoked',
            credentialSaid: options.credentialSaid,
            qviPrefix,
            revocationTelDigest: commonValue(
                before.map(({currentTelDigest}) => currentTelDigest),
                'Revocation TEL digest'
            ),
            revocationTimestamp: credentials[0].status.dt,
        };
    }
    if (beforeStatus !== '0') {
        throw new Error(
            `Credential ${options.credentialSaid} cannot be revoked from TEL sequence ${beforeStatus}`
        );
    }

    const timestamp = createTimestamp();
    await coordinateMultisigOperation(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        members[0].memberAid.prefix,
        (context) =>
            revokeCredentialMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                options.groupName,
                options.credentialSaid,
                timestamp,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            )
    );

    const after = await Promise.all(
        members.map(async ({client, memberAid}) =>
            credentialSnapshot(
                await getCredential(
                    client,
                    options.credentialSaid
                ),
                memberAid.prefix
            )
        )
    );
    const afterStatus = commonCredentialStatus(after);
    if (afterStatus !== '1') {
        throw new Error(
            `Credential ${options.credentialSaid} reached TEL sequence ${afterStatus} after revocation`
        );
    }
    return {
        status: 'revoked',
        credentialSaid: options.credentialSaid,
        qviPrefix,
        revocationTelDigest: commonValue(
            after.map(({currentTelDigest}) => currentTelDigest),
            'Revocation TEL digest'
        ),
        revocationTimestamp: timestamp,
    };
}
