import signify, { CredentialData, HabState, Serder, SignifyClient } from "signify-ts";
import { waitAndMarkNotification } from "./notifications";

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
    isInitiator: boolean = false
) {
    if (!isInitiator) await waitAndMarkNotification(client, '/multisig/vcp');

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

    await client
        .exchanges()
        .send(
            aid.name,
            'registry',
            aid,
            '/multisig/vcp',
            { gid: multisigAID.prefix },
            regbeds,
            recp
        );

    return op;
}

/**
 * Creates a credential using a multisig identifier one participant at a time.
 * @param client SignifyClient of the single-sig participant in the multisig issuing the credential
 * @param aid the singlesig AID of the participant issuing the credential
 * @param otherMembersAIDs the other multisig participants creating this credential
 * @param multisigAIDName label of the multisig AID
 * @param kargsIss content of the credential
 * @param isInitiator whether the client is the lead of the multisig operation
 * @returns 
 */
export async function issueCredentialMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAIDName: string,
    kargsIss: CredentialData,
    isInitiator: boolean = false
) {
    if (!isInitiator) await waitAndMarkNotification(client, '/multisig/iss');

    const credResult = await client
        .credentials()
        .issue(multisigAIDName, kargsIss);
    const op = credResult.op;

    const multisigAID = await client.identifiers().get(multisigAIDName);
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

    await client
        .exchanges()
        .send(
            aid.name,
            'multisig',
            aid,
            '/multisig/iss',
            { gid: multisigAID.prefix },
            embeds,
            recp
        );

    return op;
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
    issuerPrefix: String,
    recipientPrefix: String,
    schemaSAID: string
) {
    const credentialList = await issuerClient.credentials().list({
        filter: {
            '-i': issuerPrefix,
            '-s': schemaSAID,
            '-a-i': recipientPrefix,
        },
    });
    return credentialList[0];
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
): Promise<any> {
    const credentialList = await client.credentials().list({
        filter: {
            '-d': credId,
        },
    });
    let credential: any;
    if (credentialList.length > 0) {
        credential = credentialList[0];
    }
    return credential;
}

/**
 * Wait up to MAX_RETRIES * 1 second for a credential to be received.
 * @param client SignifyClient of the identifier waiting for the credential
 * @param credSAID the identifier for the credential to be received
 * @param MAX_RETRIES maximum number of retries of one second each
 * @returns 
 */
export async function waitForCredential(
    client: SignifyClient,
    credSAID: string,
    MAX_RETRIES: number = 10
) {
    let retryCount = 0;
    while (retryCount < MAX_RETRIES) {
        const cred = await getReceivedCredential(client, credSAID);
        if (cred) return cred;

        await new Promise((resolve) => setTimeout(resolve, 1000));
        console.log(` retry-${retryCount}: No credentials yet...`);
        retryCount = retryCount + 1;
    }
    throw Error('Credential SAID: ' + credSAID + ' has not been received');
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
    credential: any,
    timestamp: string,
    isInitiator: boolean = false
) {
    if (!isInitiator) await waitAndMarkNotification(client, '/multisig/exn');

    const [grant, sigs, end] = await client.ipex().grant({
        senderName: multisigAID.name,
        acdc: new Serder(credential.sad),
        anc: new Serder(credential.anc),
        iss: new Serder(credential.iss),
        recipient: recipientPrefix,
        datetime: timestamp,
    });

    await client
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

    await client
        .exchanges()
        .send(
            aid.name,
            'multisig',
            aid,
            '/multisig/exn',
            { gid: multisigAID.prefix },
            gembeds,
            recp
        );
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
    timestamp: string
) {
    const grantMsgSaid = await waitAndMarkNotification(
        client,
        '/exn/ipex/grant'
    );

    const [admit, sigs, end] = await client.ipex().admit({
        senderName: multisigAID.name,
        message: '',
        grantSaid: grantMsgSaid,
        recipient: recipientPrefix,
        datetime: timestamp,
    });

    await client
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

    await client
        .exchanges()
        .send(
            aid.name,
            'multisig',
            aid,
            '/multisig/exn',
            { gid: multisigAID.prefix },
            gembeds,
            recp
        );
}