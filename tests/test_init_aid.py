import pytest
from mockito import unstub, verify, when

from features.steps.init_aid import step_given_participants


class MockContext:
    pass


@pytest.fixture
def context():
    return MockContext()


def test_step_given_participants_multiple_values(context):
    participants = 'Alice, Bob, and Charlie'
    when('features.steps.init_aid').__init_incept(context, 'Alice', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)
    when('features.steps.init_aid').__init_incept(context, 'Bob', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)
    when('features.steps.init_aid').__init_incept(context, 'Charlie', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)

    step_given_participants(context, participants)

    verify('features.steps.init_aid').__init_incept(context, 'Alice', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    verify('features.steps.init_aid').__init_incept(context, 'Bob', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    verify('features.steps.init_aid').__init_incept(context, 'Charlie', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    unstub()


def test_step_given_participants_missing_values(context):
    participants = ''
    step_given_participants(context, participants)
    unstub()


def test_step_given_participants_out_of_order_and(context):
    participants = 'Alice and Bob and Charlie'
    when('features.steps.init_aid').__init_incept(context, 'Alice', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)
    when('features.steps.init_aid').__init_incept(context, 'Bob', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)
    when('features.steps.init_aid').__init_incept(context, 'Charlie', '0ACDEyMzQ1Njc4OWdoaWpsaw').thenReturn(None)

    step_given_participants(context, participants)

    verify('features.steps.init_aid').__init_incept(context, 'Alice', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    verify('features.steps.init_aid').__init_incept(context, 'Bob', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    verify('features.steps.init_aid').__init_incept(context, 'Charlie', '0ACDEyMzQ1Njc4OWdoaWpsaw')
    unstub()
