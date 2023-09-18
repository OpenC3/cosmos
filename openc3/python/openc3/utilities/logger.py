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

import socket
import sys
import json
from datetime import datetime
from threading import Lock
from openc3.environment import *
from openc3.topics.topic import Topic


class LoggerMeta(type):
    def __getattribute__(cls, func):
        if func == "instance" or func == "instance_mutex" or func == "my_instance":
            return super().__getattribute__(func)

        def method(*args, **kw_args):
            return getattr(cls.instance(), func)(*args, **kw_args)

        return method


# Supports different levels of logging and only writes if the level
# is exceeded.
class Logger(metaclass=LoggerMeta):
    instance_mutex = Lock()
    my_instance = None
    scope = OPENC3_SCOPE

    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3
    FATAL = 4

    DEBUG_SEVERITY_STRING = "DEBUG"
    INFO_SEVERITY_STRING = "INFO"
    WARN_SEVERITY_STRING = "WARN"
    ERROR_SEVERITY_STRING = "ERROR"
    FATAL_SEVERITY_STRING = "FATAL"

    LOG = "log"
    NOTIFICATION = "notification"
    ALERT = "alert"

    # @param level [Integer] The initial logging level
    def __init__(self, level=INFO):
        self.stdout = True
        self.level = level
        self.detail_string = None
        self.container_name = socket.gethostname()
        self.microservice_name = None
        self.no_store = OPENC3_NO_STORE

    # Get the singleton instance
    @classmethod
    def instance(cls, level=INFO):
        if cls.my_instance:
            return cls.my_instance

        with cls.instance_mutex:
            cls.my_instance = cls(level)
            return cls.my_instance

    # @param message [String] The message to print if the log level is at or
    #   below the method name log level.
    # @param block [Proc] Block to call which should return a string to append
    #   to the log message
    def debug(self, message=None, scope=None, user=None, type=LOG, url=None):
        scope = scope or self.scope
        if self.level <= self.DEBUG:
            self.log_message(
                self.DEBUG_SEVERITY_STRING,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
            )

    # (see #debug)
    def info(self, message=None, scope=None, user=None, type=LOG, url=None):
        scope = scope or self.scope
        if self.level <= self.INFO:
            self.log_message(
                self.INFO_SEVERITY_STRING,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
            )

    # (see #debug)
    def warn(self, message=None, scope=None, user=None, type=LOG, url=None):
        scope = scope or self.scope
        if self.level <= self.WARN:
            self.log_message(
                self.WARN_SEVERITY_STRING,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
            )

    # (see #debug)
    def error(self, message=None, scope=None, user=None, type=LOG, url=None):
        scope = scope or self.scope
        if self.level <= self.ERROR:
            self.log_message(
                self.ERROR_SEVERITY_STRING,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
            )

    # (see #debug)
    def fatal(self, message=None, scope=None, user=None, type=LOG, url=None):
        scope = scope or self.scope
        if self.level <= self.FATAL:
            self.log_message(
                self.FATAL_SEVERITY_STRING,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
            )

    def log_message(self, severity_string, message, scope, user, type, url):
        with self.instance_mutex:
            now_time = datetime.now()
            data = {
                "time": now_time.timestamp() * 1000000000,
                "@timestamp": now_time.isoformat(),
                "severity": severity_string,
            }
            if self.microservice_name:
                data["microservice_name"] = self.microservice_name
            if self.detail_string:
                data["detail"] = self.detail_string
            # EE: If a user is passed, put its name ('Unknown' if it doesn't have a name). Don't include user data if no user was passed
            if user:
                if "username" in user:
                    data["user"] = user["username"]
                else:
                    data["user"] = "Unknown"
            data["container_name"] = self.container_name
            data["log"] = message
            data["type"] = type
            if url:
                data["url"] = url
            if self.stdout:
                match severity_string:
                    case ("WARN" | "ERROR" | "FATAL"):
                        if OPENC3_LOG_STDERR:
                            print(json.dumps(data), file=sys.stderr)
                            sys.stderr.flush
                        else:
                            print(json.dumps(data), file=sys.stdout)
                            sys.stdout.flush
                    case _:
                        print(json.dumps(data), file=sys.stdout)
                        sys.stdout.flush
            if not self.no_store:
                if scope:
                    Topic.write_topic(f"{scope}__openc3_log_messages", data)
                else:
                    # The base openc3_log_messages doesn't have an associated logger
                    # so it must be limited to prevent unbounded stream growth
                    Topic.write_topic("NOSCOPE__openc3_log_messages", data)
