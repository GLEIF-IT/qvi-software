import {SignifyClient} from 'signify-ts';

/**
 * Create a prototype-backed SignifyClient and replace selected SDK accessors.
 *
 * Production functions keep their concrete SDK boundary. Test-only method
 * replacement stays here instead of creating exported partial-client types
 * or running the SDK constructor and its key-derivation side effects.
 */
export function testSignifyClient(
    overrides: Record<string, unknown>
): SignifyClient {
    const client: SignifyClient = Object.create(
        SignifyClient.prototype
    );
    for (const [name, value] of Object.entries(overrides)) {
        Object.defineProperty(client, name, {
            configurable: true,
            value,
        });
    }
    return client;
}
