import { parseAidInfo } from "./create-aid";
import { getOrCreateClients } from "./keystore-creation";
import { waitAndMarkNotification } from "./notifications";
import { waitOperation } from "./operations";
import { TestEnvironmentPreset } from "./resolve-env";

const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const gedaPrefix = args[2];

/**
 * As the QVI multisig the participating QARs must refresh the keystate of the GEDA multisig in order to
 * respond to the anchoring of the delegation approval seal in the GEDA's key event log (KEL). This 
 * enables the pending QVI delegated multisig inception operation to complete.
 */
async function refreshGedaMultisigstate(aidInfoArg: string, gedaPrefix: string, environment: TestEnvironmentPreset) {
    const {QAR1, QAR2, QAR3, PERSON} = parseAidInfo(aidInfoArg);
    
        // create SignifyTS Clients
        const [
            QAR1Client,
            QAR2Client,
            QAR3Client,
            personClient,
        ] = await getOrCreateClients(4, [QAR1.salt, QAR2.salt, QAR3.salt, PERSON.salt], environment);
    

    // QARs query the GEDA's key state
    const queryOp1 = await QAR1Client.keyStates().query(gedaPrefix);
    const queryOp2 = await QAR2Client.keyStates().query(gedaPrefix);
    const queryOp3 = await QAR3Client.keyStates().query(gedaPrefix);

    await Promise.all([
        waitOperation(QAR1Client, queryOp1),
        waitOperation(QAR2Client, queryOp2),
        waitOperation(QAR3Client, queryOp3),
    ]);

    await waitAndMarkNotification(QAR1Client, '/multisig/icp');

    console.log('QARs have refreshed the GEDA multisig keystate');
}
await refreshGedaMultisigstate(aidInfoArg, gedaPrefix, env);