import { getOrCreateContact } from "../agent-contacts";
import {getOrCreateClient} from "../keystore-creation";
import {parseAidInfo} from '../create-aid.ts';
import {OobiInfo} from "../qvi-data";
import { TestEnvironmentPreset } from "../resolve-env";
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

export function parseOobiInfo(oobiInfo: string) {
    const oobiInfos = oobiInfo.split(','); // expect format: "gedaName|OOBI,leName|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((oobiInfo) => {
        const [position, oobi] = oobiInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'direct-sally') as OobiInfo;
    return {SALLY};
}

export async function getSallyPre(
    aidStrArg: string,
    oobiStrArg: string,
    environment: TestEnvironmentPreset
) {
    // Get Client
    const {PERSON} = parseAidInfo(aidStrArg);
    const PersonClient = await getOrCreateClient(PERSON.salt, environment, 1);
    
    // resolve sally OOBIs 
    const {SALLY} = parseOobiInfo(oobiStrArg);
    const sallyPre = await getOrCreateContact(PersonClient, SALLY.position, SALLY.oobi);
    return sallyPre;
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'oobis'],
            ['environment', 'participant-source', 'oobis']
        );
        requireNamedArguments(parsed, ['oobis']);
        const invocation = participantInvocationFromArguments(parsed);
        const sallyPrefix = await getSallyPre(
            invocation.participantSource,
            parsed.oobis,
            invocation.environment
        );
        return {sallyPrefix};
    });
}
