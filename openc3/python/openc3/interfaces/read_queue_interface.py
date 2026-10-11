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
from datetime import datetime, timezone

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

# Marks a reader which had no read attribute of its own before it was redirected
_NO_READ_ATTRIBUTE = object()


# Interface base class which reads an underlying socket / stream (the reader) in
# a dedicated thread and buffers the results on a queue. This keeps the operating
# system receive buffers drained as fast as possible so data isn't dropped while
# the packet reading thread is busy processing protocols and writing to the database.
#
# Subclasses call start_read_queue_thread with the object they read from
# (anything with a read method) once it is connected and stop_read_queue_thread
# once it is disconnected. While the thread is running the reader's read method
# is redirected to the queue, so the subclass (and anything else such as derived
# classes or protocols) keeps calling reader.read() exactly as before and
# receives the data in the order it was read rather than competing with the read
# thread for it.
#
# Setting READ_QUEUE_MAX_SIZE to 0 disables the read thread so the reader is
# read inline, which is how interfaces read before the queue existed.
class ReadQueueInterface(Interface):
    def __init__(self):
        super().__init__()
        self.initialize_read_queue()

    # Initialize (or reset) the read queue attributes. Called by __init__.
    def initialize_read_queue(self, max_size=DEFAULT_READ_QUEUE_MAX_SIZE):
        self._read_queue = None
        self.read_queue_thread = None
        self._read_queue_reader = None
        self._read_queue_reader_read = _NO_READ_ATTRIBUTE
        # When the read thread read the data most recently returned by the
        # reader (None when the read queue is disabled)
        self.read_queue_data_time = None
        # Each read thread gets its own cancel event. A thread which is still
        # blocked in a read when it is replaced (Python can't kill it) keeps
        # seeing its own event set, so it can never touch the byte counters or
        # read again once it wakes up, even after a new thread has started.
        self._read_queue_cancel_event = None
        self._read_queue_bytes = 0
        self._read_queue_budget = 0
        self._read_queue_timeout_queued = False
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

    # @return [Boolean] Whether a read thread has been started (and not stopped)
    def read_queue_started(self):
        return self._read_queue is not None

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

    # Start the thread which continuously reads and queues data from the reader
    # and redirect the reader's read method to the queue. Does nothing beyond
    # stopping any existing thread if the read queue is disabled.
    #
    # @param reader Object to read from, e.g. a Stream or socket
    # @param read_args Arguments the read thread passes to reader.read.
    #   Arguments passed to the redirected read are ignored.
    def start_read_queue_thread(self, reader, *read_args):
        self.stop_read_queue_thread()
        if not self.read_queue_enabled():
            return
        read_queue = queue.Queue()
        cancel_event = threading.Event()
        with self._read_queue_condition:
            self._read_queue_bytes = 0
            self._read_queue_budget = 0
            self._read_queue_timeout_queued = False
            self._read_queue_cancel_event = cancel_event
            self._read_queue = read_queue
        try:
            raw_read = self._redirect_reader(reader)
        except (AttributeError, TypeError):  # e.g. __slots__ without __dict__
            Logger.warn(f"{self.name}: Can't redirect {reader.__class__.__name__}.read so disabling the read queue")
            with self._read_queue_condition:
                self._read_queue = None
                self._read_queue_cancel_event = None
            self.read_queue_max_size = 0
            return
        thread = threading.Thread(
            target=self._read_queue_thread_body, args=[read_queue, cancel_event, raw_read, read_args], daemon=True
        )
        self.read_queue_thread = thread
        thread.start()

    # Stop the read thread, restore the reader's read method and discard anything
    # left on the queue. The reader should be disconnected first so the thread
    # isn't blocked reading.
    def stop_read_queue_thread(self):
        # Allow subclasses to set their reader before initialize_read_queue
        if getattr(self, "_read_queue_condition", None) is None:
            return
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
            self._read_queue_timeout_queued = False
            self.read_queue_data_time = None
            # Unblock the read thread if it is waiting for room on the queue
            self._read_queue_condition.notify_all()
        self._restore_reader()
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
    # This is what the reader's read method returns while it is redirected.
    #
    # @return [bytes, None] Data read or None if the read source is done
    def read_queue_pop(self):
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
            if isinstance(data, tuple):
                data, data_time = data
                with self._read_queue_condition:
                    # Counters were reset if the queue was stopped / replaced
                    if read_queue is self._read_queue:
                        self._read_queue_bytes -= len(data)
                        self._read_queue_budget -= len(data) + READ_QUEUE_ENTRY_OVERHEAD
                        self.read_queue_data_time = data_time
                        # Tell the read thread there is room for more data
                        self._read_queue_condition.notify_all()
                return data
            if isinstance(data, TimeoutError):
                with self._read_queue_condition:
                    if read_queue is self._read_queue:
                        self._read_queue_timeout_queued = False
                # Data queued behind the timeout arrived while nobody was waiting
                # on it, so an inline read would have returned it rather than
                # timing out
                if not read_queue.empty():
                    continue
            # Exceptions raised by the read thread are re-raised here so they are
            # handled exactly as they were when the read happened inline
            if isinstance(data, Exception):
                raise data
            return data

    # @param data [bytes, None] Data returned by reader.read
    # @return [bool] Whether the data indicates the reader is done (closed) so
    #   the read thread should stop. Subclasses can override this.
    def read_queue_done(self, data):
        return data is None or len(data) <= 0

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

    # @return [bool] Whether a timeout should be queued. Only one is queued at a
    #   time so a reader which times out quickly can't fill the queue with them.
    def _reserve_read_queue_timeout(self, cancel_event):
        with self._read_queue_condition:
            if cancel_event.is_set() or self._read_queue_timeout_queued:
                return False
            self._read_queue_timeout_queued = True
            return True

    def _read_queue_thread_body(self, read_queue, cancel_event, raw_read, read_args):
        try:
            while not cancel_event.is_set():
                try:
                    data = raw_read(*read_args)
                    data_time = datetime.now(timezone.utc)
                except TimeoutError as error:
                    # A read timeout doesn't end the reader so pass it along and keep reading
                    if self._reserve_read_queue_timeout(cancel_event):
                        read_queue.put(error)
                    continue
                except Exception as error:
                    if not cancel_event.is_set():
                        read_queue.put(error)
                    break
                # Tell whoever reads next that the reader is done and stop reading
                if self.read_queue_done(data):
                    if not cancel_event.is_set():
                        read_queue.put(data)
                    break
                # Charge the bytes against the budget before the push so
                # read_queue_bytes never goes negative if the data is dequeued
                # before we get back here
                if not self._reserve_read_queue_bytes(len(data), cancel_event):
                    break
                # Queue the time of the read so packets are timestamped when the
                # data arrived rather than when it was processed
                read_queue.put((data, data_time))
        except Exception:
            Logger.error(f"{self.name}: Read queue thread unexpectedly died: {traceback.format_exc()}")

    # Redirect reader.read to the read queue so everything which reads the
    # reader directly gets the queued data in order.
    #
    # @return The original read method for the read thread to call
    def _redirect_reader(self, reader):
        raw_read = reader.read
        # Remember a read already set on the reader itself (e.g. a test stub) so
        # it can be put back rather than removed
        reader_read = vars(reader).get("read", _NO_READ_ATTRIBUTE)
        reader.read = lambda *_args, **_kwargs: self.read_queue_pop()
        self._read_queue_reader = reader
        self._read_queue_reader_read = reader_read
        return raw_read

    # Undo _redirect_reader so the reader reads inline again
    def _restore_reader(self):
        reader = self._read_queue_reader
        if reader is None:
            return
        if self._read_queue_reader_read is _NO_READ_ATTRIBUTE:
            vars(reader).pop("read", None)
        else:
            reader.read = self._read_queue_reader_read
        self._read_queue_reader = None
        self._read_queue_reader_read = _NO_READ_ATTRIBUTE
