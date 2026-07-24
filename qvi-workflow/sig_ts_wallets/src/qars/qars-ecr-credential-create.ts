import fs from 'node:fs';

import {
    Salter,
    type CredentialData,
    type CredentialSubject,
} from 'signify-ts';

import type {WorkflowConfig} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {issueAndGrantCredential} from './issue-and-grant.ts';
import {loadQviMembers} from './qvi-context.ts';

export const ECR_SCHEMA_SAID =
    'EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw';

/** Read one workflow credential fragment from disk. */
async function jsonFile(path: string) {
    return JSON.parse(await fs.promises.readFile(path, 'utf8'));
}

/** Build, issue, and grant the engagement-context-role credential. */
export async function createEcrCredential(options: {
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
        u: new Salter({}).qb64,
        ...(await jsonFile(
            `${options.dataDir}/temp-data/ecr-data.json`
        )),
    };
    const data: CredentialData = {
        u: new Salter({}).qb64,
        i: members[0].groupAid.prefix,
        ri: registries[0].regk,
        s: ECR_SCHEMA_SAID,
        a: subject,
        e: await jsonFile(
            `${options.dataDir}/temp-data/ecr-auth-edge.json`
        ),
        r: await jsonFile(
            `${options.dataDir}/rules/ecr-rules.json`
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
