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

from openc3.utilities.store import StoreMeta, Store, EphemeralStore
from openc3.utilities.sleeper import Sleeper
import time
import threading
import queue
import atexit

# Updated from top_level to remove circular dependency


# Attempt to gracefully kill a thread
# @param owner Object that owns the thread and may have a graceful_kill method
# @param thread The thread to gracefully kill
# @param timeout Timeout in seconds to wait for it to die gracefully
def kill_thread(owner, thread, timeout=1.0):
    if thread:
        if owner and hasattr(owner, "graceful_kill"):
            if threading.current_thread() != thread:
                owner.graceful_kill()
                thread.join(timeout=timeout)


class StoreQueued(metaclass=StoreMeta):
    # Variable that holds the singleton instance
    my_instance = None

    # Mutex used to ensure that only one instance is created
    instance_mutex = threading.Lock()

    # Get the singleton instance
    @classmethod
    def instance(cls, update_interval=1):
        if cls.my_instance:
            return cls.my_instance

        with cls.instance_mutex:
            cls.my_instance = cls(update_interval)
            return cls.my_instance

    def __init__(self, update_interval):
        self.update_interval = update_interval
        self.store = self.store_instance()
        # Queue to hold the store requests
        self.store_queue = queue.Queue()
        # Sleeper used to delay update thread
        self.update_sleeper = Sleeper()

        # Use atexit to shutdown cleanly no matter how we die
        atexit.register(self.shutdown)

        # Thread used to call methods on the store
        self.update_thread = threading.Thread(target=self.store_thread_body, daemon=True)
        self.update_thread.start()

    def set_update_interval(self, interval):
        if interval < self.update_interval and interval > 0.0:
            self.update_interval = interval

    def process_queue(self):
        if not self.store_queue.empty():
            # Pipeline the requests to redis to improve performance
            with self.store.redis_pool.get():
                with self.store.redis_pool.pipelined():
                    while not self.store_queue.empty():
                        action = self.store_queue.get()
                        getattr(self.store, action[0])(*action[1], **action[2])

    def store_thread_body(self):
        while True:
            start_time = time.time()

            self.process_queue()

            # Only check whether to update at a set interval
            run_time = time.time() - start_time
            sleep_time = self.update_interval - run_time
            if sleep_time < 0:
                sleep_time = 0
            if self.update_sleeper.sleep(sleep_time):
                break

    def shutdown(self):
        if self.update_sleeper:
            self.update_sleeper.cancel()
        if self.update_thread:
            kill_thread(self, self.update_thread)
        self.update_thread = None
        # Drain the queue before shutdown
        self.process_queue()

    # Record the message for pipelining by the thread
    def __getattr__(self, func):
        def method(*args, **kwargs):
            return self.store_queue.put([func, args, kwargs])

        return method

    # Returns the store we're working with
    def store_instance(self):
        return Store.instance()

    def graceful_kill(self):
        # Do nothing
        pass


class EphemeralStoreQueued(StoreQueued):
    # Variable that holds the singleton instance
    my_instance = None

    def store_instance(self):
        return EphemeralStore.instance()
