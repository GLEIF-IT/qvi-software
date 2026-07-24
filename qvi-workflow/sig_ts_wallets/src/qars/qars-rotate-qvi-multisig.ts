import signify, {
    type HabState,
    type KeyState,
    type SignifyClient,
} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {sendExchangeToEachRecipient} from '../exchanges.ts';
import {requireCoordinatedEventDigest} from '../multisig-coordination.ts';
import {
    submitPendingMultisigOperation,
    type MultisigMemberContext,
} from '../multisig-coordinator.ts';
import {waitForMatchingNotification} from '../notifications.ts';
import type {MatchedNotification} from '../notifications.ts';
import {waitKeyStateOperation, waitOperation} from '../operations.ts';
import {loadQviMembers} from './qvi-context.ts';

async function synchronizeMemberStates(
    members: Array<{
        client: SignifyClient;
        memberAid: HabState;
    }>
): Promise<void> {
    for (const observer of members) {
        for (const subject of members) {
            if (
                observer.memberAid.prefix ===
                subject.memberAid.prefix
            ) {
                continue;
            }
            await waitKeyStateOperation(
                observer.client,
                await observer.client
                    .keyStates()
                    .query(subject.memberAid.prefix)
            );
        }
    }
}

async function rotateMemberAids(
    members: Array<{
        client: SignifyClient;
        memberAid: HabState;
    }>
): Promise<HabState[]> {
    await synchronizeMemberStates(members);
    await Promise.all(
        members.map(async ({client, memberAid}) => {
            const result = await client
                .identifiers()
                .rotate(memberAid.name);
            await waitOperation(client, await result.op());
        })
    );
    const rotated = await Promise.all(
        members.map(({client, memberAid}) =>
            client.identifiers().get(memberAid.name)
        )
    );
    await synchronizeMemberStates(
        rotated.map((memberAid, index) => ({
            memberAid,
            client: members[index].client,
        }))
    );
    return rotated;
}

async function rotateGroupMember(
    context: MultisigMemberContext,
    groupName: string,
    states: KeyState[]
) {
    const result = await context.client
        .identifiers()
        .rotate(groupName, {states, rstates: states});
    const operation = await result.op();
    const body = result.serder;
    const sigers = result.sigs.map(
        (signature) => new signify.Siger({qb64: signature})
    );
    const message = signify.d(
        signify.messagize(body, sigers)
    );
    const attachment = message.substring(body.size);
    let coordination: MatchedNotification[] = [];
    if (context.isInitiator === false) {
        const notification = await waitForMatchingNotification(
            context.client,
            {
                notificationRoute: '/multisig/rot',
                exchangeRoute: '/multisig/rot',
                sender: context.coordinatorPrefix,
                recipient: context.aid.prefix,
                groupPrefix: body.pre,
                embeddedDigest: body.said,
            }
        );
        requireCoordinatedEventDigest(
            notification.exchange,
            '/multisig/rot',
            body.said
        );
        coordination = [notification];
    }
    const memberIds = states.map(({i}) => i);
    await sendExchangeToEachRecipient(context.client, {
        name: context.aid.name,
        topic: groupName,
        sender: context.aid,
        route: '/multisig/rot',
        payload: {
            gid: body.pre,
            smids: memberIds,
            rmids: memberIds,
        },
        embeds: {rot: [body, attachment]},
        recipients: context.otherMembers.map(({prefix}) => prefix),
    });
    return {operation, coordination};
}

export async function rotateMultisig(
    config: ParticipantConfig,
    groupName: string
) {
    const members = await loadQviMembers(config, groupName);
    const rotatedMemberAids = await rotateMemberAids(members);
    const states = rotatedMemberAids.map(({state}) => state);
    const coordinatingMembers = members.map((member, index) => ({
        client: member.client,
        aid: rotatedMemberAids[index],
    }));
    const pending = await submitPendingMultisigOperation(
        '/multisig/rot',
        members[0].groupAid.prefix,
        coordinatingMembers,
        (context) =>
            rotateGroupMember(context, groupName, states)
    );
    return {
        status: 'submitted' as const,
        groupName,
        pending,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
        ]);
        requireNamedArguments(args, ['group-name']);
        return rotateMultisig(
            participantConfigFromArguments(args),
            args['group-name']
        );
    });
}
