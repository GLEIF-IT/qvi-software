import pytest

from features.helpers.context_merge import merge_into_context


class MockContext:
    pass


@pytest.fixture
def context():
    return MockContext()


def test_merge_into_existing_dict(context):
    context.existing_attr = {'key1': 'value1'}
    new_data = {'key2': 'value2'}
    merge_into_context(context, 'existing_attr', new_data)
    assert context.existing_attr == {'key1': 'value1', 'key2': 'value2'}


def test_initialize_new_dict(context):
    new_data = {'key1': 'value1'}
    merge_into_context(context, 'new_attr', new_data)
    assert context.new_attr == {'key1': 'value1'}
