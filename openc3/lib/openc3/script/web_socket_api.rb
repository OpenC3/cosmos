# encoding: utf-8

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/streams/web_socket_client_stream'
require 'openc3/utilities/authentication'
require 'openc3/io/json_rpc'

module OpenC3
  # Base class - Do not use directly
  class WebSocketApi
    USER_AGENT = 'OpenC3 / v7 (ruby/openc3/lib/io/web_socket_api)'.freeze

    # Options every websocket api accepts, and their defaults. Subclasses
    # forward **options rather than restating these.
    DEFAULT_OPTIONS = {
      write_timeout: 10.0,
      read_timeout: 10.0,
      connect_timeout: 5.0,
      authentication: nil,
    }.freeze

    # Build a cable URL from the standard OPENC3 environment variable quartet:
    # <prefix>_SCHEMA, <prefix>_HOSTNAME, <prefix>_CABLE_PORT, <prefix>_PORT
    def self.cable_url(env_prefix:, default_hostname:, default_port:, path:)
      schema = ENV.fetch("#{env_prefix}_SCHEMA", 'http')
      # Normalize to the websocket schemes (mirrors the Python client). The
      # websocket gem accepts http/https too, but ws/wss is what the URL
      # actually is and Python's websockets library rejects anything else.
      schema = 'ws' if schema == 'http'
      schema = 'wss' if schema == 'https'
      hostname = ENV.fetch("#{env_prefix}_HOSTNAME", nil) || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : default_hostname)
      port = (ENV.fetch("#{env_prefix}_CABLE_PORT", nil) || ENV.fetch("#{env_prefix}_PORT", default_port)).to_i
      return "#{schema}://#{hostname}:#{port}#{path}"
    end

    # Create the WebsocketApi object. If a block is given will automatically connect/disconnect
    #
    # @param url [String] The cable URL to connect to
    # @param scope [String] The scope to connect with
    # @param options [Hash] See DEFAULT_OPTIONS
    def initialize(url:, scope: $openc3_scope, **options, &block)
      # Restore the arity checking that explicit keyword arguments used to give
      # us, so a typo'd option is an error rather than a silently ignored value
      unknown = options.keys - DEFAULT_OPTIONS.keys
      raise ArgumentError, "unknown keyword#{'s' if unknown.length > 1}: #{unknown.join(', ')}" unless unknown.empty?

      options = DEFAULT_OPTIONS.merge(options)
      # $openc3_scope is only set inside the Script Runner / microservice
      # environment. Fall back to OPENC3_SCOPE (mirrors the Python client) so a
      # bare `ruby script.rb` doesn't send a nil scope that the server rejects.
      @scope = scope || ENV.fetch('OPENC3_SCOPE', 'DEFAULT')
      @authentication = options[:authentication] || generate_auth()
      @url = url
      @write_timeout = options[:write_timeout]
      @read_timeout = options[:read_timeout]
      @connect_timeout = options[:connect_timeout]
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
        # Empty string is a normal end-of-stream signal when ActionCable / anycable-go
        # closes the WS. Treat it the same as nil so consumer `while (resp = api.read)`
        # loops exit cleanly instead of hitting JSON::ParserError on JSON.parse("").
        return nil if message.nil? || message.empty?

        json_hash = parse_message(message)
        if ignore_protocol_messages
          type = json_hash['type']
          if type # ping, welcome, confirm_subscription, reject_subscription, disconnect
            check_protocol_frame(json_hash)
            if timeout
              end_time = Time.now
              if (end_time - start_time) > timeout
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
    end

    # Will subscribe to the channel based on @identifier
    def subscribe
      unless @subscribed
        # Token is part of the identifier so it surfaces as params[:token] in
        # ApplicationCable::Channel#authenticate_subscription! — ActionCable
        # ignores `data` on `subscribe` commands.
        @identifier['token'] = @authentication.token(include_bearer: false)
        write_command('subscribe')
        @subscribed = true
        wait_for_subscribed()
      end
    end

    # Block until the server confirms the subscription. ActionCable / anycable-go
    # process 'subscribe' and 'message' commands as independent RPCs, so an action
    # (add/remove) written immediately after subscribe can reach
    # StreamingChannel#add before the subscription's broadcaster exists, where it
    # is silently dropped (a no-op) and no data ever streams. Waiting for
    # confirm_subscription guarantees the broadcaster is ready before any action
    # is written.
    def wait_for_subscribed
      while true
        message = @stream.read
        # Unlike #read, end-of-stream is fatal here rather than a nil return:
        # a socket that closes mid-handshake leaves nothing to carry on with.
        raise "WebSocket closed before subscription was confirmed" if message.nil? || message.empty?

        json_hash = parse_message(message)
        check_protocol_frame(json_hash)
        # Ignore welcome / ping and keep waiting for confirmation
        return if json_hash['type'] == 'confirm_subscription'
      end
    end

    # Will unsubscribe to the channel based on @identifier
    def unsubscribe
      if @subscribed
        write_command('unsubscribe')
        @subscribed = false
      end
    end

    # Send an ActionCable command
    def write_action(data_hash)
      # Subscribe first so the token is present in @identifier before we
      # serialize it below. ActionCable matches a 'message' command to its
      # subscription by the exact identifier string; if subscribe() injected the
      # token only afterward, the message identifier (no token) would not match
      # the subscription identifier (with token) and the server would silently
      # ignore the action.
      subscribe()
      write_command('message', data_hash)
    end

    # General write to the websocket
    def write(data)
      subscribe()
      @stream.write(data)
    end

    # Connect to the websocket with authorization in query params
    def connect
      disconnect()
      final_url = @url + "?scope=#{@scope}"
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
        # unsubscribe only clears this after a successful write. The stream is
        # being closed regardless, so it cannot remain subscribed.
        @subscribed = false
        @stream.disconnect
      else
        @subscribed = false
      end
    end

    # private

    # Write an ActionCable command frame for the current @identifier. Writes
    # straight to the stream because the callers have already subscribed (and
    # subscribe itself must not recurse through write).
    def write_command(command, data_hash = nil)
      json_hash = {}
      json_hash['command'] = command
      json_hash['identifier'] = JSON.generate(@identifier, allow_nan: true)
      json_hash['data'] = JSON.generate(data_hash, allow_nan: true) if data_hash
      @stream.write(JSON.generate(json_hash, allow_nan: true))
    end

    # Parse a server frame. Kept in one place so the JSON options cannot drift
    # between the two readers.
    def parse_message(message)
      return JSON.parse(message, allow_nan: true, create_additions: true)
    end

    # Apply the protocol rules shared by #read and #wait_for_subscribed
    def check_protocol_frame(json_hash)
      case json_hash['type']
      when 'reject_subscription'
        raise "Subscription Rejected"
      when 'disconnect'
        # Any other disconnect reason is not fatal; the caller keeps reading
        raise "Unauthorized" if json_hash['reason'] == 'unauthorized'
      else
        # ping, welcome, confirm_subscription and anything new the server adds
        # are informational only
        nil
      end
    end

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

  # Identifier for channels whose only parameter is the event history count.
  # Including classes supply the channel name as a CHANNEL constant.
  module HistoryCountIdentifier
    def initialize(history_count: 0, **options)
      @identifier = {
        channel: self.class::CHANNEL,
        history_count: history_count
      }
      super(**options)
    end
  end

  # Base class for cmd-tlm-api websockets - Do not use directly
  class CmdTlmWebSocketApi < WebSocketApi
    def initialize(url: nil, **options)
      url = generate_url() unless url
      super(url: url, **options)
    end

    def generate_url
      return WebSocketApi.cable_url(
        env_prefix: 'OPENC3_API',
        default_hostname: 'openc3-cosmos-cmd-tlm-api',
        default_port: '3901',
        path: '/openc3-api/cable'
      )
    end
  end

  # Base class for script-runner-api websockets - Do not use directly
  class ScriptWebSocketApi < WebSocketApi
    def initialize(url: nil, **options)
      url = generate_url() unless url
      super(url: url, **options)
    end

    def generate_url
      return WebSocketApi.cable_url(
        env_prefix: 'OPENC3_SCRIPT_API',
        default_hostname: 'openc3-cosmos-script-runner-api',
        default_port: '3902',
        path: '/script-api/cable'
      )
    end
  end

  # Running Script WebSocket
  class RunningScriptWebSocketApi < ScriptWebSocketApi
    def initialize(id:, **options)
      @identifier = {
        channel: "RunningScriptChannel",
        id: id
      }
      super(**options)
    end

    # The backlog of script events is transmitted with the subscription
    # confirmation, but LIVE events only flow once the client reports that it is
    # ready to stream events (see RunningScriptChannel#ready) -- a broadcast sent
    # before the gateway has registered this subscription's stream would be
    # silently dropped. subscribe() blocks until confirm_subscription, so the
    # 'ready' action is guaranteed to arrive after the stream is registered.
    def subscribe
      was_subscribed = @subscribed
      super
      write_action({ 'action' => 'ready' }) unless was_subscribed
    end
  end

  # All Scripts WebSocket
  class AllScriptsWebSocketApi < ScriptWebSocketApi
    def initialize(**options)
      @identifier = {
        channel: "AllScriptsChannel",
      }
      super(**options)
    end
  end

  # Log Messages WebSocket
  class MessagesWebSocketApi < CmdTlmWebSocketApi
    def initialize(history_count: 0, start_time: nil, end_time: nil, level: nil, types: nil, **options)
      @identifier = {
        channel: "MessagesChannel",
        history_count: history_count
      }
      @identifier['start_time'] = start_time if start_time
      @identifier['end_time'] = end_time if end_time
      @identifier['level'] = level if level
      @identifier['types'] = types if types
      super(**options)
    end
  end

  # Autonomic Events WebSocket (Enterprise Only)
  class AutonomicEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'AutonomicEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Calendar Events WebSocket (Enterprise Only)
  class CalendarEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'CalendarEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Config Events WebSocket
  class ConfigEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'ConfigEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Limits Events WebSocket
  class LimitsEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'LimitsEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # System Events WebSocket
  class SystemEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'SystemEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Timeline WebSocket
  class TimelineEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'TimelineEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Queue WebSocket
  class QueueEventsWebSocketApi < CmdTlmWebSocketApi
    CHANNEL = 'QueueEventsChannel'.freeze
    include HistoryCountIdentifier
  end

  # Streaming API WebSocket
  class StreamingWebSocketApi < CmdTlmWebSocketApi
    def initialize(**options)
      @identifier = {
        channel: "StreamingChannel"
      }
      super(**options)
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
    #   VALUETYPE - RAW, CONVERTED, FORMATTED
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    #   item_key is an optional shortened name to return the data as
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
    #
    def add(items: nil, packets: nil, start_time: nil, end_time: nil, scope: nil)
      times = {}
      times['start_time'] = to_nsec(start_time) if start_time
      times['end_time'] = to_nsec(end_time) if end_time
      stream_action('add', items: items, packets: packets, scope: scope, extra: times)
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
    #   VALUETYPE - RAW, CONVERTED, FORMATTED
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
    #
    def remove(items: nil, packets: nil, scope: nil)
      stream_action('remove', items: items, packets: packets, scope: scope)
    end

    # Convenience method to read all data until end marker is received.
    # Omitting end_time streams realtime and endlessly: no end marker is ever
    # sent, so a timeout is the only way the collection ends on its own.
    # Warning: DATA IS STORED IN RAM.  Do not use this with large queries
    def self.read_all(items: nil, packets: nil, start_time: nil, end_time: nil, scope: nil, timeout: nil)
      read_all_start_time = Time.now
      data = []
      self.new do |api|
        api.add(items: items, packets: packets, start_time: start_time, end_time: end_time, scope: scope)
        while true
          batch = api.read
          if batch.nil?
            # A bounded query must receive its end marker; a truncated result
            # returned as if complete is worse than an error. A realtime query
            # never gets one, so a close is an ordinary way for it to end.
            raise "WebSocket closed before end marker" if end_time

            return data
          end
          # An empty batch is the explicit end marker sent after a historical
          # query is complete.
          if batch.empty?
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

    # private

    # Accept either a Time or an already converted 64-bit nanosecond value
    def to_nsec(value)
      return Time === value ? value.to_nsec_from_epoch : value
    end

    # Build and write a StreamingChannel action. extra carries action specific
    # keys (the times for 'add') and is merged first to preserve wire ordering.
    def stream_action(action, items:, packets:, scope:, extra: {})
      data_hash = {}
      data_hash['action'] = action
      data_hash.merge!(extra)
      data_hash['items'] = items if items
      data_hash['packets'] = packets if packets
      data_hash['scope'] = scope || @scope
      data_hash['token'] = @authentication.token(include_bearer: false)
      write_action(data_hash)
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
