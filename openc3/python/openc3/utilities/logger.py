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
from datetime import datetime, timezone
from threading import Lock
from openc3.environment import *
from openc3.utilities.store_queued import EphemeralStoreQueued

# Logger class, class attribute list
CLASS_ATTRS = [
    "instance",
    "instance_mutex",
    "my_instance",
    "scope",
    "__dict__",
    "DEBUG",
    "INFO",
    "WARN",
    "ERROR",
    "FATAL",
    "DEBUG_LEVEL",
    "INFO_LEVEL",
    "WARN_LEVEL",
    "ERROR_LEVEL",
    "FATAL_LEVEL",
    "LOG",
    "NOTIFICATION",
    "ALERT",
]


# Logger class, instance attribute list
INSTANCE_ATTRS = [
    "stdout",
    "level",
    "detail_string",
    "container_name",
    "microservice_name",
    "no_store",
]


class LoggerMeta(type):
    def __getattribute__(cls, func):
        if func in CLASS_ATTRS:
            return super().__getattribute__(func)

        if func in INSTANCE_ATTRS:
            return getattr(cls.instance(), func)

        def method(*args, **kw_args):
            return getattr(cls.instance(), func)(*args, **kw_args)

        return method

    def __setattr__(cls, func, value):
        if func in INSTANCE_ATTRS:
            return setattr(cls.instance(), func, value)

        if func in CLASS_ATTRS:
            return super().__setattr__(func, value)

        raise AttributeError(f"Unknown attribute {func}")


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

    DEBUG_LEVEL = "DEBUG"
    INFO_LEVEL = "INFO"
    WARN_LEVEL = "WARN"
    ERROR_LEVEL = "ERROR"
    FATAL_LEVEL = "FATAL"

    LOG = "log"
    NOTIFICATION = "notification"
    ALERT = "alert"
    EPHEMERAL = "ephemeral"

    # @param level [Integer] The initial logging level
    def __init__(self, level=INFO):
        self.stdout = True
        self.level = level
        self.detail_string = None
        self.container_name = socket.gethostname()
        self.microservice_name = None
        if OPENC3_NO_STORE:
            self.no_store = True
        else:
            self.no_store = False

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
    def debug(self, message=None, scope=None, user=None, type=LOG, url=None, other=None):
        scope = scope or self.scope
        if self.level <= self.DEBUG:
            self.log_message(
                self.DEBUG_LEVEL,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
                other=other,
            )

    # (see #debug)
    def info(self, message=None, scope=None, user=None, type=LOG, url=None, other=None):
        scope = scope or self.scope
        if self.level <= self.INFO:
            self.log_message(
                self.INFO_LEVEL,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
                other=other,
            )

    # (see #debug)
    def warn(self, message=None, scope=None, user=None, type=LOG, url=None, other=None):
        scope = scope or self.scope
        if self.level <= self.WARN:
            self.log_message(
                self.WARN_LEVEL,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
                other=other,
            )

    # (see #debug)
    def error(self, message=None, scope=None, user=None, type=LOG, url=None, other=None):
        scope = scope or self.scope
        if self.level <= self.ERROR:
            self.log_message(
                self.ERROR_LEVEL,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
                other=other,
            )

    # (see #debug)
    def fatal(self, message=None, scope=None, user=None, type=LOG, url=None, other=None):
        scope = scope or self.scope
        if self.level <= self.FATAL:
            self.log_message(
                self.FATAL_LEVEL,
                message,
                scope=scope,
                user=user,
                type=type,
                url=url,
                other=other,
            )

    def build_log_data(self, log_level, message, user=None, type=None, url=None, other=None):
        now_time = datetime.now(timezone.utc)
        data = {
            "time": int(now_time.timestamp() * 1000000000),
            # Can't use isoformat because it appends "+00:00" instead of "Z"
            "@timestamp": now_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "level": log_level,
        }
        if self.microservice_name is not None:
            data["microservice_name"] = self.microservice_name
        if self.detail_string is not None:
            data["detail"] = self.detail_string
        # EE: If a user is passed, put its name. Don't include user data if no user was passed.
        if user is not None:
            data["user"] = user
        data["container_name"] = self.container_name
        if message is not None:
            data["message"] = message
        if type is not None:
            data["type"] = type
        if url is not None:
            data["url"] = url
        if other is not None:
            data = data | other
        return data

    def log_message(self, log_level, message, scope, user, type, url, other=None):
        with self.instance_mutex:
            data = self.build_log_data(log_level, message, user, type, url, other)
            if self.stdout:
                match log_level:
                    case "WARN" | "ERROR" | "FATAL":
                        if OPENC3_LOG_STDERR:
                            print(json.dumps(data), file=sys.stderr)
                            sys.stderr.flush()
                        else:
                            print(json.dumps(data), file=sys.stdout)
                            sys.stdout.flush()
                    case _:
                        print(json.dumps(data), file=sys.stdout)
                        sys.stdout.flush()
            if self.no_store is False:
                if scope is not None:
                    EphemeralStoreQueued.write_topic(f"{scope}__openc3_log_messages", data)
                else:
                    # The base openc3_log_messages doesn't have an associated logger
                    # so it must be limited to prevent unbounded stream growth
                    EphemeralStoreQueued.write_topic("NOSCOPE__openc3_log_messages", data)
