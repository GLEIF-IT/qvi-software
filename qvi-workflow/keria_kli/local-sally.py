#!/usr/bin/env python3
"""Run Sally with all persistent storage rooted in the workflow runtime."""

from __future__ import annotations

import os
from pathlib import Path

from hio.base import filing
from keri.db import dbing
from sally.app.cli import kli


def main() -> None:
    head_dir = os.environ.get("QVI_KERI_HEAD_DIR")
    if not head_dir:
        raise SystemExit("QVI_KERI_HEAD_DIR is required")

    resolved_head_dir = str(Path(head_dir).resolve())
    filing.Filer.HeadDirPath = resolved_head_dir
    dbing.LMDBer.HeadDirPath = resolved_head_dir
    raise SystemExit(kli.main())


if __name__ == "__main__":
    main()
