import signify, {
    type CredentialData,
    type CredentialResult,
    type HabState,
    randomNonce,
    type SignifyClient,
} from 'signify-ts';

import type {GroupMember} from './client.ts';
import {sendExchangeToEachRecipient} from './exchanges.ts';
import {coordinateMultisigOperation} from './multisig-coordinator.ts';
import {waitForMatchingNotification} from './notifications.ts';

export const LE_SCHEMA_SAID =
    'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';
export const OOR_SCHEMA_SAID =
    'EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy';
export const ECR_SCHEMA_SAID =
    'EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw';
import {retry} from './retry.ts';

export interface RegistryRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    groupName: string;
    registryName: string;
}

export interface IssueRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    groupName: string;
    issueePrefix: string;
    credentialData: CredentialData;
}

export interface RevokeRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    groupName: string;
    credentialSaid: string;
    timestamp: string;
}

/** Return the concrete group member matching one participant context. */
function groupMember(
    members: GroupMember[],
    memberPrefix: string
): GroupMember {
    const member = members.find(
        ({memberAid}) => memberAid.prefix === memberPrefix
    );
    if (member === undefined) {
        throw new Error(`Missing group member ${memberPrefix}`);
    }
    return member;
}

/** Return the member wallets used by multisig operation coordination. */
function memberWallets(members: GroupMember[]) {
    return members.map(({client, memberAid}) => ({
        client,
        aid: memberAid,
    }));
}

/**
 * Creates a multisig registry by name for a set of single sig participants.
 * @param client SignifyClient of the single-sig participant in the multisig creating the registry
 * @param aid singlesig AID of the participant creating the registry
 * @param otherMembersAIDs identifiers of the other multisig participants
 * @param multisigAID the multisig identifier creating the registry
 * @param registryName label of the registry
 * @param nonce the secure datetimestamp nonce all participants use to create the registry
 * @param initiatorPrefix member prefix that submits the proposal
 * @returns the registry operation and correlated notification identifiers
 */
export async function createRegistryMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    registryName: string,
    nonce: string,
    initiatorPrefix: string
) {
    const participantIsFollower = aid.prefix !== initiatorPrefix;
    const vcpResult = await client.registries().create({
        name: multisigAID.name,
        registryName: registryName,
        nonce: nonce,
    });
    const op = await vcpResult.op();

    const serder = vcpResult.regser;
    const anc = vcpResult.serder;
    const sigs = vcpResult.sigs;
    const sigers = sigs.map((sig) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(anc, sigers));
    const atc = ims.substring(anc.size);
    const regbeds = {
        vcp: [serder, ''],
        anc: [anc, atc],
    };
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    let notificationIds: string[] = [];
    if (participantIsFollower) {
        const notification = await waitForMatchingNotification(client, {
            exchangeRoute: '/multisig/vcp',
            sender: initiatorPrefix,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            embeddedDigest: serder.said,
        });
        notificationIds = notification.notificationIds;
    }

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'registry',
        sender: aid,
        route: '/multisig/vcp',
        payload: {gid: multisigAID.prefix},
        embeds: regbeds,
        recipients: recp,
    });

    return {
        operation: op,
        notificationIds,
    };
}

/** Create one credential registry through concrete group members. */
export async function createRegistry(
    request: RegistryRequest
): Promise<void> {
    const nonce = randomNonce();
    await coordinateMultisigOperation(
        memberWallets(request.members),
        request.initiatorPrefix,
        (context) =>
            createRegistryMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                groupMember(
                    request.members,
                    context.aid.prefix
                ).groupAid,
                request.registryName,
                nonce,
                context.initiatorPrefix
            )
    );
}

/** Issue one credential through concrete group members. */
export async function issueCredential(
    request: IssueRequest
): Promise<CredentialResult[]> {
    const schema = request.credentialData.s;
    if (typeof schema !== 'string' || schema.length === 0) {
        throw new Error('Credential issuance requires a schema SAID');
    }
    await coordinateMultisigOperation(
        memberWallets(request.members),
        request.initiatorPrefix,
        (context) =>
            issueCredentialMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                request.groupName,
                request.credentialData,
                context.initiatorPrefix
            )
    );
    return await Promise.all(
        request.members.map(async ({client, groupAid}, index) =>
            requireCredential(
                await getIssuedCredential(
                    client,
                    groupAid.prefix,
                    request.issueePrefix,
                    schema
                ),
                `Group member ${index + 1} issued credential`
            )
        )
    );
}

/** Revoke one credential through concrete group members. */
export async function revokeCredential(
    request: RevokeRequest
): Promise<void> {
    await coordinateMultisigOperation(
        memberWallets(request.members),
        request.initiatorPrefix,
        (context) =>
            revokeCredentialMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                request.groupName,
                request.credentialSaid,
                request.timestamp,
                context.initiatorPrefix
            )
    );
}

export async function issueCredentialMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAIDName: string,
    kargsIss: CredentialData,
    initiatorPrefix: string
) {
    const participantIsFollower = aid.prefix !== initiatorPrefix;
    const multisigAID = await client.identifiers().get(multisigAIDName);
    const credResult = await client
        .credentials()
        .issue(multisigAIDName, kargsIss);
    const op = credResult.op;

    const keeper = client.manager!.get(multisigAID);
    const sigs = await keeper.sign(signify.b(credResult.anc.raw));
    const sigers = sigs.map((sig: string) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(credResult.anc, sigers));
    const atc = ims.substring(credResult.anc.size);
    const embeds = {
        acdc: [credResult.acdc, ''],
        iss: [credResult.iss, ''],
        anc: [credResult.anc, atc],
    };
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    let notificationIds: string[] = [];
    if (participantIsFollower) {
        const notification = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/iss',
                sender: initiatorPrefix,
                recipient: aid.prefix,
                groupPrefix: multisigAID.prefix,
                credentialSaid: credResult.acdc.said,
                embeddedDigest: credResult.iss.said,
            }
        );
        notificationIds = notification.notificationIds;
    }

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/iss',
        payload: {
            gid: multisigAID.prefix,
            said: credResult.acdc.said,
        },
        embeds,
        recipients: recp,
    });

    return {
        operation: op,
        notificationIds,
    };
}

/**
 * Revokes a credential issued by a multisig identifier one participant at a time.
 */
export async function revokeCredentialMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAIDName: string,
    credentialSaid: string,
    timestamp: string,
    initiatorPrefix: string
) {
    const participantIsFollower = aid.prefix !== initiatorPrefix;
    const multisigAID = await client.identifiers().get(multisigAIDName);
    const result = await client
        .credentials()
        .revoke(multisigAIDName, credentialSaid, timestamp);
    const keeper = client.manager!.get(multisigAID);
    const sigs = await keeper.sign(signify.b(result.anc.raw));
    const sigers = sigs.map((sig: string) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(result.anc, sigers));
    const atc = ims.substring(result.anc.size);
    const embeds = {
        rev: [result.rev, ''],
        anc: [result.anc, atc],
    };
    const recipients = otherMembersAIDs.map((member) => member.prefix);

    let notificationIds: string[] = [];
    if (participantIsFollower) {
        const notification = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/rev',
                sender: initiatorPrefix,
                recipient: aid.prefix,
                groupPrefix: multisigAID.prefix,
                credentialSaid,
                embeddedDigest: result.rev.said,
            }
        );
        notificationIds = notification.notificationIds;
    }

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/rev',
        payload: {
            gid: multisigAID.prefix,
            said: credentialSaid,
        },
        embeds,
        recipients,
    });

    return {
        ...result,
        operation: result.op,
        notificationIds,
    };
}

/**
 * Will return a credential after it has been created. Does not mean a credential has been granted.
 *
 * @param issuerClient Client of the credential issuer, or one of the issuers if multisig
 * @param issuerPrefix identifier prefix of the issuer; multisig prefix for multisig issuers
 * @param recipientPrefix issuee; identifier prefix of the recipient; multisig prefix for multisig recipients
 * @param schemaSAID the SAID of the schema for the credential
 * @returns the issued credential
 */
export async function getIssuedCredential(
    issuerClient: SignifyClient,
    issuerPrefix: string,
    recipientPrefix: string,
    schemaSAID: string
): Promise<CredentialResult | undefined> {
    const credentialList = await issuerClient.credentials().list({
        filter: {
            '-i': issuerPrefix,
            '-s': schemaSAID,
            '-a-i': recipientPrefix,
        },
    });
    const resultIsAmbiguous = credentialList.length > 1;
    if (resultIsAmbiguous) {
        throw new Error(
            `Expected at most one credential for issuer ${issuerPrefix}, schema ${schemaSAID}, issuee ${recipientPrefix}; found ${credentialList.length}`
        );
    }
    return credentialList[0];
}

export function requireCredential(
    credential: CredentialResult | undefined,
    description: string
): CredentialResult {
    const credentialIsMissing = credential === undefined;
    if (credentialIsMissing) {
        throw new Error(`${description} was not found`);
    }
    return credential;
}

/**
 * Returns a credential that has been received through an IPEX Admit by the client.
 * @param client SignifyClient for the recipient or for multisig the client of one of the recipients
 * @param credId SAID of the credential to retrieve
 * @returns the credential body
 */
export async function getReceivedCredential(
    client: SignifyClient,
    credId: string
): Promise<CredentialResult | undefined> {
    const credentialList = await client.credentials().list({
        filter: {
            '-d': credId,
        },
    });
    const resultIsAmbiguous = credentialList.length > 1;
    if (resultIsAmbiguous) {
        throw new Error(
            `Expected at most one received credential ${credId}; found ${credentialList.length}`
        );
    }
    return credentialList[0];
}

export async function getReceivedCredBySchemaAndIssuer(
    client: SignifyClient,
    schemaSAID: string,
    issuerPrefix: string
): Promise<CredentialResult | undefined> {
    const credentialList = await client.credentials().list({
        filter: {
            '-s': schemaSAID,
            '-i': issuerPrefix
        },
    });
    const resultIsAmbiguous = credentialList.length > 1;
    if (resultIsAmbiguous) {
        throw new Error(
            `Expected at most one received credential for issuer ${issuerPrefix} and schema ${schemaSAID}; found ${credentialList.length}`
        );
    }
    return credentialList[0];
}

/** Wait for one exact credential under the workflow's configured deadline. */
export async function waitForCredential(
    client: SignifyClient,
    credSAID: string
): Promise<CredentialResult> {
    return retry(async () => {
        const cred = await getReceivedCredential(client, credSAID);
        const credentialIsMissing = cred === undefined;
        if (credentialIsMissing) {
            throw new Error(
                `Credential ${credSAID} has not been received`
            );
        }
        return cred;
    });
}
