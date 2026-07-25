#!/usr/bin/env python3
"""Exercise the harness signal path with Python's normal KeyboardInterrupt."""

import sys
import time
from pathlib import Path


def main() -> None:
    """Run until SIGINT, then leave evidence that Python cleaned up normally."""
    ready_file = Path(sys.argv[1])
    cleanup_file = Path(sys.argv[2])

    ready_file.write_text("ready\n", encoding="utf-8")
    try:
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        cleanup_file.write_text("keyboard-interrupt\n", encoding="utf-8")


if __name__ == "__main__":
    main()
