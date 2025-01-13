import {
    SignifyClient,
} from 'signify-ts';
import { waitOperation } from './operations';

/**
 * Get or resolve a Keri contact
 * @example
 * <caption>Create a Keri contact before running tests</caption>
 * let contact1_id: string;
 * beforeAll(async () => {
 *   contact1_id = await getOrCreateContact(client2, "contact1", name1_oobi);
 * });
 */
export async function getOrCreateContact(
    client: SignifyClient,
    name: string,
    oobi: string
): Promise<string> {
    const list = await client.contacts().list(undefined, 'alias', `^${name}$`);
    // console.log("contacts.list", list);
    if (list.length > 0) {
        const contact = list[0];
        if (contact.oobi === oobi) {
            // console.log("contacts.id", contact.id);
            return contact.id;
        }
    }
    let op = await client.oobis().resolve(oobi, name);
    op = await waitOperation(client, op);
    return op.response.i;
}