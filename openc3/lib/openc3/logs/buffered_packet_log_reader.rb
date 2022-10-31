# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'openc3/logs/packet_log_reader'
require 'openc3/logs/packet_log_writer'

module OpenC3
  # Buffers files so small time differences can be read in time order
  class BufferedPacketLogReader < PacketLogReader

    attr_reader :bucket_file

    def initialize(bucket_file = nil)
      super()
      @bucket_file = bucket_file
    end

    def next_packet_time
      fill_buffer()
      packet = @buffer[0]
      return packet.packet_time if packet
      return nil
    end

    def buffered_read(identify_and_define = true)
      fill_buffer(identify_and_define)
      return @buffer.shift
    end

    protected

    def fill_buffer(identify_and_define = true)
      while true
        pkt1 = @buffer[0]
        pkt2 = @buffer[-1]
        return if pkt1 and pkt2 and ((pkt1.packet_time - pkt2.packet_time) >= LogWriter::TIME_TOLERANCE_SECS)
        packet = read(identify_and_define)
        return unless packet
        @buffer << packet if packet
        @buffer.sort! {|pkt1, pkt2| pkt1.packet_time <=> pkt2.packet_time }
      end
    end

    def reset
      super()
      @buffer = []
    end

  end
end
