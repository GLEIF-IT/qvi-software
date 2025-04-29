import os
import re
import subprocess

import pysodium
from behave import given
from keri import core
from keri.app.cli.common import existing

from features.environment import BASE_DIR, CONFIG_DIR, DATA_DIR
from features.helpers.context_merge import merge_into_context

@given('"{participants}"')
def step_given_participants(context, participants):
    """
    Given step to initialize and incept AIDs.

    :param context: The context object provided by Behave.
    :param participants: A string containing the names of participants separated by commas or 'and'.
    """
    pattern = r'\b\w+\b'
    matches = re.findall(pattern, participants)
    result = [name for name in matches if name.lower() != 'and']



    for i in range(len(result)):
        for j in range(i + 1, len(result)):
            print(f'Operation on {result[i]} and {result[j]}')
            __oobi(context, result[i], result[j])

def __oobi(context, r1, r2):
    """
    Initialize and incept an AID with a passcode
    :param name:
    :param passcode:
    """
    with existing.existingHby(name=name, base=base, bran=bran) as hby:
        if alias is None:
            alias = existing.aliasInput(hby)

        hab = hby.habByName(name=alias)
        if role in (kering.Roles.witness,):
            if not hab.kever.wits:
                print(f"{alias} identifier {hab.pre} does not have any witnesses.")
                sys.exit(-1)

            for wit in hab.kever.wits:
                urls = hab.fetchUrls(eid=wit, scheme=kering.Schemes.http) or hab.fetchUrls(eid=wit, scheme=kering.Schemes.https)
                if not urls:
                    raise kering.ConfigurationError(f"unable to query witness {wit}, no http endpoint")

                url = urls[kering.Schemes.http] if kering.Schemes.http in urls else urls[kering.Schemes.https]
                up = urlparse(url)
                print(f"{up.scheme}://{up.hostname}:{up.port}/oobi/{hab.pre}/witness")
        elif role in (kering.Roles.controller,):
            urls = hab.fetchUrls(eid=hab.pre, scheme=kering.Schemes.http) or hab.fetchUrls(eid=hab.pre, scheme=kering.Schemes.https)
            if not urls:
                print(f"{alias} identifier {hab.pre} does not have any controller endpoints")
                return
            url = urls[kering.Schemes.http] if kering.Schemes.http in urls else urls[kering.Schemes.https]
            up = urlparse(url)
            print(f"{up.scheme}://{up.hostname}:{up.port}/oobi/{hab.pre}/controller")

    merge_into_context(context, f'{name}_oobi', passcode)

    print("bar")
    print(CONFIG_DIR)
    print(BASE_DIR)
    print("baz")
    subprocess.run(
        [
            'kli',
            'init',
            '--name',
            name,
            '--passcode',
            passcode,
            '--config-dir',
            CONFIG_DIR,
            '--config-file',
            'demo-witness-oobis',
            '--base',
            BASE_DIR,
        ],
        check=True,
    )

    subprocess.run(
        [
            'kli',
            'incept',
            '--passcode',
            passcode,
            '--name',
            name,
            '--alias',
            name,
            '--file',
            os.path.join(DATA_DIR, 'multisig-1-sample.json'),
            '--base',
            BASE_DIR,
        ],
        check=True,
    )