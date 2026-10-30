import type {GroupMember} from '../client.ts';
import {createRegistry} from '../credential-mutations.ts';
import {retry} from '../retry.ts';

/** Create the QVI registry and require it to converge across all members. */
export async function createQviRegistry(
    members: GroupMember[],
    groupName: string,
    registryName: string
) {
    const initiator = members[0];
    if (initiator === undefined) {
        throw new Error('Registry creation requires group members');
    }
    await createRegistry({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        groupName,
        registryName,
    });
    return retry(async () => {
        const registryLists = await Promise.all(
            members.map(({client}) =>
                client.registries().list(groupName)
            )
        );
        const registryId = registryLists[0]?.[0]?.regk;
        const registryIsAvailable =
            registryId !== undefined &&
            registryLists.every(
                (registries) =>
                    registries.length === 1 &&
                    registries[0].regk === registryId
            );
        if (registryIsAvailable === false) {
            throw new Error(
                'QVI registry has not reached all three members'
            );
        }
        return {registryRegk: registryId};
    });
}
