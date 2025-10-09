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

require 'openc3/config/config_parser'
require 'thread'

module OpenC3
  # Base class for all OpenC3 protocols which defines a framework which must be
  # implemented by a subclass.
  class Protocol
    attr_accessor :interface
    attr_accessor :allow_empty_data
    attr_accessor :extra

    # @param allow_empty_data [true/false/nil] Whether or not this protocol will allow an empty string
    # to be passed down to later Protocols (instead of returning :STOP). Can be true, false, or nil, where
    # nil is interpreted as true unless the Protocol is the last Protocol of the chain.
    def initialize(allow_empty_data = nil)
      @interface = nil
      @allow_empty_data = ConfigParser.handle_true_false_nil(allow_empty_data)
      reset()
    end

    def reset
      @extra = nil
    end

    def connect_reset
      reset()
    end

    def disconnect_reset
      reset()
    end

    # Called to provide insight into the protocol read_data for the input data
    def read_protocol_input_base(data, _extra = nil)
      if @interface
        if @interface.save_raw_data
          @read_data_input_time = Time.now
          @read_data_input = data.clone
        end
        # Todo: @interface.stream_log_pair.read_log.write(data) if @interface.stream_log_pair
      end
    end

    # Called to provide insight into the protocol read_data for the output data
    def read_protocol_output_base(data, _extra = nil)
      if @interface
        if @interface.save_raw_data
          @read_data_output_time = Time.now
          @read_data_output = data.clone
        end
        # Todo: @interface.stream_log_pair.read_log.write(data) if @interface.stream_log_pair
      end
    end

    # Called to provide insight into the protocol write_data for the input data
    def write_protocol_input_base(data, _extra = nil)
      if @interface
        if @interface.save_raw_data
          @write_data_input_time = Time.now
          @write_data_input = data.clone
        end
        # Todo: @interface.stream_log_pair.write_log.write(data) if @interface.stream_log_pair
      end
    end

    # Called to provide insight into the protocol write_data for the output data
    def write_protocol_output_base(data, _extra = nil)
      if @interface
        if @interface.save_raw_data
          @write_data_output_time = Time.now
          @write_data_output = data.clone
        end
        # Todo: @interface.stream_log_pair.write_log.write(data) if @interface.stream_log_pair
      end
    end

    # Ensure we have some data in case this is the only protocol
    def read_data(data, extra = nil)
      if data.length <= 0
        if @allow_empty_data.nil?
          if @interface and @interface.read_protocols[-1] == self
            # Last read interface in chain with auto @allow_empty_data
            return :STOP
          end
        elsif !@allow_empty_data
          # Don't @allow_empty_data means STOP
          return :STOP
        end
      end
      return data, extra
    end

    def read_packet(packet)
      return packet
    end

    def write_packet(packet)
      return packet
    end

    def write_data(data, extra = nil)
      return data, extra
    end

    def post_write_interface(packet, data, extra = nil)
      return packet, data, extra
    end

    def protocol_cmd(cmd_name, *cmd_args)
      # Default do nothing - Implemented by subclasses
      return false
    end

    def write_details
      result = {'name' => self.class.name.to_s.split("::")[-1]}
      if @write_data_input_time
        result['write_data_input_time'] = @write_data_input_time.iso8601
      else
        result['write_data_input_time'] = nil
      end
      result['write_data_input'] = @write_data_input
      if @write_data_output_time
        result['write_data_output_time'] = @write_data_output_time.iso8601
      else
        result['write_data_output_time'] = nil
      end
      result['write_data_output'] = @write_data_output
      return result
    end

    def read_details
      result = {'name' => self.class.name.to_s.split("::")[-1]}
      if @read_data_input_time
        result['read_data_input_time'] = @read_data_input_time.iso8601
      else
        result['read_data_input_time'] = nil
      end
      result['read_data_input'] = @read_data_input
      if @read_data_output_time
        result['read_data_output_time'] = @read_data_output_time.iso8601
      else
        result['read_data_output_time'] = nil
      end
      result['read_data_output'] = @read_data_output
      return result
    end
  end
end
