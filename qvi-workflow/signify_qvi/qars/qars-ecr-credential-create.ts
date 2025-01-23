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
const multisigName = args[1]
const dataDir = args[2];
const aidInfoArg = args[3]
const personPrefix = args[4]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const ECR_SCHEMA_SAID = 'EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw';

/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param personPrefix identifier prefix for the person AID who would be the recipient, or issuee, of the ECR credential.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createECRCredential(multisigName: string, aidInfo: string, personPrefix: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
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

    const qviAID = await QAR1Client.identifiers().get(multisigName);

    // QVI issues a LE vLEI credential to the LE (GIDA in this case).
    // Skip if the credential has already been issued.
    let ecrCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        personPrefix,
        ECR_SCHEMA_SAID
    );
    let ecrCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        personPrefix,
        ECR_SCHEMA_SAID
    );
    let ecrCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        personPrefix,
        ECR_SCHEMA_SAID
    );
    
    
    if (ecrCredByQAR1 && ecrCredbyQAR2 && ecrCredbyQAR3) {
        console.log("ECR credential already exists");
        return {
            ecrCredSAID: ecrCredByQAR1.sad.d,
            ecrCredIssuer: ecrCredByQAR1.sad.i,
            ecrCredIssuee: ecrCredByQAR1.sad.a.i,
        }
    }
    else {
        console.log("ECR Credential does not exist, creating and granting");

        const registries:[{name: string, regk: string}] = await QAR1Client.registries().list(multisigName)
        const qviRegistry = registries[0];
        
        let data: string = "";
        data = await fs.promises.readFile(`${dataDir}/ecr-data.json`, 'utf-8');
        let ecrData = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/ecr-auth-edge.json`, 'utf-8');
        let ecrAuthEdge = JSON.parse(data);

        data = await fs.promises.readFile(`${dataDir}/ecr-rules.json`, 'utf-8');
        let ecrRules = JSON.parse(data);

        const kargsSub: CredentialSubject = {
            i: personPrefix,
            dt: createTimestamp(),
            u: new Salter({}).qb64,
            ...ecrData,
        };
        const kargsIss: CredentialData = {
            u: new Salter({}).qb64,
            i: qviAID.prefix,
            ri: qviRegistry.regk,
            s: ECR_SCHEMA_SAID,
            a: kargsSub,
            e: ecrAuthEdge,
            r: ecrRules,
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

        ecrCredByQAR1 = await getIssuedCredential(
            QAR1Client,
            qviAID.prefix,
            personPrefix,
            ECR_SCHEMA_SAID
        );
        ecrCredbyQAR2 = await getIssuedCredential(
            QAR2Client,
            qviAID.prefix,
            personPrefix,
            ECR_SCHEMA_SAID
        );
        ecrCredbyQAR3 = await getIssuedCredential(
            QAR3Client,
            qviAID.prefix,
            personPrefix,
            ECR_SCHEMA_SAID
        );

        const grantTime = createTimestamp();
        console.log("IPEX Granting ECR credential to Person...");
        await grantMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviAID,
            personPrefix,
            ecrCredByQAR1,
            grantTime,
            true
        );
        await grantMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviAID,
            personPrefix,
            ecrCredbyQAR2,
            grantTime
        );
        await grantMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviAID,
            personPrefix,
            ecrCredbyQAR3,
            grantTime
        );

        await waitAndMarkNotification(QAR1Client, '/multisig/exn');
        return {
            ecrCredSAID: ecrCredByQAR1.sad.d,
            ecrCredIssuer: ecrCredByQAR1.sad.i,
            ecrCredIssuee: ecrCredByQAR1.sad.a.i,
        }
    }
}
const ecrCreateResult: any = await createECRCredential(multisigName, aidInfoArg, personPrefix, witnessIds, env);
await fs.promises.writeFile(`${dataDir}/signify_qvi/qvi_data/ecr-cred-info.json`, JSON.stringify(ecrCreateResult));
console.log("ECR credential created and granted");
