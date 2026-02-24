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

import pytest

from openc3.utilities.logger import Logger


@pytest.fixture(autouse=True, scope="function")
def configure_logging():
    """Let pytest capture log output - only shown on test failure."""
    original_stdout = Logger.stdout
    Logger.stdout = True
    yield
    Logger.stdout = original_stdout
