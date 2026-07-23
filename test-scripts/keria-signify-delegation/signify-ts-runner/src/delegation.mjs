import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
    Algos,
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
const ARTIFACT = path.join(
    process.env.QVI_DATA_DIR ?? '/qvi-data',
    'signify-ts-delegation.json'
);

const WIL_PRE = 'BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM';
const WIL_OOBI = `http://witness-demo:5643/oobi/${WIL_PRE}/controller?name=Wil&tag=witness`;
const QVI_WITS = [WIL_PRE];
const QVI_THRESHOLD = ['1/2', '1/2', '1/2'];
const QVI_NAME = 'signify-ts-qvi';
const MEMBERS = [
    ['signify-ts-qar1', 'tsqar1abcdefghijklmno'],
    ['signify-ts-qar2', 'tsqar2abcdefghijklmno'],
    ['signify-ts-qar3', 'tsqar3abcdefghijklmno'],
];

const POLL_INTERVAL_MS = Number(process.env.SIGNIFY_TS_DELEGATION_POLL_INTERVAL_MS ?? '500');
const DEFAULT_TIMEOUT_MS = Number(process.env.SIGNIFY_TS_DELEGATION_TIMEOUT_MS ?? '180000');

function log(message) {
    console.log(`[signify-ts] ${message}`);
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitUntil(fetcher, readyFn, describe, timeoutMs = DEFAULT_TIMEOUT_MS) {
    const deadline = Date.now() + timeoutMs;
    let lastValue;
    let lastError;
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
        if (Date.now() >= deadline)
            throw new Error(
                `timed out waiting for ${describe}; lastError=${String(lastError)}; ` +
                    `lastValue=${JSON.stringify(lastValue)}`
            );
        await sleep(POLL_INTERVAL_MS);
    }
}

async function connectClient(passcode) {
    await ready();
    const client = new SignifyClient(ADMIN_URL, passcode.padEnd(21, '_'), Tier.low, BOOT_URL);
    try {
        await client.connect();
    } catch {
        const response = await client.boot();
        if (!response.ok) {
            throw new Error(`failed to boot SignifyTS client: ${response.status}`);
        }
        await client.connect();
    }
    return client;
}

async function clients() {
    return await Promise.all(MEMBERS.map(([, passcode]) => connectClient(passcode)));
}

async function waitOperation(client, operation, timeoutMs = DEFAULT_TIMEOUT_MS) {
    let op =
        typeof operation === 'string' ? await client.operations().get(operation) : operation;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        op = await client.operations().wait(op, {
            signal: controller.signal,
            minSleep: POLL_INTERVAL_MS,
            maxSleep: POLL_INTERVAL_MS,
            increaseFactor: 1,
        });
    } finally {
        clearTimeout(timer);
    }
    return op;
}

async function resolveOobi(client, oobi, alias) {
    await waitOperation(client, await client.oobis().resolve(oobi, alias));
}

async function waitForIdentifierOobi(client, name) {
    const oobis = await waitUntil(
        async () => (await client.oobis().get(name, 'agent')).oobis,
        (value) => value.length > 0,
        `agent OOBI for ${name}`
    );
    return oobis[0];
}

async function createIdentifier(client, name) {
    await resolveOobi(client, WIL_OOBI, 'wil');
    const result = await client.identifiers().create(name, { toad: 1, wits: QVI_WITS });
    await waitOperation(client, await result.op());
    const endRole = await client.identifiers().addEndRole(name, 'agent', client.agent.pre);
    await waitOperation(client, await endRole.op());
    await waitForIdentifierOobi(client, name);
    const aid = await client.identifiers().get(name);
    log(`created member ${name}: ${aid.prefix}`);
    return aid;
}

async function exchangeAgentOobis(participants) {
    for (let i = 0; i < participants.length; i += 1) {
        const [source, sourceName] = participants[i];
        for (const [target, targetName] of participants.slice(i + 1)) {
            await resolveOobi(target, await waitForIdentifierOobi(source, sourceName), sourceName);
            await resolveOobi(source, await waitForIdentifierOobi(target, targetName), targetName);
        }
    }
}

function normalizeState(value) {
    if (Array.isArray(value)) {
        assert.equal(value.length, 1);
        return value[0];
    }
    return value;
}

async function getStates(client, prefixes) {
    return await Promise.all(
        prefixes.map(async (prefix) => normalizeState(await client.keyStates().get(prefix)))
    );
}

function embedEvent(serder, sigs) {
    const ims = d(messagize(serder, sigs.map((sig) => new Siger({ qb64: sig }))));
    return [serder, ims.substring(serder.size)];
}

async function waitForMultisigRequest(client, route) {
    const notes = await waitUntil(
        async () =>
            (await client.notifications().list()).notes.filter(
                (note) => note.r === false && note.a?.r === route
            ),
        (value) => value.length > 0,
        `${route} notification`
    );
    const note = notes.at(-1);
    await client.notifications().mark(note.i);
    return await waitUntil(
        async () => await client.groups().getRequest(note.a.d),
        (request) => request.length > 0 && request[0].exn.r === route,
        `${route} request payload`
    );
}

async function startMultisigIncept(client, localMemberName, participants, delpre) {
    const member = await client.identifiers().get(localMemberName);
    const states = await getStates(client, participants);
    const result = await client.identifiers().create(QVI_NAME, {
        algo: Algos.group,
        mhab: member,
        isith: QVI_THRESHOLD,
        nsith: QVI_THRESHOLD,
        toad: 1,
        wits: QVI_WITS,
        delpre,
        states,
        rstates: states,
    });
    const smids = states.map((state) => state.i);
    await client.exchanges().send(
        localMemberName,
        'multisig',
        member,
        '/multisig/icp',
        { gid: result.serder.pre, smids, rmids: smids },
        { icp: embedEvent(result.serder, result.sigs) },
        participants.filter((prefix) => prefix !== member.prefix)
    );
    return result.serder;
}

async function acceptMultisigIncept(client, localMemberName) {
    const request = await waitForMultisigRequest(client, '/multisig/icp');
    const exn = assertMultisigIcp(request[0]).exn;
    const icp = exn.e.icp;
    const smids = exn.a.smids;
    const rmids = exn.a.rmids ?? smids;
    const member = await client.identifiers().get(localMemberName);
    const result = await client.identifiers().create(QVI_NAME, {
        algo: Algos.group,
        mhab: member,
        isith: icp.kt,
        nsith: icp.nt,
        toad: Number.parseInt(icp.bt, 10),
        wits: icp.b,
        delpre: icp.di,
        states: await getStates(client, smids),
        rstates: await getStates(client, rmids),
    });
    await client.exchanges().send(
        localMemberName,
        'multisig',
        member,
        '/multisig/icp',
        { gid: result.serder.pre, smids, rmids },
        { icp: embedEvent(result.serder, result.sigs) },
        smids.filter((prefix) => prefix !== member.prefix)
    );
}

async function waitForGroupState(client, qviPre, gedaPre) {
    return await waitUntil(
        async () => await client.identifiers().get(QVI_NAME),
        (group) =>
            group.prefix === qviPre &&
            group.state.di === gedaPre &&
            group.state.s === '0' &&
            JSON.stringify(group.state.kt) === JSON.stringify(QVI_THRESHOLD) &&
            JSON.stringify(group.state.nt) === JSON.stringify(QVI_THRESHOLD),
        `2-of-3 delegated group state for ${QVI_NAME}`
    );
}

async function assertMultisigMembers(client, expected) {
    const members = await client.identifiers().members(QVI_NAME);
    for (const role of ['signing', 'rotation']) {
        assert.deepEqual(new Set(members[role].map((member) => member.aid)), new Set(expected));
    }
}

async function setup() {
    const gedaPre = process.env.GEDA_PRE;
    const gedaOobi = process.env.GEDA_OOBI;
    assert.ok(gedaPre && gedaOobi, 'GEDA_PRE and GEDA_OOBI are required');
    const cs = await clients();
    const names = MEMBERS.map(([name]) => name);
    const aids = [];
    for (let i = 0; i < cs.length; i += 1) {
        aids.push(await createIdentifier(cs[i], names[i]));
    }
    await exchangeAgentOobis(cs.map((client, index) => [client, names[index]]));
    for (const client of cs) {
        await resolveOobi(client, gedaOobi, 'geda');
    }

    const participants = aids.map((aid) => aid.prefix);
    const serder = await startMultisigIncept(cs[0], names[0], participants, gedaPre);
    for (let i = 1; i < cs.length; i += 1) {
        await acceptMultisigIncept(cs[i], names[i]);
    }
    fs.writeFileSync(
        ARTIFACT,
        `${JSON.stringify({ gedaPre, qviPre: serder.pre, members: participants }, null, 2)}\n`
    );
    log(`wrote delegated inception artifact for ${serder.pre}`);
}

async function complete() {
    assert.ok(fs.existsSync(ARTIFACT), `missing artifact ${ARTIFACT}`);
    const artifact = JSON.parse(fs.readFileSync(ARTIFACT, 'utf8'));
    const cs = await clients();
    for (const client of cs) {
        const operation = await client.keyStates().query(artifact.gedaPre, '1');
        const state = normalizeState((await waitOperation(client, operation)).response);
        assert.equal(state.i, artifact.gedaPre);
        assert.ok(Number.parseInt(state.s, 10) >= 1);
    }

    const groups = [];
    for (const client of cs) {
        groups.push(await waitForGroupState(client, artifact.qviPre, artifact.gedaPre));
    }
    groups.forEach((group, index) => {
        const state = group.state;
        log(
            `verified ${MEMBERS[index][0]}: prefix=${group.prefix} di=${state.di} ` +
                `s=${state.s} kt=${JSON.stringify(state.kt)} nt=${JSON.stringify(state.nt)}`
        );
    });
    await assertMultisigMembers(cs[0], artifact.members);
    log('PASS: SignifyTS 2-of-3 multisig delegate approved by KERIpy multisig KLI delegator');
}

async function main() {
    if (process.argv[2] === 'setup') {
        await setup();
    } else if (process.argv[2] === 'complete') {
        await complete();
    } else {
        throw new Error('usage: delegation.mjs setup|complete');
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
