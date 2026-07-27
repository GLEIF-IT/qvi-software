#!/usr/bin/env python3
"""Restore terminal interrupt handling before starting a background command."""

import os
import signal
import sys


def main() -> None:
    """Reset Bash-ignored terminal signals, then replace this process."""
    if len(sys.argv) < 2:
        raise SystemExit("usage: run-with-signals.py COMMAND [ARG ...]")

    # Non-interactive Bash makes `command &` ignore these signals. Restoring
    # their defaults lets Python install its normal KeyboardInterrupt handler.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGQUIT, signal.SIG_DFL)
    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
