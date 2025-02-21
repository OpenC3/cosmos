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

import os
import tempfile
import threading
from datetime import datetime, timezone, timedelta
from openc3.config.config_parser import ConfigParser
from openc3.top_level import kill_thread
from openc3.topics.topic import Topic
from openc3.utilities.bucket_utilities import BucketUtilities
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.string import build_timestamped_filename
from openc3.utilities.time import from_nsec_from_epoch, to_timestamp


# Creates a log. Can automatically cycle the log based on an elapsed
# time period or when the log file reaches a predefined size.
class LogWriter:
    # The cycle time interval. Cycle times are only checked at this level of
    # granularity.
    CYCLE_TIME_INTERVAL = 10
    # Delay in seconds before trimming Redis streams
    CLEANUP_DELAY = 60

    # Mutex protecting class variables
    mutex = threading.Lock()

    # Array of instances used to keep track of cycling logs
    instances = []

    # Thread used to cycle logs across all log writers
    cycle_thread = None

    # Sleeper used to delay cycle thread
    cycle_sleeper = None

    # self.param remote_log_directory [String] The path to store the log files
    # self.param logging_enabled [Boolean] Whether to start with logging enabled
    # self.param cycle_time [Integer] The amount of time in seconds before creating
    #   a new log file. This can be combined with cycle_size.
    # self.param cycle_size [Integer] The size in bytes before creating a new log
    #   file. This can be combined with cycle_time.
    # self.param cycle_hour [Integer] The time at which to cycle the log. Combined with
    #   cycle_minute to cycle the log daily at the specified time. If None, the log
    #   will be cycled hourly at the specified cycle_minute.
    # self.param cycle_minute [Integer] The time at which to cycle the log. See cycle_hour
    #   for more information.
    def __init__(
        self,
        remote_log_directory,
        logging_enabled=True,
        cycle_time=None,
        cycle_size=1_000_000_000,
        cycle_hour=None,
        cycle_minute=None,
        enforce_time_order=True,
    ):
        self.remote_log_directory = remote_log_directory
        self.logging_enabled = ConfigParser.handle_true_false(logging_enabled)
        self.cycle_time = ConfigParser.handle_none(cycle_time)
        if self.cycle_time:
            self.cycle_time = int(self.cycle_time)
            if self.cycle_time < LogWriter.CYCLE_TIME_INTERVAL:
                raise RuntimeError(f"cycle_time must be >= {LogWriter.CYCLE_TIME_INTERVAL}")
        self.cycle_size = ConfigParser.handle_none(cycle_size)
        if self.cycle_size:
            self.cycle_size = int(self.cycle_size)
        self.cycle_hour = ConfigParser.handle_none(cycle_hour)
        if self.cycle_hour:
            self.cycle_hour = int(self.cycle_hour)
        self.cycle_minute = ConfigParser.handle_none(cycle_minute)
        if self.cycle_minute:
            self.cycle_minute = int(self.cycle_minute)
        self.enforce_time_order = ConfigParser.handle_true_false(enforce_time_order)
        self.out_of_order = False
        self.mutex = threading.Lock()
        self.file = None
        self.label = None
        self.file_size = 0
        self.filename = None
        self.start_time = datetime.now(timezone.utc)
        self.first_time = None
        self.last_time = None
        self.cancel_threads = False
        self.last_offsets = {}
        self.cleanup_offsets = []
        self.cleanup_times = []
        self.previous_time_nsec_since_epoch = None
        self.tmp_dir = tempfile.TemporaryDirectory()

        # This is an optimization to avoid creating a new entry object
        # each time we create an entry which we do a LOT!
        self.entry = ""

        # Always make sure there is a cycle thread - (because it does trimming)
        with LogWriter.mutex:
            LogWriter.instances.append(self)

            if not LogWriter.cycle_thread:
                LogWriter.cycle_thread = threading.Thread(target=self.cycle_thread_body, daemon=True)
                LogWriter.cycle_thread.start()

    # Starts a new log file by closing the existing log file. New log files are
    # not created until packets are written by {#write} so this does not
    # immediately create a log file on the filesystem.
    def start(self):
        with self.mutex:
            self.close_file(False)
            self.logging_enabled = True

    # Stops all logging and closes the current log file.
    def stop(self):
        threads = None
        with self.mutex:
            threads = self.close_file(False)
            self.logging_enabled = False
        return threads

    # Stop all logging, close the current log file, and kill the logging threads.
    def shutdown(self):
        threads = self.stop()
        with LogWriter.mutex:
            LogWriter.instances.remove(self)
            if len(LogWriter.instances) <= 0:
                if LogWriter.cycle_sleeper:
                    LogWriter.cycle_sleeper.cancel()
                if LogWriter.cycle_thread:
                    kill_thread(self, LogWriter.cycle_thread)
                LogWriter.cycle_thread = None
        # Wait for BucketUtilities to finish move_log_file_to_bucket_thread
        for thread in threads:
            thread.join()
        self.tmp_dir.cleanup()

    def graceful_kill(self):
        self.cancel_threads = True

    # implementation details

    def create_unique_filename(self, ext=".log"):
        # Create a filename that doesn't exist
        attempt = None
        while True:
            filename_parts = [attempt]
            if self.label:
                filename_parts.insert(self.label, 0)
            filename = os.path.join(
                self.tmp_dir.name,
                build_timestamped_filename([self.label, attempt], ext),
            )
            if os.path.exists(filename):
                if attempt is None:
                    attempt = 0
                attempt += 1
                Logger.warn(f"Unexpected file name conflict {filename}")
            else:
                return filename

    def cycle_thread_body(self):
        LogWriter.cycle_sleeper = Sleeper()
        while True:
            start_time = datetime.now(timezone.utc)
            with LogWriter.mutex:
                for instance in LogWriter.instances:
                    # The check against start_time needs to be mutex protected to prevent a packet coming in between the check
                    # and closing the file
                    with instance.mutex:
                        utc_now = datetime.now(timezone.utc)
                        if instance.logging_enabled and instance.filename:  # Logging and file opened
                            # Cycle based on total time logging
                            if (
                                instance.cycle_time
                                and (utc_now - instance.start_time).total_seconds() > instance.cycle_time
                            ):
                                Logger.debug("Log writer start new file due to cycle time")
                                instance.close_file(False)
                            # Cycle daily at a specific time
                            elif (
                                instance.cycle_hour
                                and instance.cycle_minute
                                and utc_now.hour == instance.cycle_hour
                                and utc_now.min == instance.cycle_minute
                                and instance.start_time.day != utc_now.day
                            ):
                                Logger.debug("Log writer start new file daily")
                                instance.close_file(False)
                            # Cycle hourly at a specific time
                            elif (
                                instance.cycle_minute
                                and not instance.cycle_hour
                                and utc_now.min == instance.cycle_minute
                                and instance.start_time.hour != utc_now.hour
                            ):
                                Logger.debug("Log writer start new file hourly")
                                instance.close_file(False)

                        # Check for cleanup time
                        indexes_to_clear = []
                        for index, cleanup_time in enumerate(instance.cleanup_times):
                            if cleanup_time <= utc_now:
                                # Now that the file is in S3, trim the Redis stream up until the previous file.
                                # This keeps one minute of data in Redis
                                for (
                                    redis_topic,
                                    cleanup_offset,
                                ) in instance.cleanup_offsets[index]:
                                    Topic.trim_topic(redis_topic, cleanup_offset)
                                indexes_to_clear.append(index)
                        if len(indexes_to_clear) > 0:
                            for index in indexes_to_clear:
                                instance.cleanup_offsets[index] = None
                                instance.cleanup_times[index] = None
                            instance.cleanup_offsets = [x for x in instance.cleanup_offsets if x is not None]
                            instance.cleanup_times = [x for x in instance.cleanup_times if x is not None]

            # Only check whether to cycle at a set interval
            run_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            sleep_time = LogWriter.CYCLE_TIME_INTERVAL - run_time
            if sleep_time < 0:
                sleep_time = 0
            if self.cancel_threads or LogWriter.cycle_sleeper.sleep(sleep_time):
                break

    # Starting a new log file is a critical operation so the entire method is
    # wrapped with a except: and handled with handle_critical_exception
    # Assumes mutex has already been taken
    def start_new_file(self):
        try:
            if self.file:
                self.close_file(False)

            # Start log file
            self.filename = self.create_unique_filename()
            self.file = open(self.filename, "bx")
            self.file_size = 0

            self.start_time = datetime.now(timezone.utc)
            self.out_of_order = False
            self.first_time = None
            self.last_time = None
            self.previous_time_nsec_since_epoch = None
            Logger.debug(f"Log File Opened : {self.filename}")
        except IOError as error:
            Logger.error(f"Error starting new log file {repr(error)}")
            self.logging_enabled = False
            # TODO: handle_critical_exception(err)

    def prepare_write(
        self,
        time_nsec_since_epoch,
        data_length,
        redis_topic=None,
        redis_offset=None,
        allow_new_file=True,
    ):
        # This check includes logging_enabled again because it might have changed since we acquired the mutex
        # Ensures new files based on size, and ensures always increasing time order in files
        if self.logging_enabled:
            if not self.file:
                Logger.debug("Log writer start new file because no file opened")
                if allow_new_file:
                    self.start_new_file()
            elif self.cycle_size and ((self.file_size + data_length) > self.cycle_size):
                Logger.debug(f"Log writer start new file due to cycle size {self.cycle_size}")
                if allow_new_file:
                    self.start_new_file()
            elif (
                self.enforce_time_order
                and self.previous_time_nsec_since_epoch
                and (self.previous_time_nsec_since_epoch > time_nsec_since_epoch)
            ):
                # Warning= Creating new files here can cause lots of files to be created if packets make it through out of order:
                # Changed to just a error to prevent file thrashing
                if not self.out_of_order:
                    Logger.error(
                        f"Log writer out of order time detected (increase buffer depth?): {from_nsec_from_epoch(self.previous_time_nsec_since_epoch)} {from_nsec_from_epoch(time_nsec_since_epoch)}"
                    )
                    self.out_of_order = True
        # This is needed for the redis offset marker entry at the end of the log file
        if redis_topic and redis_offset:
            self.last_offsets[redis_topic] = redis_offset
        self.previous_time_nsec_since_epoch = time_nsec_since_epoch

    # Closing a log file isn't critical so we just log an error. NOTE: This also trims the Redis stream
    # to keep a full file's worth of data in the stream. This is what prevents continuous stream growth.
    # Returns thread that moves log to bucket
    def close_file(self, take_mutex=True):
        threads = []
        if take_mutex:
            self.mutex.acquire()
        try:
            if self.file:
                self.file.close()
                Logger.debug(f"Log File Closed : {self.filename}")
                date = self.first_timestamp()[0:8]  # YYYYMMDD
                bucket_key = os.path.join(self.remote_log_directory, date, self.bucket_filename())
                # Cleanup timestamps here so they are unset for the next file
                self.first_time = None
                self.last_time = None
                threads.append(BucketUtilities.move_log_file_to_bucket(self.filename, bucket_key))
                # Now that the file is in storage, trim the Redis stream after a delay
                self.cleanup_offsets.append({})
                for redis_topic, last_offset in self.last_offsets:
                    self.cleanup_offsets[-1][redis_topic] = last_offset
                self.cleanup_times.append(datetime.now(timezone.utc) + timedelta(seconds=LogWriter.CLEANUP_DELAY))
                self.last_offsets.clear
                self.file = None
                self.file_size = 0
                self.filename = None
        except RuntimeError as error:
            Logger.error(f"Error closing {self.filename} : {repr(error)}")
        finally:
            if take_mutex:
                self.mutex.release()
        return threads

    def bucket_filename(self):
        return f"{self.first_timestamp()}__{self.last_timestamp()}" + self.extension()

    def extension(self):
        return ".log"

    def first_timestamp(self):
        return to_timestamp(from_nsec_from_epoch(self.first_time))  # "YYYYMMDDHHmmSSNNNNNNNNN"

    def last_timestamp(self):
        return to_timestamp(from_nsec_from_epoch(self.last_time))  # "YYYYMMDDHHmmSSNNNNNNNNN"
