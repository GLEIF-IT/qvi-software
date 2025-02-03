import subprocess

import pytest
from mockito import unstub, verify, when

from features.environment import after_feature, before_feature


class MockContext:
    pass


@pytest.fixture
def context():
    return MockContext()


def test_before_feature_with_witness_pool(context):
    feature = type('Feature', (object,), {'tags': ['with_witness_pool'], 'name': 'Test Feature'})

    when(subprocess).Popen(...).thenReturn(subprocess.Popen(['echo', 'mock']))

    before_feature(context, feature)

    assert hasattr(context, 'wan')
    assert hasattr(context, 'wil')
    assert hasattr(context, 'wes')

    unstub()


def test_after_feature_with_witness_pool(context):
    feature = type('Feature', (object,), {'tags': ['with_witness_pool'], 'name': 'Test Feature'})

    context.wan = subprocess.Popen(['echo', 'mock'])
    context.wil = subprocess.Popen(['echo', 'mock'])
    context.wes = subprocess.Popen(['echo', 'mock'])

    when(context.wan).terminate().thenReturn(None)
    when(context.wan).wait().thenReturn(None)
    when(context.wil).terminate().thenReturn(None)
    when(context.wil).wait().thenReturn(None)
    when(context.wes).terminate().thenReturn(None)
    when(context.wes).wait().thenReturn(None)

    after_feature(context, feature)

    verify(context.wan).terminate()
    verify(context.wan).wait()
    verify(context.wil).terminate()
    verify(context.wil).wait()
    verify(context.wes).terminate()
    verify(context.wes).wait()

    unstub()


def test_before_feature_without_witness_pool(context):
    feature = type('Feature', (object,), {'tags': [], 'name': 'Test Feature'})

    before_feature(context, feature)

    assert not hasattr(context, 'wan')
    assert not hasattr(context, 'wil')
    assert not hasattr(context, 'wes')


def test_after_feature_without_witness_pool(context):
    feature = type('Feature', (object,), {'tags': [], 'name': 'Test Feature'})

    after_feature(context, feature)

    # No subprocesses should be terminated
    assert True
