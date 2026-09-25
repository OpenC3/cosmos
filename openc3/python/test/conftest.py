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

# ruff: noqa: E402, I001 - the environment below must be set before openc3 is
# imported because openc3.environment snapshots it into module constants
import os

# Unit tests never talk to a real bucket but constructing the boto3 session
# without credentials makes botocore walk the ambient credential chain, which
# picks up whatever is in the developer's AWS config. Pin dummy credentials so
# the session is built from these and the chain is never consulted. conftest is
# imported before any test module, and so before aws_bucket builds its session.
os.environ.setdefault("OPENC3_BUCKET_USERNAME", "openc3bucket")
os.environ.setdefault("OPENC3_BUCKET_PASSWORD", "openc3bucket_password")

import pytest

from openc3.utilities.logger import Logger


@pytest.fixture(autouse=True, scope="function")
def configure_logging():
    """Let pytest capture log output - only shown on test failure."""
    original_stdout = Logger.stdout
    Logger.stdout = True
    yield
    Logger.stdout = original_stdout
