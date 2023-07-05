# Copyright 2023 OpenC3, Inc.
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

from contextlib import contextmanager
from queue import SimpleQueue
from threading import Lock

class ConnectionPool:
    def __init__(self, ctor, pool_size):
        self.ctor = ctor
        self.count = 0
        self.pool_size = pool_size
        self.pool = SimpleQueue()
        self.lock = Lock()

    @contextmanager
    def get(self):
        item = None
        with self.lock:
            if not self.pool.empty():
                item = self.pool.get(False)
            elif self.count < self.pool_size:
                item = self.ctor()
                self.count += 1
            else:
                item = self.pool.get()
        yield item
        self.pool.put(item)
