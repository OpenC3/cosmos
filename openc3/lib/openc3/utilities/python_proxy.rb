# encoding: ascii-8bit

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

module OpenC3
  class PythonProxy
    attr_accessor :name
    attr_accessor :args
    attr_accessor :converted_type
    attr_accessor :converted_bit_size
    attr_accessor :converted_array_size

    def initialize(type, class_name, *params)
      @type = type
      @class_name = class_name
      @params = params
      @args = params
      @name = nil
      @converted_type = nil
      @converted_bit_size = nil
      @converted_array_size = nil
    end

    def class
      return @class_name
    end

    def as_json(*args, **kw_args)
      case @type
      when "Processor"
        return { 'name' => @name, 'class' => @class_name, 'params' => @params }
      when "Conversion"
        result = { 'class' => @class_name, 'params' => @params }
        result['converted_type'] = @converted_type.to_s if @converted_type
        result['converted_bit_size'] = @converted_bit_size if @converted_bit_size
        result['converted_array_size'] = @converted_array_size if @converted_array_size
        return result
      when "LimitsResponse"
        return { "class" => @class_name, 'params' => @params }
      else
        raise "Unknown PythonProxy type: #{@type}"
      end
    end
  end
end
