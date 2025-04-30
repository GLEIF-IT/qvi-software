import fs from "fs";
import signify, { CreateIdentiferArgs, HabState } from "signify-ts";
import { parseAidInfo } from "../create-aid";
import { getOrCreateAID, getOrCreateClients } from "../keystore-creation";
import { createAIDMultisig } from "../multisig-creation";
import { resolveEnvironment, TestEnvironmentPreset } from "../resolve-env";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const dataDir = args[2];
const aidInfoArg = args[3];
const delegationPrefix = args[4];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param multisigName the name of the multisig to create
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param delpre The prefix of the delegator to use for the multisig AID
 * @param witnessIds the list of witness IDs to use for the multisig AID
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createQviMultisig(multisigName: string, aidInfo: string, delpre: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
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

    // Create a multisig AID for the QVI.
    // Skip if a QVI AID has already been incepted.
    
    let qar1Ms, qar2Ms, qar3Ms: HabState;
    try {
        qar1Ms = await QAR1Client.identifiers().get(multisigName);
        qar2Ms = await QAR2Client.identifiers().get(multisigName);
        qar3Ms = await QAR3Client.identifiers().get(multisigName);
        // return early if the QVI AID has already been incepted
    } catch (e: any) {
        // get QAR keystates for inclusion in the multisig inception event
        const rstates = [QAR1Id.state, QAR2Id.state, QAR3Id.state];

        // configure QVI AID multisig inception event
        const kargsMultisigAID: CreateIdentiferArgs = {
            delpre: delpre,
            algo: signify.Algos.group,
            isith: ['1/3', '1/3', '1/3'],
            nsith: ['1/3', '1/3', '1/3'],
            toad: aidConfigQARs.toad,
            wits: aidConfigQARs.wits,
            states: [...rstates],
            rstates: rstates,
        };

        // set member hab to QAR1 and perform multisig inception
        kargsMultisigAID.mhab = QAR1Id;
        const multisigAIDOp1 = await createAIDMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            multisigName,
            kargsMultisigAID,
            true
        );
        // change member hab to QAR2 and perform multisig inception
        kargsMultisigAID.mhab = QAR2Id;
        const multisigAIDOp2 = await createAIDMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            multisigName,
            kargsMultisigAID
        );
        // change member hab to QAR3 and perform multisig inception
        kargsMultisigAID.mhab = QAR3Id;
        const multisigAIDOp3 = await createAIDMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            multisigName,
            kargsMultisigAID
        );

        qar1Ms = await QAR1Client.identifiers().get(multisigName);
        qar2Ms = await QAR2Client.identifiers().get(multisigName);
        qar3Ms = await QAR3Client.identifiers().get(multisigName);
    }
    
    
    return {
        msPrefix: qar1Ms.prefix,
        delegationAnchor: {
            i: qar1Ms.prefix,
            s: '0',
            d: qar1Ms.prefix,
        }
    }
}
const multisigOobiObj: any = await createQviMultisig(multisigName, aidInfoArg, delegationPrefix, witnessIds, env);
await fs.promises.writeFile(`${dataDir}/qvi-multisig-info.json`, JSON.stringify(multisigOobiObj));
console.log("QVI delegated multisig AID created, waiting for GEDA to confirm delegation...");
