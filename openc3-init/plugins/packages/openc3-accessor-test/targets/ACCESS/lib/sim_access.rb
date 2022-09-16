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

# Provides a demonstration of accessors

require 'openc3'

module OpenC3
  class SimAccess < SimulatedTarget
    def set_rates
      set_rate('JSONTLM', 100)
      set_rate('CBORTLM', 100)
      set_rate('XMLTLM', 100)
      set_rate('HTMLTLM', 100)
    end

    def tick_period_seconds
      return 1 # Override this method to optimize
    end

    def tick_increment
      return 100 # Override this method to optimize
    end

    def write(packet)
      name = packet.packet_name.upcase

      json_packet = @tlm_packets['JSONTLM']
      cbor_packet = @tlm_packets['CBORTLM']
      xml_packet = @tlm_packets['XMLTLM']
      html_packet = @tlm_packets['HTMLTLM']

      case name
      when 'JSONCMD'
        json_packet.buffer = packet.buffer
      when 'CBORCMD'
        cbor_packet.buffer = packet.buffer
      when 'XMLCMD'
        xml_packet.buffer = packet.buffer
      when 'HTMLCMD'
        html_packet.buffer = packet.buffer
      end
    end
  end
end
