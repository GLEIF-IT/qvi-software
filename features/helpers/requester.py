from hio import help
from hio.base import doing

logger = help.ogler.getLogger()


class RequestDoer(doing.Doer):
    def __init__(self, clientDoer):
        self.client = clientDoer.client
        self.clientDoer = clientDoer
        self.response = None
        super(RequestDoer, self).__init__()

    def recur(self, tyme=None):
        self.client.request(
            method='GET',
            path='/oobi',
            headers=None,
            body=None,
            qargs=None,
        )

        while not self.client.responses:
            yield self.tock

        self.response = self.client.responses.popleft()
        self.clientDoer.exit()

        return True
