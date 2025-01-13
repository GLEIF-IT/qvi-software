import fs from "fs";
import signify, { CreateIdentiferArgs, CredentialData, CredentialSubject, HabState, Saider } from "signify-ts";
import { createTimestamp, parseAidInfo } from "./create-aid";
import { getOrCreateAID, getOrCreateClients } from "./keystore-creation";
import { createAIDMultisig } from "./multisig-creation";
import { resolveEnvironment, TestEnvironmentPreset } from "./resolve-env";
import { getIssuedCredential, grantMultisig, issueCredentialMultisig } from "./credentials";
import { waitAndMarkNotification } from "./notifications";
import { waitOperation } from "./operations";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const dataDir = args[1];
const aidInfoArg = args[2]
const lePrefix = args[3]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const QVI_MS_NAME='QVI';
const LE_SCHEMA_SAID = 'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';

/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param lePrefix identifier prefix for the Legal Entity multisig AID who would be the recipient, or issuee, of the LE credential.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createLeCredential(aidInfo: string, lePrefix: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    console.log(`Creating LE credential and issuing to GIDA ${lePrefix}`)
    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get AIDs
    const kargsAID = {
        toad: witnessIds.length,
        wits: witnessIds,
    };
    const [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, kargsAID),
        getOrCreateAID(QAR2Client, QAR2.name, kargsAID),
        getOrCreateAID(QAR3Client, QAR3.name, kargsAID),
    ]);

    const qviAID = await QAR1Client.identifiers().get(QVI_MS_NAME);

    // QVI issues a LE vLEI credential to the LE (GIDA in this case).
    // Skip if the credential has already been issued.
    let leCredbyQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        lePrefix,
        LE_SCHEMA_SAID
    );
    let leCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        lePrefix,
        LE_SCHEMA_SAID
    );
    let leCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        lePrefix,
        LE_SCHEMA_SAID
    );
    
    
    if (leCredbyQAR1 && leCredbyQAR2 && leCredbyQAR3) {
        console.log("LE credential already exists");
        return {
            leCredSAID: leCredbyQAR1.sad.d,
            leCredIssuer: leCredbyQAR1.sad.i,
            leCredIssuee: leCredbyQAR1.sad.a.i,
        }
    }
    else {
        console.log("LE Credential does not exist, creating and granting");

        const registries:[{name: string, regk: string}] = await QAR1Client.registries().list(QVI_MS_NAME)
        const qviRegistry = registries[0];
        console.log(`QVI registry: ${qviRegistry.regk}`);
        
        let data: string = "";
        data = await fs.promises.readFile(`${dataDir}/legal-entity-data.json`, 'utf-8');
        let leData = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/qvi-edge.json`, 'utf-8');
        let leCredentialEdge = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/rules.json`, 'utf-8');
        let leRules = JSON.parse(data);

        const kargsSub: CredentialSubject = {
            i: lePrefix,
            dt: createTimestamp(),
            ...leData,
        };
        const kargsIss: CredentialData = {
            i: qviAID.prefix,
            ri: qviRegistry.regk,
            s: LE_SCHEMA_SAID,
            a: kargsSub,
            e: leCredentialEdge,
            r: leRules,
        };
        console.log(`LE credential data: `, kargsIss);
        const IssOp1 = await issueCredentialMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviAID.name,
            kargsIss,
            true
        );
        const IssOp2 = await issueCredentialMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviAID.name,
            kargsIss
        );
        const IssOp3 = await issueCredentialMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviAID.name,
            kargsIss
        );
        console.log("Credential issued, waiting operations...");

        await Promise.all([
            waitOperation(QAR1Client, IssOp1),
            waitOperation(QAR2Client, IssOp2),
            waitOperation(QAR3Client, IssOp3),
        ]);
        console.log("Operations completed, waiting for notifications...");

        await waitAndMarkNotification(QAR1Client, '/multisig/iss');

        console.log("LE credential issued, getting Issued Credential...");
        leCredbyQAR1 = await getIssuedCredential(
            QAR1Client,
            qviAID.prefix,
            lePrefix,
            LE_SCHEMA_SAID
        );
        leCredbyQAR2 = await getIssuedCredential(
            QAR2Client,
            qviAID.prefix,
            lePrefix,
            LE_SCHEMA_SAID
        );
        leCredbyQAR3 = await getIssuedCredential(
            QAR3Client,
            qviAID.prefix,
            lePrefix,
            LE_SCHEMA_SAID
        );

        const grantTime = createTimestamp();
        console.log("Granting LE credential...");
        await grantMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviAID,
            lePrefix,
            leCredbyQAR1,
            grantTime,
            true
        );
        await grantMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviAID,
            lePrefix,
            leCredbyQAR2,
            grantTime
        );
        await grantMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviAID,
            lePrefix,
            leCredbyQAR3,
            grantTime
        );

        console.log("Granting LE credential, waiting operations...");
        await waitAndMarkNotification(QAR1Client, '/multisig/exn');
        console.log("LE credential granted");
        return {
            leCredSAID: leCredbyQAR1.sad.d,
            leCredIssuer: leCredbyQAR1.sad.i,
            leCredIssuee: leCredbyQAR1.sad.a.i,
        }
    }
}
const leCreateResult: any = await createLeCredential(aidInfoArg, lePrefix, witnessIds, env);
await fs.writeFile(`${dataDir}/signify_qvi/qvi_data/le-cred-info.json`, JSON.stringify(leCreateResult), (err) => {
    if (err) {
        console.log(`error writing LE credential info to file: ${err}`);        
        return
    }
});
console.log("LE credential created and granted");
