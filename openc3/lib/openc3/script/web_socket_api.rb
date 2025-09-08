# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/streams/web_socket_client_stream'
require 'openc3/utilities/authentication'
require 'openc3/io/json_rpc'

module OpenC3
  # Base class - Do not use directly
  class WebSocketApi
    USER_AGENT = 'OpenC3 / v5 (ruby/openc3/lib/io/web_socket_api)'.freeze

    # Create the WebsocketApi object. If a block is given will automatically connect/disconnect
    def initialize(url:, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope, &block)
      @scope = scope
      @authentication = authentication.nil? ? generate_auth() : authentication
      @url = url
      @write_timeout = write_timeout
      @read_timeout = read_timeout
      @connect_timeout = connect_timeout
      @subscribed = false
      if block_given?
        begin
          connect()
          yield self
        ensure
          disconnect()
        end
      end
    end

    # Read the next message without filtering / parsing
    def read_message
      subscribe()
      return @stream.read
    end

    # Read the next message with json parsing, filtering, and timeout support
    def read(ignore_protocol_messages: true, timeout: nil)
      start_time = Time.now
      while true
        message = read_message()
        if message
          json_hash = JSON.parse(message, allow_nan: true, create_additions: true)
          if ignore_protocol_messages
            type = json_hash['type']
            if type # ping, welcome, confirm_subscription, reject_subscription, disconnect
              if type == 'disconnect'
                if json_hash['reason'] == 'unauthorized'
                  raise "Unauthorized"
                end
              end
              if type == 'reject_subscription'
                raise "Subscription Rejected"
              end
              if timeout
                end_time = Time.now
                if (start_time - end_time) > timeout
                  raise Timeout::Error, "No Data Timeout"
                end
              end
              if defined? RunningScript and RunningScript.instance
                raise StopScript if RunningScript.instance.stop?
              end
              next
            end
          end
          return json_hash['message']
        end
        return message
      end
    end

    # Will subscribe to the channel based on @identifier
    def subscribe
      unless @subscribed
        json_hash = {}
        json_hash['command'] = 'subscribe'
        json_hash['identifier'] = JSON.generate(@identifier)
        @stream.write(JSON.generate(json_hash))
        @subscribed = true
      end
    end

    # Will unsubscribe to the channel based on @identifier
    def unsubscribe
      if @subscribed
        json_hash = {}
        json_hash['command'] = 'unsubscribe'
        json_hash['identifier'] = JSON.generate(@identifier)
        @stream.write(JSON.generate(json_hash))
        @subscribed = false
      end
    end

    # Send an ActionCable command
    def write_action(data_hash)
      json_hash = {}
      json_hash['command'] = 'message'
      json_hash['identifier'] = JSON.generate(@identifier)
      json_hash['data'] = JSON.generate(data_hash)
      write(JSON.generate(json_hash))
    end

    # General write to the websocket
    def write(data)
      subscribe()
      @stream.write(data)
    end

    # Connect to the websocket with authorization in query params
    def connect
      disconnect()
      final_url = @url + "?scope=#{@scope}&authorization=#{@authentication.token(include_bearer: false)}"
      @stream = WebSocketClientStream.new(final_url, @write_timeout, @read_timeout, @connect_timeout)
      @stream.headers = {
        'Sec-WebSocket-Protocol' => 'actioncable-v1-json, actioncable-unsupported',
        'User-Agent' => USER_AGENT
      }
      @stream.connect
    end

    # Are we connected?
    def connected?
      if @stream
        @stream.connected?
      else
        false
      end
    end

    # Disconnect from the websocket and attempt to send unsubscribe message
    def disconnect
      if connected?()
        begin
          unsubscribe()
        rescue
          # Oh well, we tried
        end
        @stream.disconnect
      end
    end

    # private

    # Generate the appropriate token for OpenC3
    def generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD']
          return OpenC3Authentication.new()
        else
          raise "Environment Variables Not Set for Authentication"
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end
  end

  # Base class for cmd-tlm-api websockets - Do not use directly
  class CmdTlmWebSocketApi < WebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      url = generate_url() unless url
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end

    def generate_url
      schema = ENV['OPENC3_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-cmd-tlm-api')
      port = ENV['OPENC3_API_CABLE_PORT'] || ENV['OPENC3_API_PORT'] || '3901'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}/openc3-api/cable"
    end
  end

  # Base class for script-runner-api websockets - Do not use directly
  class ScriptWebSocketApi < WebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      url = generate_url() unless url
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end

    def generate_url
      schema = ENV['OPENC3_SCRIPT_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_SCRIPT_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-script-runner-api')
      port = ENV['OPENC3_SCRIPT_API_CABLE_PORT'] || ENV['OPENC3_SCRIPT_API_PORT'] || '3902'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}/script-api/cable"
    end
  end

  # Running Script WebSocket
  class RunningScriptWebSocketApi < ScriptWebSocketApi
    def initialize(id:, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "RunningScriptChannel",
        id: id
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # All Scripts WebSocket
  class AllScriptsWebSocketApi < ScriptWebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "AllScriptsChannel",
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Log Messages WebSocket
  class MessagesWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, start_time: nil, end_time: nil, level: nil, types: nil, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "MessagesChannel",
        history_count: history_count
      }
      @identifier['start_time'] = start_time if start_time
      @identifier['end_time'] = end_time if end_time
      @identifier['level'] = level if level
      @identifier['types'] = types if types
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Autonomic Events WebSocket (Enterprise Only)
  class AutonomicEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "AutonomicEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Calendar Events WebSocket (Enterprise Only)
  class CalendarEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "CalendarEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Config Events WebSocket
  class ConfigEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "ConfigEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Limits Events WebSocket
  class LimitsEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "LimitsEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # System Events WebSocket
  class SystemEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "SystemEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Timeline WebSocket
  class TimelineEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "TimelineEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Queue WebSocket
  class QueueEventsWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "QueueEventsChannel",
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  # Streaming API WebSocket
  class StreamingWebSocketApi < CmdTlmWebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      @identifier = {
        channel: "StreamingChannel"
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end

    # Request to add data to the stream
    #
    # arguments:
    # scope: scope name
    # start_time: 64-bit nanoseconds from unix epoch - If not present then realtime
    # end_time: 64-bit nanoseconds from unix epoch - If not present stream forever
    # items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE, item_key] ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   ITEM - Item Name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    #   item_key is an optional shortened name to return the data as
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
    #
    def add(items: nil, packets: nil, start_time: nil, end_time: nil, scope: $openc3_scope)
      data_hash = {}
      data_hash['action'] = 'add'
      if start_time
        if Time === start_time
          start_time = start_time.to_nsec_from_epoch
        end
        data_hash['start_time'] = start_time
      end
      if end_time
        if Time === end_time
          end_time = end_time.to_nsec_from_epoch
        end
        data_hash['end_time'] = end_time
      end
      data_hash['items'] = items if items
      data_hash['packets'] = packets if packets
      data_hash['scope'] = scope
      data_hash['token'] = @authentication.token(include_bearer: false)
      write_action(data_hash)
    end

    # Request to remove data from the stream
    #
    # arguments:
    # scope: scope name
    # items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE] ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   ITEM - Item Name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
    #
    def remove(items: nil, packets: nil, scope: $openc3_scope)
      data_hash = {}
      data_hash['action'] = 'remove'
      data_hash['items'] = items if items
      data_hash['packets'] = packets if packets
      data_hash['scope'] = scope
      data_hash['token'] = @authentication.token(include_bearer: false)
      write_action(data_hash)
    end

    # Convenience method to read all data until end marker is received.
    # Warning: DATA IS STORED IN RAM.  Do not use this with large queries
    def self.read_all(items: nil, packets: nil, start_time: nil, end_time:, scope: $openc3_scope, timeout: nil)
      read_all_start_time = Time.now
      data = []
      self.new do |api|
        api.add(items: items, packets: packets, start_time: start_time, end_time: end_time, scope: scope)
        while true
          batch = api.read
          if batch.length == 0
            return data
          else
            data.concat(batch)
          end
          if timeout
            if (Time.now - read_all_start_time) > timeout
              return data
            end
          end
        end
      end
    end
  end
end

# # Example Use
# # The following lines are only for outside of the COSMOS Docker or Kubernetes Cluster
# # Environment variables are already set inside of our containers
# # START OUTSIDE OF DOCKER ONLY
# $openc3_scope = 'DEFAULT'
# ENV['OPENC3_API_HOSTNAME'] = '127.0.0.1'
# ENV['OPENC3_API_PORT'] = '2900'
# ENV['OPENC3_SCRIPT_API_HOSTNAME'] = '127.0.0.1'
# ENV['OPENC3_SCRIPT_API_PORT'] = '2900'
# ENV['OPENC3_API_PASSWORD'] = 'password'
# # END OUTSIDE OF DOCKER ONLY
#
# OpenC3::StreamingWebSocketApi.new do |api|
#   api.add(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'])
#   5.times do
#     puts api.read
#   end
#   api.remove(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'])
#   5.times do
#     puts api.read
#   end
# end
#
# # Warning this saves all data to RAM. Do not use for large queries
# data = OpenC3::StreamingWebSocketApi.read_all(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'], start_time: Time.now - 30, end_time: Time.now + 30)

# $openc3_scope = 'DEFAULT'
# OpenC3::MessagesWebSocketApi.new(history_count: 0, start_time: (Time.now - 86400).to_nsec_from_epoch, end_time: (Time.now - 60).to_nsec_from_epoch) do |api|
#   500.times do
#     # Note returns batch array
#     data = api.read
#     return if not data or data.length == 0
#     puts "\nReceived #{data.length} log messages:"
#     puts data
#   end
# end
