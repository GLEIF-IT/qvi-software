import fs from 'node:fs';

import type {
    CredentialData,
    CredentialSubject,
} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {issueAndGrantCredential} from './issue-and-grant.ts';
import {loadQviMembers} from './qvi-context.ts';

export const OOR_SCHEMA_SAID =
    'EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy';

async function jsonFile(path: string) {
    return JSON.parse(await fs.promises.readFile(path, 'utf8'));
}

export async function createOorCredential(options: {
    config: ParticipantConfig;
    groupName: string;
    dataDir: string;
    issueePrefix: string;
}) {
    const members = await loadQviMembers(
        options.config,
        options.groupName
    );
    const registries = await members[0].client
        .registries()
        .list(options.groupName);
    if (registries.length !== 1) {
        throw new Error(
            `QVI requires one registry; found ${registries.length}`
        );
    }
    const subject: CredentialSubject = {
        i: options.issueePrefix,
        dt: createTimestamp(),
        ...(await jsonFile(
            `${options.dataDir}/temp-data/oor-data.json`
        )),
    };
    const data: CredentialData = {
        i: members[0].groupAid.prefix,
        ri: registries[0].regk,
        s: OOR_SCHEMA_SAID,
        a: subject,
        e: await jsonFile(
            `${options.dataDir}/temp-data/oor-auth-edge.json`
        ),
        r: await jsonFile(
            `${options.dataDir}/rules/oor-rules.json`
        ),
    };
    const issued = await issueAndGrantCredential({
        config: options.config,
        groupName: options.groupName,
        issueePrefix: options.issueePrefix,
        credentialData: data,
    });
    return issued[0].snapshot;
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
            'data-dir',
            'issuee-prefix',
            'artifact-dir',
        ]);
        requireNamedArguments(args, [
            'group-name',
            'data-dir',
            'issuee-prefix',
            'artifact-dir',
        ]);
        const snapshot = await createOorCredential({
            config: participantConfigFromArguments(args),
            groupName: args['group-name'],
            dataDir: args['data-dir'],
            issueePrefix: args['issuee-prefix'],
        });
        const artifact = {
            oorCredSAID: snapshot.said,
            oorCredIssuer: snapshot.issuer,
            oorCredIssuee: snapshot.issuee,
        };
        await fs.promises.writeFile(
            `${args['artifact-dir']}/oor-cred-info.json`,
            JSON.stringify(artifact)
        );
        return {
            status: 'issued',
            credential: artifact,
            credentialSaid: snapshot.said,
            registryId: snapshot.registry,
            telDigest: snapshot.currentTelDigest,
        };
    });
}
