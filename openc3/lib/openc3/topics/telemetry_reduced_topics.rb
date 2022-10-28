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

require 'openc3/topics/topic'
require 'openc3/utilities/open_telemetry'

module OpenC3
  class TelemetryReducedMinuteTopic < Topic
    def self.topics(scope:)
      super(scope, 'REDUCED_MINUTE')
    end

    def write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, id: nil, scope:)
      OpenC3.in_span("write") do
        # Write to stream
        msg_hash = {
          :time => time,
          :stored => stored.to_s,
          :target_name => target_name,
          :packet_name => packet_name,
          :json_data => data,
        }
        topic = "#{scope}__REDUCED_MINUTE__{#{target_name}}__#{packet_name}"
        offset = Topic.write_topic(topic, msg_hash, id)
        return topic, offset
      end
    end
  end

  class TelemetryReducedHourTopic < Topic
    def self.topics(scope:)
      super(scope, 'REDUCED_HOUR')
    end

    def write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, id: nil, scope:)
      OpenC3.in_span("write") do
        # Write to stream
        msg_hash = {
          :time => time,
          :stored => stored.to_s,
          :target_name => target_name,
          :packet_name => packet_name,
          :json_data => data,
        }
        topic = "#{scope}__REDUCED_HOUR__{#{target_name}}__#{packet_name}"
        offset = Topic.write_topic(topic, msg_hash, id)
        return topic, offset
      end
    end
  end

  class TelemetryReducedDayTopic < Topic
    def self.topics(scope:)
      super(scope, 'REDUCED_DAY')
    end

    def write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, id: nil, scope:)
      OpenC3.in_span("write") do
        # Write to stream
        msg_hash = {
          :time => time,
          :stored => stored.to_s,
          :target_name => target_name,
          :packet_name => packet_name,
          :json_data => data,
        }
        topic = "#{scope}__REDUCED_DAY__{#{target_name}}__#{packet_name}"
        offset = Topic.write_topic(topic, msg_hash, id)
        return topic, offset
      end
    end
  end
end
