from hio.base import doing

def run(doers, expire=0.0):
    tock = 0.03125
    doist = doing.Doist(limit=expire, tock=tock, real=True)
    doist.do(doers=doers)