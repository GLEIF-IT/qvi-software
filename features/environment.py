import os
import subprocess

from features.helpers.check_dodoer import fetch_witness_aid
from features.helpers.context_merge import merge_into_context
from features.helpers.create_witness_config_file import create_witness_config_file
from features.helpers.root import get_project_root

project_root = get_project_root()

DATA_DIR = os.path.join(project_root, 'data')
CONFIG_DIR = os.path.join(project_root, 'config')
BASE_DIR = os.path.join(project_root, 'base')


def before_feature(context, feature):
    if 'with_witness_pool' in feature.tags:
        wits = {
            'wan': 5642,
            'wil': 5643,
            'wes': 5644,
        }

        for wit, port in wits.items():
            create_witness_config_file(CONFIG_DIR, wit, port)
            proc = subprocess.Popen(
                [
                    'kli',
                    'witness',
                    'start',
                    '--alias',
                    wit,
                    '--http',
                    str(port),
                    '--config-dir',
                    CONFIG_DIR,
                    '--config-file',
                    wit,
                    '--base',
                    BASE_DIR,
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            merge_into_context(context, wit, proc)
            fetch_witness_aid(port)


def after_feature(context, feature):
    if 'with_witness_pool' in feature.tags:
        if hasattr(context, 'wan'):
            context.wan.terminate()
            context.wan.wait()
        if hasattr(context, 'wil'):
            context.wil.terminate()
            context.wil.wait()
        if hasattr(context, 'wes'):
            context.wes.terminate()
            context.wes.wait()

    print(f'Cleanup after feature: {feature.name}')
