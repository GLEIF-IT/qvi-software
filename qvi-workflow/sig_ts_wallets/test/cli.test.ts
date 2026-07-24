import assert from 'node:assert/strict';
import {
    mkdtempSync,
    rmSync,
    writeFileSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {describe, it} from 'node:test';

import {
    parseNamedArguments,
    participantConfigFromArguments,
    singleSigParticipantInvocationFromArguments,
} from '../src/cli.ts';

const workflowRunnerModules = [
    '../src/qars/qars-and-person-setup.ts',
    '../src/qars/resolve-oobi-gars-lars-sally.ts',
    '../src/qars/qvi-resolve-oobi.ts',
    '../src/qars/qars-refresh-geda-multisig-state.ts',
    '../src/qars/qars-create-qvi-multisig.ts',
    '../src/qars/qars-complete-multisig-incept.ts',
    '../src/qars/qars-authorize-endroles-get-qvi-oobi.ts',
    '../src/qars/qars-admit-credential-qvi.ts',
    '../src/qars/qars-registry-create.ts',
    '../src/qars/qars-le-credential-create.ts',
    '../src/qars/qars-oor-credential-create.ts',
    '../src/qars/qars-ecr-credential-create.ts',
    '../src/qars/qars-revoke-credential.ts',
    '../src/qars/qars-present-credential.ts',
    '../src/qars/qars-assert-group-state.ts',
    '../src/qars/qars-assert-credential-state.ts',
    '../src/person-resolve-qvi-oobi.ts',
    '../src/person/person-admit-credential.ts',
    '../src/person/person-grant-credential.ts',
    '../src/person/person-assert-credential-state.ts',
    '../src/keria-challenge.ts',
    '../src/qars/qar-check-issued-credential.ts',
    '../src/qars/qars-admit-ecr-auth-credential.ts',
    '../src/qars/qars-rotate-qvi-multisig.ts',
    '../src/qars/qar-check-qvi-multisig.ts',
    '../src/qars/qars-resolve-geda-and-le-oobis.ts',
    '../src/qars/qar-check-received-credential.ts',
    '../src/person/person-check-received-credential.ts',
    '../src/person/person-get-sally-pre.ts',
    '../src/single-sig/resolve-qvi-oobi-person.ts',
    '../src/single-sig/qvi-check-received-credential.ts',
    '../src/single-sig/qvi-admit-credential.ts',
    '../src/single-sig/resolve-oobis-lar-gar-sally.ts',
    '../src/single-sig/delegation-completion-qvi.ts',
    '../src/single-sig/qvi-present-credential.ts',
    '../src/single-sig/resolve-schema-oobis-qvi.ts',
    '../src/single-sig/qar-and-person-setup.ts',
    '../src/single-sig/create-qvi-delegate.ts',
] as const;

describe('workflow runner command lines', () => {
    it('imports every supported workflow runner without executing it', async () => {
        for (const modulePath of workflowRunnerModules) {
            const imported = await import(modulePath);
            assert.equal(typeof imported, 'object');
        }
    });

    it('accepts named arguments and rejects unknown options', () => {
        const parsed = parseNamedArguments(
            [
                '--config',
                '/run/qvi/participants.json',
                '--credential-said',
                'ECredential',
            ],
            ['config', 'credential-said']
        );
        assert.deepEqual(parsed, {
            config: '/run/qvi/participants.json',
            'credential-said': 'ECredential',
        });

        assert.throws(
            () =>
                parseNamedArguments(
                    ['--unknown', 'value'],
                    ['config']
                ),
            /Unknown argument/
        );
    });

    it('rejects positional workflow arguments', () => {
        assert.throws(
            () =>
                parseNamedArguments(
                    ['docker-tsx', 'ECredential'],
                    ['environment', 'credential-said']
                ),
            /named --option value pairs/
        );
    });

    it('loads single-signature participants from a config path', () => {
        const directory = mkdtempSync(
            join(tmpdir(), 'qvi-single-sig-config-')
        );
        const configPath = join(directory, 'participants.json');
        writeFileSync(
            configPath,
            JSON.stringify({
                environment: 'single-sig-docker',
                participants: {
                    qar: {
                        position: 'qar',
                        name: 'QAR',
                        salt: 'qar-salt',
                        keriaHost: 1,
                    },
                    person: {
                        position: 'person',
                        name: 'Person',
                        salt: 'person-salt',
                        keriaHost: 1,
                    },
                    qvi: {
                        position: 'qvi',
                        name: 'QVI',
                        salt: 'qvi-salt',
                        keriaHost: 1,
                    },
                },
            }),
            {mode: 0o600}
        );

        try {
            assert.deepEqual(
                singleSigParticipantInvocationFromArguments({
                    config: configPath,
                }),
                {
                    environment: 'single-sig-docker',
                    participantSource:
                        'qar|QAR|qar-salt,' +
                        'person|Person|person-salt,' +
                        'qvi|QVI|qvi-salt',
                }
            );
        } finally {
            rmSync(directory, {recursive: true, force: true});
        }
    });

    it('loads QVI participants from ordinary environment arguments', () => {
        const config = participantConfigFromArguments({
            environment: 'docker-tsx',
            'participant-source': [
                'qar1|QAR1|qar1-salt',
                'qar2|QAR2|qar2-salt',
                'qar3|QAR3|qar3-salt',
                'person|Person|person-salt',
            ].join(','),
        });

        assert.equal(config.environment, 'docker-tsx');
        assert.deepEqual(
            Object.values(config.participants).map(
                ({position, name, keriaHost}) => ({
                    position,
                    name,
                    keriaHost,
                })
            ),
            [
                {position: 'qar1', name: 'QAR1', keriaHost: 1},
                {position: 'qar2', name: 'QAR2', keriaHost: 2},
                {position: 'qar3', name: 'QAR3', keriaHost: 3},
                {position: 'person', name: 'Person', keriaHost: 1},
            ]
        );
    });
});
