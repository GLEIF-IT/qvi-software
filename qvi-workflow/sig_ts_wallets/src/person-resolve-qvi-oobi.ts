import {readFileSync} from 'node:fs';

import {getOrCreateContact} from './agent-contacts.ts';
import {
    isMainModule,
    parseNamedArguments,
    readParticipantConfig,
    requireNamedArguments,
    runJsonCli,
} from './cli.ts';
import {getOrCreateClient} from './keystore-creation.ts';
import type {QviAgentOobis} from './qars/qars-authorize-endroles-get-qvi-oobi.ts';

export interface ResolveQviOobisOptions {
    configPath: string;
    groupName: string;
    oobiFile: string;
}

function readQviOobis(path: string): QviAgentOobis {
    const decoded = JSON.parse(
        readFileSync(path, 'utf8')
    ) as unknown;
    const artifactIsInvalid =
        typeof decoded !== 'object' ||
        decoded === null ||
        typeof (decoded as {qviPrefix?: unknown}).qviPrefix !==
            'string' ||
        Array.isArray(
            (decoded as {agentOobis?: unknown}).agentOobis
        ) === false;
    if (artifactIsInvalid) {
        throw new Error(`Invalid QVI OOBI artifact ${path}`);
    }

    const artifact = decoded as QviAgentOobis;
    const entryCountIsInvalid = artifact.agentOobis.length !== 3;
    const eids = artifact.agentOobis.map((entry) => entry.eid);
    const urls = artifact.agentOobis.map((entry) => entry.oobi);
    const valuesAreNotUnique =
        new Set(eids).size !== 3 || new Set(urls).size !== 3;
    if (entryCountIsInvalid || valuesAreNotUnique) {
        throw new Error(
            'QVI OOBI artifact must contain three unique EIDs and URLs'
        );
    }
    for (const entry of artifact.agentOobis) {
        const expectedPath =
            `/oobi/${artifact.qviPrefix}/agent/${entry.eid}`;
        const pathMatches =
            new URL(entry.oobi).pathname === expectedPath;
        if (pathMatches === false) {
            throw new Error(
                `QVI OOBI ${entry.oobi} does not match ${expectedPath}`
            );
        }
    }
    return artifact;
}

export async function resolveQviOobisForPerson(
    options: ResolveQviOobisOptions
) {
    const config = readParticipantConfig(options.configPath);
    const person = config.participants.person;
    const client = await getOrCreateClient(
        person.salt,
        config.environment,
        person.keriaHost
    );
    const artifact = readQviOobis(options.oobiFile);
    const resolvedPrefixes = [];
    for (const entry of artifact.agentOobis) {
        resolvedPrefixes.push(
            await getOrCreateContact(
                client,
                options.groupName,
                entry.oobi
            )
        );
    }
    const everyOobiResolvedToQvi = resolvedPrefixes.every(
        (prefix) => prefix === artifact.qviPrefix
    );
    if (everyOobiResolvedToQvi === false) {
        throw new Error(
            `QVI agent OOBIs resolved to unexpected prefixes: ${resolvedPrefixes.join(',')}`
        );
    }

    return {
        status: 'resolved' as const,
        qviPrefix: artifact.qviPrefix,
        agentEids: artifact.agentOobis.map((entry) => entry.eid),
    };
}

function parseResolveArguments(
    argv: string[]
): ResolveQviOobisOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'group-name',
        'oobi-file',
    ]);
    requireNamedArguments(args, [
        'config',
        'group-name',
        'oobi-file',
    ]);
    return {
        configPath: args.config,
        groupName: args['group-name'],
        oobiFile: args['oobi-file'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseResolveArguments(
            process.argv.slice(2)
        );
        return resolveQviOobisForPerson(options);
    });
}
