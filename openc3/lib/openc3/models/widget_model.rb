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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/top_level'
require 'openc3/models/model'
require 'openc3/models/scope_model'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'

module OpenC3
  class WidgetModel < Model
    PRIMARY_KEY = 'openc3_widgets'

    attr_accessor :name
    attr_accessor :full_name
    attr_accessor :filename
    attr_accessor :bucket_key
    attr_accessor :needs_dependencies
    attr_accessor :disable_erb

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope: nil)
      array = []
      all(scope: scope).each do |name, _widget|
        array << name
      end
      array
    end

    def self.all(scope: nil)
      tools = Store.hgetall("#{scope}__#{PRIMARY_KEY}")
      tools.each do |key, value|
        tools[key] = JSON.parse(value, allow_nan: true, create_additions: true)
      end
      return tools
    end

    def self.all_scopes
      result = {}
      scopes = OpenC3::ScopeModel.all
      scopes.each do |key, _scope|
        widgets = all(scope: key)
        result.merge!(widgets)
      end
      result
    end

    # Called by the PluginModel to allow this class to validate it's top-level keyword: "WIDGET"
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'WIDGET'
        parser.verify_num_parameters(1, 3, "WIDGET <Name> <Label> <Select Items (true/false)>")
        # Label is optional and if it doesn't exist nil is fine
        # Select Items is optional and if it doesn't exist nil is fine
        items = ConfigParser.handle_true_false_nil(parameters[2])
        return self.new(name: parameters[0], plugin: plugin, label: parameters[1], items: items, needs_dependencies: needs_dependencies, scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Widget: #{keyword} #{parameters.join(" ")}")
      end
      return nil
    end

    def initialize(
      name:,
      updated_at: nil,
      plugin: nil,
      label: nil,
      items: false,
      needs_dependencies: false,
      disable_erb: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, plugin: plugin, updated_at: updated_at, scope: scope)
      @full_name = @name.capitalize + 'Widget'
      @filename = @full_name + '.umd.min.js'
      @bucket_key = 'widgets/' + @full_name + '/' + @filename
      @label = label
      # Ensure items is a boolean because it could be nil
      @items = items ? true : false
      @needs_dependencies = needs_dependencies
      @disable_erb = disable_erb
    end

    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'label' => @label,
        'items' => @items,
        'needs_dependencies' => @needs_dependencies,
        'disable_erb' => @disable_erb,
      }
    end

    def handle_config(parser, keyword, parameters)
      case keyword
      when 'DISABLE_ERB'
        # 0 to unlimited parameters
        @disable_erb ||= []
        if parameters
          @disable_erb.concat(parameters)
        end
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Widget: #{keyword} #{parameters.join(" ")}")
      end
    end

    def deploy(gem_path, variables, validate_only: false)
      # Ensure tools bucket exists
      bucket = nil
      unless validate_only
        bucket = Bucket.getClient()
        bucket.ensure_public(ENV['OPENC3_TOOLS_BUCKET'])
      end

      filename = gem_path + "/tools/widgets/" + @full_name + '/' + @filename

      # Load widget file
      data = File.read(filename, mode: "rb")
      erb_disabled = check_disable_erb(filename)
      unless erb_disabled
        OpenC3.set_working_dir(File.dirname(filename)) do
          data = ERB.new(data.comment_erb(), trim_mode: "-").result(binding.set_variables(variables)) if data.is_printable?
        end
      end
      unless validate_only
        cache_control = BucketUtilities.get_cache_control(@filename)
        # TODO: support widgets that aren't just a single js file (and its associated map file)
        bucket.put_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], content_type: 'application/javascript', cache_control: cache_control, key: @bucket_key, body: data)
        data = File.read(filename + '.map', mode: "rb")
        bucket.put_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], content_type: 'application/json', cache_control: cache_control, key: @bucket_key + '.map', body: data)
      end
    end

    def undeploy
      bucket = Bucket.getClient()
      bucket.delete_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], key: @bucket_key)
      bucket.delete_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], key: @bucket_key + '.map')
    rescue Exception => e
      Logger.error("Error undeploying widget model #{@name} in scope #{@scope} due to #{e}")
    end
  end
end
