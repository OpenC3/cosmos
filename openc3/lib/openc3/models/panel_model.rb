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

require 'openc3/models/model'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'

module OpenC3
  # A custom Dashboards panel type installed by a plugin:
  #
  #   PANEL MAP
  #
  # deploys tools/panels/MAP/MAP.js (a SystemJS module, plus its
  # optional .map) from the plugin gem to the tools bucket, where the
  # Dashboards tool loads it.
  class PanelModel < Model
    PRIMARY_KEY = 'openc3_panels'

    attr_accessor :name
    attr_accessor :filename
    attr_accessor :bucket_key

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope: nil)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope: nil)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    # Called by the PluginModel to validate its top-level keyword: "PANEL"
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'PANEL'
        parser.verify_num_parameters(1, 1, "PANEL <Panel Type>")
        return self.new(name: parameters[0].upcase, plugin: plugin, scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Panel: #{keyword} #{parameters.join(" ")}")
      end
    end

    def initialize(name:, updated_at: nil, plugin: nil, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name, plugin: plugin, updated_at: updated_at, scope: scope)
      @filename = "#{@name}.js"
      @bucket_key = "panels/#{@name}/#{@filename}"
    end

    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'url' => "/tools/#{@bucket_key}",
      }
    end

    def handle_config(parser, keyword, parameters)
      raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Panel: #{keyword} #{parameters.join(" ")}")
    end

    def deploy(gem_path, _variables, validate_only: false)
      filename = File.join(gem_path, 'tools', 'panels', @name, @filename)
      # Bundled JavaScript isn't run through ERB; it can legitimately contain '<%'
      data = File.read(filename, mode: "rb")
      return if validate_only

      bucket = Bucket.getClient()
      cache_control = BucketUtilities.get_cache_control(@filename)
      bucket.put_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], content_type: 'application/javascript', cache_control: cache_control, key: @bucket_key, body: data)
      if File.exist?(filename + '.map')
        bucket.put_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], content_type: 'application/json', cache_control: cache_control, key: @bucket_key + '.map', body: File.read(filename + '.map', mode: "rb"))
      end
    end

    def undeploy
      bucket = Bucket.getClient()
      bucket.delete_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], key: @bucket_key)
      bucket.delete_object(bucket: ENV['OPENC3_TOOLS_BUCKET'], key: @bucket_key + '.map')
    rescue Exception => e
      Logger.error("Error undeploying panel model #{@name} in scope #{@scope} due to #{e}")
    end
  end
end
