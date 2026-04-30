# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import contextlib
import selectors
import socket


# Allows for a breakable sleep implementation using the self-pipe trick
# See http://www.sitepoint.com/the-self-pipe-trick-explained/
# socket.socketpair (rather than os.pipe) so the readable end can be
# registered with selectors on Windows, where the default selector is
# backed by select.select which only accepts sockets.
class Sleeper:
    def __init__(self):
        self.pipe_reader, self.pipe_writer = socket.socketpair()
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
            with contextlib.suppress(Exception):
                self.pipe_reader.close()
            return True
        else:
            return False

    # Break sleeping - Once canceled a sleeper cannot be used again
    def cancel(self):
        if not self.canceled:
            self.canceled = True
            with contextlib.suppress(OSError):
                self.pipe_writer.send(b".")
            self.pipe_writer.close()
