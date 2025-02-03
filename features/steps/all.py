import os
import subprocess

from behave import then, when

from features.environment import CONFIG_DIR, DATA_DIR

# Constants
ALICE = 'EKYLUMmNPZeEs77Zvclf0bSN5IN-mLfLpx2ySb-HDlk4'
BOB = 'EJccSRTfXYF6wrUVuenAIHzwcx3hJugeiJsEKmndi5q1'


@when('I initialize and incept multisig2')
def step_initialize_multisig2(context):
    subprocess.run(
        [
            'kli',
            'init',
            '--name',
            'multisig2',
            '--salt',
            '0ACDEyMzQ1Njc4OWdoaWpsaw',
            '--nopasscode',
            '--config-dir',
            CONFIG_DIR,
            '--config-file',
            'demo-witness-oobis',
        ],
        check=True,
    )
    subprocess.run(
        [
            'kli',
            'incept',
            '--name',
            'multisig2',
            '--alias',
            'multisig2',
            '--file',
            os.path.join(DATA_DIR, 'data/multisig-2-sample.json'),
        ],
        check=True,
    )


@when('I resolve OOBIs between multisig1 and multisig2')
def step_resolve_oobis(context):
    subprocess.run(
        [
            'kli',
            'oobi',
            'resolve',
            '--name',
            'multisig1',
            '--oobi-alias',
            'multisig2',
            '--oobi',
            f'http://127.0.0.1:5642/oobi/{context.bob}/witness/BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha',
        ],
        check=True,
    )
    subprocess.run(
        [
            'kli',
            'oobi',
            'resolve',
            '--name',
            'multisig2',
            '--oobi-alias',
            'multisig1',
            '--oobi',
            f'http://127.0.0.1:5642/oobi/{context.alice}/witness/BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha',
        ],
        check=True,
    )


@when('I perform multisig inception for both multisig1 and multisig2')
def step_multisig_inception(context):
    pid1 = subprocess.Popen(
        [
            'kli',
            'multisig',
            'incept',
            '--name',
            'multisig1',
            '--alias',
            'multisig1',
            '--group',
            'multisig',
            '--file',
            os.path.join(DATA_DIR, 'data/multisig-sample.json'),
        ]
    )
    pid2 = subprocess.Popen(
        [
            'kli',
            'multisig',
            'incept',
            '--name',
            'multisig2',
            '--alias',
            'multisig2',
            '--group',
            'multisig',
            '--file',
            os.path.join(DATA_DIR, 'data/multisig-sample.json'),
        ]
    )
    context.pid_list.extend([pid1, pid2])


@then('the process should complete successfully')
def step_wait_for_processes(context):
    for pid in context.pid_list:
        pid.wait()
    context.pid_list = []
