import signify, {
    type CredentialData,
    type CredentialResult,
    type ExchangeOperation,
    type HabState,
    Serder,
    type SignifyClient,
} from 'signify-ts';

import {sendExchangeToEachRecipient} from './exchanges.ts';
import {requireCoordinatedEventDigest} from './multisig-coordination.ts';
import {
    consumeNotification,
    waitForMatchingNotification,
    type MatchedNotification,
} from './notifications.ts';
import {waitOperation} from './operations.ts';
import {retry} from './retry.ts';

/**
 * Creates a multisig registry by name for a set of single sig participants.
 * @param client SignifyClient of the single-sig participant in the multisig creating the registry
 * @param aid singlesig AID of the participant creating the registry
 * @param otherMembersAIDs identifiers of the other multisig participants
 * @param multisigAID the multisig identifier creating the registry
 * @param registryName label of the registry
 * @param nonce the secure datetimestamp nonce all participants use to create the registry
 * @param isInitiator is lead of this multisig operation
 * @returns the identifier of the registry created  
 */
export async function createRegistryMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    registryName: string,
    nonce: string,
    options: MultisigOperationOptions
) {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/vcp'
    );
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

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(client, {
            notificationRoute: '/multisig/vcp',
            exchangeRoute: '/multisig/vcp',
            sender: coordinator,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            embeddedDigest: serder.said,
        });
    }

    if (coordination !== undefined) {
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/vcp',
            serder.said
        );
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
        coordination:
            coordination === undefined ? [] : [coordination],
    };
}

/**
 * Creates a credential using a multisig identifier one participant at a time.
 * @param client SignifyClient of the single-sig participant in the multisig issuing the credential
 * @param aid the singlesig AID of the participant issuing the credential
 * @param otherMembersAIDs the other multisig participants creating this credential
 * @param multisigAIDName label of the multisig AID
 * @param kargsIss content of the credential
 * @param options coordination options for this participant
 * @returns 
 */
export interface MultisigIssueOptions {
    isInitiator?: boolean;
    coordinator?: string;
}

export type MultisigOperationOptions = MultisigIssueOptions;

function requireCoordinator(
    options: MultisigOperationOptions,
    participantIsFollower: boolean,
    route: string
): string | undefined {
    if (participantIsFollower === false) {
        return undefined;
    }
    const coordinatorIsMissing =
        typeof options.coordinator !== 'string' ||
        options.coordinator.length === 0;
    if (coordinatorIsMissing) {
        throw new Error(
            `${route} follower requires an explicit coordinator prefix`
        );
    }
    return options.coordinator;
}

export async function issueCredentialMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAIDName: string,
    kargsIss: CredentialData,
    options: MultisigIssueOptions = {}
) {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/iss'
    );
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

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(
            client,
            {
                notificationRoute: '/multisig/iss',
                exchangeRoute: '/multisig/iss',
                sender: coordinator,
                recipient: aid.prefix,
                groupPrefix: multisigAID.prefix,
                credentialSaid: credResult.acdc.said,
                embeddedDigest: credResult.iss.said,
            }
        );
    }

    if (coordination !== undefined) {
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/iss',
            credResult.iss.said
        );
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
        coordination:
            coordination === undefined ? [] : [coordination],
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
    options: MultisigOperationOptions
) {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/rev'
    );
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

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(
            client,
            {
                notificationRoute: '/multisig/rev',
                exchangeRoute: '/multisig/rev',
                sender: coordinator,
                recipient: aid.prefix,
                groupPrefix: multisigAID.prefix,
                credentialSaid,
                embeddedDigest: result.rev.said,
            }
        );
    }

    if (coordination !== undefined) {
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/rev',
            result.rev.said
        );
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
        coordination:
            coordination === undefined ? [] : [coordination],
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

/**
 * IPEX Grants a credential to a recipient.
 * @param client SignifyClient of the single-sig participant IPEX Grant-ing the credential
 * @param aid the singlesig AID of the participant IPEX Grant-ing the credential
 * @param otherMembersAIDs the other multisig participants IPEX Grant-ing the credential
 * @param multisigAID the multisig identifier prefix of the credential issuer granting the credential
 * @param recipientPrefix the identifier prefix of the recipient of the credential
 * @param credential Serder of the credential data being granted
 * @param timestamp unique timestamp used across all multisig participants
 * @param isInitiator whether the client is the lead of the multisig operation
 */
export async function grantMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    recipientPrefix: string,
    credential: CredentialResult,
    timestamp: string,
    options: MultisigOperationOptions
): Promise<MultisigIpexResult> {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/exn'
    );

    const [grant, sigs, end] = await client.ipex().grant({
        senderName: multisigAID.name,
        acdc: new Serder(credential.sad),
        anc: new Serder(credential.anc),
        iss: new Serder(credential.iss),
        recipient: recipientPrefix,
        datetime: timestamp,
    });

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(client, {
            notificationRoute: '/multisig/exn',
            exchangeRoute: '/multisig/exn',
            sender: coordinator,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            credentialSaid: credential.sad.d,
            embeddedDigest: grant.said,
        });
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/exn',
            grant.said
        );
    }

    const operation = await client
        .ipex()
        .submitGrant(multisigAID.name, grant, sigs, end, [recipientPrefix]);

    const mstate = multisigAID.state;
    const seal = [
        'SealEvent',
        { i: multisigAID.prefix, s: mstate['ee']['s'], d: mstate['ee']['d'] },
    ];
    const sigers = sigs.map((sig) => new signify.Siger({ qb64: sig }));
    const gims = signify.d(signify.messagize(grant, sigers, seal));
    let atc = gims.substring(grant.size);
    atc += end;
    const gembeds = {
        exn: [grant, atc],
    };
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/exn',
        payload: {
            gid: multisigAID.prefix,
            credentialSaid: credential.sad.d,
        },
        embeds: gembeds,
        recipients: recp,
    });
    return {
        operation,
        coordination:
            coordination === undefined ? [] : [coordination],
    };
}

export interface MultisigIpexResult {
    operation: ExchangeOperation;
    coordination: MatchedNotification[];
}

/**
 * Admits the most recent IPEX Admit message for a single-sig credential.
 * @param client
 * @param aidName
 * @param recipientPrefix
 */
export async function admitSinglesig(
    client: SignifyClient,
    aidName: string,
    recipientPrefix: string,
    credentialSaid: string
): Promise<CredentialResult> {
    const aid = await client.identifiers().get(aidName);
    const grantNotification = await waitForMatchingNotification(
        client,
        {
            notificationRoute: '/exn/ipex/grant',
            exchangeRoute: '/ipex/grant',
            sender: recipientPrefix,
            recipient: aid.prefix,
            credentialSaid,
        }
    );

    const [admit, sigs, aend] = await client.ipex().admit({
        senderName: aidName,
        recipient: recipientPrefix,
        message: '',
        grantSaid: grantNotification.exchangeSaid,
    });

    const operation = await client
        .ipex()
        .submitAdmit(aidName, admit, sigs, aend, [recipientPrefix]);
    await waitOperation(client, operation);
    const credential = await waitForCredential(
        client,
        credentialSaid
    );
    await consumeNotification(client, grantNotification);
    return credential;
}

/**
 * Admits the most recent IPEX Admit message for a multisig credential.
 * @param client SignifyClient of the recipient admitting the credential
 * @param aid the multisig participating single-sig AID admitting the IPEX message
 * @param otherMembersAIDs the other members who are admitting the credential
 * @param multisigAID the identifier admitting the credential; the multisig prefix
 * @param recipientPrefix recipient of the IPEX Admit message; the credential issuer who performed the IPEX Grant
 * @param timestamp the timestamp all of the multisig participants are using to admit a given credential. 
 *                  Must be the same across all participants.
 */
export async function admitMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    recipientPrefix: string,
    credentialSaid: string,
    timestamp: string,
    options: MultisigOperationOptions
): Promise<MultisigIpexResult> {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/exn'
    );
    const grantNotification = await waitForMatchingNotification(client, {
        notificationRoute: '/exn/ipex/grant',
        exchangeRoute: '/ipex/grant',
        sender: recipientPrefix,
        recipient: multisigAID.prefix,
        credentialSaid,
    });

    const [admit, sigs, end] = await client.ipex().admit({
        senderName: multisigAID.name,
        message: '',
        grantSaid: grantNotification.exchangeSaid,
        recipient: recipientPrefix,
        datetime: timestamp,
    });

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(client, {
            notificationRoute: '/multisig/exn',
            exchangeRoute: '/multisig/exn',
            sender: coordinator,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            payloadFields: {
                grantSaid: grantNotification.exchangeSaid,
            },
            credentialSaid,
            embeddedDigest: admit.said,
        });
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/exn',
            admit.said
        );
    }

    const operation = await client
        .ipex()
        .submitAdmit(multisigAID.name, admit, sigs, end, [recipientPrefix]);

    const mstate = multisigAID.state;
    const seal = [
        'SealEvent',
        { i: multisigAID.prefix, s: mstate['ee']['s'], d: mstate['ee']['d'] },
    ];
    const sigers = sigs.map((sig: string) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(admit, sigers, seal));
    let atc = ims.substring(admit.size);
    atc += end;
    const gembeds = {
        exn: [admit, atc],
    };
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/exn',
        payload: {
            gid: multisigAID.prefix,
            credentialSaid,
            grantSaid: grantNotification.exchangeSaid,
        },
        embeds: gembeds,
        recipients: recp,
    });
    return {
        operation,
        coordination:
            coordination === undefined
                ? [grantNotification]
                : [grantNotification, coordination],
    };
}
