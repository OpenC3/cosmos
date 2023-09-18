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

import os
import selectors


# Allows for a breakable sleep implementation using the self-pipe trick
# See http://www.sitepoint.com/the-self-pipe-trick-explained/
class Sleeper:
    def __init__(self):
        self.pipe_reader, self.pipe_writer = os.pipe()
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.pipe_reader, selectors.EVENT_READ)
        self.canceled = False

    # Breakable version of sleep
    # @param seconds Number of seconds to sleep
    # @return true if the sleep was broken by someone calling cancel
    #   otherwise returns false
    def sleep(self, seconds):
        list = self.selector.select(timeout=seconds)
        if list and list[0]:
            try:
                os.close(self.pipe_reader)
            except Exception:
                pass
            return True
        else:
            return False

    # Break sleeping - Once canceled a sleeper cannot be used again
    def cancel(self):
        if not self.canceled:
            self.canceled = True
            os.write(self.pipe_writer, bytes(".", encoding="ascii"))
            os.close(self.pipe_writer)
