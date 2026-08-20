# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
from unittest.mock import patch


os.environ["OPENC3_NO_STORE"] = "true"
os.environ["OPENC3_CLOUD"] = "local"
os.environ["OPENC3_LOGS_BUCKET"] = "logs"
os.environ["OPENC3_TOOLS_BUCKET"] = "tools"
os.environ["OPENC3_CONFIG_BUCKET"] = "config"
os.environ["OPENC3_LOCAL_MODE_PATH"] = os.path.dirname(__file__)
import io
import json
import queue
import sys
import threading
import time

import fakeredis

from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.system.system import System
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.store import EphemeralStore, Store
from openc3.utilities.store_queued import EphemeralStoreQueued, StoreQueued


TEST_DIR = os.path.dirname(__file__)
Logger.no_store = True


# Record the message for pipelining by the thread
def my_getattr(self, func):
    def method(*args, **kwargs):
        return getattr(self.store, func)(*args, **kwargs)

    return method


def my_init(self, update_interval, db_shard=0):
    self.update_interval = update_interval
    self.db_shard = db_shard
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
    TargetModel.clear_packet_cache()
    System.instance(targets, target_config_dir)

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
        except Exception:
            pass
        try:
            for packet_name, packet in System.commands.packets(target_name).items():
                Store.hset(
                    f"DEFAULT__openc3cmd__{target_name}",
                    packet_name,
                    json.dumps(packet.as_json()),
                )
        except Exception:
            pass

        try:
            sets = {}
            for set in System.limits.sets():
                sets[set] = "false"
            Store.hset("DEFAULT__limits_sets", mapping=sets)
        except Exception:
            pass


class XreadTracker:
    """Wraps xread to record which threads have issued a read.

    Topic offsets are tracked per thread (see StoreImplementation.read_topics),
    so a microservice run thread only receives messages written after its own
    first read. Tests use wait_for_first_topic_read to wait for that read rather
    than sleeping a fixed amount.
    """

    def __init__(self, xread):
        self.xread = xread
        self.thread_ids = set()

    def __call__(self, *args, **kwargs):
        # Record before delegating: read_topics has already snapshotted the
        # topic offsets by the time it calls xread, so anything written from
        # here on is guaranteed to be delivered to this thread.
        self.thread_ids.add(threading.get_native_id())
        return self.xread(*args, **kwargs)


def mock_redis(self):
    """Ensure the store builds a new instance of valkey and doesn't
    reuse the existing instance which results in a reused FakeValkey.

    IMPORTANT: The mock must be applied BEFORE clearing singleton instances
    to prevent a race condition where a lingering background thread from a
    previous test sees my_instance=None, calls instance(), and recreates
    the singleton using the real valkey.Valkey (causing DNS resolution
    failures in CI).
    """
    redis = fakeredis.FakeValkey()
    redis.flushall()
    # Track reads by thread so tests can wait for a microservice run thread to
    # start reading. Tests that replace redis.xread themselves wrap this
    # tracker, so it still sees every read.
    redis.openc3_xread_tracker = XreadTracker(redis.xread)
    redis.xread = redis.openc3_xread_tracker
    patcher = patch("valkey.Valkey", return_value=redis)
    patcher.start()
    self.addCleanup(patcher.stop)
    EphemeralStore.my_instances = {}
    Store.my_instances = {}
    Store._db_shard_cache = {}
    EphemeralStoreQueued.my_instances = {}
    StoreQueued.my_instances = {}
    return redis


import zlib


class BucketMock:
    instance = None

    def __init__(self):
        self.objs = {}

    @classmethod
    def get_client(cls):
        if cls.instance:
            return cls.instance
        cls.instance = cls()
        return cls.instance

    def put_object(self, *args, **kwargs):
        data = ""
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


def wait_for_first_topic_read(redis, thread, timeout=5):
    """Block until the given thread has issued its first xread.

    Call this after starting a microservice run thread, instead of sleeping.

    Topic offsets are tracked per thread (see StoreImplementation.read_topics),
    so the offsets recorded by Topic.update_topic_offsets when a microservice is
    constructed on the main thread do not apply to its run thread. That thread
    records its own start offset on its first read_topics call, which is the
    current end of the stream, so anything written before then is skipped and
    never processed. Sleeping a fixed amount after Thread.start() is racy: on a
    loaded CI runner the run thread can reach its first read after the test has
    already written to the topic.
    """
    tracker = redis.openc3_xread_tracker
    start = time.time()
    while (time.time() - start) < timeout:
        # native_id is only assigned once the thread is actually running
        if thread.native_id is not None and thread.native_id in tracker.thread_ids:
            return
        time.sleep(0.001)
    raise RuntimeError(f"Thread {thread.name} never read from its topics")


def capture_io():
    stdout = sys.stdout
    captured_output = io.StringIO()  # Create StringIO object
    sys.stdout = captured_output  # and redirect stdout.
    Logger.stdout = True
    Logger.level = Logger.INFO
    try:
        yield captured_output
    finally:
        Logger.level = Logger.FATAL
        sys.stdout = stdout
