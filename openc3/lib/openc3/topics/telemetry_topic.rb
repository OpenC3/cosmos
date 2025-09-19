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

require 'openc3/topics/topic'
require 'openc3/utilities/store_queued'

module OpenC3
  class TelemetryTopic < Topic
    def self.write_packet(packet, queued: false, scope:)
      msg_hash = {
        :time => packet.packet_time.to_nsec_from_epoch,
        :received_time => packet.received_time.to_nsec_from_epoch,
        :stored => packet.stored.to_s,
        :target_name => packet.target_name,
        :packet_name => packet.packet_name,
        :received_count => packet.received_count,
        :buffer => packet.buffer(false)
      }
      msg_hash[:extra] = JSON.generate(packet.extra.as_json, allow_nan: true, allow_nan: true) if packet.extra
      if queued
        EphemeralStoreQueued.write_topic("#{scope}__TELEMETRY__{#{packet.target_name}}__#{packet.packet_name}", msg_hash)
      else
        Topic.write_topic("#{scope}__TELEMETRY__{#{packet.target_name}}__#{packet.packet_name}", msg_hash)
      end
    end
  end
end
