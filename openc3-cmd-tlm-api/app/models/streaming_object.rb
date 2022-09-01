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

require 'openc3'
OpenC3.require_file 'openc3/utilities/authorization'

# Helper class to store information about the streaming item
class StreamingObject
  include OpenC3::Authorization

  attr_accessor :key
  attr_accessor :cmd_or_tlm
  attr_accessor :target_name
  attr_accessor :packet_name
  attr_accessor :item_name
  attr_accessor :value_type
  attr_accessor :start_time
  attr_accessor :end_time
  attr_accessor :offset
  attr_accessor :topic
  attr_accessor :thread_id

  def initialize(key, start_time, end_time, thread_id = nil, stream_mode:, scope:, token: nil)
    @key = key
    key_split = key.split('__')
    @cmd_or_tlm = key_split[0].to_s.intern
    @scope = scope
    @target_name = key_split[1]
    @packet_name = key_split[2]
    type = nil
    if stream_mode == :RAW
      # value_type is implied to be :RAW and this must be a whole packet
      @value_type = :RAW
      type = (@cmd_or_tlm == :CMD) ? 'COMMAND' : 'TELEMETRY'
    elsif stream_mode == :DECOM
      type = (@cmd_or_tlm == :CMD) ? 'DECOMCMD' : 'DECOM'
      # If our value type is the 4th param we're streaming a packet, otherwise item
      if OpenC3::Packet::VALUE_TYPES.include?(key_split[3].intern)
        @value_type = key_split[3].intern
      else
        @item_name = key_split[3]
        @value_type = key_split[4].intern
      end
    else # Reduced
      type = stream_mode
      # Reduced items are passed as TGT__PKT__ITEM_REDUCETYPE__VALUETYPE
      # e.g. INST__HEALTH_STATUS__TEMP1_AVG__CONVERTED
      # Note there is NOT a double underscore between item name and reduce type
      @item_name = key_split[3]
      @value_type = key_split[4].intern
    end
    @start_time = start_time
    @end_time = end_time
    authorize(permission: @cmd_or_tlm.to_s.downcase, target_name: @target_name, packet_name: @packet_name, scope: scope, token: token)
    @topic = "#{@scope}__#{type}__{#{@target_name}}__#{@packet_name}"
    @offset = nil
    @offset = OpenC3::Topic.get_last_offset(@topic) unless @start_time
    OpenC3::Logger.info("Streaming from #{@topic} start:#{@start_time} end:#{@end_time} offset:#{@offset}")
    @thread_id = thread_id
  end
end
