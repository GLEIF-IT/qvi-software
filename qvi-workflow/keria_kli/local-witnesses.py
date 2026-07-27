#!/usr/bin/env python3
"""Run the three deterministic demo witnesses in workflow-owned storage."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from hio.base import doing, filing
from keri.app import configing, directing, habbing, indirecting
from keri.core import Salter
from keri.db import dbing


@dataclass(frozen=True)
class Witness:
    alias: str
    salt: bytes
    tcp_port: int
    http_port: int


WITNESSES = (
    Witness("wan", b"wann-the-witness", 5632, 5642),
    Witness("wil", b"will-the-witness", 5633, 5643),
    Witness("wes", b"wess-the-witness", 5634, 5644),
)

class WitnessDoer(doing.DoDoer):
    def __init__(self, haberies: dict[str, habbing.Habery]):
        self.haberies = haberies
        super().__init__(doers=[doing.doify(self.initialize)])

    def initialize(self, tymth, tock: float = 0.0, **_):
        self.wind(tymth)
        self.tock = tock
        yield self.tock

        doers = []
        for witness in WITNESSES:
            doers.extend(
                indirecting.setupWitness(
                    hby=self.haberies[witness.alias],
                    alias=witness.alias,
                    tcpPort=witness.tcp_port,
                    httpPort=witness.http_port,
                )
            )
        self.extend(doers)


def parser() -> argparse.ArgumentParser:
    argument_parser = argparse.ArgumentParser(
        description="Run Wan, Wil, and Wes with isolated local state"
    )
    argument_parser.add_argument("--head-dir", required=True)
    argument_parser.add_argument("--base", default="witnesses")
    argument_parser.add_argument("--config-dir", required=True)
    return argument_parser


def main() -> None:
    args = parser().parse_args()
    head_dir = str(Path(args.head_dir).resolve())
    base = args.base
    config_dir = str(Path(args.config_dir).resolve())

    filing.Filer.HeadDirPath = head_dir
    dbing.LMDBer.HeadDirPath = head_dir

    haberies = {}
    for witness in WITNESSES:
        config = configing.Configer(
            name=witness.alias,
            base="",
            headDirPath=config_dir,
            temp=False,
            reopen=True,
            clear=False,
        )
        haberies[witness.alias] = habbing.Habery(
            name=witness.alias,
            base=base,
            salt=Salter(raw=witness.salt).qb64,
            temp=False,
            cf=config,
            headDirPath=head_dir,
        )

    directing.runController(
        doers=[WitnessDoer(haberies=haberies)],
        expire=0.0,
    )


if __name__ == "__main__":
    main()
