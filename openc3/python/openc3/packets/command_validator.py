# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# This file implements a class to handle command validation

from collections import namedtuple


# Returned by pre_check and post_check. result is True to indicate Success,
# False to indicate Failure, and None to indicate Unknown. message is optional.
# Returning a plain tuple or list (result, message) is still supported.
CommandValidatorResult = namedtuple("CommandValidatorResult", ["result", "message"])


# This class defines methods which are called when a command is sent.
# This class must be subclassed and the pre_check or
# post_check methods implemented. Do NOT use this class directly.
class CommandValidator:
    def __init__(self, command=None):
        self.command = command
        self.args = []

    def pre_check(self, command):
        # Return a CommandValidatorResult(result, message). result is True to indicate
        # Success, False to indicate Failure, and None to indicate Unknown.
        # message is optional.
        return CommandValidatorResult(True, None)

    def post_check(self, command):
        # Return a CommandValidatorResult(result, message). result is True to indicate
        # Success, False to indicate Failure, and None to indicate Unknown.
        # message is optional.
        return CommandValidatorResult(True, None)
