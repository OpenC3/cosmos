"""Console-script entry point for the openc3pycli command.

This module lives outside the openc3 package on purpose: pip's generated
wrapper imports the entry-point module before calling its function, and any
import path inside the openc3 package would run openc3/__init__.py first.
That pulls in openc3.environment, which captures OPENC3_NO_STORE once at
import time. By setting the env var here — before importing openc3.cli —
the Logger sees no_store=True and avoids talking to a Redis store that
doesn't exist when running on a host (e.g. a bridge).
"""

import os


os.environ.setdefault("OPENC3_NO_STORE", "1")

from openc3.cli import main  # noqa: E402


__all__ = ["main"]
