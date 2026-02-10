# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/io/io_multiplexer'

module OpenC3
  # Adds STDERR to the multiplexed streams
  class Stderr < IoMultiplexer
    @@instance = nil

    def initialize
      super()
      @streams << STDERR
      @@instance = self
    end

    # @return [Stderr] Returns a single instance of Stderr
    def self.instance
      self.new unless @@instance
      @@instance
    end

    def tty?
      false
    end
  end
end
