import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {
    Algos,
    HabState,
    Operation,
    Siger,
    SignifyClient,
    Tier,
    assertMultisigIcp,
    d,
    messagize,
    ready,
} from 'signify-ts';

const ADMIN_URL = process.env.KERIA_ADMIN_URL ?? 'http://keria:3901';
const BOOT_URL = process.env.KERIA_BOOT_URL ?? 'http://keria:3903';
const QVI_DATA_DIR = process.env.QVI_DATA_DIR ?? '/qvi-data';
const SCENARIO = process.env.SCENARIO ?? 'signify-ts';
const ARTIFACT = path.join(QVI_DATA_DIR, `${SCENARIO}-delegation.json`);

const GEDA_PRE = process.env.GEDA_PRE;
const GEDA_OOBI = process.env.GEDA_OOBI;

const WIL_PRE = 'BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM';
const WIL_OOBI = `http://witness-demo:5643/oobi/${WIL_PRE}/controller?name=Wil&tag=witness`;
const QVI_WITS = [WIL_PRE];
const QVI_NAME = 'signify-ts-qvi';
const MEMBERS: Array<[string, string]> = [
    ['signify-ts-qar1', 'tsqar1abcdefghijklmno'],
    ['signify-ts-qar2', 'tsqar2abcdefghijklmno'],
    ['signify-ts-qar3', 'tsqar3abcdefghijklmno'],
];

const POLL_INTERVAL_MS = Number(process.env.SIGNIFY_TS_DELEGATION_POLL_INTERVAL_MS ?? '500');
const DEFAULT_TIMEOUT_MS = Number(process.env.SIGNIFY_TS_DELEGATION_TIMEOUT_MS ?? '180000');

type AnyOperation = Operation | { name: string; done?: boolean; [key: string]: any };

interface Artifact {
    client: string;
    gedaPre: string;
    qviPre: string;
    members: string[];
    anchor: { i: string; s: string; d: string };
    operations: string[];
}

function log(message: string): void {
    console.log(`[signify-ts] ${message}`);
}

function requireEnv(): { gedaPre: string; gedaOobi: string } {
    assert.ok(GEDA_PRE, 'GEDA_PRE is required');
    assert.ok(GEDA_OOBI, 'GEDA_OOBI is required');
    return { gedaPre: GEDA_PRE, gedaOobi: GEDA_OOBI };
}

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitUntil<T>(
    fetcher: () => Promise<T>,
    readyFn: (value: T) => boolean,
    describe: string,
    timeoutMs = DEFAULT_TIMEOUT_MS
): Promise<T> {
    const deadline = Date.now() + timeoutMs;
    let lastValue: T | undefined;
    let lastError: unknown;
    while (true) {
        try {
            const value = await fetcher();
            lastValue = value;
            if (readyFn(value)) {
                return value;
            }
        } catch (error) {
            lastError = error;
        }

        if (Date.now() >= deadline) {
            throw new Error(
                `timed out waiting for ${describe}; lastError=${String(
                    lastError
                )}; lastValue=${JSON.stringify(lastValue)}`
            );
        }
        await sleep(POLL_INTERVAL_MS);
    }
}

async function connectClient(passcode: string): Promise<SignifyClient> {
    await ready();
    const client = new SignifyClient(ADMIN_URL, passcode.padEnd(21, '_'), Tier.low, BOOT_URL);
    try {
        await client.connect();
    } catch {
        const response = await client.boot();
        if (!response.ok) {
            throw new Error(`failed to boot SignifyTS client: ${response.status} ${await response.text()}`);
        }
        await client.connect();
    }
    return client;
}

async function clients(): Promise<SignifyClient[]> {
    return await Promise.all(MEMBERS.map(([, passcode]) => connectClient(passcode)));
}

async function waitOperation(
    client: SignifyClient,
    operation: AnyOperation | string,
    timeoutMs = DEFAULT_TIMEOUT_MS
): Promise<AnyOperation> {
    let op: AnyOperation =
        typeof operation === 'string'
            ? ((await client.operations().get(operation)) as AnyOperation)
            : operation;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        op = (await client.operations().wait(op as Operation, {
            signal: controller.signal,
            minSleep: POLL_INTERVAL_MS,
            maxSleep: POLL_INTERVAL_MS,
            increaseFactor: 1,
        })) as AnyOperation;
    } finally {
        clearTimeout(timer);
    }

    if (op.name) {
        try {
            await client.operations().delete(op.name);
        } catch {
            // The operation may already have been removed by a dependency wait.
        }
    }
    return op;
}

async function resolveOobi(client: SignifyClient, oobi: string, alias: string): Promise<void> {
    await waitOperation(client, await client.oobis().resolve(oobi, alias));
}

async function ensureWitness(client: SignifyClient): Promise<void> {
    await resolveOobi(client, WIL_OOBI, 'wil');
}

async function waitForIdentifierOobi(
    client: SignifyClient,
    name: string,
    role: string
): Promise<string> {
    const oobis = await waitUntil(
        async () => (await client.oobis().get(name, role)).oobis,
        (value) => value.length > 0,
        `${role} OOBI for ${name}`
    );
    return oobis[0];
}

async function waitForEndRole(client: SignifyClient, name: string, eid: string): Promise<void> {
    const aid = await client.identifiers().get(name);
    await waitUntil(
        async () => await client.oobis().endroles(aid.prefix, 'agent'),
        (roles) => roles.some((role: any) => role.eid === eid),
        `agent end role for ${name}`
    );
}

async function getOrCreateIdentifier(client: SignifyClient, name: string): Promise<HabState> {
    try {
        return await client.identifiers().get(name);
    } catch {
        // Create below.
    }

    await ensureWitness(client);
    const result = await client.identifiers().create(name, {
        toad: 1,
        wits: QVI_WITS,
    });
    await waitOperation(client, await result.op());

    const endRoleResult = await client
        .identifiers()
        .addEndRole(name, 'agent', client.agent!.pre);
    await waitOperation(client, await endRoleResult.op());
    await waitForEndRole(client, name, client.agent!.pre);
    await waitForIdentifierOobi(client, name, 'agent');

    const aid = await client.identifiers().get(name);
    log(`created member ${name}: ${aid.prefix}`);
    return aid;
}

async function resolveAgentOobi(
    source: SignifyClient,
    sourceName: string,
    target: SignifyClient
): Promise<void> {
    const oobi = await waitForIdentifierOobi(source, sourceName, 'agent');
    await resolveOobi(target, oobi, sourceName);
}

async function exchangeAgentOobis(participants: Array<[SignifyClient, string]>): Promise<void> {
    for (let i = 0; i < participants.length; i += 1) {
        const [source, sourceName] = participants[i];
        for (const [target, targetName] of participants.slice(i + 1)) {
            await resolveAgentOobi(source, sourceName, target);
            await resolveAgentOobi(target, targetName, source);
        }
    }
}

function normalizeState(value: any): any {
    if (Array.isArray(value)) {
        assert.equal(value.length, 1);
        return value[0];
    }
    return value;
}

async function getStates(client: SignifyClient, prefixes: string[]): Promise<any[]> {
    const states = [];
    for (const prefix of prefixes) {
        states.push(normalizeState(await client.keyStates().get(prefix)));
    }
    return states;
}

function embedEvent(serder: any, sigs: string[]): [any, string] {
    const sigers = sigs.map((sig) => new Siger({ qb64: sig }));
    const ims = d(messagize(serder, sigers));
    return [serder, ims.substring(serder.size)];
}

async function unreadNotes(client: SignifyClient, route: string): Promise<any[]> {
    const response = await client.notifications().list();
    return response.notes.filter((note: any) => note.r === false && note.a?.r === route);
}

async function waitForMultisigRequest(client: SignifyClient, route: string): Promise<any[]> {
    const notes = await waitUntil(
        async () => await unreadNotes(client, route),
        (value) => value.length > 0,
        `${route} notification`
    );
    const note = notes[notes.length - 1];
    await client.notifications().mark(note.i);
    return await waitUntil(
        async () => await client.groups().getRequest(note.a.d),
        (request) => request.length > 0 && request[0].exn.r === route,
        `${route} request payload`
    );
}

async function startMultisigIncept(
    client: SignifyClient,
    input: {
        groupName: string;
        localMemberName: string;
        participants: string[];
        delpre: string;
    }
): Promise<{ operation: AnyOperation; serder: any }> {
    const member = await client.identifiers().get(input.localMemberName);
    const states = await getStates(client, input.participants);
    const result = await client.identifiers().create(input.groupName, {
        algo: Algos.group,
        mhab: member,
        isith: ['1/3', '1/3', '1/3'],
        nsith: ['1/3', '1/3', '1/3'],
        toad: 1,
        wits: QVI_WITS,
        delpre: input.delpre,
        states,
        rstates: states,
    });

    const serder = result.serder;
    const smids = states.map((state) => state.i);
    const recipients = input.participants.filter((prefix) => prefix !== member.prefix);
    await client.exchanges().send(
        input.localMemberName,
        'multisig',
        member,
        '/multisig/icp',
        { gid: serder.pre, smids, rmids: smids },
        { icp: embedEvent(serder, result.sigs) },
        recipients
    );
    return { operation: await result.op(), serder };
}

async function acceptMultisigIncept(
    client: SignifyClient,
    input: { groupName: string; localMemberName: string }
): Promise<AnyOperation> {
    const request = await waitForMultisigRequest(client, '/multisig/icp');
    const groupExn = assertMultisigIcp(request[0] as any) as any;
    const icp = groupExn.exn.e.icp;
    const smids = groupExn.exn.a.smids;
    const rmids = groupExn.exn.a.rmids ?? smids;
    const member = await client.identifiers().get(input.localMemberName);
    const states = await getStates(client, smids);
    const rstates = await getStates(client, rmids);
    const result = await client.identifiers().create(input.groupName, {
        algo: Algos.group,
        mhab: member,
        isith: icp.kt,
        nsith: icp.nt,
        toad: parseInt(icp.bt),
        wits: icp.b,
        delpre: icp.di,
        states,
        rstates,
    });
    const recipients = smids.filter((prefix: string) => prefix !== member.prefix);
    await client.exchanges().send(
        input.localMemberName,
        'multisig',
        member,
        '/multisig/icp',
        { gid: result.serder.pre, smids, rmids },
        { icp: embedEvent(result.serder, result.sigs) },
        recipients
    );
    return await result.op();
}

async function assertMultisigMembers(
    client: SignifyClient,
    groupName: string,
    expected: string[]
): Promise<void> {
    const members = await client.identifiers().members(groupName);
    assert.deepEqual(
        new Set((members as any).signing.map((member: any) => member.aid)),
        new Set(expected)
    );
    assert.deepEqual(
        new Set((members as any).rotation.map((member: any) => member.aid)),
        new Set(expected)
    );
}

async function waitForGroupState(
    client: SignifyClient,
    groupName: string,
    qviPre: string,
    gedaPre: string
): Promise<HabState> {
    return await waitUntil(
        async () => await client.identifiers().get(groupName),
        (group) =>
            group.prefix === qviPre &&
            group.state.di === gedaPre &&
            group.state.s === '0',
        `delegated group state for ${groupName}`
    );
}

async function clearGroupOperation(
    client: SignifyClient,
    operationName: string,
    groupName: string,
    qviPre: string,
    gedaPre: string
): Promise<void> {
    await waitForGroupState(client, groupName, qviPre, gedaPre);
    let operation: AnyOperation;
    try {
        operation = (await client.operations().get(operationName)) as AnyOperation;
    } catch {
        return;
    }

    if (operation.done === true) {
        await waitOperation(client, operation);
        return;
    }
    // KERIA 0.4.x can leave the group op pending after the identifier state is
    // materialized. The state check above is the convergence proof for this test.
    await client.operations().delete(operationName);
}

async function unfinishedOperations(client: SignifyClient): Promise<AnyOperation[]> {
    const operations = (await client.operations().list()) as AnyOperation[];
    return operations.filter((operation) => operation.done === false);
}

async function setup(): Promise<void> {
    const { gedaPre, gedaOobi } = requireEnv();
    fs.mkdirSync(QVI_DATA_DIR, { recursive: true });
    const cs = await clients();
    const names = MEMBERS.map(([name]) => name);

    const aids = [];
    for (const [client, name] of cs.map((client, index) => [client, names[index]] as const)) {
        aids.push(await getOrCreateIdentifier(client, name));
    }
    await exchangeAgentOobis(cs.map((client, index) => [client, names[index]] as [SignifyClient, string]));
    for (const client of cs) {
        await resolveOobi(client, gedaOobi, 'geda');
    }

    const participants = aids.map((aid) => aid.prefix);
    const { operation, serder } = await startMultisigIncept(cs[0], {
        groupName: QVI_NAME,
        localMemberName: names[0],
        participants,
        delpre: gedaPre,
    });
    const operations = [operation];
    for (let i = 1; i < cs.length; i += 1) {
        operations.push(
            await acceptMultisigIncept(cs[i], {
                groupName: QVI_NAME,
                localMemberName: names[i],
            })
        );
    }

    const artifact: Artifact = {
        client: 'signify-ts',
        gedaPre,
        qviPre: serder.pre,
        members: participants,
        anchor: { i: serder.pre, s: '0', d: serder.pre },
        operations: operations.map((op) => op.name),
    };
    fs.writeFileSync(ARTIFACT, `${JSON.stringify(artifact, null, 2)}\n`);
    log(`wrote delegated inception artifact for ${serder.pre}`);
}

async function complete(): Promise<void> {
    assert.ok(fs.existsSync(ARTIFACT), `missing artifact ${ARTIFACT}`);
    const artifact = JSON.parse(fs.readFileSync(ARTIFACT, 'utf8')) as Artifact;
    const cs = await clients();
    assert.deepEqual(artifact.anchor, { i: artifact.qviPre, s: '0', d: artifact.qviPre });

    for (const client of cs) {
        const result = await waitOperation(
            client,
            await client.keyStates().query(artifact.gedaPre, '1')
        );
        const state = normalizeState((result as any).response);
        assert.equal(state.i, artifact.gedaPre);
        assert.ok(Number.parseInt(state.s, 10) >= 1);
    }
    for (let i = 0; i < cs.length; i += 1) {
        await clearGroupOperation(
            cs[i],
            artifact.operations[i],
            QVI_NAME,
            artifact.qviPre,
            artifact.gedaPre
        );
    }

    const groups = [];
    for (const client of cs) {
        groups.push(await client.identifiers().get(QVI_NAME));
    }
    assert.deepEqual(new Set(groups.map((group) => group.prefix)), new Set([artifact.qviPre]));
    for (const group of groups) {
        assert.equal(group.state.di, artifact.gedaPre);
        assert.equal(group.state.s, '0');
    }

    await assertMultisigMembers(cs[0], QVI_NAME, artifact.members);
    const incomplete = [];
    for (const client of cs) {
        incomplete.push(...(await unfinishedOperations(client)));
    }
    assert.equal(incomplete.length, 0, `incomplete operations remain: ${JSON.stringify(incomplete)}`);
    log('PASS: SignifyTS multisig delegate approved by KERIpy multisig KLI delegator');
}

async function main(): Promise<void> {
    const command = process.argv[2];
    if (command === 'setup') {
        await setup();
    } else if (command === 'complete') {
        await complete();
    } else {
        throw new Error('usage: tsx src/delegation.ts setup|complete');
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
