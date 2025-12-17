# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'openc3/top_level'
require 'openc3/models/model'
require 'openc3/models/scope_model'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'

module OpenC3
  class ScriptEngineModel < Model
    PRIMARY_KEY = 'openc3_script_engines'

    attr_accessor :filename # Script Engine filename

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super(PRIMARY_KEY, name: name)
    end

    def self.names(scope: nil)
      array = []
      all(scope: scope).each do |name, _script_engine|
        array << name
      end
      array
    end

    def self.all(scope: nil)
      tools = Store.hgetall(PRIMARY_KEY)
      tools.each do |key, value|
        tools[key] = JSON.parse(value, allow_nan: true, create_additions: true)
      end
      return tools
    end

    # Called by the PluginModel to allow this class to validate it's top-level keyword: "SCRIPT_ENGINE"
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'SCRIPT_ENGINE'
        parser.verify_num_parameters(1, 3, "SCRIPT_ENGINE <Extension> <Filename>")
        return self.new(name: parameters[0], plugin: plugin, filename: parameters[1], scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Script Engine: #{keyword} #{parameters.join(" ")}")
      end
      return nil
    end

    def initialize(
      name:,
      updated_at: nil,
      plugin: nil,
      filename: nil,
      scope:
    )
      super(PRIMARY_KEY, name: name, plugin: plugin, updated_at: updated_at, scope: scope)
      @filename = filename
    end

    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'filename' => @filename
      }
    end

    def handle_config(parser, keyword, parameters)
      raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Script Engine: #{keyword} #{parameters.join(" ")}")
    end

    def deploy(gem_path, variables, validate_only: false)
      # Nothing to do
    end
  end
end
