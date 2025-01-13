import { SignifyClient } from "signify-ts";
import { waitOperation } from "./operations";
import { OobiInfo } from "./qvi-data";

export async function resolveOobi(
    client: SignifyClient,
    oobi: string,
    alias?: string
) {
    const op = await client.oobis().resolve(oobi, alias);
    await waitOperation(client, op);
}