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

require 'openc3'
require_relative 'streaming_key'
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
  attr_reader :db_shard
  attr_reader :scope
  attr_reader :id
  attr_reader :realtime
  attr_reader :item_key

  def initialize(key, start_time_nsec, end_time_nsec, item_key: nil, scope:, token: nil)
    key = key.upcase
    @key = key
    @item_key = item_key
    parsed = StreamingKey.parse(key, item_key: !!item_key)
    @stream_mode = parsed.stream_mode
    @cmd_or_tlm = parsed.cmd_or_tlm
    @scope = scope
    @target_name = parsed.target_name
    @packet_name = parsed.packet_name
    @item_name = parsed.item_name
    @value_type = parsed.value_type
    @reduced_type = parsed.reduced_type
    if @stream_mode == :RAW
      type = (@cmd_or_tlm == :CMD) ? 'COMMAND' : 'TELEMETRY'
    elsif @stream_mode == :DECOM
      type = (@cmd_or_tlm == :CMD) ? 'DECOMCMD' : 'DECOM'
    else
      type = @stream_mode # REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    end
    @start_time = start_time_nsec
    @end_time = end_time_nsec
    if not @end_time or @end_time > Time.now.to_nsec_from_epoch
      @realtime = true
    else
      @realtime = false
    end
    # Streaming is read-only, so use cmd_info for commands instead of cmd
    permission = @cmd_or_tlm == :CMD ? 'cmd_info' : 'tlm'
    authorize(permission: permission, target_name: @target_name, packet_name: @packet_name, manual: false, scope: scope, token: token)
    @topic = "#{@scope}__#{type}__{#{@target_name}}__#{@packet_name}"
    @db_shard = OpenC3::Store.db_shard_for_target(@target_name, scope: @scope)
    @offset = "0-0"
    @offset = OpenC3::Topic.get_last_offset(@topic, db_shard: @db_shard) unless @start_time
    if @item_key
      @id = 'ITEM__' + key
    else
      @id = 'PACKET__' + key
    end
    OpenC3::Logger.info("Creating object #{@id} start:#{@start_time} end:#{@end_time} offset:#{@offset}")
  end
end
