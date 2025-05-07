# Copyright 2025 OpenC3, Inc.
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
os.environ["OPENC3_LOCAL_MODE_PATH"] = os.path.dirname(__file__)
import io
import sys
import json
import fakeredis
import queue

from unittest.mock import *
from openc3.models.cvt_model import CvtModel
from openc3.utilities.logger import Logger
from openc3.utilities.store import Store, EphemeralStore
from openc3.utilities.store_queued import StoreQueued, EphemeralStoreQueued
from openc3.utilities.sleeper import Sleeper
from openc3.system.system import System

TEST_DIR = os.path.dirname(__file__)
Logger.no_store = True


# Record the message for pipelining by the thread
def my_getattr(self, func):
    def method(*args, **kwargs):
        return getattr(self.store, func)(*args, **kwargs)

    return method


def my_init(self, update_interval):
    self.update_interval = update_interval
    self.store = self.store_instance()
    # Queue to hold the store requests
    self.store_queue = queue.Queue()
    # Sleeper used to delay update thread
    self.update_sleeper = Sleeper()

    # Thread used to call methods on the store
    self.update_thread = None


import openc3.utilities.store_queued

openc3.utilities.store_queued.StoreQueued.__init__ = my_init
openc3.utilities.store_queued.StoreQueued.__getattr__ = my_getattr


def setup_system(targets=None):
    if targets is None:
        targets = ["SYSTEM", "INST", "EMPTY"]
    Logger.stdout = False
    file_path = os.path.realpath(__file__)
    target_config_dir = os.path.abspath(os.path.join(file_path, "..", "install", "config", "targets"))
    System.instance_obj = None
    System(targets, target_config_dir)

    # Initialize the packets in Redis
    for target_name in targets:
        try:
            for packet_name, packet in System.telemetry.packets(target_name).items():
                Store.hset(
                    f"DEFAULT__openc3tlm__{target_name}",
                    packet_name,
                    json.dumps(packet.as_json()),
                )
                packet = System.telemetry.packet(target_name, packet_name)
                # packet.received_time = datetime.now(timezone.utc)
                json_hash = {}
                for item in packet.sorted_items:
                    # Initialize all items to None like TargetModel::update_store does in Ruby
                    json_hash[item.name] = None
                CvtModel.set(
                    json_hash,  # CvtModel.build_json_from_packet(packet),
                    packet.target_name,
                    packet.packet_name,
                    scope="DEFAULT",
                )
        except RuntimeError:
            pass
        try:
            for packet_name, packet in System.commands.packets(target_name).items():
                Store.hset(
                    f"DEFAULT__openc3cmd__{target_name}",
                    packet_name,
                    json.dumps(packet.as_json()),
                )
        except RuntimeError:
            pass

        try:
            sets = {}
            for set in System.limits.sets():
                sets[set] = "false"
            Store.hset("DEFAULT__limits_sets", mapping=sets)
        except RuntimeError:
            pass


def mock_redis(self):
    """Ensure the store builds a new instance of redis and doesn't
    reuse the existing instance which results in a reused FakeRedis
    """
    EphemeralStore.my_instance = None
    Store.my_instance = None
    EphemeralStoreQueued.my_instance = None
    StoreQueued.my_instance = None
    redis = fakeredis.FakeRedis()
    patcher = patch("redis.Redis", return_value=redis)
    patcher.start()
    self.addCleanup(patcher.stop)
    return redis


import zlib
class BucketMock:
    instance = None
    def __init__(self):
        self.objs = {}

    @classmethod
    def getClient(cls):
        if cls.instance:
            return cls.instance
        cls.instance = cls()
        return cls.instance

    def put_object(self, *args, **kwargs):
        data = ''
        try:
            data = kwargs["body"].read()
        except AttributeError:
            data = kwargs["body"]
        self.objs[kwargs["key"]] = data

    def clear(self):
        self.objs = {}

    def files(self):
        return list(self.objs.keys())

    def data(self, key):
        data = self.objs[key]
        return zlib.decompress(data)


def capture_io():
    stdout = sys.stdout
    captured_output = io.StringIO()  # Create StringIO object
    sys.stdout = captured_output  # and redirect stdout.
    Logger.stdout = True
    Logger.level = Logger.INFO
    yield captured_output
    Logger.level = Logger.FATAL
    sys.stdout = stdout
