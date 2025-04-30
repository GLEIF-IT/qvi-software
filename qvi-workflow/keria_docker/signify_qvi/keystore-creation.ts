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

/**
 * Connect or boot a SignifyClient instance
 */
export async function getOrCreateClient(
    bran: string | undefined = undefined, 
    environment: TestEnvironmentPreset | undefined = undefined
): Promise<SignifyClient> {
    const env = resolveEnvironment(environment);
    await ready();
    bran ??= randomPasscode();
    bran = bran.padEnd(21, '_');
    const client = new SignifyClient(env.url, bran, Tier.low, env.bootUrl);
    try {
        await client.connect();
    } catch {
        const res = await client.boot();
        if (!res.ok) throw new Error();
        await client.connect();
    }
    // console.log('client', {agent: client.agent?.pre, controller: client.controller.pre});
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

        const op = await client
            .identifiers()
            .addEndRole(name, 'agent', client!.agent!.pre);
        await waitOperation(client, await op.op());
        // console.log(name, 'AID:', aid.prefix);
        return aid;
    }
}