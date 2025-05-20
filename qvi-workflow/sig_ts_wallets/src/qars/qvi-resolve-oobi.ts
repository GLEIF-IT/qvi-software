import {getOrCreateContact} from "../agent-contacts";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {parseAidInfo} from "../create-aid";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const aliasArg = args[2];
const oobiArg = args[3];

/**
 * Resolves an OOBI for the QVI Multisig participants.
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param alias
 * @param oobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
async function resolveQVIOobi(aidInfo: string, alias: string, oobi: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);

    await getOrCreateContact(QAR1Client, alias, oobi);
    await getOrCreateContact(QAR2Client, alias, oobi);
    await getOrCreateContact(QAR3Client, alias, oobi);
}
await resolveQVIOobi(aidInfoArg, aliasArg, oobiArg, env);
console.log(`QVI resolved OOBI ${aliasArg} ${oobiArg}`);