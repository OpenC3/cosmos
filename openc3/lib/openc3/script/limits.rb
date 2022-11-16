# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  module Script
    private

    # Define all the modification methods such that we can disconnect them
    %i(enable_limits disable_limits set_limits enable_limits_group disable_limits_group set_limits_set).each do |method_name|
      define_method(method_name) do |*args, **kw_args, &block|
        kw_args[:scope] = $openc3_scope unless kw_args[:scope]
        if $disconnect
          Logger.info "DISCONNECT: #{method_name}(#{args}) ignored"
        else
          $api_server.public_send(method_name, *args, **kw_args, &block)
        end
      end
    end
  end
end
