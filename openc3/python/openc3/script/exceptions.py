# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


class CheckError(Exception):
    """Raised when a telemetry check such as `check` or `wait_check` fails."""

    pass


class StopScriptError(Exception):
    """Raise to stop the running script."""

    pass


# Deprecated alias for backwards compatibility
StopScript = StopScriptError


class SkipScriptError(Exception):
    """Raise to skip the current suite script, which is recorded with a SKIP result."""

    pass


# Deprecated alias for backwards compatibility
SkipScript = SkipScriptError
