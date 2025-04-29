import os
import re
import subprocess

import pysodium
from behave import given
from keri import core
from keri.app.cli.commands.init import InitDoer

from features.environment import BASE_DIR, CONFIG_DIR, DATA_DIR
from features.helpers.context_merge import merge_into_context
from features.helpers.runner import run


def __init_incept(context, name, passcode):
    """
    Initialize and incept an AID with a passcode
    :param name:
    :param passcode:
    """
    if passcode == '':
        passcode = core.Salter(raw=pysodium.randombytes(pysodium.crypto_sign_SEEDBYTES)).qb64

    merge_into_context(context, f'{name}_passcode', passcode)
    init = InitDoer()
    run(init)


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

    for r in result:
        __init_incept(context, r, '0ACDEyMzQ1Njc4OWdoaWpsaw')
