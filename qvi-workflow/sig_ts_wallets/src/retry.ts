import { setTimeout } from 'timers/promises';

const DEFAULT_WORKFLOW_TIMEOUT_MS = 120_000;

/**
 * Poll local KERIA often enough to observe completed work without busy loops.
 *
 * The minimum deliberately stays above HIO's 1/32-second scheduler tick.
 */
export const LOCAL_OPERATION_POLLING = {
    minSleep: 32,
    maxSleep: 32,
    increaseFactor: 32,
} as const;

export function workflowTimeoutMs(): number {
    const configured =
        process.env.QVI_OPERATION_TIMEOUT_SECONDS;
    if (configured === undefined) {
        return DEFAULT_WORKFLOW_TIMEOUT_MS;
    }

    const seconds = Number(configured);
    const timeoutIsInvalid =
        Number.isFinite(seconds) === false ||
        Number.isInteger(seconds) === false ||
        seconds < 1;
    if (timeoutIsInvalid) {
        throw new Error(
            'QVI_OPERATION_TIMEOUT_SECONDS must be a positive integer'
        );
    }
    return seconds * 1_000;
}

export interface RetryOptions {
    maxSleep?: number;
    minSleep?: number;
    maxRetries?: number;
    timeout?: number;
    signal?: AbortSignal;
}

export async function retry<T>(
    fn: () => Promise<T>,
    options: RetryOptions = {}
): Promise<T> {
    const {
        maxSleep = 32,
        minSleep = 32,
        maxRetries,
        timeout = workflowTimeoutMs(),
    } = options;

    const increaseFactor = 32;

    let retries = 0;
    let cause: Error | null = null;
    const start = Date.now();

    while (
        (options.signal === undefined || options.signal.aborted === false) &&
        Date.now() - start < timeout &&
        (maxRetries === undefined || retries < maxRetries)
    ) {
        try {
            return await fn();
        } catch (err) {
            cause = err as Error;
            const delay = Math.max(
                minSleep,
                Math.min(maxSleep, 2 ** retries * increaseFactor)
            );
            retries++;
            await setTimeout(delay, undefined, { signal: options.signal });
        }
    }

    const finalCause =
        cause ?? new Error(`Failed after ${retries} attempts`);
    Object.assign(finalCause, {
        retries,
        maxAttempts: maxRetries,
    });
    throw finalCause;
}
