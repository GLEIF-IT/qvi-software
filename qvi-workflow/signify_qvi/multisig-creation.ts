import signify, { CreateIdentiferArgs, HabState, SignifyClient } from "signify-ts";
import { waitAndMarkNotification } from "./notifications";

export async function createAIDMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    groupName: string,
    kargs: CreateIdentiferArgs,
    isInitiator: boolean = false
) {
    if (!isInitiator) await waitAndMarkNotification(client, '/multisig/icp');

    const icpResult = await client.identifiers().create(groupName, kargs);
    const op = await icpResult.op();

    const serder = icpResult.serder;
    const sigs = icpResult.sigs;
    const sigers = sigs.map((sig) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(serder, sigers));
    const atc = ims.substring(serder.size);
    const embeds = {
        icp: [serder, atc],
    };
    const smids = kargs.states?.map((state) => state['i']);
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    await client
        .exchanges()
        .send(
            aid.name,
            'multisig',
            aid,
            '/multisig/icp',
            { gid: serder.pre, smids: smids, rmids: smids },
            embeds,
            recp
        );

    return op;
}

export async function addEndRoleMultisig(
    client: SignifyClient,
    groupName: string,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    timestamp: string,
    isInitiator: boolean = false
) {
    if (!isInitiator) await waitAndMarkNotification(client, '/multisig/rpy');

    const opList: any[] = [];
    const members = await client.identifiers().members(multisigAID.name);
    const signings = members['signing'];

    for (const signing of signings) {
        const eid = Object.keys(signing.ends.agent)[0];
        const endRoleResult = await client
            .identifiers()
            .addEndRole(multisigAID.name, 'agent', eid, timestamp);
        const op = await endRoleResult.op();
        opList.push(op);

        const rpy = endRoleResult.serder;
        const sigs = endRoleResult.sigs;
        const ghabState1 = multisigAID.state;
        const seal = [
            'SealEvent',
            {
                i: multisigAID.prefix,
                s: ghabState1['ee']['s'],
                d: ghabState1['ee']['d'],
            },
        ];
        const sigers = sigs.map(
            (sig: string) => new signify.Siger({ qb64: sig })
        );
        const roleims = signify.d(
            signify.messagize(rpy, sigers, seal, undefined, undefined, false)
        );
        const atc = roleims.substring(rpy.size);
        const roleembeds = {
            rpy: [rpy, atc],
        };
        const recp = otherMembersAIDs.map((aid) => aid.prefix);
        await client
            .exchanges()
            .send(
                aid.name,
                groupName,
                aid,
                '/multisig/rpy',
                { gid: multisigAID.prefix },
                roleembeds,
                recp
            );
    }

    return opList;
}