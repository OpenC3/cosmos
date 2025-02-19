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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
from threading import Lock

class ThreadManager:
    MONITOR_SLEEP_SECONDS = 0.25

    # Variable that holds the singleton instance
    instance_obj = None

    # Mutex used to ensure that only one instance is created
    instance_mutex = Lock()

    # Get the singleton instance of ThreadManager
    @classmethod
    def instance(cls):
        if ThreadManager.instance_obj is not None:
            return ThreadManager.instance_obj

        with ThreadManager.instance_mutex:
            ThreadManager.instance_obj = cls()
            return ThreadManager.instance_obj

    def __init__(self):
        self.threads = []
        self.shutdown_started = False

    def register(self, thread, stop_object=None, shutdown_object=None):
        self.threads.append([thread, stop_object, shutdown_object])

    def monitor(self):
        while True:
            for thread, _, _ in self.threads:
                if not thread.is_alive():
                    return
            time.sleep(self.MONITOR_SLEEP_SECONDS)

    def shutdown(self):
        with ThreadManager.instance_mutex:
            if self.shutdown_started:
                return
            self.shutdown_started = True
        for thread, stop_object, shutdown_object in self.threads:
            if thread.is_alive():
                if stop_object is not None:
                    stop_object.stop()
                if shutdown_object is not None:
                    shutdown_object.shutdown()

    def join(self):
        for thread, _, _ in self.threads:
            thread.join()
