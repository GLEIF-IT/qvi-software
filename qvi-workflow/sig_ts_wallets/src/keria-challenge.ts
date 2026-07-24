import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

import {
    isMainModule,
    parseNamedArguments,
    readParticipantConfig,
    requireNamedArguments,
    runJsonCli,
    type ParticipantPosition,
} from './cli.ts';
import {getOrCreateClient} from './keystore-creation.ts';
import {
    requireOperationResponse,
    waitOperation,
} from './operations.ts';

export type ChallengeAction = 'respond' | 'verify';

export interface RunChallengeOptions {
    configPath: string;
    participant: ParticipantPosition;
    action: ChallengeAction;
    peerPrefix: string;
    wordsFile: string;
}

export interface ChallengeResult {
    status: 'responded' | 'verified';
    participant: ParticipantPosition;
    participantPrefix: string;
    peerPrefix: string;
    challengeDigest: string;
    responseExnSaid: string;
    completedAt: string;
}

function parseChallengeWords(wordsFile: string): string[] {
    const words = readFileSync(wordsFile, 'utf8')
        .trim()
        .split(/\s+/);
    const challengeWordCountIsInvalid = words.length !== 12;
    if (challengeWordCountIsInvalid) {
        throw new Error(
            `Expected a 128-bit, 12-word challenge; received ${words.length} words`
        );
    }
    return words;
}

function challengeDigest(words: string[]): string {
    return createHash('sha256')
        .update(words.join(' '), 'utf8')
        .digest('hex');
}

function isChallengeOperationResponse(
    value: unknown
): value is {exn: {d: string}} {
    if (typeof value !== 'object' || value === null) {
        return false;
    }
    const exn = (value as {exn?: unknown}).exn;
    return (
        typeof exn === 'object' &&
        exn !== null &&
        typeof (exn as {d?: unknown}).d === 'string'
    );
}

export async function runChallenge(
    options: RunChallengeOptions
): Promise<ChallengeResult> {
    const config = readParticipantConfig(options.configPath);
    const participant = config.participants[options.participant];
    const words = parseChallengeWords(options.wordsFile);
    const digest = challengeDigest(words);
    const client = await getOrCreateClient(
        participant.salt,
        config.environment,
        participant.keriaHost
    );
    const participantAid = await client
        .identifiers()
        .get(participant.name);

    if (options.action === 'respond') {
        const exchange = await client
            .challenges()
            .respond(
                participant.name,
                options.peerPrefix,
                words
            );
        const exchangeSaidIsMissing =
            typeof exchange.d !== 'string' ||
            exchange.d.length === 0;
        if (exchangeSaidIsMissing) {
            throw new Error(
                `Challenge response to ${options.peerPrefix} completed without an EXN SAID`
            );
        }

        return {
            status: 'responded',
            participant: options.participant,
            participantPrefix: participantAid.prefix,
            peerPrefix: options.peerPrefix,
            challengeDigest: digest,
            responseExnSaid: exchange.d,
            completedAt: new Date().toISOString(),
        };
    }

    const operation = await client
        .challenges()
        .verify(options.peerPrefix, words);
    const completed = await waitOperation(client, operation);
    const response = requireOperationResponse(
        completed,
        isChallengeOperationResponse,
        `Challenge verification for ${options.peerPrefix}`
    );
    const responseExnSaid = response.exn.d;
    const accepted = await client
        .challenges()
        .responded(options.peerPrefix, responseExnSaid);
    const responseWasNotAccepted = accepted.ok !== true;
    if (responseWasNotAccepted) {
        throw new Error(
            `Failed to accept challenge response ${responseExnSaid} from ${options.peerPrefix}`
        );
    }

    return {
        status: 'verified',
        participant: options.participant,
        participantPrefix: participantAid.prefix,
        peerPrefix: options.peerPrefix,
        challengeDigest: digest,
        responseExnSaid,
        completedAt: new Date().toISOString(),
    };
}

function parseChallengeArguments(argv: string[]): RunChallengeOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'participant',
        'action',
        'peer-prefix',
        'words-file',
    ]);
    requireNamedArguments(args, [
        'config',
        'participant',
        'action',
        'peer-prefix',
        'words-file',
    ]);

    const participant = args.participant as ParticipantPosition;
    const participantIsInvalid = [
        'qar1',
        'qar2',
        'qar3',
        'person',
    ].includes(participant) === false;
    if (participantIsInvalid) {
        throw new Error(
            `Unknown KERIA participant ${args.participant}`
        );
    }

    const action = args.action as ChallengeAction;
    const actionIsInvalid =
        action !== 'respond' && action !== 'verify';
    if (actionIsInvalid) {
        throw new Error(`Unknown challenge action ${args.action}`);
    }

    return {
        configPath: args.config,
        participant,
        action,
        peerPrefix: args['peer-prefix'],
        wordsFile: args['words-file'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseChallengeArguments(
            process.argv.slice(2)
        );
        return runChallenge(options);
    });
}
