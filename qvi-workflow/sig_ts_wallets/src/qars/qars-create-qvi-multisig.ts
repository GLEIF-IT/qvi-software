import fs from 'node:fs';

import signify, {type CreateIdentiferArgs} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {parseAidInfo} from '../create-aid.ts';
import {getOrCreateAID, getOrCreateClient} from '../keystore-creation.ts';
import {createAIDMultisig} from '../multisig-creation.ts';
import {submitPendingMultisigOperation} from '../multisig-coordinator.ts';
import {qviNextThreshold, qviSigningThreshold} from '../qvi-configuration.ts';
import {
    resolveEnvironment,
    type TestEnvironmentPreset,
} from '../resolve-env.ts';

export async function createQviMultisig(
    groupName: string,
    participantSource: string,
    delegatorPrefix: string,
    environment: TestEnvironmentPreset
) {
    const {witnessIds} = resolveEnvironment(environment);
    const [, witness] = witnessIds;
    const {QAR1, QAR2, QAR3} = parseAidInfo(participantSource);
    const clients = await Promise.all([
        getOrCreateClient(QAR1.salt, environment, 1),
        getOrCreateClient(QAR2.salt, environment, 2),
        getOrCreateClient(QAR3.salt, environment, 3),
    ]);
    const aidConfig = {toad: 1, wits: [witness]};
    const aids = await Promise.all([
        getOrCreateAID(clients[0], QAR1.name, aidConfig),
        getOrCreateAID(clients[1], QAR2.name, aidConfig),
        getOrCreateAID(clients[2], QAR3.name, aidConfig),
    ]);
    const states = aids.map(({state}) => state);
    const createArgs: CreateIdentiferArgs = {
        delpre: delegatorPrefix,
        algo: signify.Algos.group,
        isith: qviSigningThreshold(),
        nsith: qviNextThreshold(),
        toad: aidConfig.toad,
        wits: aidConfig.wits,
        states,
        rstates: states,
    };
    const members = aids.map((aid, index) => ({
        aid,
        client: clients[index],
    }));

    let groupPrefix = '';
    const pending = await submitPendingMultisigOperation(
        '/multisig/icp',
        delegatorPrefix,
        members,
        async (context) => {
            const memberArgs = {
                ...createArgs,
                mhab: context.aid,
            };
            const result = await createAIDMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                groupName,
                memberArgs,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
            const group = await context.client
                .identifiers()
                .get(groupName);
            groupPrefix = group.prefix;
            return result;
        }
    );
    pending.groupPrefix = groupPrefix;
    return {msPrefix: groupPrefix, pending};
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(process.argv.slice(2), [
            'config',
            'group-name',
            'data-dir',
            'delegator-prefix',
        ]);
        requireNamedArguments(parsed, [
            'group-name',
            'data-dir',
            'delegator-prefix',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const multisig = await createQviMultisig(
            parsed['group-name'],
            invocation.participantSource,
            parsed['delegator-prefix'],
            invocation.environment
        );
        await fs.promises.writeFile(
            `${parsed['data-dir']}/qvi-multisig-info.json`,
            JSON.stringify(multisig)
        );
        return {status: 'inception-submitted', ...multisig};
    });
}
