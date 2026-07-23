import {Operation} from 'signify-ts';
import {parseAidInfo} from './create-aid.ts';
import {getOrCreateClient} from './keystore-creation.ts';
import {waitOperation} from './operations.ts';
import {TestEnvironmentPreset} from './resolve-env.ts';

const [env, aidInfoArg, position, action, peerPrefix, wordsArg] =
    process.argv.slice(2);

const requiredArgumentIsMissing =
    !env || !aidInfoArg || !position || !action || !peerPrefix || !wordsArg;
if (requiredArgumentIsMissing) {
    throw new Error(
        'Usage: keria-challenge.ts <environment> <SIGTS_AIDS> <participant> <respond|verify> <peer-prefix> <words>'
    );
}

const participants = parseAidInfo(aidInfoArg);
const participantByPosition = {
    qar1: {info: participants.QAR1, keriaHost: 1},
    qar2: {info: participants.QAR2, keriaHost: 2},
    qar3: {info: participants.QAR3, keriaHost: 3},
    person: {info: participants.PERSON, keriaHost: 1},
} as const;
const participant =
    participantByPosition[position as keyof typeof participantByPosition];

const participantIsUnknown = participant === undefined;
if (participantIsUnknown) {
    throw new Error(`Unknown KERIA participant: ${position}`);
}

const words = wordsArg.trim().split(/\s+/);
const challengeWordCountIsInvalid = words.length !== 12;
if (challengeWordCountIsInvalid) {
    throw new Error(
        `Expected a 128-bit, 12-word challenge; received ${words.length} words`
    );
}

const client = await getOrCreateClient(
    participant.info.salt,
    env as TestEnvironmentPreset,
    participant.keriaHost
);

if (action === 'respond') {
    const exchange = (await client
        .challenges()
        .respond(participant.info.name, peerPrefix, words)) as {d?: string};
    const exchangeSaidIsMissing = exchange.d === undefined;
    if (exchangeSaidIsMissing) {
        throw new Error(
            `Challenge response to ${peerPrefix} was not accepted with an EXN SAID`
        );
    }
    console.log(
        `[challenge] ${position} submitted response ${exchange.d} to ${peerPrefix}`
    );
} else if (action === 'verify') {
    const operation = await client.challenges().verify(peerPrefix, words);
    const completed = (await waitOperation(client, operation)) as Operation<{
        exn?: {d?: string};
    }>;
    const exnSaid = completed.response?.exn?.d;
    const responseSaidIsMissing = exnSaid === undefined;
    if (responseSaidIsMissing) {
        throw new Error(
            `Challenge verification for ${peerPrefix} completed without a response EXN SAID`
        );
    }

    const response = await client.challenges().responded(peerPrefix, exnSaid);
    const responseWasNotAccepted = response.ok !== true;
    if (responseWasNotAccepted) {
        throw new Error(
            `Failed to mark ${peerPrefix} challenge response ${exnSaid} as accepted`
        );
    }
    console.log(
        `[challenge] ${position} verified and accepted response ${exnSaid} from ${peerPrefix}`
    );
} else {
    throw new Error(`Unknown challenge action: ${action}`);
}
