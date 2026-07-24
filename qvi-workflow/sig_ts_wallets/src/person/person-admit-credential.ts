import type {HabState, SignifyClient} from 'signify-ts';

import {admitSinglesig} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';

/** Admit one credential into a concrete person wallet. */
export async function admitCredential(
    client: SignifyClient,
    personAid: HabState,
    issuerPrefix: string,
    credentialSaid: string
) {
    const credential = await admitSinglesig(
        client,
        personAid.name,
        issuerPrefix,
        credentialSaid
    );
    return credentialSnapshot(credential, personAid.prefix);
}
