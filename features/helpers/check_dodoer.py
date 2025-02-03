import json

from hio.base import doing
from hio.core.http import Client, ClientDoer


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


def fetch_witness_aid(port):
    client_doer = ClientDoer(client=Client(hostname='127.0.0.1', port=port))
    tock = 0.03125
    doist = doing.Doist(limit=5, tock=tock, real=True)
    check_dodoer = CheckDoDoer(client_doer=client_doer)
    doist.do(doers=[check_dodoer])
    print(check_dodoer.response.get('body'))
    body = check_dodoer.response.get('body').decode('utf-8')
    print(body)
    end = body.rfind('}') + 1
    print(end)
    print(body[:end])
    # print(json.loads().get('i'))
