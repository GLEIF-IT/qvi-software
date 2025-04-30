import {
    Operation,
    SignifyClient,
} from 'signify-ts';

/**
 * Deletes and operation from an Agent in a KERIA server
 * @param client SignifyClient to use to connect to KERIA
 * @param op Operation to delete
 */
async function deleteOperations<T = any>(
    client: SignifyClient,
    op: Operation<T>
) {
    if (op.metadata?.depends) {
        await deleteOperations(client, op.metadata.depends);
    }

    await client.operations().delete(op.name);
}

/**
 * Poll for operation to become completed.
 * Removes completed operation
 */
export async function waitOperation<T = any>(
    client: SignifyClient,
    op: Operation<T> | string,
    signal?: AbortSignal
): Promise<Operation<T>> {
    if (typeof op === 'string') {
        op = await client.operations().get(op);
    }

    op = await client
        .operations()
        .wait(op, { signal: signal ?? AbortSignal.timeout(30000) });
    await deleteOperations(client, op);

    return op;
}