#!/usr/bin/env python3
"""Verify QVI's generated KERIA tocks and environment precedence."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from keri.app import tocking as keritocking
from keria.app import tocking


def main() -> None:
    config_path = Path(sys.argv[1])
    config = json.loads(config_path.read_text())
    resolved = tocking.resolveTocks(config)
    kli_config = json.loads(Path(sys.argv[2]).read_text())
    kli_tocks = keritocking.resolveTocks(kli_config["tocks"], environ={})

    assert config["tocks"]["pollerConnect"] == 0.03125
    assert resolved.keri["pollerConnect"] == 0.03125
    assert config["tocks"]["signify"]["initer"] == 0.0
    assert resolved.signify["initer"] == 0.0
    assert config["tocks"]["signify"]["escrower"] == 0.03125
    assert resolved.signify["escrower"] == 0.0
    assert "signify" not in kli_config["tocks"]
    assert kli_tocks["counselorEscrow"] == 0.03125
    assert kli_tocks["registrarEscrow"] == 0.03125
    assert kli_tocks["credentialerEscrow"] == 0.03125
    print(
        "tocks: KLI counselor/registrar/credentialer=0.03125, "
        "KERIA pollerConnect=0.03125, explicit initer=0.0, "
        "KERIA_ESCROWER_TOCK override=0.0"
    )


if __name__ == "__main__":
    main()
