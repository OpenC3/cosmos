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
import sys
import threading
import importlib
import time
import socket
import traceback
from openc3.utilities.logger import Logger

openc3_chdir_mutex = threading.RLock()


class HazardousError(Exception):
    def __init__(self):
        self.target_name = ""
        self.cmd_name = ""
        self.cmd_params = ""
        self.hazardous_description = ""
        self.formatted = ""
        super().__init__()

    def __str__(self):
        string = (
            f"{self.target_name} {self.cmd_name} with {self.cmd_params} is Hazardous"
        )
        if self.hazardous_description:
            string += f"due to '{self.hazardous_description}'"
        # Pass along the original formatted command so it can be resent
        string += f".\n{self.formatted}"
        return string


# Adds a path to the global Ruby search path
#
# @param path [String] Directory path
def add_to_search_path(path, front=True):
    path = os.path.abspath(path)
    if path not in sys.path:
        if front:
            sys.path.insert(0, path)
        else:  # Back
            sys.path.append(path)


# Temporarily set the working directory during a block
# Working directory is global, so this can make other threads wait
# Ruby Dir.chdir with block always throws an error if multiple threads
# call Dir.chdir
def set_working_dir(working_dir):
    openc3_chdir_mutex.acquire()
    try:
        current_dir = os.getcwd()
        os.chdir(working_dir)
        yield
    finally:
        openc3_chdir_mutex.release()
        os.chdir(current_dir)


# Attempt to gracefully kill a thread
# @param owner Object that owns the thread and may have a graceful_kill method
# @param thread The thread to gracefully kill
# @param graceful_timeout Timeout in seconds to wait for it to die gracefully
# @param timeout_interval How often to poll for aliveness
# @param hard_timeout Timeout in seconds to wait for it to die ungracefully
def kill_thread(
    owner, thread, graceful_timeout=1, timeout_interval=0.01, hard_timeout=1
):
    if thread:
        if owner and hasattr(owner, "graceful_kill"):
            if threading.current_thread() != thread:
                owner.graceful_kill()
                end_time = time.time() + graceful_timeout
                while thread.is_alive() and ((end_time - time.time()) > 0):
                    time.sleep(timeout_interval)
            else:
                Logger.warn("Threads cannot graceful_kill themselves")
        elif owner:
            Logger.info(
                f"Thread owner {owner.__class__.__name__} does not support graceful_kill"
            )
        if thread.is_alive():
            # If the thread dies after alive? but before backtrace, bt will be nil.
            trace = []
            for filename, lineno, name, line in traceback.extract_stack(
                sys._current_frames()[thread.ident]
            ):
                trace.append(f"{filename}:{lineno}:{name}:{line}")
            caller_trace = []
            for filename, lineno, name, line in traceback.extract_stack(
                sys._current_frames()[threading.current_thread().ident]
            ):
                caller_trace.append(f"{filename}:{lineno}:{name}:{line}")

            # Graceful failed
            caller_trace_string = "\n  ".join(caller_trace)
            trace_string = "\n  ".join(trace)
            msg = "Failed to gracefully kill thread:\n"
            msg = msg + f"  Caller Backtrace:\n  {caller_trace_string}\n"
            msg = msg + f"  \n  Thread Backtrace:\n  {trace_string}\n\n"
            Logger.warn(msg)


# Close a socket in a manner that ensures that any reads blocked in select
# will unblock across platforms
# @param socket The socket to close
def close_socket(socket_to_close):
    if socket_to_close:
        # Calling shutdown and then sleep seems to be required
        # to get select to reliably unblock on linux
        try:
            socket_to_close.shutdown(socket.SHUT_RDWR)
            time.sleep(0)
        except OSError:
            # Oh well we tried
            pass
        try:
            socket_to_close.close()
        # Capture the Socket is not connected error
        except OSError:
            pass


def get_class_from_module(module, class_name):
    """Returns the class from the given module, importing it if necessary"""
    if not sys.modules.get(module):
        parts = module.split(".")
        importlib.import_module(f".{parts[-1]}", ".".join(parts[0:-1]))
    return getattr(sys.modules[module], class_name)


# # Import the class represented by the filename. This uses the standard Python
# # convention of having a single class per file where the class name is camel
# # cased and filename is lowercase with underscores.
# #
# # @param class_name_or_class_filename [String] The name of the class or the file which contains the
# #   Python class to import
# # @param log_error [Boolean] Whether to log an error if we can't import the class
# def import_class(class_name_or_class_filename, log_error=True):
#     if class_name_or_class_filename.lower()[-3:] == ".py" or (
#         class_name_or_class_filename[0] == class_name_or_class_filename[0].lower()
#     ):
#         class_filename = class_name_or_class_filename
#         class_name = filename_to_class_name(class_filename)
#     else:
#         class_name = class_name_or_class_filename
#         class_filename = class_name_to_filename(class_name)
#     if to_class(class_name) and sys.modules[class_name]:
#         return to_class(class_name)

#     importlib.import_module(class_filename)
#     klass = to_class(class_name)
#     if klass is None:
#         raise RuntimeError(f"Python class #{class_name} not found")

#     return klass
