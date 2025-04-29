import json
import os

from keri.help import helping


def create_witness_config_file(config_dir, alias, port):
    dt = helping.nowIso8601()

    config_data = {
        'dt': dt,
        alias: {
            'dt': dt,
            'curls': [f'http://127.0.0.1:{port}'],
        },
        'iurls': [],
    }

    config_file_path = os.path.join(config_dir, 'keri', 'cf', 'main', f'{alias}.json')
    with open(config_file_path, 'w') as config_file:
        json.dump(config_data, config_file, indent=4)

    print(f'Config file created: {config_file_path}')
