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
        # Clear any existing ThreadManager instance from previous tests
        ThreadManager.instance_obj = None

    def tearDown(self):
        ThreadManager.MONITOR_SLEEP_SECONDS = 0.25
        # Critical to set this to None to clean up the singleton instance
        ThreadManager.instance_obj = None

    def test_monitors_threads(self):
        self.continue2 = True
        self.continue3 = True
        stop_object = Mock()
        stop_object.stop = Mock(side_effect=lambda: setattr(self, "continue2", False))
        shutdown_object = Mock()
        shutdown_object.shutdown = Mock(side_effect=lambda: setattr(self, "continue3", False))

        def thread1_body():
            time.sleep(0.1)

        thread1 = threading.Thread(target=thread1_body)
        thread1.start()

        def thread2_body():
            while self.continue2:
                time.sleep(0.01)

        thread2 = threading.Thread(target=thread2_body)
        thread2.start()

        def thread3_body():
            while self.continue3:
                time.sleep(0.01)

        thread3 = threading.Thread(target=thread3_body)
        thread3.start()
        # Register all the threads with the ThreadManager
        # We add stop_object and shutdown_object to the second and third threads
        # so they can be stopped when the ThreadManager monitor detects the first thread has stopped
        ThreadManager.instance().register(thread1)
        ThreadManager.instance().register(thread2, stop_object=stop_object)
        ThreadManager.instance().register(thread3, shutdown_object=shutdown_object)

        # Create a new thread to monitor and shutdown the threads
        def monitor_and_shutdown():
            ThreadManager.instance().monitor()
            ThreadManager.instance().shutdown()

        manager_thread = threading.Thread(target=monitor_and_shutdown)
        manager_thread.start()
        # Wait for the first thread to finish as the second and third spin
        thread1.join()
        # The monitor should detect the first thread has finished
        # shutdown will stop the second and third threads
        manager_thread.join()
        # Allow time for the threads to sleep and stop
        time.sleep(0.02)
        self.assertFalse(thread1.is_alive())
        self.assertFalse(thread2.is_alive())
        self.assertFalse(thread3.is_alive())

    def test_joins_threads(self):
        def task(duration):
            time.sleep(duration)

        thread1 = threading.Thread(target=task, args=[0.02])
        thread2 = threading.Thread(target=task, args=[0.15])
        thread3 = threading.Thread(target=task, args=[0.08])
        ThreadManager.instance().register(thread1)
        ThreadManager.instance().register(thread2)
        ThreadManager.instance().register(thread3)
        thread1.start()
        thread2.start()
        thread3.start()
        # Note: thread1 might finish quickly, so only check threads 2 and 3
        self.assertTrue(thread2.is_alive())
        self.assertTrue(thread3.is_alive())
        start_time = perf_counter()
        ThreadManager.instance().join()
        stop_time = perf_counter()
        # The join should wait for the longest running thread (0.15 seconds)
        # Use delta=0.1 to allow for timing variations in test environments
        self.assertAlmostEqual(stop_time - start_time, 0.15, delta=0.1)
        # All threads should be stopped
        self.assertFalse(thread1.is_alive())
        self.assertFalse(thread2.is_alive())
        self.assertFalse(thread3.is_alive())
