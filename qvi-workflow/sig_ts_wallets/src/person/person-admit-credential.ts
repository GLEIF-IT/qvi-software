import {parseAidInfo} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {
    admitSinglesig,
    getReceivedCredential,
    requireCredential
} from "../credentials";
import {
    assertExpectedCredential,
    credentialSnapshot,
} from '../credential-state.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

/**
 * Admits a credential for the person AID
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function admitCredential(
    aidInfo: string,
    issuerPrefix: string,
    credSAID: string,
    environment: TestEnvironmentPreset,
    expectedSchema?: string,
    expectedIssuee?: string
) {
    const {PERSON} = parseAidInfo(aidInfo);
    const PersonClient = await getOrCreateClient(PERSON.salt, environment, 1);

    const PersonId = await PersonClient.identifiers().get(PERSON.name);

    let cred = await getReceivedCredential(PersonClient, credSAID);
    const credentialIsMissing = cred === undefined;
    if (credentialIsMissing) {
        console.log(`Credential ${credSAID} not found for ${PersonId.name}, admitting...`);
        cred = await admitSinglesig(
            PersonClient,
            PersonId.name,
            issuerPrefix,
            credSAID,
        );
    } else{
        console.log(`Credential ${credSAID} already admitted`);
    }
    const snapshot = credentialSnapshot(
        requireCredential(
            cred,
            `Person credential ${credSAID}`
        ),
        PersonId.prefix
    );
    assertExpectedCredential(snapshot, {
        said: credSAID,
        issuer: issuerPrefix,
        schema: expectedSchema ?? snapshot.schema,
        issuee: expectedIssuee ?? PersonId.prefix,
    });
    const credentialIsActive = snapshot.statusSequence === '0';
    if (credentialIsActive === false) {
        throw new Error(
            `Person credential ${credSAID} is not active at TEL sequence 0`
        );
    }
    return snapshot;
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            [
                'config',
                'issuer-prefix',
                'credential-said',
                'expected-schema',
                'expected-issuee',
            ],
            [
                'environment',
                'participant-source',
                'issuer-prefix',
                'credential-said',
            ]
        );
        requireNamedArguments(parsed, [
            'issuer-prefix',
            'credential-said',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const admitted = await admitCredential(
            invocation.participantSource,
            parsed['issuer-prefix'],
            parsed['credential-said'],
            invocation.environment,
            parsed['expected-schema'],
            parsed['expected-issuee']
        );
        return {
            status: 'admitted',
            credentialSaid: admitted.said,
            telDigest: admitted.currentTelDigest,
        };
    });
}
