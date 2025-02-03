from pathlib import Path

import pytest

from features.helpers.root import get_project_root


def test_get_project_root_found(monkeypatch):
    def mock_resolve(self):
        return Path('/mock/project/features/helpers/root.py')

    def mock_exists(self):
        return self == Path('/mock/project/pyproject.toml')

    monkeypatch.setattr(Path, 'resolve', mock_resolve)
    monkeypatch.setattr(Path, 'exists', mock_exists)

    assert get_project_root() == Path('/mock/project')


def test_get_project_root_not_found(monkeypatch):
    def mock_resolve(self):
        return Path('/mock/project/features/helpers/root.py')

    def mock_exists(self):
        return False

    monkeypatch.setattr(Path, 'resolve', mock_resolve)
    monkeypatch.setattr(Path, 'exists', mock_exists)

    with pytest.raises(RuntimeError, match='Project root not found.'):
        get_project_root()
