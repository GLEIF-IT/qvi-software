from behave import *

 use_step_matcher("re")


@when('"Alice and Bob exchange oobis"')
def step_impl(context):
    """
    :type context: behave.runner.Context
    """
    raise NotImplementedError(u'STEP: When "Alice and Bob exchange oobis"')