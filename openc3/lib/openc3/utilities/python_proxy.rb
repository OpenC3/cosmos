# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

# TODO: Delegate to actual Python to verify that classes exist
# and to get proper data from them like converted_type

module OpenC3
  class PythonProxy
    attr_accessor :name
    attr_accessor :args

    def initialize(type, class_name, *params)
      @type = type
      @class_name = class_name
      @params = params
      @args = params
      @name = nil
    end

    def class
      return @class_name
    end

    def as_json(*args, **kw_args)
      case @type
      when "Processor"
        return { 'name' => @name, 'class' => @class_name, 'params' => @params }
      when "Conversion"
        return { 'class' => @class_name, 'params' => @params }
      when "LimitsResponse"
        return { "class" => @class_name, 'params' => @params }
      else
        raise "Unknown PythonProxy type: #{@type}"
      end
    end
  end
end
