import {readFileSync} from 'node:fs';

import {getOrCreateContact} from './agent-contacts.ts';
import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from './cli.ts';
import {getOrCreateClient} from './keystore-creation.ts';

export interface ResolveQviOobiOptions {
    config: ParticipantConfig;
    groupName: string;
    oobiFile: string;
}

interface QviOobiArtifact {
    qviPrefix: string;
    multisigOobi: string;
}

function readQviOobi(path: string): QviOobiArtifact {
    const decoded = JSON.parse(
        readFileSync(path, 'utf8')
    ) as unknown;
    const artifactIsInvalid =
        typeof decoded !== 'object' ||
        decoded === null ||
        typeof (decoded as {qviPrefix?: unknown}).qviPrefix !==
            'string' ||
        typeof (decoded as {multisigOobi?: unknown}).multisigOobi !==
            'string';
    if (artifactIsInvalid) {
        throw new Error(`Invalid QVI OOBI artifact ${path}`);
    }

    const artifact = decoded as QviOobiArtifact;
    const expectedPath = `/oobi/${artifact.qviPrefix}`;
    const pathMatches =
        new URL(artifact.multisigOobi).pathname === expectedPath;
    if (pathMatches === false) {
        throw new Error(
            `QVI OOBI ${artifact.multisigOobi} does not match ${expectedPath}`
        );
    }
    return artifact;
}

export async function resolveQviOobiForPerson(
    options: ResolveQviOobiOptions
) {
    const config = options.config;
    const person = config.participants.person;
    const client = await getOrCreateClient(
        person.salt,
        config.environment,
        person.keriaHost
    );
    const artifact = readQviOobi(options.oobiFile);
    const resolvedPrefix = await getOrCreateContact(
        client,
        options.groupName,
        artifact.multisigOobi
    );
    const oobiResolvedToQvi =
        resolvedPrefix === artifact.qviPrefix;
    if (oobiResolvedToQvi === false) {
        throw new Error(
            `QVI multisig OOBI resolved to unexpected prefix ${resolvedPrefix}`
        );
    }

    return {
        status: 'resolved' as const,
        qviPrefix: artifact.qviPrefix,
    };
}

function parseResolveArguments(
    argv: string[]
): ResolveQviOobiOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'environment',
        'participant-source',
        'group-name',
        'oobi-file',
    ]);
    requireNamedArguments(args, [
        'group-name',
        'oobi-file',
    ]);
    return {
        config: participantConfigFromArguments(args),
        groupName: args['group-name'],
        oobiFile: args['oobi-file'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseResolveArguments(
            process.argv.slice(2)
        );
        return resolveQviOobiForPerson(options);
    });
}
