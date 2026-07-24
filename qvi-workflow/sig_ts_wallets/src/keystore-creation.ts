import {
    CreateIdentiferArgs,
    EventResult,
    HabState,
    randomPasscode,
    ready,
    SignifyClient,
    Tier,
} from 'signify-ts';
import { resolveEnvironment, TestEnvironmentPreset } from './resolve-env';
import { waitOperation } from './operations';
import {workflowTimeoutMs} from './retry.ts';

let boundedFetchIsInstalled = false;

function installBoundedFetch(): void {
    if (boundedFetchIsInstalled) {
        return;
    }

    const originalFetch = globalThis.fetch.bind(globalThis);
    globalThis.fetch = async (
        input: RequestInfo | URL,
        init: RequestInit = {}
    ): Promise<Response> => {
        const controller = new AbortController();
        const timeout = setTimeout(
            () => controller.abort(
                new Error('KERIA HTTP request timed out')
            ),
            workflowTimeoutMs()
        );
        const upstreamSignal = init.signal;
        const abortFromUpstream = () =>
            controller.abort(upstreamSignal?.reason);
        upstreamSignal?.addEventListener(
            'abort',
            abortFromUpstream,
            {once: true}
        );

        try {
            return await originalFetch(input, {
                ...init,
                signal: controller.signal,
            });
        } finally {
            clearTimeout(timeout);
            upstreamSignal?.removeEventListener(
                'abort',
                abortFromUpstream
            );
        }
    };
    boundedFetchIsInstalled = true;
}

/**
 * Connect or boot a SignifyClient instance
 */
export async function getOrCreateClient(
    bran: string | undefined = undefined, 
    environment: TestEnvironmentPreset | undefined = undefined,
    keriaHost?: number
): Promise<SignifyClient> {
    const env = resolveEnvironment(environment);
    installBoundedFetch();
    await ready();
    bran ??= randomPasscode();
    bran = bran.padEnd(21, '_');
    let adminUrl = env.adminUrl1;
    let bootUrl = env.bootUrl1;
    switch (keriaHost) {
        case 1:
            adminUrl = env.adminUrl1;
            bootUrl = env.bootUrl1;
            break;
        case 2:
            adminUrl = env.adminUrl2 ?? env.adminUrl1;
            bootUrl = env.bootUrl2 ?? env.bootUrl1;
            break;
        case 3:
            adminUrl = env.adminUrl3 ?? env.adminUrl1;
            bootUrl = env.bootUrl3 ?? env.bootUrl1;
            break;
        default:
            adminUrl = env.adminUrl1;
            bootUrl = env.bootUrl1;
            break;
    }
    const client = new SignifyClient(adminUrl, bran, Tier.low, bootUrl);
    try {
        await client.connect();
    } catch (error: unknown) {
        const failureIsMissingAgent =
            error instanceof Error &&
            error.message.includes('agent does not exist for controller');
        if (failureIsMissingAgent === false) {
            throw error;
        }

        const res = await client.boot();
        const bootSucceeded = res.ok;
        if (bootSucceeded === false) {
            const body = await res.text();
            throw new Error(
                `KERIA boot failed: ${res.status} ${res.statusText} ${body}`
            );
        }
        await client.connect();
    }
    const connectedAgentIsMissing =
        typeof client.agent?.pre !== 'string' ||
        client.agent.pre.length === 0;
    if (connectedAgentIsMissing) {
        throw new Error('KERIA connect completed without an agent AID');
    }
    return client;
}

/**
 * Connect or boot a number of SignifyClient instances
 * @example
 * <caption>Create two clients with random secrets</caption>
 * let client1: SignifyClient, client2: SignifyClient;
 * beforeAll(async () => {
 *   [client1, client2] = await getOrCreateClients(2);
 * });
 * @example
 * <caption>Launch jest from shell with pre-defined secrets</caption>
 * $ SIGNIFY_SECRETS="0ACqshJKkJ7DDXcaDuwnmI8s,0ABqicvyicXGvIVg6Ih-dngE" npx jest ./tests
 */
export async function getOrCreateClients(
    count: number,
    brans: string[] | undefined = undefined,
    environment: TestEnvironmentPreset | undefined = undefined
): Promise<SignifyClient[]> {
    const tasks: Promise<SignifyClient>[] = [];
    const secrets = process.env['SIGNIFY_SECRETS']?.split(',');
    for (let i = 0; i < count; i++) {
        tasks.push(
            getOrCreateClient(brans?.at(i) ?? secrets?.at(i) ?? undefined, environment)
        );
    }
    const clients: SignifyClient[] = await Promise.all(tasks);
    return clients;
}

export async function getOrCreateAID(
    client: SignifyClient,
    name: string,
    kargs: CreateIdentiferArgs
): Promise<HabState> {
    try {
        return await client.identifiers().get(name);
    } catch {
        const result: EventResult = await client
            .identifiers()
            .create(name, kargs);

        await waitOperation(client, await result.op());
        const aid = await client.identifiers().get(name);

        const agentPrefix = client.agent?.pre;
        const agentPrefixIsMissing =
            typeof agentPrefix !== 'string' ||
            agentPrefix.length === 0;
        if (agentPrefixIsMissing) {
            throw new Error(
                `Cannot authorize ${name} without a connected KERIA agent`
            );
        }
        const op = await client
            .identifiers()
            .addEndRole(name, 'agent', agentPrefix);
        await waitOperation(client, await op.op());
        return aid;
    }
}
