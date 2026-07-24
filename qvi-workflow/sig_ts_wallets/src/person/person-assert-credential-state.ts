import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {
    credentialSnapshot,
    getCredential,
} from '../credential-state.ts';
import {getOrCreateClient} from '../keystore-creation.ts';

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'credential-said',
            'issuer-prefix',
            'schema',
            'issuee-prefix',
            'status-sequence',
        ]);
        requireNamedArguments(args, [
            'credential-said',
            'issuer-prefix',
            'schema',
            'issuee-prefix',
            'status-sequence',
        ]);
        const config = participantConfigFromArguments(args);
        const person = config.participants.person;
        const client = await getOrCreateClient(
            person.salt,
            config.environment,
            person.keriaHost
        );
        const snapshot = credentialSnapshot(
            await getCredential(client, args['credential-said']),
            (await client.identifiers().get(person.name)).prefix
        );
        const actual = {
            said: snapshot.said,
            issuer: snapshot.issuer,
            schema: snapshot.schema,
            issuee: snapshot.issuee,
            statusSequence: snapshot.statusSequence,
        };
        const expected = {
            said: args['credential-said'],
            issuer: args['issuer-prefix'],
            schema: args.schema,
            issuee: args['issuee-prefix'],
            statusSequence: args['status-sequence'],
        };
        if (
            JSON.stringify(actual) !== JSON.stringify(expected)
        ) {
            throw new Error(
                `Person credential state ${JSON.stringify(actual)} does not match ${JSON.stringify(expected)}`
            );
        }
        return {status: 'observed', state: snapshot};
    });
}
