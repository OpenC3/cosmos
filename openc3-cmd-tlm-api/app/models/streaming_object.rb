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

  attr_reader :key
  attr_reader :stream_mode
  attr_reader :cmd_or_tlm
  attr_reader :target_name
  attr_reader :packet_name
  attr_reader :item_name
  attr_reader :value_type
  attr_reader :reduced_type
  attr_accessor :start_time
  attr_accessor :end_time
  attr_accessor :offset
  attr_reader :topic
  attr_reader :id
  attr_reader :item_key

  def initialize(key, start_time, end_time, item_key: nil, scope:, token: nil)
    key = key.upcase
    @key = key
    @item_key = item_key
    key_split = key.split('__')
    @stream_mode = key_split[0].to_s.intern
    @cmd_or_tlm = key_split[1].to_s.intern
    @scope = scope
    @target_name = key_split[2].to_s
    @packet_name = key_split[3].to_s
    type = nil
    if stream_mode == :RAW
      # value_type is implied to be :RAW and this must be a whole packet
      @value_type = :RAW
      type = (@cmd_or_tlm == :CMD) ? 'COMMAND' : 'TELEMETRY'
    else
      if stream_mode == :DECOM
        type = (@cmd_or_tlm == :CMD) ? 'DECOMCMD' : 'DECOM'
      else
        type = stream_mode # REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
      end

      if @item_key
        @item_name = key_split[4].to_s
        @value_type = key_split[5].to_s.intern
        @reduced_type = key_split[6].to_s.intern if key_split.length >= 7
      else
        # Full Packet
        @value_type = key_split[4].to_s.intern
        @reduced_type = key_split[5].to_s.intern if key_split.length >= 6
      end
    end
    @start_time = start_time
    @end_time = end_time
    authorize(permission: @cmd_or_tlm.to_s.downcase, target_name: @target_name, packet_name: @packet_name, scope: scope, token: token)
    @topic = "#{@scope}__#{type}__{#{@target_name}}__#{@packet_name}"
    @offset = nil
    @offset = OpenC3::Topic.get_last_offset(@topic) unless @start_time
    if @item_key
      @id = 'ITEM__' + key
    else
      @id = 'PACKET__' + key
    end
    OpenC3::Logger.info("Streaming from #{@topic} start:#{@start_time} end:#{@end_time} offset:#{@offset}")
  end
end
