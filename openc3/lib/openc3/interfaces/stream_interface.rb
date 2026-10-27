# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/interfaces/read_queue_interface'

module OpenC3
  # Base class for interfaces that act read and write from a stream
  class StreamInterface < ReadQueueInterface
    attr_reader :stream

    def initialize(protocol_type = nil, protocol_args = [])
      super()
      @stream = nil
      @protocol_type = ConfigParser.handle_nil(protocol_type)
      @protocol_args = protocol_args
      if @protocol_type
        protocol_class_name = protocol_type.to_s.capitalize << 'Protocol'
        klass = OpenC3.require_class(protocol_class_name.class_name_to_filename)
        add_protocol(klass, protocol_args, :PARAMS)
      end
    end

    # Replacing the stream stops the read thread which is reading the old one
    def stream=(stream)
      stop_read_queue_thread()
      @stream = stream
    end

    def connect
      super() # Reset the protocols
      @stream.connect if @stream
      # The read thread continuously drains the stream so the operating system
      # buffers don't fill up while we're busy processing the previous read.
      # @stream.read is redirected to the queue so everything reading the
      # stream (including subclasses and protocols) still sees all the data.
      start_read_queue_thread(@stream) if @stream and read_allowed?
    end

    def connected?
      if @stream
        @stream.connected?
      else
        false
      end
    end

    def disconnect
      # Disconnect the stream first to unblock the read thread
      @stream.disconnect if @stream
      stop_read_queue_thread()
      super()
    end

    def read_interface
      # The read thread is normally started by connect but interfaces can also
      # be handed an already connected stream so start it on demand
      if @stream and !read_queue_started? and read_queue_enabled? and read_allowed? and connected?
        start_read_queue_thread(@stream)
      end

      timeout = false
      begin
        data = @stream.read
      rescue Timeout::Error
        Logger.error "#{@name}: Timeout waiting for data to be read"
        timeout = true
        data = nil
      end
      if data.nil? or data.length <= 0
        Logger.info "#{@name}: #{@stream.class} read returned nil" if data.nil? and not timeout
        Logger.info "#{@name}: #{@stream.class} read returned 0 bytes (stream closed)" if not data.nil? and data.length <= 0
        return nil
      end

      extra = nil
      read_interface_base(data, extra)
      return data, extra
    end

    def write_interface(data, extra = nil)
      write_interface_base(data, extra)
      @stream.write(data)
      return data, extra
    end
  end
end
