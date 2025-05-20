import fs from "fs";
import {CredentialData, CredentialSubject} from "signify-ts";
import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {getIssuedCredential, grantMultisig, issueCredentialMultisig} from "../credentials";
import {waitAndMarkNotification} from "../notifications";
import {waitOperation} from "../operations";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const dataDir = args[2];
const aidInfoArg = args[3];
const lePrefix = args[4];
const qviDataDir = args[5];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const LE_SCHEMA_SAID = 'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';

/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param multisigName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param lePrefix identifier prefix for the Legal Entity multisig AID who would be the recipient, or issuee, of the LE credential.
 * @param witnessIds
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createLeCredential(multisigName: string, aidInfo: string, lePrefix: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get QVI participant AIDs
    const QAR1Id = await QAR1Client.identifiers().get(QAR1.name);
    const QAR2Id = await QAR2Client.identifiers().get(QAR2.name);
    const QAR3Id = await QAR3Client.identifiers().get(QAR3.name);

    const qviAID = await QAR1Client.identifiers().get(multisigName);

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

        const registries:[{name: string, regk: string}] = await QAR1Client.registries().list(multisigName)
        const qviRegistry = registries[0];
        
        let data: string = "";
        data = await fs.promises.readFile(`${dataDir}/temp-data/legal-entity-data.json`, 'utf-8');
        let leData = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/temp-data/qvi-edge.json`, 'utf-8');
        let leCredentialEdge = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/rules/rules.json`, 'utf-8');
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

        await Promise.all([
            waitOperation(QAR1Client, IssOp1),
            waitOperation(QAR2Client, IssOp2),
            waitOperation(QAR3Client, IssOp3),
        ]);

        await waitAndMarkNotification(QAR1Client, '/multisig/iss');

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
        console.log("IPEX Granting LE credential to GIDA (LE)...");
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

        await waitAndMarkNotification(QAR1Client, '/multisig/exn');
        return {
            leCredSAID: leCredbyQAR1.sad.d,
            leCredIssuer: leCredbyQAR1.sad.i,
            leCredIssuee: leCredbyQAR1.sad.a.i,
        }
    }
}
const leCreateResult: any = await createLeCredential(multisigName, aidInfoArg, lePrefix, witnessIds, env);
await fs.promises.writeFile(`${qviDataDir}/le-cred-info.json`, JSON.stringify(leCreateResult));
console.log("LE credential created and granted");
