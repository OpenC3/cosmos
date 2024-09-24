# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# This file implements a class to handle command validation


# This class defines methods which are called when a command is sent.
# This class must be subclassed and the pre_check or
# post_check methods implemented. Do NOT use this class directly.
class CommandValidator:
    def __init__(self, command=None):
        self.command = command
        self.args = []

    def pre_check(self, command):
        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]

    def post_check(self, command):
        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]

    def args(self):
        return self.args
