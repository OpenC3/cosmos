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

import gc
import os
import sys

import pytest


# OPENC3_TEST_PYTHON points at the openc3/python directory of a different
# checkout (e.g. a worktree of main) so the same tests can run against older
# code. See ../run_against.sh
sys.path.insert(
    0,
    os.environ.get("OPENC3_TEST_PYTHON", os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python")),
)
sys.path.insert(0, os.path.dirname(__file__))

# Keep the Logger from trying to publish to Redis
os.environ.setdefault("OPENC3_NO_STORE", "1")


@pytest.fixture(autouse=True)
def collect_garbage():
    # A garbage collection pass holds the GIL long enough for the read thread
    # to fall behind the default Linux socket buffer (~200KB, ~5ms at 40MB/s).
    # Start each test clean so one test's garbage doesn't land on the next.
    gc.collect()
    yield


def pytest_report_header(config):
    from openc3.interfaces import udp_interface

    return f"Testing {udp_interface.__file__}"
