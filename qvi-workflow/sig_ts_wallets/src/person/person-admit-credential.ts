import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {admitSinglesig} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';
import {getOrCreateClient} from '../keystore-creation.ts';

export async function admitCredential(
    config: ParticipantConfig,
    issuerPrefix: string,
    credentialSaid: string
) {
    const person = config.participants.person;
    const client = await getOrCreateClient(
        person.salt,
        config.environment,
        person.keriaHost
    );
    const personAid = await client
        .identifiers()
        .get(person.name);
    const credential = await admitSinglesig(
        client,
        person.name,
        issuerPrefix,
        credentialSaid
    );
    return credentialSnapshot(credential, personAid.prefix);
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'issuer-prefix',
            'credential-said',
        ]);
        requireNamedArguments(args, [
            'issuer-prefix',
            'credential-said',
        ]);
        const admitted = await admitCredential(
            participantConfigFromArguments(args),
            args['issuer-prefix'],
            args['credential-said']
        );
        return {
            status: 'admitted',
            credential: admitted,
        };
    });
}
