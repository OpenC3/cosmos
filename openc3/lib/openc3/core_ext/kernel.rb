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

# OpenC3 specific additions to the Ruby Kernel module
module Kernel
  # @return [Boolean] Whether the current platform is Windows
  def is_windows?
    Gem.win_platform?
  end

  # @return [Boolean] Whether the current platform is Mac
  def is_mac?
    _, platform, *_ = RUBY_PLATFORM.split("-")
    result = false
    if /darwin/.match?(platform)
      result = true
    end
    return result
  end

  # @param start [Integer] The number of stack entries to skip
  # @return [Symbol] The name of the calling method
  def calling_method(start = 1)
    caller[start][/[`']([^']*)'/, 1].intern
  end
end
