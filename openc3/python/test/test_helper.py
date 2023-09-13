# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os

os.environ["OPENC3_NO_STORE"] = "true"
os.environ["OPENC3_CLOUD"] = "local"
os.environ["OPENC3_LOGS_BUCKET"] = "logs"
os.environ["OPENC3_TOOLS_BUCKET"] = "tools"
os.environ["OPENC3_CONFIG_BUCKET"] = "config"
import io
import sys
import fakeredis
from unittest.mock import *
from openc3.utilities.logger import Logger
from openc3.utilities.store import Store
from openc3.system.system import System


def setup_system(targets=["SYSTEM", "INST", "EMPTY"]):
    file_path = os.path.realpath(__file__)
    dir = os.path.abspath(os.path.join(file_path, "..", "install", "config", "targets"))
    System.instance_obj = None
    System(targets, dir)
    Logger.stdout = False


def mock_redis(self):
    # Ensure the store builds a new instance of redis and doesn't
    # reuse the existing instance which results in a reused FakeRedis
    Store.my_instance = None
    redis = fakeredis.FakeRedis(decode_responses=True)
    patcher = patch("redis.Redis", return_value=redis)
    self.mock_redis = patcher.start()
    self.addCleanup(patcher.stop)
    return redis


class MockS3:
    def __init__(self):
        self.clear()

    def client(self, *args, **kwags):
        return self

    def put_object(self, *args, **kwargs):
        self.files[kwargs["Key"]] = kwargs["Body"].read()

    def clear(self):
        self.files = {}


mock = MockS3()


def mock_s3(self):
    # We have to remove all the openc3 modules to allow the boto3 mock patch
    # to be applied when we use the aws_bucket. There's probably an easier or
    # more targeted way to achieve this but I don't know it. To test print
    # the s3_session object in aws_bucket __init__.
    # TODO: is there a way to use importlib.reload
    names = []
    for name, _ in sys.modules.items():
        if "openc3" in name:
            names.append(name)
    for name in names:
        del sys.modules[name]
    patcher = patch("boto3.session.Session", return_value=mock)
    self.mock_s3 = patcher.start()
    self.addCleanup(patcher.stop)
    return mock


def capture_io():
    stdout = sys.stdout
    capturedOutput = io.StringIO()  # Create StringIO object
    sys.stdout = capturedOutput  #  and redirect stdout.
    Logger.stdout = True
    Logger.level = Logger.INFO
    yield capturedOutput
    Logger.level = Logger.FATAL
    sys.stdout = stdout
