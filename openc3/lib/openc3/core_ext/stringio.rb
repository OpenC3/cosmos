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

require 'stringio'
require 'openc3/core_ext/openc3_io'

# OpenC3 specific additions to the Ruby IO class
class StringIO
  include OpenC3IO

  if !(StringIO.method_defined?(:path))
    # @return [nil]
    def path
      nil
    end
  end
end
