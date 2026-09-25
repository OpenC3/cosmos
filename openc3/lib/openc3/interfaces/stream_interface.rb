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

require 'openc3/interfaces/interface'
require 'openc3/utilities/read_queue'

module OpenC3
  # Base class for interfaces that act read and write from a stream
  class StreamInterface < Interface
    include ReadQueue

    attr_reader :stream

    def initialize(protocol_type = nil, protocol_args = [])
      super()
      initialize_read_queue()
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
      # buffers don't fill up while we're busy processing the previous read
      start_read_queue_thread() if @stream and read_allowed?
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

    # Called by the read thread to perform a single blocking stream read
    # @return [String, nil] Data read or nil if the stream is done
    def read_queue_data
      begin
        data = @stream.read
      rescue Timeout::Error
        Logger.error "#{@name}: Timeout waiting for data to be read"
        return nil
      end
      if data.nil?
        Logger.info "#{@name}: #{@stream.class} read returned nil"
        return nil
      end
      if data.length <= 0
        Logger.info "#{@name}: #{@stream.class} read returned 0 bytes (stream closed)"
        return nil
      end
      return data
    end

    def read_interface
      data = read_queue_pop()
      return nil if data.nil?

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
