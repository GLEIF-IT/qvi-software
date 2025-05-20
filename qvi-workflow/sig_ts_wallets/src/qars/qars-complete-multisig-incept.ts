import {waitAndMarkNotification} from "../notifications";
import {TestEnvironmentPreset} from "../resolve-env";
import {refreshGedaMultisigstate} from "../qvi-operations.ts";

const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const gedaPrefix = args[2];



/**
 * Finish KERIA+Signify multisig inception by refreshing keystate to discover the delegation seal and
 * then marking the inception notification as read.
 * @param aidInfoArg
 * @param gedaPrefix
 * @param environment
 */
async function completeMultisigIncept(aidInfoArg: string, gedaPrefix: string, environment: TestEnvironmentPreset) {

    const {QAR1Client} = await refreshGedaMultisigstate(aidInfoArg, gedaPrefix, environment);
    try {
        await waitAndMarkNotification(QAR1Client, '/multisig/icp');
    } catch (e) {
        console.error("Error marking inception notification as read", e);
    }
    console.log("QVI delegated multisig inception completed");
}
await completeMultisigIncept(aidInfoArg, gedaPrefix, env);