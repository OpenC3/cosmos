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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  autoload(:FileInterface, 'openc3/interfaces/file_interface.rb')
  autoload(:HttpClientInterface, 'openc3/interfaces/http_client_interface.rb')
  autoload(:HttpServerInterface, 'openc3/interfaces/http_server_interface.rb')
  autoload(:Interface, 'openc3/interfaces/interface.rb')
  autoload(:MqttInterface, 'openc3/interfaces/mqtt_interface.rb')
  autoload(:MqttStreamInterface, 'openc3/interfaces/mqtt_stream_interface.rb')
  autoload(:SerialInterface, 'openc3/interfaces/serial_interface.rb')
  autoload(:SimulatedTargetInterface, 'openc3/interfaces/simulated_target_interface.rb')
  autoload(:StreamInterface, 'openc3/interfaces/stream_interface.rb')
  autoload(:TcpipClientInterface, 'openc3/interfaces/tcpip_client_interface.rb')
  autoload(:TcpipServerInterface, 'openc3/interfaces/tcpip_server_interface.rb')
  autoload(:UdpInterface, 'openc3/interfaces/udp_interface.rb')

  autoload(:Protocol, 'openc3/interfaces/protocols/protocol.rb')
  autoload(:BurstProtocol, 'openc3/interfaces/protocols/burst_protocol.rb')
  autoload(:FixedProtocol, 'openc3/interfaces/protocols/fixed_protocol.rb')
  autoload(:LengthProtocol, 'openc3/interfaces/protocols/length_protocol.rb')
  autoload(:PreidentifiedProtocol, 'openc3/interfaces/protocols/preidentified_protocol.rb')
  autoload(:TemplateProtocol, 'openc3/interfaces/protocols/template_protocol.rb')
  autoload(:TerminatedProtocol, 'openc3/interfaces/protocols/terminated_protocol.rb')
  autoload(:CmdResponseProtocol, 'openc3/interfaces/protocols/cmd_response_protocol.rb')
  autoload(:CrcProtocol, 'openc3/interfaces/protocols/crc_protocol.rb')
  autoload(:IgnorePacketProtocol, 'openc3/interfaces/protocols/ignore_packet_protocol.rb')
end
