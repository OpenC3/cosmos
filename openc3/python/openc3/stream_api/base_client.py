#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
base_client.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime
from threading import Event
import time


class BaseClient:
    """
    The BaseClient is designed to be a parent class for websocket
    implementations to expand upon.
    """

    def __init__(self, timeout: int = 30) -> None:
        self._event = Event()
        self._data = []
        self._last_msg = datetime.now().timestamp()
        self._timeout = timeout

    def wait(self):
        """
        Wait for the internal event method to or to timeout. This
        should swallow signals from ctrl+C and return to allow the
        rest of the program to finish.
        """
        try:
            while not self._event.is_set():
                time.sleep(1)
                current_time = datetime.now().timestamp()
                if (current_time - self._last_msg) > self._timeout:
                    self._event.set()
        except KeyboardInterrupt:
            pass
