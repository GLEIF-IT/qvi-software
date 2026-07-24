import fs from 'node:fs';

import type {
    CredentialData,
    CredentialSubject,
} from 'signify-ts';

import type {WorkflowConfig} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {issueAndGrantCredential} from './issue-and-grant.ts';
import {loadQviMembers} from './qvi-context.ts';

export const OOR_SCHEMA_SAID =
    'EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy';

/** Read one workflow credential fragment from disk. */
async function jsonFile(path: string) {
    return JSON.parse(await fs.promises.readFile(path, 'utf8'));
}

/** Build, issue, and grant the official-organizational-role credential. */
export async function createOorCredential(options: {
    config: WorkflowConfig;
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
