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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

require 'openc3/microservices/microservice'
require 'openc3/microservices/interface_decom_common'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/interface_status_model'
require 'openc3/models/router_status_model'
require 'openc3/models/scope_model'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'
require 'openc3/topics/interface_topic'
require 'openc3/topics/router_topic'
require 'openc3/interfaces/interface'

begin
  require 'openc3-enterprise/models/critical_cmd_model'
rescue LoadError
  # LoadError expected in COSMOS Core
end

module OpenC3
  class InterfaceCmdHandlerThread
    include InterfaceDecomCommon

    def initialize(interface, tlm, logger: nil, metric: nil, scope:)
      @interface = interface
      @tlm = tlm
      @scope = scope
      scope_model = ScopeModel.get_model(name: @scope)
      if scope_model
        @critical_commanding = scope_model.critical_commanding
      else
        @critical_commanding = 'OFF'
      end
      @logger = logger
      @logger = Logger unless @logger
      @metric = metric
      @count = 0
      @directive_count = 0
      @metric.set(name: 'interface_directive_total', value: @directive_count, type: 'counter') if @metric
      @metric.set(name: 'interface_cmd_total', value: @count, type: 'counter') if @metric
    end

    def start
      @thread = Thread.new do
        run()
      rescue Exception => e
        @logger.error "#{@interface.name}: Command handler thread died: #{e.formatted}"
        raise e
      end
      ThreadManager.instance.register(@thread, stop_object: self)
    end

    def stop()
      OpenC3.kill_thread(self, @thread)
    end

    def graceful_kill
      InterfaceTopic.shutdown(@interface, scope: @scope)
      sleep(0.001) # Allow other threads to run
    end

    def run
      InterfaceTopic.receive_commands(@interface, scope: @scope) do |topic, msg_id, msg_hash, _redis|
        OpenC3.with_context(msg_hash) do
          release_critical = false
          msgid_seconds_from_epoch = msg_id.split('-')[0].to_i / 1000.0
          delta = Time.now.to_f - msgid_seconds_from_epoch
          @metric.set(name: 'interface_topic_delta_seconds', value: delta, type: 'gauge', unit: 'seconds', help: 'Delta time between data written to stream and interface cmd start') if @metric

          if topic == "OPENC3__SYSTEM__EVENTS"
            msg = JSON.parse(msg_hash['event'])
            if msg['type'] == 'scope'
              if msg['name'] == @scope
                @critical_commanding = msg['critical_commanding']
              end
            end
            next 'SUCCESS'
          end

          # Check for a raw write to the interface
          if topic =~ /CMD}INTERFACE/
            @directive_count += 1
            @metric.set(name: 'interface_directive_total', value: @directive_count, type: 'counter') if @metric
            if msg_hash['shutdown']
              @logger.info "#{@interface.name}: Shutdown requested"
              InterfaceTopic.clear_topics(InterfaceTopic.topics(@interface, scope: @scope))
              return
            end
            if msg_hash['connect']
              @logger.info "#{@interface.name}: Connect requested"
              params = []
              if msg_hash['params']
                params = JSON.parse(msg_hash['params'], :allow_nan => true, :create_additions => true)
              end
              @interface = @tlm.attempting(*params)
              next 'SUCCESS'
            end
            if msg_hash['disconnect']
              @logger.info "#{@interface.name}: Disconnect requested"
              @tlm.disconnect(false)
              next 'SUCCESS'
            end
            if msg_hash['raw']
              if @interface.connected?
                begin
                  @logger.info "#{@interface.name}: Write raw"
                  # A raw interface write results in an UNKNOWN packet
                  command = System.commands.packet('UNKNOWN', 'UNKNOWN')
                  command.received_count = TargetModel.increment_command_count('UNKNOWN', 'UNKNOWN', 1, scope: @scope)
                  command = command.clone
                  command.buffer = msg_hash['raw']
                  command.received_time = Time.now
                  CommandTopic.write_packet(command, scope: @scope)
                  @logger.info("write_raw sent #{msg_hash['raw'].length} bytes to #{@interface.name}", scope: @scope)
                  @interface.write_raw(msg_hash['raw'])
                rescue => e
                  @logger.error "#{@interface.name}: write_raw: #{e.formatted}"
                  next e.message
                end
                next 'SUCCESS'
              else
                next "Interface not connected: #{@interface.name}"
              end
            end
            if msg_hash.key?('log_stream')
              if msg_hash['log_stream'] == 'true'
                @logger.info "#{@interface.name}: Enable stream logging"
                @interface.start_raw_logging
              else
                @logger.info "#{@interface.name}: Disable stream logging"
                @interface.stop_raw_logging
              end
              next 'SUCCESS'
            end
            if msg_hash.key?('interface_cmd')
              params = JSON.parse(msg_hash['interface_cmd'], allow_nan: true, create_additions: true)
              begin
                @logger.info "#{@interface.name}: interface_cmd: #{params['cmd_name']} #{params['cmd_params'].join(' ')}"
                @interface.interface_cmd(params['cmd_name'], *params['cmd_params'])
                InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
              rescue => e
                @logger.error "#{@interface.name}: interface_cmd: #{e.formatted}"
                next e.message
              end
              next 'SUCCESS'
            end
            if msg_hash.key?('protocol_cmd')
              params = JSON.parse(msg_hash['protocol_cmd'], allow_nan: true, create_additions: true)
              begin
                @logger.info "#{@interface.name}: protocol_cmd: #{params['cmd_name']} #{params['cmd_params'].join(' ')} read_write: #{params['read_write']} index: #{params['index']}"
                @interface.protocol_cmd(params['cmd_name'], *params['cmd_params'], read_write: params['read_write'], index: params['index'])
                InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
              rescue => e
                @logger.error "#{@interface.name}: protocol_cmd: #{e.formatted}"
                next e.message
              end
              next 'SUCCESS'
            end
            if msg_hash.key?('inject_tlm')
              handle_inject_tlm(msg_hash['inject_tlm'])
              next 'SUCCESS'
            end
            if msg_hash.key?('release_critical')
              # Note: intentional fall through below this point
              model = CriticalCmdModel.get_model(name: msg_hash['release_critical'], scope: @scope)
              if model
                msg_hash = model.cmd_hash
                release_critical = true
              else
                next "Critical command #{msg_hash['release_critical']} not found"
              end
            end
          end

          target_name = msg_hash['target_name']
          cmd_name = msg_hash['cmd_name']
          manual = ConfigParser.handle_true_false(msg_hash['manual'])
          cmd_params = nil
          cmd_buffer = nil
          hazardous_check = nil
          if msg_hash['cmd_params']
            cmd_params = JSON.parse(msg_hash['cmd_params'], :allow_nan => true, :create_additions => true)
            range_check = ConfigParser.handle_true_false(msg_hash['range_check'])
            raw = ConfigParser.handle_true_false(msg_hash['raw'])
            hazardous_check = ConfigParser.handle_true_false(msg_hash['hazardous_check'])
          elsif msg_hash['cmd_buffer']
            cmd_buffer = msg_hash['cmd_buffer']
          end

          begin
            begin
              if cmd_params
                command = System.commands.build_cmd(target_name, cmd_name, cmd_params, range_check, raw)
              elsif cmd_buffer
                if target_name
                  command = System.commands.identify(cmd_buffer, [target_name])
                else
                  command = System.commands.identify(cmd_buffer, @interface.cmd_target_names)
                end
                unless command
                  command = System.commands.packet('UNKNOWN', 'UNKNOWN').clone
                  command.buffer = cmd_buffer
                end
              else
                raise "Invalid command received:\n #{msg_hash}"
              end
              orig_command = System.commands.packet(command.target_name, command.packet_name)
              orig_command.received_count = TargetModel.increment_command_count(command.target_name, command.packet_name, 1, scope: @scope)
              command.received_count = orig_command.received_count
              command.received_time = Time.now
            rescue => e
              @logger.error "#{@interface.name}: #{msg_hash}"
              @logger.error "#{@interface.name}: #{e.formatted}"
              next e.message
            end

            command.extra ||= {}
            command.extra['cmd_string'] = msg_hash['cmd_string']
            command.extra['username'] = msg_hash['username']
            hazardous, hazardous_description = System.commands.cmd_pkt_hazardous?(command)

            # Initial Are you sure? Hazardous check
            # Return back the error, description, and the formatted command
            # This allows the error handler to simply re-send the command
            next "HazardousError\n#{hazardous_description}\n#{msg_hash['cmd_string']}" if hazardous_check and hazardous and not release_critical

            # Check for Critical Command
            if @critical_commanding and @critical_commanding != 'OFF' and not release_critical
              restricted = command.restricted
              if hazardous or restricted or (@critical_commanding == 'ALL' and manual)
                if hazardous
                  type = 'HAZARDOUS'
                elsif restricted
                  type = 'RESTRICTED'
                else
                  type = 'NORMAL'
                end
                model = CriticalCmdModel.new(name: SecureRandom.uuid, type: type, interface_name: @interface.name, username: msg_hash['username'], cmd_hash: msg_hash, scope: @scope)
                model.create
                @logger.info("Critical Cmd Pending: #{msg_hash['cmd_string']}", user: msg_hash['username'], scope: @scope)
                next "CriticalCmdError\n#{model.name}"
              end
            end

            validate = ConfigParser.handle_true_false(msg_hash['validate'])
            begin
              if @interface.connected?
                result = true
                reason = nil
                if command.validator and validate
                  begin
                    result, reason = command.validator.pre_check(command)
                  rescue => e
                    result = false
                    reason = e.message
                  end
                  # Explicitly check for false to allow nil to represent unknown
                  if result == false
                    message = "pre_check returned false for #{msg_hash['cmd_string']} due to #{reason}"
                    raise WriteRejectError.new(message)
                  end
                end

                @count += 1
                @metric.set(name: 'interface_cmd_total', value: @count, type: 'counter') if @metric

                log_message = ConfigParser.handle_true_false(msg_hash['log_message'])
                if log_message
                  @logger.info(msg_hash['cmd_string'], user: msg_hash['username'], scope: @scope)
                end

                @interface.write(command)

                # TODO: After the write, obfuscate params
                # command.obfuscate

                if command.validator and validate
                  begin
                    result, reason = command.validator.post_check(command)
                  rescue => e
                    result = false
                    reason = e.message
                  end
                  command.extra['cmd_success'] = result
                  command.extra['cmd_reason'] = reason if reason
                end

                CommandDecomTopic.write_packet(command, scope: @scope)
                CommandTopic.write_packet(command, scope: @scope)
                InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)

                # Explicitly check for false to allow nil to represent unknown
                if result == false
                  message = "post_check returned false for #{msg_hash['cmd_string']} due to #{reason}"
                  raise WriteRejectError.new(message)
                end
                next 'SUCCESS'
              else
                next "Interface not connected: #{@interface.name}"
              end
            rescue WriteRejectError => e
              next e.message
            rescue => e
              @logger.error "#{@interface.name}: #{e.formatted}"
              next e.message
            end
          rescue => e
            @logger.error "#{@interface.name}: #{e.formatted}"
            next e.message
          end
        end
      end
    end
  end

  class RouterTlmHandlerThread
    def initialize(router, tlm, logger: nil, metric: nil, scope:)
      @router = router
      @tlm = tlm
      @scope = scope
      @logger = logger
      @logger = Logger unless @logger
      @metric = metric
      @count = 0
      @directive_count = 0
      @metric.set(name: 'router_directive_total', value: @directive_count, type: 'counter') if @metric
      @metric.set(name: 'router_tlm_total', value: @count, type: 'counter') if @metric
    end

    def start
      @thread = Thread.new do
        run()
      rescue Exception => e
        @logger.error "#{@router.name}: Telemetry handler thread died: #{e.formatted}"
        raise e
      end
      ThreadManager.instance.register(@thread, stop_object: self)
    end

    def stop
      OpenC3.kill_thread(self, @thread)
    end

    def graceful_kill
      RouterTopic.shutdown(@router, scope: @scope)
      sleep(0.001) # Allow other threads to run
    end

    def run
      RouterTopic.receive_telemetry(@router, scope: @scope) do |topic, msg_id, msg_hash, _redis|
        msgid_seconds_from_epoch = msg_id.split('-')[0].to_i / 1000.0
        delta = Time.now.to_f - msgid_seconds_from_epoch
        @metric.set(name: 'router_topic_delta_seconds', value: delta, type: 'gauge', unit: 'seconds', help: 'Delta time between data written to stream and router tlm start') if @metric

        # Check for commands to the router itself
        if /CMD}ROUTER/.match?(topic)
          @directive_count += 1
          @metric.set(name: 'router_directive_total', value: @directive_count, type: 'counter') if @metric

          if msg_hash['shutdown']
            @logger.info "#{@router.name}: Shutdown requested"
            RouterTopic.clear_topics(RouterTopic.topics(@router, scope: @scope))
            return
          end
          if msg_hash['connect']
            @logger.info "#{@router.name}: Connect requested"
            params = []
            if msg_hash['params']
              params = JSON.parse(msg_hash['params'], :allow_nan => true, :create_additions => true)
            end
            @router = @tlm.attempting(*params)
          end
          if msg_hash['disconnect']
            @logger.info "#{@router.name}: Disconnect requested"
            @tlm.disconnect(false)
          end
          if msg_hash.key?('log_stream')
            if msg_hash['log_stream'] == 'true'
              @logger.info "#{@router.name}: Enable stream logging"
              @router.start_raw_logging
            else
              @logger.info "#{@router.name}: Disable stream logging"
              @router.stop_raw_logging
            end
          end
          if msg_hash.key?('router_cmd')
            params = JSON.parse(msg_hash['router_cmd'], allow_nan: true, create_additions: true)
            begin
              @logger.info "#{@router.name}: router_cmd: #{params['cmd_name']} #{params['cmd_params'].join(' ')}"
              @router.interface_cmd(params['cmd_name'], *params['cmd_params'])
              RouterStatusModel.set(@router.as_json(:allow_nan => true), queued: true, scope: @scope)
            rescue => e
              @logger.error "#{@router.name}: router_cmd: #{e.formatted}"
              next e.message
            end
            next 'SUCCESS'
          end
          if msg_hash.key?('protocol_cmd')
            params = JSON.parse(msg_hash['protocol_cmd'], allow_nan: true, create_additions: true)
            begin
              @logger.info "#{@router.name}: protocol_cmd: #{params['cmd_name']} #{params['cmd_params'].join(' ')} read_write: #{params['read_write']} index: #{params['index']}"
              @router.protocol_cmd(params['cmd_name'], *params['cmd_params'], read_write: params['read_write'], index: params['index'])
              RouterStatusModel.set(@router.as_json(:allow_nan => true), queued: true, scope: @scope)
            rescue => e
              @logger.error "#{@router.name}: protoco_cmd: #{e.formatted}"
              next e.message
            end
            next 'SUCCESS'
          end
          next 'SUCCESS'
        end

        if @router.connected?
          @count += 1
          @metric.set(name: 'router_tlm_total', value: @count, type: 'counter') if @metric

          target_name = msg_hash["target_name"]
          packet_name = msg_hash["packet_name"]

          packet = System.telemetry.packet(target_name, packet_name)
          packet.stored = ConfigParser.handle_true_false(msg_hash["stored"])
          packet.received_time = Time.from_nsec_from_epoch(msg_hash["time"].to_i)
          packet.received_count = msg_hash["received_count"].to_i
          packet.buffer = msg_hash["buffer"]

          begin
            @router.write(packet)
            RouterStatusModel.set(@router.as_json(:allow_nan => true), queued: true, scope: @scope)
            next 'SUCCESS'
          rescue => e
            @logger.error "#{@router.name}: #{e.formatted}"
            next e.message
          end
        end
      end
    end
  end

  class InterfaceMicroservice < Microservice
    UNKNOWN_BYTES_TO_PRINT = 16

    def initialize(name)
      @mutex = Mutex.new
      super(name)

      @interface_or_router = self.class.name.to_s.split("Microservice")[0].upcase.split("::")[-1]
      if @interface_or_router == 'INTERFACE'
        @metric.set(name: 'interface_tlm_total', value: @count, type: 'counter')
      else
        @metric.set(name: 'router_cmd_total', value: @count, type: 'counter')
      end

      interface_name = name.split("__")[2]
      if @interface_or_router == 'INTERFACE'
        @interface = InterfaceModel.get_model(name: interface_name, scope: @scope).build
      else
        @interface = RouterModel.get_model(name: interface_name, scope: @scope).build
      end
      @interface.name = interface_name
      # Map the interface to the interface's targets
      @interface.target_names.each do |target_name|
        target = System.targets[target_name]
        target.interface = @interface
      end
      @interface.tlm_target_names.each do |target_name|
        # Initialize the target's packet counters based on the Topic stream
        # Prevents packet count resetting to 0 when interface restarts
        begin
          System.telemetry.packets(target_name).each do |packet_name, packet|
            topic = "#{@scope}__TELEMETRY__{#{target_name}}__#{packet_name}"
            msg_id, msg_hash = Topic.get_newest_message(topic)
            if msg_id
              packet.received_count = msg_hash['received_count'].to_i
            else
              packet.received_count = 0
            end
          end
        rescue
          # Handle targets without telemetry
        end
      end
      if @interface.connect_on_startup
        @interface.state = 'ATTEMPTING'
      else
        @interface.state = 'DISCONNECTED'
      end
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      end

      @queued = false
      @sync_packet_count_data = {}
      @sync_packet_count_time = nil
      @sync_packet_count_delay_seconds = 1.0 # Sync packet counts every second
      @interface.options.each do |option_name, option_values|
        if option_name.upcase == 'OPTIMIZE_THROUGHPUT'
          @queued = true
          update_interval = option_values[0].to_f
          EphemeralStoreQueued.instance.set_update_interval(update_interval)
          StoreQueued.instance.set_update_interval(update_interval)
        end
        if option_name.upcase == 'SYNC_PACKET_COUNT_DELAY_SECONDS'
          @sync_packet_count_delay_seconds = option_values[0].to_f
        end
      end

      @interface_thread_sleeper = Sleeper.new
      @cancel_thread = false
      @connection_failed_messages = []
      @connection_lost_messages = []
      if @interface_or_router == 'INTERFACE'
        @handler_thread = InterfaceCmdHandlerThread.new(@interface, self, logger: @logger, metric: @metric, scope: @scope)
      else
        @handler_thread = RouterTlmHandlerThread.new(@interface, self, logger: @logger, metric: @metric, scope: @scope)
      end
      @handler_thread.start
    end

    # Called to connect the interface/router. It takes optional parameters to
    # rebuilt the interface/router. Once we set the state to 'ATTEMPTING' the
    # run method handles the actual connection.
    def attempting(*params)
      unless params.empty?
        @interface.disconnect()
        # Build New Interface, this can fail if passed bad parameters
        new_interface = @interface.class.new(*params)
        @interface.copy_to(new_interface)

        # Replace interface for targets
        @interface.target_names.each do |target_name|
          target = System.targets[target_name]
          target.interface = new_interface
        end
        @interface = new_interface
      end

      @interface.state = 'ATTEMPTING'
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      end
      @interface # Return the interface/router since we may have recreated it
    # Need to rescue Exception so we cover LoadError
    rescue Exception => e
      @logger.error("Attempting connection #{@interface.connection_string} failed due to #{e.message}")
      if SignalException === e
        @logger.info "#{@interface.name}: Closing from signal"
        @cancel_thread = true
      end
      @interface # Return the original interface/router in case of error
    end

    def run
      begin
        if @interface.read_allowed?
          @logger.info "#{@interface.name}: Starting packet reading"
        else
          @logger.info "#{@interface.name}: Starting connection maintenance"
        end
        while true
          break if @cancel_thread

          case @interface.state
          when 'DISCONNECTED'
            # Just wait to see if we should connect later
            @interface_thread_sleeper.sleep(1)
          when 'ATTEMPTING'
            begin
              @mutex.synchronize do
                # We need to make sure connect is not called after stop() has been called
                connect() unless @cancel_thread
              end
            rescue Exception => e
              handle_connection_failed(@interface.connection_string, e)
              break if @cancel_thread
            end
          when 'CONNECTED'
            if @interface.read_allowed?
              begin
                packet = @interface.read
                if packet
                  handle_packet(packet)
                  @count += 1
                  if @interface_or_router == 'INTERFACE'
                    @metric.set(name: 'interface_tlm_total', value: @count, type: 'counter')
                  else
                    @metric.set(name: 'router_cmd_total', value: @count, type: 'counter')
                  end
                else
                  @logger.info "#{@interface.name}: Internal disconnect requested (returned nil)"
                  handle_connection_lost()
                  break if @cancel_thread
                end
              rescue Exception => e
                handle_connection_lost(e)
                break if @cancel_thread
              end
            else
              @interface_thread_sleeper.sleep(1)
              handle_connection_lost() if !@interface.connected?
            end
          end
        end
      rescue Exception => e
        unless SystemExit === e or SignalException === e
          @logger.error "#{@interface.name}: Packet reading thread died: #{e.formatted}"
          OpenC3.handle_fatal_exception(e)
        end
        # Try to do clean disconnect because we're going down
        disconnect(false)
      end
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      end
      @logger.info "#{@interface.name}: Stopped packet reading"
    end

    def handle_packet(packet)
      InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      packet.received_time = Time.now.sys unless packet.received_time

      if packet.stored
        # Stored telemetry does not update the current value table
        identified_packet = System.telemetry.identify_and_define_packet(packet, @interface.tlm_target_names)
      else
        # Identify and update packet
        if packet.identified?
          begin
            # Preidentifed packet - place it into the current value table
            identified_packet = System.telemetry.update!(packet.target_name,
                                                         packet.packet_name,
                                                         packet.buffer)
          rescue RuntimeError
            # Packet identified but we don't know about it
            # Clear packet_name and target_name and try to identify
            @logger.warn "#{@interface.name}: Received unknown identified telemetry: #{packet.target_name} #{packet.packet_name}"
            packet.target_name = nil
            packet.packet_name = nil
            identified_packet = System.telemetry.identify!(packet.buffer,
                                                           @interface.tlm_target_names)
          end
        else
          # Packet needs to be identified
          identified_packet = System.telemetry.identify!(packet.buffer,
                                                         @interface.tlm_target_names)
        end
      end

      if identified_packet
        identified_packet.received_time = packet.received_time
        identified_packet.stored = packet.stored
        identified_packet.extra = packet.extra
        packet = identified_packet
      else
        unknown_packet = System.telemetry.update!('UNKNOWN', 'UNKNOWN', packet.buffer)
        unknown_packet.received_time = packet.received_time
        unknown_packet.stored = packet.stored
        unknown_packet.extra = packet.extra
        packet = unknown_packet
        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, queued: @queued, scope: @scope)
        num_bytes_to_print = [UNKNOWN_BYTES_TO_PRINT, packet.length].min
        data = packet.buffer(false)[0..(num_bytes_to_print - 1)]
        prefix = data.each_byte.map { | byte | sprintf("%02X", byte) }.join()
        @logger.warn "#{@interface.name} #{packet.target_name} packet length: #{packet.length} starting with: #{prefix}"
      end

      # Write to stream
      sync_tlm_packet_counts(packet)
      TelemetryTopic.write_packet(packet, queued: @queued, scope: @scope)
    end

    def handle_connection_failed(connection, connect_error)
      @error = connect_error
      @logger.error "#{@interface.name}: Connection #{connection} failed due to #{connect_error.formatted(false, false)}"
      case connect_error
      when SignalException
        @logger.info "#{@interface.name}: Closing from signal"
        @cancel_thread = true
      when Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENOTSOCK, Errno::EHOSTUNREACH, IOError
        # Do not write an exception file for these extremely common cases
      else
        if RuntimeError === connect_error and (connect_error.message =~ /canceled/ or connect_error.message =~ /timeout/)
          # Do not write an exception file for these extremely common cases
        else
          @logger.error "#{@interface.name}: #{connect_error.formatted}"
          unless @connection_failed_messages.include?(connect_error.message)
            OpenC3.write_exception_file(connect_error)
            @connection_failed_messages << connect_error.message
          end
        end
      end
      disconnect() # Ensure we do a clean disconnect
    end

    def handle_connection_lost(err = nil, reconnect: true)
      if err
        @error = err
        @logger.info "#{@interface.name}: Connection Lost: #{err.formatted(false, false)}"
        case err
        when SignalException
          @logger.info "#{@interface.name}: Closing from signal"
          @cancel_thread = true
        when Errno::ECONNABORTED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EBADF, Errno::ENOTSOCK, IOError
          # Do not write an exception file for these extremely common cases
        else
          @logger.error "#{@interface.name}: #{err.formatted}"
          unless @connection_lost_messages.include?(err.message)
            OpenC3.write_exception_file(err)
            @connection_lost_messages << err.message
          end
        end
      else
        @logger.info "#{@interface.name}: Connection Lost"
      end
      disconnect(reconnect) # Ensure we do a clean disconnect
    end

    def connect
      @logger.info "#{@interface.name}: Connect #{@interface.connection_string}"
      begin
        @interface.connect
        @interface.post_connect
      rescue Exception => e
        begin
          @interface.disconnect # Ensure disconnect is called at least once on a partial connect
        rescue Exception
          # We want to report any connect errors, not disconnect in this case
        end
        raise e
      end
      @interface.state = 'CONNECTED'
      if @interface_or_router == 'INTERFACE'
        InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      else
        RouterStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
      end
      @logger.info "#{@interface.name}: Connection Success"
    end

    def disconnect(allow_reconnect = true)
      return if @interface.state == 'DISCONNECTED' && !@interface.connected?

      # Synchronize the calls to @interface.disconnect since it takes an unknown
      # amount of time. If two calls to disconnect stack up, the if statement
      # should avoid multiple calls to disconnect.
      @mutex.synchronize do
        begin
          @interface.disconnect if @interface.connected?
        rescue => e
          @logger.error "Disconnect: #{@interface.name}: #{e.formatted}"
        end
      end

      # If the interface is set to auto_reconnect then delay so the thread
      # can come back around and allow the interface a chance to reconnect.
      if allow_reconnect and @interface.auto_reconnect and @interface.state != 'DISCONNECTED'
        attempting()
        if !@cancel_thread
          # @logger.debug "reconnect delay: #{@interface.reconnect_delay}"
          @interface_thread_sleeper.sleep(@interface.reconnect_delay)
        end
      else
        @interface.state = 'DISCONNECTED'
        if @interface_or_router == 'INTERFACE'
          InterfaceStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
        else
          RouterStatusModel.set(@interface.as_json(:allow_nan => true), queued: true, scope: @scope)
        end
      end
    end

    # Disconnect from the interface and stop the thread
    def stop
      @logger.info "#{@interface ? @interface.name : @name}: stop requested"
      @mutex.synchronize do
        # Need to make sure that @cancel_thread is set and the interface disconnected within
        # mutex to ensure that connect() is not called when we want to stop()
        @cancel_thread = true
        @handler_thread.stop if @handler_thread
        @interface_thread_sleeper.cancel if @interface_thread_sleeper
        if @interface
          @interface.disconnect
          if @interface_or_router == 'INTERFACE'
            valid_interface = InterfaceStatusModel.get_model(name: @interface.name, scope: @scope)
          else
            valid_interface = RouterStatusModel.get_model(name: @interface.name, scope: @scope)
          end
          valid_interface.destroy if valid_interface
        end
      end
    end

    def shutdown(_sig = nil)
      @logger.info "#{@interface ? @interface.name : @name}: shutdown requested"
      stop()
      super()
    end

    def graceful_kill
      # Just to avoid warning
    end

    def sync_tlm_packet_counts(packet)
      if @sync_packet_count_delay_seconds <= 0 or $openc3_redis_cluster
        # Perfect but slow method
        packet.received_count = TargetModel.increment_telemetry_count(packet.target_name, packet.packet_name, 1, scope: @scope)
      else
        # Eventually consistent method
        # Only sync every period (default 1 second) to avoid hammering Redis
        # This is a trade off between speed and accuracy
        # The packet count is eventually consistent
        @sync_packet_count_data[packet.target_name] ||= {}
        @sync_packet_count_data[packet.target_name][packet.packet_name] ||= 0
        @sync_packet_count_data[packet.target_name][packet.packet_name] += 1

        # Ensures counters change between syncs
        packet.received_count += 1

        # Check if we need to sync the packet counts
        if @sync_packet_count_time.nil? or (Time.now - @sync_packet_count_time) > @sync_packet_count_delay_seconds
          @sync_packet_count_time = Time.now

          inc_count = 0
          # Use pipeline to make this one transaction
          result = Store.redis_pool.pipelined do
            # Increment global counters for packets received
            @sync_packet_count_data.each do |target_name, packet_data|
              packet_data.each do |packet_name, count|
                TargetModel.increment_telemetry_count(target_name, packet_name, count, scope: @scope)
                inc_count += 1
              end
            end
            @sync_packet_count_data = {}

            # Get all the packet counts with the global counters
            @interface.tlm_target_names.each do |target_name|
              TargetModel.get_all_telemetry_counts(target_name, scope: @scope)
            end
            TargetModel.get_all_telemetry_counts('UNKNOWN', scope: @scope)
          end
          @interface.tlm_target_names.each do |target_name|
            result[inc_count].each do |packet_name, count|
              update_packet = System.telemetry.packet(target_name, packet_name)
              update_packet.received_count = count.to_i
            end
            inc_count += 1
          end
          result[inc_count].each do |packet_name, count|
            update_packet = System.telemetry.packet('UNKNOWN', packet_name)
            update_packet.received_count = count.to_i
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  OpenC3::InterfaceMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end