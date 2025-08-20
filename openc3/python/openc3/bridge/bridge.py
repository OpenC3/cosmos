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

import atexit
import signal
import sys
import time
from openc3.bridge.bridge_config import BridgeConfig
from openc3.bridge.bridge_interface_thread import BridgeInterfaceThread
from openc3.bridge.bridge_router_thread import BridgeRouterThread
from openc3.utilities.logger import Logger


class Bridge:
    def __init__(self, filename, existing_variables=None):
        if existing_variables is None:
            existing_variables = {}
            
        self.config = BridgeConfig(filename, existing_variables)
        self.threads = []

        # Start Interface Threads
        for interface_name, interface in self.config.interfaces.items():
            thread = BridgeInterfaceThread(interface)
            self.threads.append(thread)
            thread.start()

        # Start Router Threads  
        for router_name, router in self.config.routers.items():
            thread = BridgeRouterThread(router)
            self.threads.append(thread)
            thread.start()

        # Register shutdown handlers
        atexit.register(self.shutdown)
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def shutdown(self):
        for thread in self.threads:
            try:
                thread.stop()
            except Exception as e:
                Logger.error(f"Error stopping thread: {e}")

    def _signal_handler(self, signum, frame):
        self.shutdown()
        sys.exit(0)

    def wait_forever(self):
        """Keep the main thread alive while daemon threads run"""
        try:
            while any(thread.alive for thread in self.threads):
                time.sleep(1)
        except KeyboardInterrupt:
            self.shutdown()