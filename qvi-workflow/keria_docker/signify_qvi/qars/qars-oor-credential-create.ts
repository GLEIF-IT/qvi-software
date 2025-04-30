import fs from "fs";
import {CredentialData, CredentialSubject, Salter} from "signify-ts";
import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {getIssuedCredential, grantMultisig, issueCredentialMultisig} from "../credentials";
import {waitAndMarkNotification} from "../notifications";
import {waitOperation} from "../operations";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const dataDir = args[2];
const aidInfoArg = args[3];
const personPrefix = args[4];
const qviDataDir = args[5];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const OOR_SCHEMA_SAID = 'EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy';

/**
 * Uses QAR1, QAR2, and QAR3 to issue the OOR credential to the person AID.
 *
 * @param multisigName name of the QVI multisig to create and issue the OOR from
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param personPrefix identifier prefix for the person AID who would be the recipient, or issuee, of the OOR credential.
 * @param witnessIds list of witness identifiers to use for the multisig AID configuration
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createOORCredential(multisigName: string, aidInfo: string, personPrefix: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    const [WAN, WIL, WES, WIT] = witnessIds; // QARs use WIL, Person uses WES

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get AIDs
    const aidConfigQARs = {
        toad: 1,
        wits: [WIL],
    };
    const [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs),
        getOrCreateAID(QAR2Client, QAR2.name, aidConfigQARs),
        getOrCreateAID(QAR3Client, QAR3.name, aidConfigQARs),
    ]);

    const qviAID = await QAR1Client.identifiers().get(multisigName);

    // QVI issues a LE vLEI credential to the LE (GIDA in this case).
    // Skip if the credential has already been issued.
    let oorCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        personPrefix,
        OOR_SCHEMA_SAID
    );
    let oorCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        personPrefix,
        OOR_SCHEMA_SAID
    );
    let oorCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        personPrefix,
        OOR_SCHEMA_SAID
    );
    
    
    if (oorCredByQAR1 && oorCredbyQAR2 && oorCredbyQAR3) {
        console.log("OOR credential already exists");
        return {
            oorCredSAID: oorCredByQAR1.sad.d,
            oorCredIssuer: oorCredByQAR1.sad.i,
            oorCredIssuee: oorCredByQAR1.sad.a.i,
        }
    }
    else {
        console.log("OOR Credential does not exist, creating and granting");

        const registries:[{name: string, regk: string}] = await QAR1Client.registries().list(multisigName)
        const qviRegistry = registries[0];
        
        let data: string = "";
        data = await fs.promises.readFile(`${dataDir}/temp-data/oor-data.json`, 'utf-8');
        let oorData = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/temp-data/oor-auth-edge.json`, 'utf-8');
        let oorAuthEdge = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/rules/oor-rules.json`, 'utf-8');
        let oorRules = JSON.parse(data);

        const kargsSub: CredentialSubject = {
            i: personPrefix,
            dt: createTimestamp(),
            ...oorData,
        };
        const kargsIss: CredentialData = {
            i: qviAID.prefix,
            ri: qviRegistry.regk,
            s: OOR_SCHEMA_SAID,
            a: kargsSub,
            e: oorAuthEdge,
            r: oorRules,
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

        oorCredByQAR1 = await getIssuedCredential(
            QAR1Client,
            qviAID.prefix,
            personPrefix,
            OOR_SCHEMA_SAID
        );
        oorCredbyQAR2 = await getIssuedCredential(
            QAR2Client,
            qviAID.prefix,
            personPrefix,
            OOR_SCHEMA_SAID
        );
        oorCredbyQAR3 = await getIssuedCredential(
            QAR3Client,
            qviAID.prefix,
            personPrefix,
            OOR_SCHEMA_SAID
        );

        const grantTime = createTimestamp();
        console.log("IPEX Granting OOR credential to Person...");
        await grantMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviAID,
            personPrefix,
            oorCredByQAR1,
            grantTime,
            true
        );
        await grantMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviAID,
            personPrefix,
            oorCredbyQAR2,
            grantTime
        );
        await grantMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviAID,
            personPrefix,
            oorCredbyQAR3,
            grantTime
        );

        await waitAndMarkNotification(QAR1Client, '/multisig/exn');
        return {
            oorCredSAID: oorCredByQAR1.sad.d,
            oorCredIssuer: oorCredByQAR1.sad.i,
            oorCredIssuee: oorCredByQAR1.sad.a.i,
        }
    }
}
const oorCreateResult: any = await createOORCredential(multisigName, aidInfoArg, personPrefix, witnessIds, env);
await fs.promises.writeFile(`${qviDataDir}/oor-cred-info.json`, JSON.stringify(oorCreateResult));
console.log("OOR credential created and granted");
