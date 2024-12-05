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

require 'openc3/models/model'
require 'openc3/models/scope_model'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'
require 'rack'

module OpenC3
  class ToolModel < Model
    PRIMARY_KEY = 'openc3_tools'

    attr_accessor :folder_name
    attr_accessor :icon
    attr_accessor :url
    attr_accessor :inline_url
    attr_accessor :window
    attr_accessor :category
    attr_accessor :shown
    attr_accessor :position
    attr_accessor :needs_dependencies
    attr_accessor :disable_erb
    attr_accessor :import_map_items

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope: nil)
      array = []
      all(scope: scope).each do |name, _tool|
        array << name
      end
      array
    end

    def self.all(scope: nil)
      ordered_array = []
      tools = unordered_all(scope: scope)
      tools.each do |_name, tool|
        ordered_array << tool
      end
      ordered_array.sort! { |a, b| a['position'] <=> b['position'] }
      ordered_hash = {}
      ordered_array.each do |tool|
        ordered_hash[tool['name']] = tool
      end
      ordered_hash
    end

    def self.all_scopes
      result = {}
      scopes = OpenC3::ScopeModel.all
      scopes.each do |key, _scope|
        tools = unordered_all(scope: key)
        result.merge!(tools)
      end
      result
    end

    # Called by the PluginModel to allow this class to validate it's top-level keyword: "TOOL"
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'TOOL'
        parser.verify_num_parameters(2, 2, "TOOL <Folder Name> <Name>")
        return self.new(folder_name: parameters[0], name: parameters[1], plugin: plugin, needs_dependencies: needs_dependencies, scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Tool: #{keyword} #{parameters.join(" ")}")
      end
      return nil
    end

    # The ToolsTab.vue calls the ToolsController which uses this method to reorder the tools
    # Position is index in the list starting with 0 = first
    def self.set_position(name:, position:, scope:)
      moving = from_json(get(name: name, scope: scope), scope: scope)
      old_pos = moving.position
      new_pos = position
      direction = :down
      if (old_pos == new_pos)
        return # we're not doing anything
      elsif (new_pos > old_pos)
        direction = :up
      end

      # Go through all the tools and reorder
      all(scope: scope).each do |_tool_name, tool|
        tool_model = from_json(tool, scope: scope)
        # Update the requested model to the new position
        if tool_model.name == name
          tool_model.position = position
        elsif direction == :down
          if tool_model.position >= new_pos && tool_model.position < old_pos
            tool_model.position += 1
          end
        else # up
          if tool_model.position > old_pos && tool_model.position <= new_pos
            tool_model.position -= 1
          end
        end
        tool_model.update
      end
    end

    def initialize(
      name:,
      folder_name: nil,
      icon: 'astro:warning',
      url: nil,
      inline_url: nil,
      window: 'INLINE',
      category: nil,
      shown: true,
      position: nil,
      updated_at: nil,
      plugin: nil,
      needs_dependencies: false,
      disable_erb: nil,
      import_map_items: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, plugin: plugin, updated_at: updated_at, scope: scope)
      @folder_name = folder_name
      @icon = icon
      @url = url
      @inline_url = inline_url
      @window = window.to_s.upcase
      @category = category
      @shown = shown
      @position = position

      if @shown and @window == 'INLINE'
        @inline_url = 'main.js' unless @inline_url
        @url = "/tools/#{folder_name}" unless @url
      end
      @needs_dependencies = needs_dependencies
      @disable_erb = disable_erb
      @import_map_items = import_map_items
    end

    def create(update: false, force: false, queued: false)
      tools = self.class.all(scope: @scope)

      # Make sure a tool with this folder_name doesn't already exist
      unless update
        if @folder_name
          tools.each do |_tool_name, tool|
            if tool['folder_name'] == @folder_name
              raise "Tool with folder_name #{@folder_name} already exists at create"
            end
          end
        end
      end

      # Autoset tool position
      unless @position
        _, tool = tools.max_by { |_tool_name, tool| tool['position'] }
        if tool
          @position = tool['position'] + 1
        else
          @position = 0
        end
      end

      if @url and !@url.start_with?('/') and !@url.start_with?('http')
        raise "URL must be a full URL (http://domain.com/path) or a relative path (/path)"
      end

      super(update: update, force: force, queued: queued)
    end

    def as_json(*a)
      {
        'name' => @name,
        'folder_name' => @folder_name,
        'icon' => @icon,
        'url' => @url,
        'inline_url' => @inline_url,
        'window' => @window,
        'category' => @category,
        'shown' => @shown,
        'position' => @position,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'needs_dependencies' => @needs_dependencies,
        'disable_erb' => @disable_erb,
        'import_map_items' => @import_map_items,
      }
    end

    def handle_config(parser, keyword, parameters)
      case keyword
      when 'URL'
        parser.verify_num_parameters(1, 1, "URL <URL>")
        @url = parameters[0]
      when 'INLINE_URL'
        parser.verify_num_parameters(1, 1, "INLINE_URL <URL>")
        @inline_url = ConfigParser.handle_nil(parameters[0])
      when 'ICON'
        parser.verify_num_parameters(1, 1, "ICON <ICON Name>")
        @icon = parameters[0]
      when 'WINDOW'
        parser.verify_num_parameters(1, 1, "WINDOW <INLINE | IFRAME | SAME | NEW>")
        @window = parameters[0].to_s.upcase
        raise ConfigParser::Error.new(parser, "Invalid WINDOW setting: #{@window}") unless ['INLINE', 'IFRAME', 'SAME', 'NEW'].include?(@window)
      when 'CATEGORY'
        parser.verify_num_parameters(1, 1, "CATEGORY <Category Name>")
        @category = parameters[0].to_s
      when 'SHOWN'
        parser.verify_num_parameters(1, 1, "SHOWN <true/false>")
        @shown = ConfigParser.handle_true_false(parameters[0])
      when 'POSITION'
        parser.verify_num_parameters(1, 1, "POSITION <value>")
        @position = parameters[0].to_f
      when 'DISABLE_ERB'
        # 0 to unlimited parameters
        @disable_erb ||= []
        if parameters
          @disable_erb.concat(parameters)
        end
      when 'IMPORT_MAP_ITEM'
        parser.verify_num_parameters(2, 2, "IMPORT_MAP_ITEM <key> <value>")
        @import_map_items ||= []
        @import_map_items << [parameters[0], parameters[1]]
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Tool: #{keyword} #{parameters.join(" ")}")
      end
      return nil
    end

    def deploy(gem_path, variables, validate_only: false)
      return unless @folder_name

      variables["tool_name"] = @name
      start_path = "/tools/#{@folder_name}/"
      Dir.glob(gem_path + start_path + "**/*") do |filename|
        next if filename == '.' or filename == '..' or File.directory?(filename)

        key = filename.split(gem_path + '/tools/')[-1]
        extension = filename.split('.')[-1]
        content_type = Rack::Mime.mime_type(".#{extension}")

        # Load tool files
        data = File.read(filename, mode: "rb")
        erb_disabled = check_disable_erb(filename)
        unless erb_disabled
          data = ERB.new(data.comment_erb(), trim_mode: "-").result(binding.set_variables(variables)) if data.is_printable?
        end
        unless validate_only
          client = Bucket.getClient()
          cache_control = BucketUtilities.get_cache_control(filename)
          client.put_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], content_type: content_type, cache_control: cache_control, key: key, body: data)
          ConfigTopic.write({ kind: 'created', type: 'tool', name: @folder_name, plugin: @plugin }, scope: @scope)
        end
      end
    end

    def undeploy
      if @folder_name and @folder_name.to_s.length > 0
        bucket = Bucket.getClient
        prefix = "#{@folder_name}/"
        bucket.list_objects(bucket: ENV['OPENC3_TOOLS_BUCKET'], prefix: prefix).each do |object|
          bucket.delete_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], key: object.key)
          ConfigTopic.write({ kind: 'deleted', type: 'tool', name: @folder_name, plugin: @plugin }, scope: @scope)
        end
      end
    rescue Exception => e
      Logger.error("Error undeploying tool model #{@name} in scope #{@scope} due to #{e}")
    end

    ##################################################
    # The following methods are implementation details
    ##################################################

    # Returns the list of tools or the default OpenC3 tool set if no tools have been created
    def self.unordered_all(scope: nil)
      tools = Store.hgetall("#{scope}__#{PRIMARY_KEY}")
      tools.each do |key, value|
        tools[key] = JSON.parse(value, :allow_nan => true, :create_additions => true)
      end
      return tools
    end
  end
end
