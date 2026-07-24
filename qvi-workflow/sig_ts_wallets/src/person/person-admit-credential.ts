import {admitSinglesig} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';
import {
    connectClient,
    type WorkflowConfig,
} from '../client.ts';

/** Admit one credential into the configured person wallet. */
export async function admitCredential(
    config: WorkflowConfig,
    issuerPrefix: string,
    credentialSaid: string
) {
    const person = config.participants.person;
    const client = await connectClient(person);
    const personAid = await client
        .identifiers()
        .get(person.name);
    const credential = await admitSinglesig(
        client,
        person.name,
        issuerPrefix,
        credentialSaid
    );
    return credentialSnapshot(credential, personAid.prefix);
}
