import {createTimestamp, parseAidInfo} from '../create-aid.ts';
import {revokeCredentialMultisig} from '../credentials.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {waitOperation} from '../operations.ts';
import {TestEnvironmentPreset} from '../resolve-env.ts';

const [env, multisigName, aidInfoArg, credentialSaid] = process.argv.slice(2);

const requiredArgumentIsMissing =
    !env || !multisigName || !aidInfoArg || !credentialSaid;
if (requiredArgumentIsMissing) {
    throw new Error(
        'Usage: qars-revoke-credential.ts <environment> <QVI-name> <SIGTS_AIDS> <credential-SAID>'
    );
}

const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfoArg);
const clients = await Promise.all([
    getOrCreateClient(QAR1.salt, env as TestEnvironmentPreset, 1),
    getOrCreateClient(QAR2.salt, env as TestEnvironmentPreset, 2),
    getOrCreateClient(QAR3.salt, env as TestEnvironmentPreset, 3),
]);
const memberInfo = [QAR1, QAR2, QAR3];
const memberAids = await Promise.all(
    memberInfo.map((member, index) =>
        clients[index].identifiers().get(member.name)
    )
);
const groupAids = await Promise.all(
    clients.map((client) => client.identifiers().get(multisigName))
);
const qviPrefixIsConsistent = groupAids.every(
    (group) => group.prefix === groupAids[0].prefix
);
if (qviPrefixIsConsistent === false) {
    throw new Error(
        `QARs disagree on QVI ${multisigName}: ${groupAids.map((group) => group.prefix).join(',')}`
    );
}

async function credentialStatus(index: number): Promise<string> {
    try {
        const credential = await clients[index]
            .credentials()
            .get(credentialSaid);
        return credential.status?.s;
    } catch (error) {
        throw new Error(
            `${memberInfo[index].position} is missing credential ${credentialSaid}: ${error}`
        );
    }
}

const startingStatuses = await Promise.all(
    clients.map((_, index) => credentialStatus(index))
);
const credentialIsRevokedOnEveryQar = startingStatuses.every(
    (status) => status === '1'
);
if (credentialIsRevokedOnEveryQar) {
    console.log(
        `[revocation] ${credentialSaid} is already revoked on all three QARs`
    );
    process.exit(0);
}
const credentialIsIssuedOnEveryQar = startingStatuses.every(
    (status) => status === '0'
);
if (credentialIsIssuedOnEveryQar === false) {
    throw new Error(
        `Credential ${credentialSaid} must start issued on all QARs; observed ${startingStatuses.join(',')}`
    );
}

const timestamp = createTimestamp();
const operations = [];
for (let index = 0; index < clients.length; index++) {
    const otherMembers = memberAids.filter(
        (_, memberIndex) => memberIndex !== index
    );
    operations.push(
        await revokeCredentialMultisig(
            clients[index],
            memberAids[index],
            otherMembers,
            multisigName,
            credentialSaid,
            timestamp,
            index === 0
        )
    );
}

await Promise.all(
    operations.map((operation, index) =>
        waitOperation(clients[index], operation)
    )
);

const finalStatuses = await Promise.all(
    clients.map((_, index) => credentialStatus(index))
);
const revocationConverged = finalStatuses.every(
    (status) => status === '1'
);
if (revocationConverged === false) {
    throw new Error(
        `Credential ${credentialSaid} revocation did not converge; observed ${finalStatuses.join(',')}`
    );
}

console.log(
    `[revocation] ${credentialSaid} converged at status sequence 1 on all three QARs`
);
