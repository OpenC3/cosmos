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

require 'openssl'
require 'openc3/streams/tcpip_client_stream'
require 'websocket'
require 'uri'

module OpenC3
  class WebSocketClientStream < TcpipClientStream
    attr_accessor :headers

    # @param url [String] The host to connect to
    # @param write_timeout [Float] Seconds to wait before aborting writes
    # @param read_timeout [Float|nil] Seconds to wait before aborting reads.
    #   Pass nil to block until the read is complete.
    # @param connect_timeout [Float|nil] Seconds to wait before aborting connect.
    #   Pass nil to block until the connection is complete.
    def initialize(url, write_timeout, read_timeout, connect_timeout = 5.0)
      @url = url
      @uri = URI.parse @url
      port = ((@uri.scheme == 'wss' or @uri.scheme == 'https') ? 443 : 80)
      port = @uri.port if @uri.port
      super(@uri.host, port, port, write_timeout, read_timeout, connect_timeout)
      if ['https', 'wss'].include? @uri.scheme
        socket = ::OpenSSL::SSL::SSLSocket.new(@write_socket)
        socket.sync_close = true
        socket.hostname = @uri.host
        @write_socket = socket
        @read_socket = socket
      end
      @headers = {}
    end

    def connect
      super()
      @handshake = ::WebSocket::Handshake::Client.new(:url => @url, :headers => @headers)
      @frame = ::WebSocket::Frame::Incoming::Client.new
      @handshaked = false
      @write_socket.write(@handshake.to_s)
      read() # This should wait for the handshake
      return true
    end

    def read
      while true
        if @handshaked
          msg = @frame.next
          return msg.data if msg
        end

        data = super()
        return data if data.length <= 0

        if @handshaked
          @frame << data
          msg = @frame.next
          return msg.data if msg
        else
          index = 0
          chars = ""
          data.each_char do |char|
            @handshake << char
            chars << char
            index += 1
            if @handshake.finished?
              @handshaked = true
              break
            end
          end
          if @handshaked
            data = data[index..-1]
            @frame << data
            return
          end
        end
      end
    end

    def write(data, type: :text)
      frame = ::WebSocket::Frame::Outgoing::Client.new(:data => data, :type => type, :version => @handshake.version)
      super(frame.to_s)
    end
  end
end
