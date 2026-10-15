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

import os


# Keep boto3 away from the developer's real AWS setup. Without this a local
# ~/.aws/config (e.g. an `aws login` session, which needs botocore[crt]) makes
# every boto3 client creation fail, while CI with no AWS config passes. Set
# before any openc3 import since clients are created at import time.
os.environ["AWS_CONFIG_FILE"] = os.devnull
os.environ["AWS_SHARED_CREDENTIALS_FILE"] = os.devnull
os.environ.pop("AWS_PROFILE", None)
os.environ.pop("AWS_DEFAULT_PROFILE", None)
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ.pop("AWS_SESSION_TOKEN", None)

import pytest  # noqa: E402

from openc3.utilities.logger import Logger  # noqa: E402


@pytest.fixture(autouse=True, scope="function")
def configure_logging():
    """Let pytest capture log output - only shown on test failure."""
    original_stdout = Logger.stdout
    Logger.stdout = True
    yield
    Logger.stdout = original_stdout
