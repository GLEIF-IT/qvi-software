import {parseAidInfoSingleSig} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {
    getReceivedCredential,
    requireCredential,
} from "../credential-mutations.ts";
import {admitSinglesig} from "../ipex.ts";
import {credentialSnapshot} from '../credential-state.ts';
import {
    isMainModule,
    parseNamedArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

/**
 * Admits a credential using the QVI AID
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function admitCredentialQvi(
    aidInfo: string,
    issuerPrefix: string,
    credSAID: string,
    environment: TestEnvironmentPreset
) {
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);
    const QVIId = await QVIClient.identifiers().get(QVI.name);
    
    let cred = await getReceivedCredential(QVIClient, credSAID);
    const credentialMustBeAdmitted = cred === undefined;
    if (credentialMustBeAdmitted) {
        cred = await admitSinglesig(
            QVIClient,
            QVIId.name,
            issuerPrefix,
            credSAID,
        );
        console.log(
            `Credential ${credSAID} admitted by QVI: `,
            credentialSnapshot(cred, QVIId.prefix)
        );
    }
    const admittedCredential = requireCredential(
        cred,
        `QVI credential ${credSAID}`
    );
    return {
        status: 'admitted' as const,
        credential: credentialSnapshot(
            admittedCredential,
            QVIId.prefix
        ),
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            [
                'config',
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
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        return admitCredentialQvi(
            invocation.participantSource,
            parsed['issuer-prefix'],
            parsed['credential-said'],
            invocation.environment
        );
    });
}
