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

import queue
import threading
import traceback

from openc3.interfaces.interface import Interface
from openc3.utilities.logger import Logger


# Maximum number of bytes buffered on the queue before the read thread blocks
# and lets the operating system do the buffering instead
DEFAULT_READ_QUEUE_MAX_SIZE = 20 * 1024 * 1024  # 20MB

# Approximate memory each queued read costs on top of the data itself (the bytes
# object plus the queue entry). Small reads are dominated by this so it is
# charged against the budget, otherwise a stream delivering a few bytes at a
# time would hold many times the budget in actual memory.
READ_QUEUE_ENTRY_OVERHEAD = 64

# How long to wait on a blocked queue operation before re-checking whether the
# interface has been disconnected
QUEUE_POLL_TIMEOUT = 0.1

# How long to wait for the read thread to exit when disconnecting
THREAD_JOIN_TIMEOUT = 2.0


# Interface base class which reads an underlying socket / stream in a dedicated
# thread and buffers the results on a queue. This keeps the operating system receive
# buffers drained as fast as possible so data isn't dropped while the packet
# reading thread is busy processing protocols and writing to the database.
#
# Subclasses must implement read_queue_data which performs
# a single blocking read and returns the data read or None to indicate the read
# source is done (which disconnects the interface).
#
# Setting READ_QUEUE_MAX_SIZE to 0 disables the read thread and reads inline
# from read_queue_pop, which is how interfaces read before the queue existed.
class ReadQueue(Interface):
    # Initialize the read queue attributes. Must be called from the subclass
    # __init__ method.
    def initialize_read_queue(self, max_size=DEFAULT_READ_QUEUE_MAX_SIZE):
        self._read_queue = None
        self.read_queue_thread = None
        # Each read thread gets its own cancel event. A thread which is still
        # blocked in a read when it is replaced (Python can't kill it) keeps
        # seeing its own event set, so it can never touch the byte counters or
        # read again once it wakes up, even after a new thread has started.
        self._read_queue_cancel_event = None
        self._read_queue_bytes = 0
        self._read_queue_budget = 0
        # Guards _read_queue_bytes / _read_queue_budget and wakes the read thread
        # when the bytes it queued are consumed and there is room to queue more
        self._read_queue_condition = threading.Condition()
        self.read_queue_max_size = max_size

    # Supported Options
    # READ_QUEUE_MAX_SIZE - Maximum number of bytes buffered on the read queue
    #   or 0 to disable the read thread and read inline (see Interface.set_option)
    def set_option(self, option_name, option_values):
        super().set_option(option_name, option_values)
        if option_name.upper() == "READ_QUEUE_MAX_SIZE":
            max_size = int(option_values[0])
            if max_size < 0:
                raise RuntimeError(f"READ_QUEUE_MAX_SIZE must be 0 (disabled) or a positive integer but was {max_size}")
            self.read_queue_max_size = max_size

    # @return [Boolean] Whether reads are buffered by a read thread (False when
    #   READ_QUEUE_MAX_SIZE is 0 and reads happen inline)
    def read_queue_enabled(self):
        return self.read_queue_max_size > 0

    # @return [Integer] The number of reads waiting on the read queue
    def read_queue_size(self):
        read_queue = self._read_queue
        if read_queue is None:
            return 0
        return read_queue.qsize()

    # @return [Integer] The number of bytes waiting on the read queue
    def read_queue_bytes(self):
        if self._read_queue is None:
            return 0
        with self._read_queue_condition:
            return self._read_queue_bytes

    # Perform a single blocking read. Must be implemented by the subclass.
    #
    # @return [bytes, None] Data read or None if the read source is done
    def read_queue_data(self):
        raise RuntimeError(f"read_queue_data not defined by {self.__class__.__name__}")

    # Start the thread which continuously reads and queues data. Does nothing
    # beyond stopping any existing thread if the read queue is disabled.
    def start_read_queue_thread(self):
        self.stop_read_queue_thread()
        if not self.read_queue_enabled():
            return
        read_queue = queue.Queue()
        cancel_event = threading.Event()
        with self._read_queue_condition:
            self._read_queue_bytes = 0
            self._read_queue_budget = 0
            self._read_queue_cancel_event = cancel_event
            self._read_queue = read_queue
        thread = threading.Thread(target=self._read_queue_thread_body, args=[read_queue, cancel_event], daemon=True)
        self.read_queue_thread = thread
        thread.start()

    # Stop the read thread and discard anything left on the queue. The read
    # source should be disconnected first so the thread isn't blocked reading.
    def stop_read_queue_thread(self):
        with self._read_queue_condition:
            read_queue = self._read_queue
            self._read_queue = None
            cancel_event = self._read_queue_cancel_event
            self._read_queue_cancel_event = None
            # Setting the event under the lock guarantees the thread either
            # already charged its bytes (and they're reset below) or never will
            if cancel_event is not None:
                cancel_event.set()
            self._read_queue_bytes = 0
            self._read_queue_budget = 0
            # Unblock the read thread if it is waiting for room on the queue
            self._read_queue_condition.notify_all()
        if read_queue is not None:
            # Discard anything left on the queue
            while True:
                try:
                    read_queue.get_nowait()
                except queue.Empty:
                    break
        thread = self.read_queue_thread
        self.read_queue_thread = None
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=THREAD_JOIN_TIMEOUT)
            if thread.is_alive():
                # The thread is stuck in a read which the disconnect didn't
                # unblock. Its cancel event is set so it exits as soon as the
                # read returns without queueing or reading anything else.
                Logger.warn(f"{self.name}: Read queue thread did not stop")

    # Retrieve the next data off the read queue, blocking until it is available.
    #
    # @return [bytes, None] Data read or None if the read source is done
    def read_queue_pop(self):
        # Disabled so read inline exactly as interfaces did before the queue
        if not self.read_queue_enabled():
            return self.read_queue_data()

        read_queue = self._read_queue
        if read_queue is None:
            # The read thread is normally started by connect but interfaces can
            # also be handed an already connected stream so start it on demand
            if self.connected():
                self.start_read_queue_thread()
            read_queue = self._read_queue
            if read_queue is None:
                return None
        thread = self.read_queue_thread
        while True:
            try:
                data = read_queue.get(timeout=QUEUE_POLL_TIMEOUT)
            except queue.Empty:
                # Nothing will ever be queued again once the read thread is done
                # or replaced so return rather than blocking forever
                if read_queue is not self._read_queue or thread is None or not thread.is_alive():
                    return None
                continue
            if isinstance(data, (bytes, bytearray)):
                with self._read_queue_condition:
                    # Counters were reset if the queue was stopped / replaced
                    if read_queue is self._read_queue:
                        self._read_queue_bytes -= len(data)
                        self._read_queue_budget -= len(data) + READ_QUEUE_ENTRY_OVERHEAD
                        # Tell the read thread there is room for more data
                        self._read_queue_condition.notify_all()
            # Exceptions raised by the read thread are re-raised here so they are
            # handled exactly as they were when the read happened inline
            if isinstance(data, Exception):
                raise data
            return data

    # Wait until the data fits in the byte budget and charge it against the
    # budget. A read larger than the entire budget is queued on its own rather
    # than never fitting, so the budget can be exceeded by at most one read.
    #
    # @return [bool] Whether the bytes were reserved (False if cancelled)
    def _reserve_read_queue_bytes(self, length, cancel_event):
        cost = length + READ_QUEUE_ENTRY_OVERHEAD
        with self._read_queue_condition:
            while self._read_queue_budget > 0 and (self._read_queue_budget + cost) > self.read_queue_max_size:
                if cancel_event.is_set():
                    return False
                self._read_queue_condition.wait(QUEUE_POLL_TIMEOUT)
            if cancel_event.is_set():
                return False
            self._read_queue_bytes += length
            self._read_queue_budget += cost
            return True

    def _read_queue_thread_body(self, read_queue, cancel_event):
        try:
            while not cancel_event.is_set():
                try:
                    data = self.read_queue_data()
                except Exception as error:
                    if not cancel_event.is_set():
                        read_queue.put(error)
                    break
                # None means the read source is done so tell read_queue_pop to disconnect
                if data is None:
                    if not cancel_event.is_set():
                        read_queue.put(None)
                    break
                # Charge the bytes against the budget before the push so
                # read_queue_bytes never goes negative if the data is dequeued
                # before we get back here
                if not self._reserve_read_queue_bytes(len(data), cancel_event):
                    break
                read_queue.put(data)
        except Exception:
            Logger.error(f"{self.name}: Read queue thread unexpectedly died: {traceback.format_exc()}")
