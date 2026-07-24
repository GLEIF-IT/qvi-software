import {readFileSync} from 'node:fs';

import {
    isMainModule,
    parseNamedArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {parseAidInfo} from '../create-aid.ts';
import {
    completePendingMultisigOperation,
    parsePendingMultisigOperation,
    type PendingMultisigOperation,
} from '../multisig-coordinator.ts';
import {refreshGedaMultisigstate} from '../qvi-operations.ts';
import type {TestEnvironmentPreset} from '../resolve-env.ts';

interface InceptionArtifact {
    msPrefix: string;
    pending: PendingMultisigOperation;
}

function readInceptionArtifact(path: string): InceptionArtifact {
    const value = JSON.parse(readFileSync(path, 'utf8')) as unknown;
    const valueIsRecord =
        typeof value === 'object' && value !== null;
    if (valueIsRecord === false) {
        throw new Error('Delegated inception artifact must be an object');
    }
    const record = value as Record<string, unknown>;
    const msPrefix = record.msPrefix;
    if (typeof msPrefix !== 'string' || msPrefix.length === 0) {
        throw new Error(
            'Delegated inception artifact has no QVI prefix'
        );
    }
    return {
        msPrefix,
        pending: parsePendingMultisigOperation(record.pending),
    };
}

export async function completeMultisigIncept(
    participantSource: string,
    gedaPrefix: string,
    environment: TestEnvironmentPreset,
    pending: PendingMultisigOperation
): Promise<void> {
    const clients = await refreshGedaMultisigstate(
        participantSource,
        gedaPrefix,
        environment
    );
    const {QAR1, QAR2, QAR3} = parseAidInfo(participantSource);
    const aids = await Promise.all([
        clients.QAR1Client.identifiers().get(QAR1.name),
        clients.QAR2Client.identifiers().get(QAR2.name),
        clients.QAR3Client.identifiers().get(QAR3.name),
    ]);
    const clientsByMember = new Map(
        aids.map((aid, index) => [
            aid.prefix,
            [
                clients.QAR1Client,
                clients.QAR2Client,
                clients.QAR3Client,
            ][index],
        ])
    );
    await completePendingMultisigOperation(
        clientsByMember,
        pending
    );
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(process.argv.slice(2), [
            'config',
            'geda-prefix',
            'operation-artifact',
        ]);
        requireNamedArguments(parsed, [
            'geda-prefix',
            'operation-artifact',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const inception = readInceptionArtifact(
            parsed['operation-artifact']
        );
        await completeMultisigIncept(
            invocation.participantSource,
            parsed['geda-prefix'],
            invocation.environment,
            inception.pending
        );
        return {
            status: 'completed',
            gedaPrefix: parsed['geda-prefix'],
            qviPrefix: inception.msPrefix,
        };
    });
}
