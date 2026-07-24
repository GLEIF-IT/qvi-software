import {randomNonce} from 'signify-ts';

import type {WorkflowConfig} from '../client.ts';
import {createRegistryMultisig} from '../credentials.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import {retry} from '../retry.ts';
import {loadQviMembers} from './qvi-context.ts';

/** Create the QVI registry and require it to converge across all members. */
export async function createQviRegistry(
    config: WorkflowConfig,
    groupName: string,
    registryName: string
) {
    const members = await loadQviMembers(config, groupName);
    const nonce = randomNonce();
    await coordinateMultisigOperation(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        (context) => {
            const member = members.find(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (member === undefined) {
                throw new Error(
                    `Missing QVI member ${context.aid.prefix}`
                );
            }
            return createRegistryMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                member.groupAid,
                registryName,
                nonce,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
        }
    );
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
