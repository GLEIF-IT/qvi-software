import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
    type ParticipantPosition,
} from './cli.ts';
import {getOrCreateClient} from './keystore-creation.ts';
import {
    requireOperationResponse,
    waitOperation,
} from './operations.ts';

export type ChallengeAction = 'respond' | 'verify';

export interface RunChallengeOptions {
    config: ParticipantConfig;
    participant: ParticipantPosition;
    action: ChallengeAction;
    peerPrefix: string;
    words: string[];
}

export interface ChallengeResult {
    status: 'responded' | 'verified';
}

function parseChallengeWords(wordsValue: string): string[] {
    const words = wordsValue.trim().split(/\s+/);
    const challengeWordCountIsInvalid = words.length !== 12;
    if (challengeWordCountIsInvalid) {
        throw new Error(
            `Expected a 128-bit, 12-word challenge; received ${words.length} words`
        );
    }
    return words;
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
    const config = options.config;
    const participant = config.participants[options.participant];
    const words = options.words;
    const client = await getOrCreateClient(
        participant.salt,
        config.environment,
        participant.keriaHost
    );
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
    };
}

function parseChallengeArguments(argv: string[]): RunChallengeOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'environment',
        'participant-source',
        'participant',
        'action',
        'peer-prefix',
        'words',
    ]);
    requireNamedArguments(args, [
        'participant',
        'action',
        'peer-prefix',
        'words',
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
        config: participantConfigFromArguments(args),
        participant,
        action,
        peerPrefix: args['peer-prefix'],
        words: parseChallengeWords(args.words),
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
