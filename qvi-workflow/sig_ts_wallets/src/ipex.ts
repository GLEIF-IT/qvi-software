import signify, {
    type CredentialResult,
    type ExchangeOperation,
    type HabState,
    Serder,
    type SignifyClient,
} from 'signify-ts';

import type {GroupMember} from './client.ts';
import {waitForCredential} from './credential-mutations.ts';
import {sendExchangeToEachRecipient} from './exchanges.ts';
import {coordinateMultisigOperation} from './multisig-coordinator.ts';
import {
    consumeNotifications,
    waitForMatchingNotification,
} from './notifications.ts';
import {waitOperation} from './operations.ts';

export interface GrantRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    recipientPrefix: string;
    credentials: CredentialResult[];
    timestamp: string;
}

export interface AdmitRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    issuerPrefix: string;
    credentialSaid: string;
    timestamp: string;
}

export interface MultisigIpexResult {
    operation: ExchangeOperation;
    notificationIds: string[];
}

/** Grant one credential through concrete group members. */
export async function grantCredential(
    request: GrantRequest
): Promise<void> {
    if (request.credentials.length !== request.members.length) {
        throw new Error(
            'Credential grants require one local credential per member'
        );
    }
    await coordinateMultisigOperation(
        request.members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        request.initiatorPrefix,
        (context) => {
            const memberIndex = request.members.findIndex(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (memberIndex < 0) {
                throw new Error(
                    `Missing group member ${context.aid.prefix}`
                );
            }
            return grantMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                request.members[memberIndex].groupAid,
                request.recipientPrefix,
                request.credentials[memberIndex],
                request.timestamp,
                context.initiatorPrefix
            );
        }
    );
}

/** Admit one credential through concrete group members. */
export async function admitCredential(
    request: AdmitRequest
): Promise<void> {
    await coordinateMultisigOperation(
        request.members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        request.initiatorPrefix,
        (context) => {
            const member = request.members.find(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (member === undefined) {
                throw new Error(
                    `Missing group member ${context.aid.prefix}`
                );
            }
            return admitMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                member.groupAid,
                request.issuerPrefix,
                request.credentialSaid,
                request.timestamp,
                context.initiatorPrefix
            );
        }
    );
}

/** Build and submit one member's recipient-bound IPEX grant. */
export async function grantMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    recipientPrefix: string,
    credential: CredentialResult,
    timestamp: string,
    initiatorPrefix: string
): Promise<MultisigIpexResult> {
    const [grant, sigs, end] = await client.ipex().grant({
        senderName: multisigAID.name,
        acdc: new Serder(credential.sad),
        anc: new Serder(credential.anc),
        iss: new Serder(credential.iss),
        recipient: recipientPrefix,
        datetime: timestamp,
    });

    let notificationIds: string[] = [];
    if (aid.prefix !== initiatorPrefix) {
        const notification = await waitForMatchingNotification(client, {
            exchangeRoute: '/multisig/exn',
            sender: initiatorPrefix,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            credentialSaid: credential.sad.d,
            embeddedDigest: grant.said,
        });
        notificationIds = notification.notificationIds;
    }

    const operation = await client
        .ipex()
        .submitGrant(multisigAID.name, grant, sigs, end, [recipientPrefix]);

    const establishment = multisigAID.state.ee;
    const seal = [
        'SealEvent',
        {
            i: multisigAID.prefix,
            s: establishment.s,
            d: establishment.d,
        },
    ];
    const sigers = sigs.map(
        (signature) => new signify.Siger({qb64: signature})
    );
    const message = signify.d(
        signify.messagize(grant, sigers, seal)
    );
    const attachment = `${message.substring(grant.size)}${end}`;
    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/exn',
        payload: {
            gid: multisigAID.prefix,
            credentialSaid: credential.sad.d,
        },
        embeds: {exn: [grant, attachment]},
        recipients: otherMembersAIDs.map(
            ({prefix}) => prefix
        ),
    });
    return {operation, notificationIds};
}

/** Admit one IPEX grant into a single-signature wallet. */
export async function admitSinglesig(
    client: SignifyClient,
    aidName: string,
    issuerPrefix: string,
    credentialSaid: string
): Promise<CredentialResult> {
    const aid = await client.identifiers().get(aidName);
    const grantNotification = await waitForMatchingNotification(
        client,
        {
            notificationRoute: '/exn/ipex/grant',
            exchangeRoute: '/ipex/grant',
            sender: issuerPrefix,
            recipient: aid.prefix,
            credentialSaid,
        }
    );
    const [admit, signatures, attachment] =
        await client.ipex().admit({
            senderName: aidName,
            recipient: issuerPrefix,
            message: '',
            grantSaid: grantNotification.said,
        });
    const operation = await client
        .ipex()
        .submitAdmit(
            aidName,
            admit,
            signatures,
            attachment,
            [issuerPrefix]
        );
    await waitOperation(client, operation);
    const credential = await waitForCredential(
        client,
        credentialSaid
    );
    await consumeNotifications(
        client,
        grantNotification.notificationIds
    );
    return credential;
}

/** Build and submit one member's correlated IPEX admit. */
export async function admitMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    issuerPrefix: string,
    credentialSaid: string,
    timestamp: string,
    initiatorPrefix: string
): Promise<MultisigIpexResult> {
    const grantNotification = await waitForMatchingNotification(client, {
        notificationRoute: '/exn/ipex/grant',
        exchangeRoute: '/ipex/grant',
        sender: issuerPrefix,
        recipient: multisigAID.prefix,
        credentialSaid,
    });
    const [admit, signatures, end] = await client.ipex().admit({
        senderName: multisigAID.name,
        message: '',
        grantSaid: grantNotification.said,
        recipient: issuerPrefix,
        datetime: timestamp,
    });

    let coordinationIds: string[] = [];
    if (aid.prefix !== initiatorPrefix) {
        const notification = await waitForMatchingNotification(client, {
            exchangeRoute: '/multisig/exn',
            sender: initiatorPrefix,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            payloadFields: {grantSaid: grantNotification.said},
            credentialSaid,
            embeddedDigest: admit.said,
        });
        coordinationIds = notification.notificationIds;
    }

    const operation = await client
        .ipex()
        .submitAdmit(
            multisigAID.name,
            admit,
            signatures,
            end,
            [issuerPrefix]
        );
    const establishment = multisigAID.state.ee;
    const seal = [
        'SealEvent',
        {
            i: multisigAID.prefix,
            s: establishment.s,
            d: establishment.d,
        },
    ];
    const sigers = signatures.map(
        (signature) => new signify.Siger({qb64: signature})
    );
    const message = signify.d(
        signify.messagize(admit, sigers, seal)
    );
    const attachment = `${message.substring(admit.size)}${end}`;
    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/exn',
        payload: {
            gid: multisigAID.prefix,
            credentialSaid,
            grantSaid: grantNotification.said,
        },
        embeds: {exn: [admit, attachment]},
        recipients: otherMembersAIDs.map(
            ({prefix}) => prefix
        ),
    });
    return {
        operation,
        notificationIds: [
            ...grantNotification.notificationIds,
            ...coordinationIds,
        ],
    };
}
