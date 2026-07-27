import {createServer, type IncomingMessage, type ServerResponse} from 'node:http';

import {run, UsageError} from './sig-wallet.ts';

const HOST = '127.0.0.1';
const PORT = Number(process.env.QVI_WALLET_PORT ?? '8923');
const MAX_REQUEST_BYTES = 1024 * 1024;

/** Write one JSON response with an explicit status and content length. */
function sendJson(
    response: ServerResponse,
    status: number,
    value: Record<string, unknown>
): void {
    const body = JSON.stringify(value);
    response.writeHead(status, {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
    });
    response.end(body);
}

/** Read one bounded JSON request body from the local workflow driver. */
async function readJson(request: IncomingMessage): Promise<unknown> {
    const chunks: Buffer[] = [];
    let size = 0;

    for await (const chunk of request) {
        const buffer = Buffer.from(chunk);
        size += buffer.length;
        if (size > MAX_REQUEST_BYTES) {
            throw new UsageError('Wallet request is too large');
        }
        chunks.push(buffer);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

/** Require the daemon boundary to receive only a string argument vector. */
function requireArguments(value: unknown): string[] {
    if (
        typeof value !== 'object' ||
        value === null ||
        !('argv' in value) ||
        !Array.isArray(value.argv) ||
        !value.argv.every((argument) => typeof argument === 'string')
    ) {
        throw new UsageError(
            'Wallet request must contain a string argv array'
        );
    }
    return value.argv;
}

/** Dispatch health probes and one explicit wallet action request. */
async function handleRequest(
    request: IncomingMessage,
    response: ServerResponse
): Promise<void> {
    if (request.method === 'GET' && request.url === '/health') {
        sendJson(response, 200, {ok: true, status: 'ready'});
        return;
    }
    if (request.method !== 'POST' || request.url !== '/run') {
        sendJson(response, 404, {ok: false, error: 'Not found'});
        return;
    }

    const argv = requireArguments(await readJson(request));
    try {
        const result = await run(argv);
        sendJson(response, 200, {ok: true, ...result});
    } catch (error: unknown) {
        const usage = error instanceof UsageError;
        const message =
            error instanceof Error ? error.message : String(error);
        const stack = error instanceof Error ? error.stack : undefined;
        sendJson(response, usage ? 400 : 500, {
            ok: false,
            type: usage ? 'usage' : 'workflow',
            error: message,
            ...(stack === undefined ? {} : {stack}),
        });
    }
}

/** Start the loopback-only wallet daemon used by the local workflow. */
function main(): void {
    if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) {
        throw new Error('QVI_WALLET_PORT must be a valid TCP port');
    }

    const server = createServer((request, response) => {
        void handleRequest(request, response).catch((error: unknown) => {
            const message =
                error instanceof Error ? error.message : String(error);
            sendJson(response, 500, {ok: false, error: message});
        });
    });
    server.listen(PORT, HOST, () => {
        process.stdout.write(
            `Signify wallet daemon listening on http://${HOST}:${PORT}\n`
        );
    });
}

main();
