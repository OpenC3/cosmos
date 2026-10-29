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
    self.shutdown_mutex = threading.Lock()
    # Sleeper used to delay update thread
    self.update_sleeper = Sleeper()

    # Thread used to call methods on the store
    self.update_thread = None


import openc3.utilities.store_queued


openc3.utilities.store_queued.StoreQueued.__init__ = my_init
openc3.utilities.store_queued.StoreQueued.__getattr__ = my_getattr


def setup_system(targets=None, db_shards=None):
    """db_shards maps target names to the db_shard they are installed on.
    When given, every target gets its target JSON (carrying its db_shard,
    default 0) on db_shard 0 like the Ruby TargetModel install writes, and its
    packet definitions and current values on its own db_shard. They're written
    there directly rather than routed by the code under test so a routing bug
    can't also move the setup data."""
    if targets is None:
        targets = ["SYSTEM", "INST", "EMPTY"]
    Logger.stdout = False
    file_path = os.path.realpath(__file__)
    target_config_dir = os.path.abspath(os.path.join(file_path, "..", "install", "config", "targets"))
    System.instance_obj = None
    TargetModel.clear_packet_cache()
    System.instance(targets, target_config_dir)

    if db_shards is None:
        db_shards = {}
    else:
        for target_name in targets:
            set_target_db_shard(target_name, db_shards.get(target_name, 0))

    # Initialize the packets in Redis
    for target_name in targets:
        db_shard = db_shards.get(target_name, 0)
        try:
            for packet_name, packet in System.telemetry.packets(target_name).items():
                Store.instance(db_shard=db_shard).hset(
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
                if db_shard == 0:
                    CvtModel.set(
                        json_hash,  # CvtModel.build_json_from_packet(packet),
                        packet.target_name,
                        packet.packet_name,
                        scope="DEFAULT",
                    )
                else:
                    Store.instance(db_shard=db_shard).hset(
                        f"DEFAULT__tlm__{target_name}", packet_name, json.dumps(json_hash)
                    )
        except Exception:
            pass
        try:
            for packet_name, packet in System.commands.packets(target_name).items():
                Store.instance(db_shard=db_shard).hset(
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


def set_target_db_shard(target_name, db_shard, scope="DEFAULT"):
    """Install a target on a db_shard by writing its target JSON to db_shard 0,
    which is where Store.db_shard_for_target looks it up"""
    Store.instance(db_shard=0).hset(
        f"{scope}__openc3_targets",
        target_name,
        json.dumps({"name": target_name, "folder_name": target_name, "db_shard": db_shard, "scope": scope}),
    )
    Store._db_shard_cache = {}


def shard_redis(db_shard):
    """Return the FakeValkey mock_redis built for db_shard"""
    return Store.instance(db_shard=db_shard).build_redis()


def read_topics_from_start(db_shard, topics):
    """Make the calling thread's reads of topics on db_shard start at the
    beginning of each stream rather than only seeing messages written after
    its first read"""
    offsets = EphemeralStore.instance(db_shard=db_shard).topic_offsets.setdefault(threading.get_native_id(), {})
    for topic in topics:
        offsets[topic] = "0-0"


def ack_next_message(redis, topic, ack_topic, result=b"SUCCESS", fields=None, timeout=5):
    """Start a thread which waits for the next message written to topic in the
    given db_shard fake and acks it on ack_topic in the same fake, like the
    microservice listening on that topic would. Join the returned thread."""
    start_len = redis.xlen(topic)

    def respond():
        start = time.time()
        while (time.time() - start) < timeout:
            if redis.xlen(topic) > start_len:
                msg_id, _ = redis.xrevrange(topic, count=1)[0]
                redis.xadd(ack_topic, {"id": msg_id, "result": result, **(fields or {})})
                return
            time.sleep(0.001)

    thread = threading.Thread(target=respond)
    thread.start()
    return thread


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

    Each db_shard gets its own FakeValkey (with its own FakeServer) so a read
    or write against the wrong shard misses instead of silently hitting the
    same data. Store and EphemeralStore share the fake for a given shard.
    Returns the shard 0 fake.
    """
    redis_shards = {}
    redis_shards_lock = threading.Lock()

    def shard_redis(db_shard):
        with redis_shards_lock:
            if db_shard in redis_shards:
                return redis_shards[db_shard]
            shard = fakeredis.FakeValkey(server=fakeredis.FakeServer())
            # Track reads by thread so tests can wait for a microservice run thread to
            # start reading. Tests that replace redis.xread themselves wrap this
            # tracker, so it still sees every read.
            shard.openc3_xread_tracker = XreadTracker(shard.xread)
            shard.xread = shard.openc3_xread_tracker
            redis_shards[db_shard] = shard
            return shard

    redis = shard_redis(0)
    patcher = patch("valkey.Valkey", return_value=redis)
    patcher.start()
    self.addCleanup(patcher.stop)
    build_patcher = patch.object(Store, "build_redis", lambda store: shard_redis(store.db_shard))
    build_patcher.start()
    self.addCleanup(build_patcher.stop)
    EphemeralStore.my_instances = {}
    Store.my_instances = {}
    Store._db_shard_cache = {}
    EphemeralStoreQueued.my_instances = {}
    StoreQueued.my_instances = {}
    EphemeralStoreQueued.all_shards_update_interval = None
    StoreQueued.all_shards_update_interval = None
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


def wait_for(condition, timeout=5, interval=0.005):
    """Poll until condition() is truthy or timeout expires.

    Call this instead of sleeping a fixed amount when waiting on a background
    microservice thread to process telemetry. A sleep that is long enough on a
    developer machine can be too short on a loaded CI runner, which makes the
    assertion that follows it flaky. Does not assert on timeout: the caller's
    assertion still runs so its failure message stays useful.
    """
    start = time.time()
    while (time.time() - start) < timeout:
        if condition():
            return
        time.sleep(interval)


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
