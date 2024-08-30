# encoding: ascii-8bit

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

require 'openc3/api/api'

module OpenC3
  # This class defines methods which are called when a command is sent.
  # This class must be subclassed and the pre_check or
  # post_check methods implemented. Do NOT use this class directly.
  class CommandValidator
    include Api

    def initialize(command = nil)
      @command = command
    end

    def pre_check(command)
      return [true, nil]
    end

    def post_check(command)
      return [true, nil]
    end
  end
end
