import fs from 'node:fs';

import type {
    CredentialData,
    CredentialSubject,
} from 'signify-ts';

import {
    connectClient,
    type WorkflowConfig,
} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {OOR_SCHEMA_SAID} from '../credentials.ts';
import {issueAndGrantCredential} from './issue-and-grant.ts';
import {loadGroupMembers} from './qvi-context.ts';

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
    const participants = options.config.qvi.finalMembers.map(
        (role) => options.config.participants[role]
    );
    const clients = await Promise.all(
        participants.map(connectClient)
    );
    const members = await loadGroupMembers(
        clients,
        participants.map(({name}) => name),
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
        members,
        groupName: options.groupName,
        issueePrefix: options.issueePrefix,
        credentialData: data,
    });
    return issued[0].snapshot;
}
