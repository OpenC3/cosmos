# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import redis
from redis.exceptions import TimeoutError
from openc3.utilities.connection_pool import ConnectionPool
from contextlib import contextmanager
import threading
from openc3.environment import *

if OPENC3_REDIS_CLUSTER:
    openc3_redis_cluster = True
else:
    openc3_redis_cluster = False


class StoreConnectionPool(ConnectionPool):
    @contextmanager
    def pipelined(self):
        if openc3_redis_cluster:
            yield  # TODO: Update keys to support pipelining in cluster
        else:
            with self.get() as redis:
                pipeline = redis.pipeline(transaction=False)
                thread_id = threading.get_native_id()
                self.pipelines[thread_id] = pipeline
                try:
                    yield
                finally:
                    pipeline.execute()
                    self.pipelines[thread_id] = None

    @contextmanager
    def get(self):
        thread_id = threading.get_native_id()
        if thread_id not in self.pipelines:
            self.pipelines[thread_id] = None
        pipeline = self.pipelines[thread_id]
        if pipeline:
            yield pipeline
        else:
            item = None
            with self.lock:
                if not self.pool.empty():
                    item = self.pool.get(False)
                elif self.count < self.pool_size:
                    item = self.ctor()
                    self.count += 1
                else:
                    item = self.pool.get()
            try:
                yield item
            finally:
                self.pool.put(item)


class StoreMeta(type):
    def __getattribute__(cls, func):
        if func == "instance" or func == "instance_mutex" or func == "my_instance":
            return super().__getattribute__(func)

        def method(*args, **kw_args):
            return getattr(cls.instance(), func)(*args, **kw_args)

        return method


class Store(metaclass=StoreMeta):
    # Variable that holds the singleton instance
    my_instance = None

    # Mutex used to ensure that only one instance is created
    instance_mutex = threading.Lock()

    # Get the singleton instance
    @classmethod
    def instance(cls, pool_size=100):
        if cls.my_instance:
            return cls.my_instance

        with cls.instance_mutex:
            cls.my_instance = cls(pool_size)
            return cls.my_instance

    # Delegate all unknown methods to redis through the @redis_pool
    def __getattr__(self, func):
        with self.redis_pool.get() as redis:

            def method(*args, **kwargs):
                return getattr(redis, func)(*args, **kwargs)

            return method

    def __init__(self, pool_size=10):
        self.redis_host = OPENC3_REDIS_HOSTNAME
        self.redis_port = OPENC3_REDIS_PORT
        self.redis_pool = StoreConnectionPool(self.build_redis, pool_size)
        self.topic_offsets = {}
        self.pipelines = {}

    if not openc3_redis_cluster:

        def build_redis(self):
            # NOTE: We can't use decode_response because it tries to decode the binary
            # packet buffer which does not work. Thus strings come back as bytes like
            # b"target_name" and we decode them using b"target_name".decode()
            return redis.Redis(
                host=self.redis_host,
                port=self.redis_port,
                username=OPENC3_REDIS_USERNAME,
                password=OPENC3_REDIS_PASSWORD,
            )

    ###########################################################################
    # Stream APIs
    ###########################################################################

    def get_oldest_message(self, topic):
        with self.redis_pool.get() as redis:
            result = redis.xrange(topic, count=1)
            if result and len(result) > 0:
                return result[0]
            else:
                return None

    def get_newest_message(self, topic):
        with self.redis_pool.get() as redis:
            # Default in xrevrange is range end '+', start '-' which means get all
            # elements from higher ID to lower ID and since we're limiting to 1
            # we get the last element. See https://redis.io/commands/xrevrange.
            result = redis.xrevrange(topic, count=1)
            if result and len(result) > 0:
                first = list(result[0])
                first[0] = first[0].decode()
                return first
            else:
                return (None, None)

    def get_last_offset(self, topic):
        with self.redis_pool.get() as redis:
            result = redis.xrevrange(topic, count=1)
            if result and result[0] and result[0][0]:
                return result[0][0].decode()
            else:
                return "0-0"

    def update_topic_offsets(self, topics):
        offsets = []
        for topic in topics:
            # Normally we will just be grabbing the topic offset
            # this allows xread to get everything past this point
            thread_id = threading.get_native_id()
            if thread_id not in self.topic_offsets:
                self.topic_offsets[thread_id] = {}
            topic_offsets = self.topic_offsets[thread_id]
            last_id = topic_offsets.get(topic)
            if last_id:
                offsets.append(last_id)
            else:
                # If there is no topic offset this is the first call.
                # Get the last offset ID so we'll start getting everything from now on
                offsets.append(self.get_last_offset(topic))
                topic_offsets[topic] = offsets[-1]
        return offsets

    if not openc3_redis_cluster:

        def read_topics(self, topics, offsets=None, timeout_ms=1000, count=None):
            if len(topics) == 0:
                return {}
            thread_id = threading.get_native_id()
            if thread_id not in self.topic_offsets:
                self.topic_offsets[thread_id] = {}
            topic_offsets = self.topic_offsets[thread_id]
            try:
                with self.redis_pool.get() as redis:
                    if not offsets:
                        offsets = self.update_topic_offsets(topics)
                    streams = {}
                    index = 0
                    for topic in topics:
                        streams[topic] = offsets[index]
                        index += 1
                    result = redis.xread(streams, block=timeout_ms, count=count)
                    if result and len(result) > 0:
                        for topic, messages in result:
                            for msg_id, msg_hash in messages:
                                if isinstance(topic, bytes):
                                    topic = topic.decode()
                                if isinstance(msg_id, bytes):
                                    msg_id = msg_id.decode()
                                topic_offsets[topic] = msg_id
                                yield topic, msg_id, msg_hash, redis
                    return result
            except TimeoutError:
                # Should return an empty hash not array - xread returns a hash
                return {}

    # Add new entry to the redis stream.
    # > https://www.rubydoc.info/github/redis/redis-rb/Redis:xadd
    #
    # @example Without options
    #   store.write_topic('MANGO__TOPIC', {'message' => 'something'})
    # @example With options
    #   store.write_topic('MANGO__TOPIC', {'message' => 'something'}, id: '0-0', maxlen: 1000, approximate: 'true')
    #
    # @param topic [String] the stream / topic
    # @param msg_hash [Hash]   one or multiple field-value pairs
    #
    # @option opts [String]  :id          the entry id, default value is `*`, it means auto generation,
    #   if `nil` id is passed it will be changed to `*`
    # @option opts [Integer] :maxlen      max length of entries, default value is `nil`, it means will grow forever
    # @option opts [String] :approximate whether to add `~` modifier of maxlen or not, default value is 'true'
    #
    # @return [String] the entry id
    def write_topic(self, topic, msg_hash, id="*", maxlen=None, approximate=True):
        if not id:
            id = "*"
        with self.redis_pool.get() as redis:
            return redis.xadd(topic, msg_hash, id=id, maxlen=maxlen, approximate=approximate)

    # Trims older entries of the redis stream if needed.
    # > https://www.rubydoc.info/github/redis/redis-rb/Redis:xtrim
    #
    # @example Without options
    #   store.trim_topic('MANGO__TOPIC', 1000)
    # @example With options
    #   store.trim_topic('MANGO__TOPIC', 1000, approximate: 'true', limit: 0)
    #
    # @param topic  [String]  the stream key
    # @param minid  [Integer] Id to throw away data up to
    # @param approximate [Boolean] whether to add `~` modifier of maxlen or not
    # @param limit  [Boolean] number of items to return from the call
    #
    # @return [Integer] the number of entries actually deleted
    def trim_topic(self, topic, minid, approximate=True, limit=0):
        with self.redis_pool.get() as redis:
            return redis.xtrim(name=topic, minid=minid, approximate=approximate, limit=limit)


class EphemeralStore(Store):
    # Variable that holds the singleton instance
    my_instance = None

    def __init__(self, pool_size=10):
        super().__init__(pool_size)
        self.redis_host = OPENC3_REDIS_EPHEMERAL_HOSTNAME
        self.redis_port = OPENC3_REDIS_EPHEMERAL_PORT
        self.redis_pool = StoreConnectionPool(self.build_redis, pool_size)
