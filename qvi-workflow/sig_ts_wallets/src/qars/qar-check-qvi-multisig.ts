import { HabState } from "signify-ts";
import { parseAidInfo } from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import { TestEnvironmentPreset } from "../resolve-env";
import fs from 'fs';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';


/**
 * Checks to see if the QVI multisig exists
 *
 * @param multisigName name of the multisig AID
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI multisig AID exists or not
 */
export async function checkQviMultisig(
    multisigName: string,
    aidInfo: string,
    environment: TestEnvironmentPreset
): Promise<number> {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);

    // Check to see if QVI multisig exists    
    let qar1Ms: HabState;
    try {
        qar1Ms = await QAR1Client.identifiers().get(multisigName);
    } catch {
        return -1;
    }
    return parseInt(qar1Ms.state.s);
}

export async function recordQviSequence(options: {
    groupName: string;
    participantSource: string;
    artifactDir: string;
    environment: TestEnvironmentPreset;
}) {
    const sequenceNo = await checkQviMultisig(
        options.groupName,
        options.participantSource,
        options.environment
    );
    const artifact = {sequenceNo};
    await fs.promises.writeFile(
        `${options.artifactDir}/qvi-sequence-no.json`,
        JSON.stringify(artifact)
    );
    return artifact;
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'group-name', 'artifact-dir'],
            [
                'environment',
                'group-name',
                'participant-source',
                'artifact-dir',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'artifact-dir',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        return recordQviSequence({
            groupName: parsed['group-name'],
            participantSource: invocation.participantSource,
            artifactDir: parsed['artifact-dir'],
            environment: invocation.environment,
        });
    });
}
