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
  class ExampleTarget < Microservice
    class ExampleServerInterface < TcpipServerInterface
      def initialize(port)
        super(port.to_i, port.to_i, 5.0, nil, 'LENGTH', 0, 32, 4, 1, 'BIG_ENDIAN', 4, nil, nil, true)
      end
    end

    class ExampleInterfaceThread < InterfaceThread
      attr_accessor :target_name

      protected
      def handle_packet(packet)
        identified_packet = System.commands.identify(packet.buffer, [@target_name])
        if identified_packet
          Logger.info "Received command: #{identified_packet.target_name} #{identified_packet.packet_name}"
        else
          Logger.info "Received UNKNOWN command"
        end
      end
    end

    class ExampleTelemetryThread
      attr_reader :thread

      def initialize(interface, target_name)
        @interface = interface
        @target_name = target_name
        @sleeper = Sleeper.new
      end

      def start
        packet = System.telemetry.packet(@target_name, 'STATUS')
        @thread = Thread.new do
          @stop_thread = false
          @sleeper.sleep(5)
          begin
            loop do
              packet.write('PACKET_ID', 1)
              packet.write('STRING', "The time is now: #{Time.now.sys.formatted}")
              @interface.write(packet)
              break if @sleeper.sleep(1)
            end
          rescue Exception => err
            Logger.error "ExampleTelemetryThread unexpectedly died\n#{err.formatted}"
            raise err
          end
        end
      end

      def stop
        OpenC3.kill_thread(self, @thread)
      end

      def graceful_kill
        @sleeper.cancel
      end
    end

    def initialize(name)
      super(name)
      @sleep_period = 1 # 1 second between runs
      # @target_names is an array of all the names mapped to this microservice
      @target_name = @target_names[0] # Should only be 1
      # ports is an array of arrays consisting of the port number and protocol
      # e.g. [[1234, "UDP"], [5678, "TCP"]]
      port = @config["ports"][0][0] # Should only be 1
      # Create interface to receive commands and send telemetry
      @interface = ExampleServerInterface.new(port)
      @interface_thread = nil
      @telemetry_thread = nil
    end

    def start
      @interface_thread = ExampleInterfaceThread.new(@interface)
      @interface_thread.target_name = @target_name
      @interface_thread.start
      @telemetry_thread = ExampleTelemetryThread.new(@interface, @target_name)
      @telemetry_thread.start
    end

    def stop
      @telemetry_thread.stop if @telemetry_thread
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

OpenC3::ExampleTarget.run if __FILE__ == $0
