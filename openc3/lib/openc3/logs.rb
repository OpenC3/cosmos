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

module OpenC3
  autoload(:BufferedPacketLogReader, 'openc3/logs/buffered_packet_log_reader.rb')
  autoload(:BufferedPacketLogWriter, 'openc3/logs/buffered_packet_log_writer.rb')
  autoload(:LogWriter, 'openc3/logs/log_writer.rb')
  autoload(:PacketLogConstants, 'openc3/logs/packet_log_constants.rb')
  autoload(:PacketLogReader, 'openc3/logs/packet_log_reader.rb')
  autoload(:PacketLogWriter, 'openc3/logs/packet_log_writer.rb')
  autoload(:TextLogWriter, 'openc3/logs/text_log_writer.rb')
end
