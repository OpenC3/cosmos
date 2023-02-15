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

module OpenC3
  class WebSocketApi
    USER_AGENT = 'OpenC3 / v5 (ruby/openc3/lib/io/web_socket_api)'.freeze

    def initialize(url:, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope, &block)
      @scope = scope
      @authentication = authentication.nil? ? generate_auth() : authentication
      @stream = WebSocketClientStream.new(url, write_timeout, read_timeout, connect_timeout)
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

    def generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD'] || ENV['OPENC3_SERVICE_PASSWORD']
          return OpenC3Authentication.new()
        else
          raise "Environment Variables Not Set for Authentication"
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end

    def read_message
      subscribe()
      return @stream.read
    end

    def read(ignore_keep_alive: true, timeout: nil)
      start_time = Time.now
      while true
        message = read_message()
        if message
          json_hash = JSON.parse(message, allow_nan: true, create_additions: true)
          if ignore_keep_alive
            type = json_hash['type']
            if type # ping, welcome, confirm_subscription
              if type == 'disconnect' and json_hash['reason'] == 'unauthorized'
                raise "Unauthorized"
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
          return JSON.parse(json_hash['message'], allow_nan: true, create_additions: true)
        end
        return message
      end
    end

    def subscribe
      unless @subscribed
        json_hash = {}
        json_hash['command'] = 'subscribe'
        json_hash['identifier'] = JSON.generate(@identifier)
        @stream.write(JSON.generate(json_hash))
        @subscribed = true
      end
    end

    def write_action(identifier_hash, data_hash)
      subscribe()
      json_hash = {}
      json_hash['command'] = 'message'
      json_hash['identifier'] = JSON.generate(identifier_hash)
      json_hash['data'] = JSON.generate(data_hash)
      @stream.write(JSON.generate(json_hash))
    end

    def connect
      @stream.headers = {
        'Sec-WebSocket-Protocol' => 'actioncable-v1-json, actioncable-unsupported',
        'User-Agent' => USER_AGENT,
        'X-OPENC3-SCOPE' => @scope,
        'Authorization' => @authentication.token
      }
      @stream.connect
    end

    def write(data)
      subscribe()
      @stream.write(data)
    end

    def disconnect
      @stream.disconnect
    end
  end

  class CmdTlmWebSocketApi < WebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil, scope: $openc3_scope)
      url = generate_url() unless url
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end

    def generate_url
      schema = ENV['OPENC3_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-cmd-tlm-api')
      port = ENV['OPENC3_API_PORT'] || '2901'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}/openc3-api/cable"
    end
  end

  class LogWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, scope: $openc3_scope, url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil)
      @identifier = {
        channel: "MessagesChannel",
        scope: scope,
        history_count: history_count
      }
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication, scope: scope)
    end
  end

  class NotificationsWebSocketApi < CmdTlmWebSocketApi
    def subscribe(history_count: 0, start_offset: nil, scope: $openc3_scope)
      unless @subscribed
        identifier = {
          channel: "NotificationsChannel",
          scope: scope,
          token: @authentication.token,
          history_count: history_count,
          start_offset: start_offset
        }
        super(identifier)
      end
    end
  end

  class StreamingWebSocketApi < CmdTlmWebSocketApi
    def subscribe(scope: $openc3_scope)
      super(identifier())
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
      write_action(identifier(), data_hash)
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
      write_action(identifier(), data_hash)
    end

    def identifier
      return {
        channel: "StreamingChannel",
        scope: scope,
        token: @authentication.token
      }
    end
  end

  class ScriptWebSocketApi < WebSocketApi
    def initialize(url: nil, write_timeout: 10.0, read_timeout: 10.0, connect_timeout: 5.0, authentication: nil)
      url = generate_url() unless url
      super(url: url, write_timeout: write_timeout, read_timeout: read_timeout, connect_timeout: connect_timeout, authentication: authentication)
    end

    def generate_url
      schema = ENV['OPENC3_SCRIPT_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_SCRIPT_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-script-runner-api')
      port = ENV['OPENC3_SCRIPT_API_PORT'] || '2902'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}/script-api/cable"
    end
  end
end

$openc3_scope = 'DEFAULT'
ENV['OPENC3_API_HOSTNAME'] = 'localhost'
ENV['OPENC3_API_PORT'] = '2900'
ENV['OPENC3_API_PASSWORD'] = 'password'
OpenC3::LogWebSocketApi.new do |api|
  while true
    puts api.read
  end
end