import fs from 'node:fs';

import type {
    CredentialData,
    CredentialSubject,
} from 'signify-ts';

import type {WorkflowConfig} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {issueAndGrantCredential} from './issue-and-grant.ts';
import {loadQviMembers} from './qvi-context.ts';

export const LE_SCHEMA_SAID =
    'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';

/** Read one workflow credential fragment from disk. */
async function jsonFile(path: string) {
    return JSON.parse(await fs.promises.readFile(path, 'utf8'));
}

/** Build, issue, and grant the legal-entity credential. */
export async function createLeCredential(options: {
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
            `${options.dataDir}/temp-data/legal-entity-data.json`
        )),
    };
    const data: CredentialData = {
        i: members[0].groupAid.prefix,
        ri: registries[0].regk,
        s: LE_SCHEMA_SAID,
        a: subject,
        e: await jsonFile(
            `${options.dataDir}/temp-data/qvi-edge.json`
        ),
        r: await jsonFile(
            `${options.dataDir}/rules/rules.json`
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
