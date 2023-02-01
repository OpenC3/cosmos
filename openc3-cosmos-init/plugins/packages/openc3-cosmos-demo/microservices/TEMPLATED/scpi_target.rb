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

require 'openc3'
require 'openc3/interfaces'
require 'openc3/microservices/microservice'
require 'openc3/tools/cmd_tlm_server/interface_thread'

module OpenC3
  class ScpiTarget < Microservice
    class ScpiServerInterface < TcpipServerInterface
      def initialize(port)
        super(port.to_i, port.to_i, 5.0, nil, 'TERMINATED', '0xA', '0xA')
      end
    end

    class ScpiInterfaceThread < InterfaceThread
      def initialize(interface)
        super(interface)
        @index = 0
      end

      protected
      def handle_packet(packet)
        Logger.info "Received command: #{packet.buffer}"
        if packet.buffer.include?('?')
          @interface.write_raw(@index.to_s + "\x0A")
        end
        @index += 1
      end
    end

    def initialize(name)
      super(name)
      @sleep_period = 1 # 1 second between runs
      # ports is an array of arrays consisting of the port number and protocol
      # e.g. [[1234, "UDP"], [5678, "TCP"]]
      port = @config["ports"][0][0] # Should only be 1
      # Create interface to receive commands and send telemetry
      @target_interface = ScpiServerInterface.new(port)
      @interface_thread = nil
    end

    def start
      @interface_thread = ScpiInterfaceThread.new(@target_interface)
      @interface_thread.start
    end

    def stop
      @interface_thread.stop if @interface_thread
    end

    def run
      Logger.level = Logger::INFO
      Thread.abort_on_exception = true

      @state = 'STARTING'
      start()
      @state = 'RUNNING'
      while true
        break if @cancel_thread
        sleep @sleep_period
      end
      @state = 'STOPPING'
      stop()
      @state = 'STOPPED'
    end
  end
end

OpenC3::ScpiTarget.run if __FILE__ == $0
