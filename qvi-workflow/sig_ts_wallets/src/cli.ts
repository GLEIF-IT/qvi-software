import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

import type {AidInfo} from './qvi-data.ts';
import {
    parseEnvironmentPreset,
    type TestEnvironmentPreset,
} from './resolve-env.ts';

export type ParticipantPosition = 'qar1' | 'qar2' | 'qar3' | 'person';
export type SingleSigParticipantPosition = 'qar' | 'person' | 'qvi';

export interface ParticipantConfig {
    environment: TestEnvironmentPreset;
    participants: Record<ParticipantPosition, AidInfo & {keriaHost: number}>;
}

export interface ParticipantInvocation {
    environment: TestEnvironmentPreset;
    participantSource: string;
}

export interface SingleSigParticipantConfig {
    environment: TestEnvironmentPreset;
    participants: Record<
        SingleSigParticipantPosition,
        AidInfo & {keriaHost: number}
    >;
}

export function isMainModule(importMetaUrl: string): boolean {
    const entrypoint = process.argv[1];
    return (
        entrypoint !== undefined &&
        pathToFileURL(resolve(entrypoint)).href === importMetaUrl
    );
}

export async function runJsonCli<T extends object>(
    action: () => Promise<T>
): Promise<void> {
    const originalLog = console.log;
    const originalInfo = console.info;
    const writeDiagnostic = (...values: unknown[]) => {
        console.error(...values);
    };

    // Domain functions may retain useful human diagnostics. Keep those off
    // stdout so every runner still emits exactly one machine-readable result.
    console.log = writeDiagnostic;
    console.info = writeDiagnostic;
    try {
        const result = await action();
        process.stdout.write(
            `${JSON.stringify({ok: true, ...result})}\n`
        );
    } catch (error: unknown) {
        const message =
            error instanceof Error ? error.message : String(error);
        process.stderr.write(
            `${JSON.stringify({ok: false, error: message})}\n`
        );
        process.exitCode = 1;
    } finally {
        console.log = originalLog;
        console.info = originalInfo;
    }
}

export function parseNamedArguments(
    argv: string[],
    allowedNames: readonly string[]
): Record<string, string> {
    const allowed = new Set(allowedNames);
    const parsed: Record<string, string> = {};

    for (let index = 0; index < argv.length; index += 2) {
        const name = argv[index];
        const value = argv[index + 1];
        const nameHasExpectedPrefix = name?.startsWith('--') === true;
        const valueIsMissing = value === undefined;
        if (nameHasExpectedPrefix === false || valueIsMissing) {
            throw new Error(
                'Arguments must use named --option value pairs'
            );
        }

        const key = name.slice(2);
        const optionIsUnknown = allowed.has(key) === false;
        if (optionIsUnknown) {
            throw new Error(`Unknown argument --${key}`);
        }

        const optionIsDuplicated = parsed[key] !== undefined;
        if (optionIsDuplicated) {
            throw new Error(`Argument --${key} was provided more than once`);
        }
        parsed[key] = value;
    }

    return parsed;
}

/**
 * Parses the hardened named interface while preserving existing sibling
 * workflow callers until they are migrated independently.
 */
export function parseNamedOrPositionalArguments(
    argv: string[],
    allowedNames: readonly string[],
    positionalNames: readonly string[]
): Record<string, string> {
    const usesNamedArguments = argv[0]?.startsWith('--') === true;
    if (usesNamedArguments) {
        return parseNamedArguments(argv, allowedNames);
    }

    const positionalCountMatches = argv.length === positionalNames.length;
    if (positionalCountMatches === false) {
        throw new Error(
            `Expected named arguments or exactly ${positionalNames.length} legacy positional arguments`
        );
    }

    return Object.fromEntries(
        positionalNames.map((name, index) => [name, argv[index]])
    );
}

export function requireNamedArguments(
    parsed: Record<string, string>,
    requiredNames: readonly string[]
): void {
    const missing = requiredNames.filter((name) => !parsed[name]);
    const requiredArgumentIsMissing = missing.length > 0;
    if (requiredArgumentIsMissing) {
        throw new Error(
            `Missing required argument(s): ${missing.map((name) => `--${name}`).join(', ')}`
        );
    }
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function parseParticipant(
    value: unknown,
    expectedPosition: ParticipantPosition
): AidInfo & {keriaHost: number} {
    const participantIsInvalid = isRecord(value) === false;
    if (participantIsInvalid) {
        throw new Error(`Missing participant ${expectedPosition}`);
    }

    const {position, name, salt, keriaHost} = value;
    const fieldsAreInvalid =
        position !== expectedPosition ||
        typeof name !== 'string' ||
        name.length === 0 ||
        typeof salt !== 'string' ||
        salt.length === 0 ||
        typeof keriaHost !== 'number' ||
        Number.isInteger(keriaHost) === false ||
        keriaHost < 1 ||
        keriaHost > 3;
    if (fieldsAreInvalid) {
        throw new Error(
            `Participant ${expectedPosition} must contain its position, nonempty name and salt, and keriaHost 1-3`
        );
    }

    return {
        position: expectedPosition,
        name: name as string,
        salt: salt as string,
        keriaHost: keriaHost as number,
    };
}

export function readParticipantConfig(configPath: string): ParticipantConfig {
    let decoded: unknown;
    try {
        decoded = JSON.parse(readFileSync(configPath, 'utf8')) as unknown;
    } catch (error: unknown) {
        const reason =
            error instanceof Error ? error.message : String(error);
        throw new Error(
            `Unable to read participant config ${configPath}: ${reason}`,
            {cause: error}
        );
    }

    const configIsInvalid = isRecord(decoded) === false;
    if (configIsInvalid) {
        throw new Error('Participant config must be a JSON object');
    }

    const config = decoded as Record<string, unknown>;
    const participantsValue = config.participants;
    const participantsAreInvalid = isRecord(participantsValue) === false;
    if (participantsAreInvalid) {
        throw new Error(
            'Participant config must contain a participants object'
        );
    }

    const environment = parseEnvironmentPreset(config.environment);
    const positions: ParticipantPosition[] = [
        'qar1',
        'qar2',
        'qar3',
        'person',
    ];
    const participants = Object.fromEntries(
        positions.map((position) => [
            position,
            parseParticipant(participantsValue[position], position),
        ])
    ) as ParticipantConfig['participants'];

    return {environment, participants};
}

export function participantInvocationFromArguments(
    parsed: Record<string, string>
): ParticipantInvocation {
    const configPath = parsed.config;
    const configWasProvided =
        typeof configPath === 'string' && configPath.length > 0;
    if (configWasProvided) {
        return {
            environment: readParticipantConfig(configPath).environment,
            participantSource: configPath,
        };
    }

    const environment = parsed.environment;
    const participantSource = parsed['participant-source'];
    const legacyArgumentsAreMissing =
        typeof environment !== 'string' ||
        typeof participantSource !== 'string' ||
        participantSource.length === 0;
    if (legacyArgumentsAreMissing) {
        throw new Error('A protected --config path is required');
    }

    return {
        environment: parseEnvironmentPreset(environment),
        participantSource,
    };
}

function parseSingleSigParticipant(
    value: unknown,
    expectedPosition: SingleSigParticipantPosition
): AidInfo & {keriaHost: number} {
    const participantIsInvalid = isRecord(value) === false;
    if (participantIsInvalid) {
        throw new Error(`Missing participant ${expectedPosition}`);
    }

    const {position, name, salt, keriaHost} = value;
    const fieldsAreInvalid =
        position !== expectedPosition ||
        typeof name !== 'string' ||
        name.length === 0 ||
        typeof salt !== 'string' ||
        salt.length === 0 ||
        typeof keriaHost !== 'number' ||
        Number.isInteger(keriaHost) === false ||
        keriaHost !== 1;
    if (fieldsAreInvalid) {
        throw new Error(
            `Single-signature participant ${expectedPosition} must contain its position, nonempty name and salt, and keriaHost 1`
        );
    }

    return {
        position: expectedPosition,
        name: name as string,
        salt: salt as string,
        keriaHost: keriaHost as number,
    };
}

export function readSingleSigParticipantConfig(
    configPath: string
): SingleSigParticipantConfig {
    let decoded: unknown;
    try {
        decoded = JSON.parse(readFileSync(configPath, 'utf8')) as unknown;
    } catch (error: unknown) {
        const reason =
            error instanceof Error ? error.message : String(error);
        throw new Error(
            `Unable to read single-signature participant config ${configPath}: ${reason}`,
            {cause: error}
        );
    }

    const configIsInvalid = isRecord(decoded) === false;
    if (configIsInvalid) {
        throw new Error(
            'Single-signature participant config must be a JSON object'
        );
    }

    const config = decoded as Record<string, unknown>;
    const participantsValue = config.participants;
    const participantsAreInvalid = isRecord(participantsValue) === false;
    if (participantsAreInvalid) {
        throw new Error(
            'Single-signature participant config must contain a participants object'
        );
    }

    const environment = parseEnvironmentPreset(config.environment);
    const positions: SingleSigParticipantPosition[] = [
        'qar',
        'person',
        'qvi',
    ];
    const participants = Object.fromEntries(
        positions.map((position) => [
            position,
            parseSingleSigParticipant(
                participantsValue[position],
                position
            ),
        ])
    ) as SingleSigParticipantConfig['participants'];

    return {environment, participants};
}

/**
 * Resolves a protected single-signature config without placing participant
 * salts in process arguments or emitted results. Legacy callers may continue
 * supplying their existing positional participant string.
 */
export function singleSigParticipantInvocationFromArguments(
    parsed: Record<string, string>
): ParticipantInvocation {
    const configPath = parsed.config;
    const configWasProvided =
        typeof configPath === 'string' && configPath.length > 0;
    if (configWasProvided) {
        const config = readSingleSigParticipantConfig(configPath);
        const participantSource = (
            ['qar', 'person', 'qvi'] as const
        )
            .map((position) => {
                const participant = config.participants[position];
                return [
                    participant.position,
                    participant.name,
                    participant.salt,
                ].join('|');
            })
            .join(',');
        return {
            environment: config.environment,
            participantSource,
        };
    }

    const environment = parsed.environment;
    const participantSource = parsed['participant-source'];
    const legacyArgumentsAreMissing =
        typeof environment !== 'string' ||
        typeof participantSource !== 'string' ||
        participantSource.length === 0;
    if (legacyArgumentsAreMissing) {
        throw new Error('A protected --config path is required');
    }

    return {
        environment: parseEnvironmentPreset(environment),
        participantSource,
    };
}
