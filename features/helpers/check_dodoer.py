from hio.base import doing


class CheckDoDoer(doing.DoDoer):
    def __init__(
        self,
        client_doer,
    ):
        self.client_doer = client_doer
        self.response = None
        doers = [doing.doify(self.request), self.client_doer]

        super(CheckDoDoer, self).__init__(doers=doers)

    def request(self, tymth, tock=0.0):
        self.wind(tymth)
        self.tock = tock
        _ = yield self.tock
        self.client_doer.client.request(
            method='GET',
            path='/oobi',
            headers=None,
            body=None,
            qargs=None,
        )

        while not self.client_doer.client.responses:
            yield self.tock

        self.response = self.client_doer.client.responses.popleft()
        self.remove([self.client_doer])
