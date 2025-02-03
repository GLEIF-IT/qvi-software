from pathlib import Path


def get_project_root():
    current_dir = Path(__file__).resolve()
    for parent in current_dir.parents:
        if (parent / 'pyproject.toml').exists():
            return parent
    raise RuntimeError('Project root not found.')
