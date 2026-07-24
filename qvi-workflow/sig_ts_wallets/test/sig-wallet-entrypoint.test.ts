import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {describe, it} from 'node:test';

import {requireHttpUrl} from '../src/client.ts';
import {
    readPendingWorkflowEvent,
    run,
    UsageError,
} from '../src/sig-wallet.ts';

const PENDING_EVENT = {
    eventKind: 'rotation',
    groupPrefix: 'E-group',
    eventSaid: 'E-event',
    eventSequence: '2',
    signingMembers: ['E-qar1', 'E-qar2', 'E-qar3'],
    rotationMembers: ['E-qar1', 'E-qar2', 'E-qar4'],
    members: [
        {
            memberPrefix: 'E-qar1',
            operationName: 'op-1',
            notificationIds: [],
        },
        {
            memberPrefix: 'E-qar2',
            operationName: 'op-2',
            notificationIds: ['note-2'],
        },
        {
            memberPrefix: 'E-qar3',
            operationName: 'op-3',
            notificationIds: ['note-3'],
        },
    ],
};

describe('Signify wallet entrypoint boundary', () => {
    it('imports without performing workflow work', async () => {
        await assert.doesNotReject(
            import(`../src/sig-wallet.ts?test=${Date.now()}`)
        );
    });

    it('rejects unknown actions and arguments as usage errors', async () => {
        await assert.rejects(run([]), UsageError);
        await assert.rejects(
            run(['preflight', '--config', 'config.json', '--extra', 'x']),
            UsageError
        );
    });

    it('accepts only credential-free HTTP(S) URLs', () => {
        assert.equal(
            requireHttpUrl('http://keria1:3901/', 'admin'),
            'http://keria1:3901'
        );
        assert.throws(
            () => requireHttpUrl('ftp://keria1/path', 'admin'),
            /HTTP\(S\)/
        );
        assert.throws(
            () => requireHttpUrl('http://user:pass@keria1', 'admin'),
            /without credentials/
        );
        assert.throws(
            () => requireHttpUrl('not a URL', 'admin'),
            /malformed/
        );
    });

    it('validates the exact persisted event at the JSON boundary', async () => {
        const directory = await fs.mkdtemp(
            path.join(os.tmpdir(), 'qvi-pending-')
        );
        const eventPath = path.join(directory, 'event.json');
        try {
            await fs.writeFile(
                eventPath,
                `${JSON.stringify(PENDING_EVENT)}\n`
            );
            assert.deepEqual(
                await readPendingWorkflowEvent(eventPath),
                PENDING_EVENT
            );

            await fs.writeFile(
                eventPath,
                JSON.stringify({...PENDING_EVENT, unexpected: true})
            );
            await assert.rejects(
                readPendingWorkflowEvent(eventPath),
                /incompatible fields/
            );

            await fs.writeFile(
                eventPath,
                JSON.stringify({
                    ...PENDING_EVENT,
                    rotationMembers: [
                        'E-qar1',
                        'E-qar1',
                        'E-qar4',
                    ],
                })
            );
            await assert.rejects(
                readPendingWorkflowEvent(eventPath),
                /duplicate/
            );

            await fs.writeFile(eventPath, '{');
            await assert.rejects(readPendingWorkflowEvent(eventPath));
        } finally {
            await fs.rm(directory, {recursive: true, force: true});
        }
    });
});
