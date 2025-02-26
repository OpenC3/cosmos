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

require 'openc3/conversions/conversion'
require 'openc3/packets/binary_accessor'

module OpenC3
  # Performs a generic conversion by evaluating Ruby code
  class GenericConversion < Conversion
    # @return [String] The Ruby code to evaluate which should return the
    #   converted value
    attr_accessor :code_to_eval

    # @param code_to_eval [String] The Ruby code to evaluate which should
    #   return the converted value
    # @param converted_type [Symbol] The converted data type. Must be one of
    #   {BinaryAccessor::DATA_TYPES}
    # @param converted_bit_size [Integer] The size in bits of the converted
    #   value
    # @param converted_array_size [Integer] The size in bits of the converted array
    #   value (full size of all items if array)
    def initialize(code_to_eval, converted_type = nil, converted_bit_size = nil, converted_array_size = nil)
      super()
      @code_to_eval = code_to_eval
      if ConfigParser.handle_nil(converted_type)
        converted_type = converted_type.to_s.upcase.intern
        raise "Invalid type #{converted_type}" unless BinaryAccessor::DATA_TYPES.include?(converted_type)

        @converted_type = converted_type
      end
      @converted_bit_size = Integer(converted_bit_size) if ConfigParser.handle_nil(converted_bit_size)
      @converted_array_size = Integer(converted_array_size) if ConfigParser.handle_nil(converted_array_size)
      @params = [@code_to_eval, @converted_type, @converted_bit_size, @converted_array_size]
    end

    # (see OpenC3::Conversion#call)
    def call(value, packet, buffer)
      myself = packet # For backwards compatibility
      if myself # Remove unused variable warning for myself
        return eval(@code_to_eval)
      end
    end

    # @return [String] The conversion class followed by the code to evaluate
    def to_s
      "#{@code_to_eval}"
    end

    # @param (see Conversion#to_config)
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write)
      config = "    GENERIC_#{read_or_write}_CONVERSION_START"
      config << " #{@converted_type}" if @converted_type
      config << " #{@converted_bit_size}" if @converted_bit_size
      config << " #{@converted_array_size}" if @converted_array_size
      config << "\n"
      config << @code_to_eval
      config << "    GENERIC_#{read_or_write}_CONVERSION_END\n"
      config
    end
  end
end
