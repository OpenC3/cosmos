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

from time import perf_counter
import time
import threading
import unittest
from unittest.mock import Mock
from openc3.utilities.thread_manager import ThreadManager

class TestThreadManager(unittest.TestCase):
    def setUp(self):
        ThreadManager.MONITOR_SLEEP_SECONDS = 0.01

    def test_monitors_threads(self):
        self.continue2 = True
        self.continue3 = True
        stop_object = Mock()
        stop_object.stop = Mock(side_effect=lambda: setattr(self, "continue2", False))
        shutdown_object = Mock()
        shutdown_object.shutdown = Mock(side_effect=lambda: setattr(self, "continue3", False))

        def thread1_body(name, duration):
            time.sleep(duration)
        thread1 = threading.Thread(target=thread1_body, args=('thread 1', 0.05))
        thread1.start()
        def thread2_body(name, duration):
            while self.continue2:
                time.sleep(duration)
        thread2 = threading.Thread(target=thread2_body, args=('thread 1', 0.01))
        thread2.start()
        def thread3_body(name, duration):
            while self.continue3:
                time.sleep(duration)
        thread3 = threading.Thread(target=thread3_body, args=('thread 1', 0.01))
        thread3.start()
        ThreadManager.instance().register(thread1)
        ThreadManager.instance().register(thread2, stop_object=stop_object)
        ThreadManager.instance().register(thread3, shutdown_object=shutdown_object)
        def monitor_and_shutdown():
            ThreadManager.instance().monitor()
            ThreadManager.instance().shutdown()
        manager_thread = threading.Thread(target=monitor_and_shutdown)
        manager_thread.start()
        time.sleep(0.001)
        thread1.join()
        time.sleep(0.001)
        manager_thread.join()
        time.sleep(0.1)
        self.assertFalse(thread1.is_alive())
        self.assertFalse(thread2.is_alive())
        self.assertFalse(thread3.is_alive())

    def test_joins_threads(self):
        def task(name, duration):
            time.sleep(duration)
        thread1 = threading.Thread(target=task, args=('thread 1', 0.01))
        thread2 = threading.Thread(target=task, args=('thread 2', 0.1))
        thread3 = threading.Thread(target=task, args=('thread 3', 0.05))
        ThreadManager.instance().register(thread1)
        ThreadManager.instance().register(thread2)
        ThreadManager.instance().register(thread3)
        thread1.start()
        thread2.start()
        thread3.start()
        self.assertTrue(thread1.is_alive())
        self.assertTrue(thread2.is_alive())
        self.assertTrue(thread3.is_alive())
        start_time = perf_counter()
        ThreadManager.instance().join()
        stop_time = perf_counter()
        self.assertAlmostEqual(stop_time - start_time, 0.1, delta=0.01)
        self.assertFalse(thread1.is_alive())
        self.assertFalse(thread2.is_alive())
        self.assertFalse(thread3.is_alive())
