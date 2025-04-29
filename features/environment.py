import os
import shutil
import subprocess

from features.helpers.context_merge import merge_into_context
from features.helpers.create_witness_config_file import create_witness_config_file
from features.helpers.root import get_project_root

project_root = get_project_root()

DATA_DIR = os.path.join(project_root, 'data')
CONFIG_DIR = os.path.join(project_root, 'config')
BASE_DIR = os.path.join(project_root, 'base')


def before_feature(context, feature):
    print("Before feature: ", feature.name)
    if 'with_witness' in feature.tags:
        create_witness_config_file(CONFIG_DIR, 'wit', 5646)
        command = [
            'kli',
            'witness',
            'start',
            '--name',
            'wit',
            '--alias',
            'wit',
            '--http',
            '5646',
            '--config-dir',
            CONFIG_DIR,
            '--config-file',
            'wit',
            '--base',
            BASE_DIR,
            '--passcode',
            '0ACDEyMzQ1Njc4OWdoaWp',
        ]

        proc = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        merge_into_context(context, 'wit', proc)


def after_feature(context, feature):
    if 'with_witness' in feature.tags:
        if hasattr(context, 'wit'):
            context.wit.terminate()
            context.wit.wait()

    print(f'Cleanup after feature: {feature.name}')
    for root, dirs, files in os.walk(BASE_DIR):
        for file in files:
            if file != 'DO_NOT_DELETE':
                os.remove(os.path.join(root, file))
        for d in dirs:
            shutil.rmtree(os.path.join(root, d))
