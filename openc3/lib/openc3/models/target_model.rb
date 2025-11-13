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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953 and https://github.com/OpenC3/cosmos/pull/1963

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

require 'openc3/top_level'
require 'openc3/models/model'
require 'openc3/models/cvt_model'
require 'openc3/models/microservice_model'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/config_topic'
require 'openc3/system'
require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'
require 'openc3/utilities/zip'
require 'fileutils'
require 'ostruct'
require 'tmpdir'

module OpenC3
  # Manages the target in Redis. It stores the target itself under the
  # <SCOPE>__openc3_targets key under the target name field. All the command packets
  # in the target are stored under the <SCOPE>__openc3cmd__<TARGET NAME> key and the
  # telemetry under the <SCOPE>__openc3tlm__<TARGET NAME> key. Any new limits sets
  # are merged into the <SCOPE>__limits_sets key as fields. Any new limits groups are
  # created under <SCOPE>__limits_groups with field name. These Redis key/fields are
  # all removed when the undeploy method is called.
  class TargetModel < Model
    PRIMARY_KEY = 'openc3_targets'
    VALID_TYPES = %i(CMD TLM)
    ERB_EXTENSIONS = %w(.txt .rb .py .json .yaml .yml)
    ITEM_MAP_CACHE_TIMEOUT = 10.0
    @@item_map_cache = {}

    attr_accessor :folder_name
    attr_accessor :requires
    attr_accessor :ignored_parameters
    attr_accessor :ignored_items
    attr_accessor :limits_groups
    attr_accessor :cmd_tlm_files
    attr_accessor :cmd_unique_id_mode
    attr_accessor :tlm_unique_id_mode
    attr_accessor :id
    attr_accessor :cmd_buffer_depth
    attr_accessor :cmd_log_cycle_time
    attr_accessor :cmd_log_cycle_size
    attr_accessor :cmd_log_retain_time
    attr_accessor :cmd_decom_log_cycle_time
    attr_accessor :cmd_decom_log_cycle_size
    attr_accessor :cmd_decom_log_retain_time
    attr_accessor :tlm_buffer_depth
    attr_accessor :tlm_log_cycle_time
    attr_accessor :tlm_log_cycle_size
    attr_accessor :tlm_log_retain_time
    attr_accessor :tlm_decom_log_cycle_time
    attr_accessor :tlm_decom_log_cycle_size
    attr_accessor :tlm_decom_log_retain_time
    attr_accessor :reduced_minute_log_retain_time
    attr_accessor :reduced_hour_log_retain_time
    attr_accessor :reduced_day_log_retain_time
    attr_accessor :cleanup_poll_time
    attr_accessor :needs_dependencies
    attr_accessor :target_microservices
    attr_accessor :children
    attr_accessor :disable_erb
    attr_accessor :shard

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    # All targets with indication of modified targets
    def self.all_modified(scope:)
      targets = self.all(scope: scope)
      targets.each { |_target_name, target| target['modified'] = false }

      if ENV['OPENC3_LOCAL_MODE']
        modified_targets = OpenC3::LocalMode.modified_targets(scope: scope)
        modified_targets.each do |target_name|
          targets[target_name]['modified'] = true if targets[target_name]
        end
      else
        modified_targets = Bucket.getClient().list_files(bucket: ENV['OPENC3_CONFIG_BUCKET'], path: "DEFAULT/targets_modified/", only_directories: true)
        modified_targets.each do |target_name|
          # A target could have been deleted without removing the modified files
          # Thus we have to check for the existence of the target_name key
          if targets.has_key?(target_name)
            targets[target_name]['modified'] = true
          end
        end
      end
      # Sort (which turns hash to array) and return hash
      # This enables a consistent listing of the targets
      targets.sort.to_h
    end

    # Given target's modified file list
    def self.modified_files(target_name, scope:)
      modified = []

      if ENV['OPENC3_LOCAL_MODE']
        modified = OpenC3::LocalMode.modified_files(target_name, scope: scope)
      else
        resp = Bucket.getClient().list_objects(
          bucket: ENV['OPENC3_CONFIG_BUCKET'],
          # The trailing slash is important!
          prefix: "#{scope}/targets_modified/#{target_name}/",
        )
        resp.each do |item|
          # Results look like DEFAULT/targets_modified/INST/procedures/new.rb
          # so split on '/' and ignore the first two values
          modified << item.key.split('/')[2..-1].join('/')
        end
      end
      # Sort to enable a consistent listing of the modified files
      modified.sort
    end

    def self.delete_modified(target_name, scope:)
      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.delete_modified(target_name, scope: scope)
      end
      bucket = Bucket.getClient()
      # Delete the remote files as well
      resp = bucket.list_objects(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        # The trailing slash is important!
        prefix: "#{scope}/targets_modified/#{target_name}/",
      )
      resp.each do |item|
        bucket.delete_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: item.key)
      end
    end

    def self.download(target_name, scope:)
      # Validate target_name to not allow directory traversal
      if target_name.include?('..') || target_name.include?('/') || target_name.include?('\\')
        raise ArgumentError, "Invalid target_name: #{target_name.inspect}"
      end
      tmp_dir = Dir.mktmpdir
      zip_filename = File.join(tmp_dir, "#{target_name}.zip")
      Zip.continue_on_exists_proc = true
      zip = Zip::File.open(zip_filename, create: true)

      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.zip_target(target_name, zip, scope: scope)
      else
        bucket = Bucket.getClient()
        # The trailing slash is important!
        prefix = "#{scope}/targets_modified/#{target_name}/"
        resp = bucket.list_objects(
          bucket: ENV['OPENC3_CONFIG_BUCKET'],
          prefix: prefix,
        )
        resp.each do |item|
          # item.key looks like DEFAULT/targets_modified/INST/screens/blah.txt
          base_path = item.key.sub(prefix, '') # remove prefix
          local_path = File.join(tmp_dir, base_path)
          # Ensure dir structure exists, get_object fails if not
          FileUtils.mkdir_p(File.dirname(local_path))
          bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: item.key, path: local_path)
          zip.add(base_path, local_path)
        end
      end
      zip.close

      result = OpenStruct.new
      result.filename = File.basename(zip_filename)
      result.contents = File.read(zip_filename, mode: 'rb')
      return result
    end

    # @return [Hash] Packet hash or raises an exception
    def self.packet(target_name, packet_name, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name} #{packet_name}" unless VALID_TYPES.include?(type)

      # Assume it exists and just try to get it to avoid an extra call to Store.exist?
      json = Store.hget("#{scope}__openc3#{type.to_s.downcase}__#{target_name}", packet_name)
      raise "Packet '#{target_name} #{packet_name}' does not exist" if json.nil?

      JSON.parse(json, allow_nan: true, create_additions: true)
    end

    # @return [Array<Hash>] All packet hashes under the target_name
    def self.packets(target_name, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name}" unless VALID_TYPES.include?(type)
      raise "Target '#{target_name}' does not exist for scope: #{scope}" unless get(name: target_name, scope: scope)

      result = []
      packets = Store.hgetall("#{scope}__openc3#{type.to_s.downcase}__#{target_name}")
      packets.sort.each do |_packet_name, packet_json|
        result << JSON.parse(packet_json, allow_nan: true, create_additions: true)
      end
      result
    end

    # @return [Array<Hash>] All packet hashes under the target_name
    def self.all_packet_name_descriptions(target_name, type: :TLM, scope:)
      self.packets(target_name, type: type, scope: scope).map! { |hash| hash.slice("packet_name", "description") }
    end

    def self.set_packet(target_name, packet_name, packet, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name} #{packet_name}" unless VALID_TYPES.include?(type)

      begin
        Store.hset("#{scope}__openc3#{type.to_s.downcase}__#{target_name}", packet_name, JSON.generate(packet.as_json, allow_nan: true))
      rescue JSON::GeneratorError => e
        Logger.error("Invalid text present in #{target_name} #{packet_name} #{type.to_s.downcase} packet")
        raise e
      end
    end

    # @return [Hash] Item hash or raises an exception
    def self.packet_item(target_name, packet_name, item_name, type: :TLM, scope:)
      packet = packet(target_name, packet_name, type: type, scope: scope)
      item = packet['items'].find { |item| item['name'] == item_name.to_s }
      raise "Item '#{packet['target_name']} #{packet['packet_name']} #{item_name}' does not exist" unless item
      item
    end

    # @return [Array<Hash>] Item hash array or raises an exception
    def self.packet_items(target_name, packet_name, items, type: :TLM, scope:)
      packet = packet(target_name, packet_name, type: type, scope: scope)
      found = packet['items'].find_all { |item| items.map(&:to_s).include?(item['name']) }
      if found.length != items.length # we didn't find them all
        found_items = found.collect { |item| item['name'] }
        not_found = []
        (items - found_items).each do |item|
          not_found << "'#{target_name} #{packet_name} #{item}'"
        end
        # 'does not exist' not grammatically correct but we use it in every other exception
        raise "Item(s) #{not_found.join(', ')} does not exist"
      end
      found
    end

    # @return [Array<String>] All the item names for every packet in a target
    def self.all_item_names(target_name, type: :TLM, scope:)
      items = Store.zrange("#{scope}__openc3tlm__#{target_name}__allitems", 0, -1)
      items = rebuild_target_allitems_list(target_name, type: type, scope: scope) if items.empty?
      items
    end

    def self.rebuild_target_allitems_list(target_name, type: :TLM, scope:)
      packets = packets(target_name, type: type, scope: scope)
      packets.each do |packet|
        packet['items'].each do |item|
          TargetModel.add_to_target_allitems_list(target_name, item['name'], scope: scope)
        end
      end
      Store.zrange("#{scope}__openc3tlm__#{target_name}__allitems", 0, -1) # return the new sorted set to let redis do the sorting
    end

    def self.add_to_target_allitems_list(target_name, item_name, scope:)
      score = 0 # https://redis.io/docs/latest/develop/data-types/sorted-sets/#lexicographical-scores
      Store.zadd("#{scope}__openc3tlm__#{target_name}__allitems", score, item_name)
    end

    # @return [Hash{String => Array<Array<String, String, String>>}]
    def self.limits_groups(scope:)
      groups = Store.hgetall("#{scope}__limits_groups")
      if groups
        groups.map { |group, items| [group, JSON.parse(items, allow_nan: true, create_additions: true)] }.to_h
      else
        {}
      end
    end

    def self.get_item_to_packet_map(target_name, scope:)
      cache_time, item_map = @@item_map_cache[target_name]
      return item_map if item_map and (Time.now - cache_time) < ITEM_MAP_CACHE_TIMEOUT
      item_map_key = "#{scope}__#{target_name}__item_to_packet_map"
      target_name = target_name.upcase
      json_data = Store.get(item_map_key)
      if json_data
        item_map = JSON.parse(json_data, allow_nan: true, create_additions: true)
      else
        item_map = build_item_to_packet_map(target_name, scope: scope)
        Store.set(item_map_key, JSON.generate(item_map, allow_nan: true))
      end
      @@item_map_cache[target_name] = [Time.now, item_map]
      return item_map
    end

    def self.build_item_to_packet_map(target_name, scope:)
      item_map = {}
      packets = packets(target_name, scope: scope)
      packets.each do |packet|
        items = packet['items']
        items.each do |item|
          item_name = item['name']
          item_map[item_name] ||= []
          item_map[item_name] << packet['packet_name']
        end
      end
      return item_map
    end

    # Called by the PluginModel to allow this class to validate it's top-level keyword: "TARGET"
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'TARGET'
        usage = "#{keyword} <TARGET FOLDER NAME> <TARGET NAME>"
        parser.verify_num_parameters(2, 2, usage)
        parser.verify_parameter_naming(2) # Target name is the 2nd parameter
        return self.new(name: parameters[1].to_s.upcase, folder_name: parameters[0].to_s.upcase, plugin: plugin,  needs_dependencies: needs_dependencies, scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Target: #{keyword} #{parameters.join(" ")}")
      end
    end

    # Make sure to update target_model.py if you add additional parameters
    def initialize(
      name:,
      folder_name: nil,
      requires: [],
      ignored_parameters: [],
      ignored_items: [],
      limits_groups: [],
      cmd_tlm_files: [],
      cmd_unique_id_mode: false,
      tlm_unique_id_mode: false,
      id: nil,
      updated_at: nil,
      plugin: nil,
      cmd_buffer_depth: 5,
      cmd_log_cycle_time: 600,
      cmd_log_cycle_size: 50_000_000,
      cmd_log_retain_time: nil,
      cmd_decom_log_cycle_time: 600,
      cmd_decom_log_cycle_size: 50_000_000,
      cmd_decom_log_retain_time: nil,
      tlm_buffer_depth: 60,
      tlm_log_cycle_time: 600,
      tlm_log_cycle_size: 50_000_000,
      tlm_log_retain_time: nil,
      tlm_decom_log_cycle_time: 600,
      tlm_decom_log_cycle_size: 50_000_000,
      tlm_decom_log_retain_time: nil,
      reduced_minute_log_retain_time: nil,
      reduced_hour_log_retain_time: nil,
      reduced_day_log_retain_time: nil,
      cleanup_poll_time: 600,
      needs_dependencies: false,
      target_microservices: {'REDUCER' => [[]]},
      reducer_disable: false,
      reducer_max_cpu_utilization: 30.0,
      disable_erb: nil,
      shard: 0,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, plugin: plugin, updated_at: updated_at,
        cmd_buffer_depth: cmd_buffer_depth, cmd_log_cycle_time: cmd_log_cycle_time, cmd_log_cycle_size: cmd_log_cycle_size,
        cmd_log_retain_time: cmd_log_retain_time,
        cmd_decom_log_cycle_time: cmd_decom_log_cycle_time, cmd_decom_log_cycle_size: cmd_decom_log_cycle_size,
        cmd_decom_log_retain_time: cmd_decom_log_retain_time,
        tlm_buffer_depth: tlm_buffer_depth, tlm_log_cycle_time: tlm_log_cycle_time, tlm_log_cycle_size: tlm_log_cycle_size,
        tlm_log_retain_time: tlm_log_retain_time,
        tlm_decom_log_cycle_time: tlm_decom_log_cycle_time, tlm_decom_log_cycle_size: tlm_decom_log_cycle_size,
        tlm_decom_log_retain_time: tlm_decom_log_retain_time,
        reduced_minute_log_retain_time: reduced_minute_log_retain_time,
        reduced_hour_log_retain_time: reduced_hour_log_retain_time, reduced_day_log_retain_time: reduced_day_log_retain_time,
        cleanup_poll_time: cleanup_poll_time, needs_dependencies: needs_dependencies, target_microservices: target_microservices,
        reducer_disable: reducer_disable, reducer_max_cpu_utilization: reducer_max_cpu_utilization,
        scope: scope)
      @folder_name = folder_name
      @requires = requires
      @ignored_parameters = ignored_parameters
      @ignored_items = ignored_items
      @limits_groups = limits_groups
      @cmd_tlm_files = cmd_tlm_files
      @cmd_unique_id_mode = cmd_unique_id_mode
      @tlm_unique_id_mode = tlm_unique_id_mode
      @id = id
      @cmd_buffer_depth = cmd_buffer_depth
      @cmd_log_cycle_time = cmd_log_cycle_time
      @cmd_log_cycle_size = cmd_log_cycle_size
      @cmd_log_retain_time = cmd_log_retain_time
      @cmd_decom_log_cycle_time = cmd_decom_log_cycle_time
      @cmd_decom_log_cycle_size = cmd_decom_log_cycle_size
      @cmd_decom_log_retain_time = cmd_decom_log_retain_time
      @tlm_buffer_depth = tlm_buffer_depth
      @tlm_log_cycle_time = tlm_log_cycle_time
      @tlm_log_cycle_size = tlm_log_cycle_size
      @tlm_log_retain_time = tlm_log_retain_time
      @tlm_decom_log_cycle_time = tlm_decom_log_cycle_time
      @tlm_decom_log_cycle_size = tlm_decom_log_cycle_size
      @tlm_decom_log_retain_time = tlm_decom_log_retain_time
      @reduced_minute_log_retain_time = reduced_minute_log_retain_time
      @reduced_hour_log_retain_time = reduced_hour_log_retain_time
      @reduced_day_log_retain_time = reduced_day_log_retain_time
      @cleanup_poll_time = cleanup_poll_time
      @needs_dependencies = needs_dependencies
      @target_microservices = target_microservices
      @reducer_disable = reducer_disable
      @reducer_max_cpu_utilization = reducer_max_cpu_utilization
      @disable_erb = disable_erb
      @shard = shard.to_i # to_i to handle nil
      @bucket = Bucket.getClient()
      @children = []
    end

    def as_json(*_a)
      {
        'name' => @name,
        'folder_name' => @folder_name,
        'requires' => @requires,
        'ignored_parameters' => @ignored_parameters,
        'ignored_items' => @ignored_items,
        'limits_groups' => @limits_groups,
        'cmd_tlm_files' => @cmd_tlm_files,
        'cmd_unique_id_mode' => @cmd_unique_id_mode,
        'tlm_unique_id_mode' => @tlm_unique_id_mode,
        'id' => @id,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'cmd_buffer_depth' => @cmd_buffer_depth,
        'cmd_log_cycle_time' => @cmd_log_cycle_time,
        'cmd_log_cycle_size' => @cmd_log_cycle_size,
        'cmd_log_retain_time' => @cmd_log_retain_time,
        'cmd_decom_log_cycle_time' => @cmd_decom_log_cycle_time,
        'cmd_decom_log_cycle_size' => @cmd_decom_log_cycle_size,
        'cmd_decom_log_retain_time' => @cmd_decom_log_retain_time,
        'tlm_buffer_depth' => @tlm_buffer_depth,
        'tlm_log_cycle_time' => @tlm_log_cycle_time,
        'tlm_log_cycle_size' => @tlm_log_cycle_size,
        'tlm_log_retain_time' => @tlm_log_retain_time,
        'tlm_decom_log_cycle_time' => @tlm_decom_log_cycle_time,
        'tlm_decom_log_cycle_size' => @tlm_decom_log_cycle_size,
        'tlm_decom_log_retain_time' => @tlm_decom_log_retain_time,
        'reduced_minute_log_retain_time' => @reduced_minute_log_retain_time,
        'reduced_hour_log_retain_time' => @reduced_hour_log_retain_time,
        'reduced_day_log_retain_time' => @reduced_day_log_retain_time,
        'cleanup_poll_time' => @cleanup_poll_time,
        'needs_dependencies' => @needs_dependencies,
        'target_microservices' => @target_microservices.as_json(),
        'reducer_disable' => @reducer_disable,
        'reducer_max_cpu_utilization' => @reducer_max_cpu_utilization,
        'disable_erb' => @disable_erb,
        'shard' => @shard,
      }
    end

    # Handles Target specific configuration keywords
    def handle_config(parser, keyword, parameters)
      case keyword
      when 'CMD_BUFFER_DEPTH'
        parser.verify_num_parameters(1, 1, "#{keyword} <Number of commands to buffer to ensure logged in order>")
        @cmd_buffer_depth = parameters[0].to_i
      when 'CMD_LOG_CYCLE_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum time between files in seconds>")
        @cmd_log_cycle_time = parameters[0].to_i
      when 'CMD_LOG_CYCLE_SIZE'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum file size in bytes>")
        @cmd_log_cycle_size = parameters[0].to_i
      when 'CMD_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for cmd log files in seconds - nil = Forever>")
        @cmd_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @cmd_log_retain_time = @cmd_log_retain_time.to_i if @cmd_log_retain_time
      when 'CMD_DECOM_LOG_CYCLE_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum time between files in seconds>")
        @cmd_decom_log_cycle_time = parameters[0].to_i
      when 'CMD_DECOM_LOG_CYCLE_SIZE'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum file size in bytes>")
        @cmd_decom_log_cycle_size = parameters[0].to_i
      when 'CMD_DECOM_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for cmd decom log files in seconds - nil = Forever>")
        @cmd_decom_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @cmd_decom_log_retain_time = @cmd_decom_log_retain_time.to_i if @cmd_decom_log_retain_time
      when 'TLM_BUFFER_DEPTH'
        parser.verify_num_parameters(1, 1, "#{keyword} <Number of telemetry packets to buffer to ensure logged in order>")
        @tlm_buffer_depth = parameters[0].to_i
      when 'TLM_LOG_CYCLE_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum time between files in seconds>")
        @tlm_log_cycle_time = parameters[0].to_i
      when 'TLM_LOG_CYCLE_SIZE'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum file size in bytes>")
        @tlm_log_cycle_size = parameters[0].to_i
      when 'TLM_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for tlm log files in seconds - nil = Forever>")
        @tlm_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @tlm_log_retain_time = @tlm_log_retain_time.to_i if @tlm_log_retain_time
      when 'TLM_DECOM_LOG_CYCLE_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum time between files in seconds>")
        @tlm_decom_log_cycle_time = parameters[0].to_i
      when 'TLM_DECOM_LOG_CYCLE_SIZE'
        parser.verify_num_parameters(1, 1, "#{keyword} <Maximum file size in bytes>")
        @tlm_decom_log_cycle_size = parameters[0].to_i
      when 'TLM_DECOM_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for tlm decom log files in seconds - nil = Forever>")
        @tlm_decom_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @tlm_decom_log_retain_time = @tlm_decom_log_retain_time.to_i if @tlm_decom_log_retain_time
      when 'REDUCED_MINUTE_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for reduced minute log files in seconds - nil = Forever>")
        @reduced_minute_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @reduced_minute_log_retain_time = @reduced_minute_log_retain_time.to_i if @reduced_minute_log_retain_time
      when 'REDUCED_HOUR_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for reduced hour log files in seconds - nil = Forever>")
        @reduced_hour_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @reduced_hour_log_retain_time = @reduced_hour_log_retain_time.to_i if @reduced_hour_log_retain_time
      when 'REDUCED_DAY_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for reduced day log files in seconds - nil = Forever>")
        @reduced_day_log_retain_time = ConfigParser.handle_nil(parameters[0])
        @reduced_day_log_retain_time = @reduced_day_log_retain_time.to_i if @reduced_day_log_retain_time
      when 'LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for all log files in seconds - nil = Forever>")
        log_retain_time = ConfigParser.handle_nil(parameters[0])
        if log_retain_time
          @cmd_log_retain_time = log_retain_time.to_i
          @cmd_decom_log_retain_time = log_retain_time.to_i
          @tlm_log_retain_time = log_retain_time.to_i
          @tlm_decom_log_retain_time = log_retain_time.to_i
        end
      when 'REDUCED_LOG_RETAIN_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Retention time for all reduced log files in seconds - nil = Forever>")
        reduced_log_retain_time = ConfigParser.handle_nil(parameters[0])
        if reduced_log_retain_time
          @reduced_minute_log_retain_time = reduced_log_retain_time.to_i
          @reduced_hour_log_retain_time = reduced_log_retain_time.to_i
          @reduced_day_log_retain_time = reduced_log_retain_time.to_i
        end
      when 'REDUCER_DISABLE', 'REDUCER_DISABLED' # Handle typos
        @reducer_disable = true
      when 'REDUCER_MAX_CPU_UTILIZATION', 'REDUCED_MAX_CPU_UTILIZATION' # Handle typos
        parser.verify_num_parameters(1, 1, "#{keyword} <Max cpu utilization to allocate to the reducer microservice - 0.0 to 100.0>")
        @reducer_max_cpu_utilization = Float(parameters[0])
      when 'CLEANUP_POLL_TIME'
        parser.verify_num_parameters(1, 1, "#{keyword} <Cleanup polling period in seconds>")
        @cleanup_poll_time = parameters[0].to_i
      when 'TARGET_MICROSERVICE'
        parser.verify_num_parameters(1, 1, "#{keyword} <Type: DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP>")
        type = parameters[0].to_s.upcase
        unless %w(DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP).include?(type)
          raise "Unknown TARGET_MICROSERVICE #{type}"
        end
        @target_microservices[type] ||= []
        @target_microservices[type] << []
        @current_target_microservice = type
      when 'PACKET'
        if @current_target_microservice
          parser.verify_num_parameters(1, 1, "#{keyword} <Packet Name>")
          if @current_target_microservice == 'REDUCER' or @current_target_microservice == 'CLEANUP'
            raise ConfigParser::Error.new(parser, "PACKET cannot be used with target microservice #{@current_target_microservice}")
          end
          @target_microservices[@current_target_microservice][-1] << parameters[0].to_s.upcase
        else
          raise ConfigParser::Error.new(parser, "PACKET cannot be used without a TARGET_MICROSERVICE")
        end
      when 'DISABLE_ERB'
        # 0 to unlimited parameters
        @disable_erb ||= []
        if parameters
          @disable_erb.concat(parameters)
        end
      when 'SHARD'
        parser.verify_num_parameters(1, 1, "#{keyword} <Shard Number Starting from 0>")
        @shard = Integer(parameters[0])

      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Target: #{keyword} #{parameters.join(" ")}")
      end
      return nil
    end

    def deploy(gem_path, variables, validate_only: false)
      variables["target_name"] = @name
      start_path = "/targets/#{@folder_name}/"
      temp_dir = Dir.mktmpdir
      found = false
      begin
        target_path = gem_path + start_path + "**/*"
        Dir.glob(target_path) do |filename|
          next if filename == '.' or filename == '..' or File.directory?(filename)

          path = filename.split(gem_path)[-1]
          target_folder_path = path.split(start_path)[-1]
          key = "#{@scope}/targets/#{@name}/#{target_folder_path}"

          # Load target files
          @filename = filename # For render
          data = File.read(filename, mode: "rb")
          erb_disabled = check_disable_erb(filename)
          begin
            unless erb_disabled
              OpenC3.set_working_dir(File.dirname(filename)) do
                if ERB_EXTENSIONS.include?(File.extname(filename).downcase) and File.basename(filename)[0] != '_'
                  data = ERB.new(data.force_encoding("UTF-8").comment_erb(), trim_mode: "-").result(binding.set_variables(variables))
                end
              end
            end
          rescue => e
            # ERB error parsing a screen is just a logger error because life can go on
            # With cmd/tlm or scripts this is a serious error and we raise
            if (filename.include?('/screens/'))
              Logger.error("ERB error parsing #{key} due to #{e.message}")
            else
              raise "ERB error parsing #{key} due to #{e.message}"
            end
          end
          local_path = File.join(temp_dir, @name, target_folder_path)
          FileUtils.mkdir_p(File.dirname(local_path))
          File.open(local_path, 'wb') { |file| file.write(data) }
          found = true
          @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key, body: data) unless validate_only
        end
        raise "No target files found at #{target_path}" unless found

        target_folder = File.join(temp_dir, @name)
        # Build a System for just this target
        system = System.new([@name], temp_dir)
        if variables["xtce_output"]
          puts "Converting target #{@name} to .xtce files in #{variables["xtce_output"]}/#{@name}"
          system.packet_config.to_xtce(variables["xtce_output"])
        end
        unless validate_only
          build_target_archive(temp_dir, target_folder)
          system = update_store(system)
          deploy_microservices(gem_path, variables, system)
          ConfigTopic.write({ kind: 'created', type: 'target', name: @name, plugin: @plugin }, scope: @scope)
        end
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
      end
    end

    def undeploy
      prefix = "#{@scope}/targets/#{@name}/"
      @bucket.list_objects(bucket: ENV['OPENC3_CONFIG_BUCKET'], prefix: prefix).each do |object|
        @bucket.delete_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: object.key)
      end

      self.class.get_model(name: @name, scope: @scope).limits_groups.each do |group|
        Store.hdel("#{@scope}__limits_groups", group)
      end
      self.class.packets(@name, type: :CMD, scope: @scope).each do |packet|
        Topic.del("#{@scope}__COMMAND__{#{@name}}__#{packet['packet_name']}")
        Topic.del("#{@scope}__DECOMCMD__{#{@name}}__#{packet['packet_name']}")
      end
      self.class.packets(@name, scope: @scope).each do |packet|
        Topic.del("#{@scope}__TELEMETRY__{#{@name}}__#{packet['packet_name']}")
        Topic.del("#{@scope}__DECOM__{#{@name}}__#{packet['packet_name']}")
        Topic.del("#{@scope}__REDUCED_MINUTE__{#{@name}}__#{packet['packet_name']}")
        Topic.del("#{@scope}__REDUCED_HOUR__{#{@name}}__#{packet['packet_name']}")
        Topic.del("#{@scope}__REDUCED_DAY__{#{@name}}__#{packet['packet_name']}")
        CvtModel.del(target_name: @name, packet_name: packet['packet_name'], scope: @scope)
      end
      LimitsEventTopic.delete(@name, scope: @scope)
      Store.del("#{@scope}__openc3tlm__#{@name}")
      Store.del("#{@scope}__openc3cmd__#{@name}")
      Store.del("#{@scope}__TELEMETRYCNTS__{#{@name}}")
      Store.del("#{@scope}__COMMANDCNTS__{#{@name}}")

      # Note: these match the names of the services in deploy_microservices
      %w(MULTI DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP).each do |type|
        target_microservices = @target_microservices[type]
        if target_microservices
          max_instances = target_microservices.length + 1
        else
          max_instances = 1
        end
        max_instances.times do |index|
          instance = nil
          instance = index unless index == 0
          model = MicroserviceModel.get_model(name: "#{@scope}__#{type}#{instance}__#{@name}", scope: @scope)
          model.destroy if model
        end
      end
      # Delete item_map
      item_map_key = "#{@scope}__#{@name}__item_to_packet_map"
      Store.del(item_map_key)
      @@item_map_cache[@name] = nil

      topic = { kind: 'deleted', type: 'target', name: @name }
      # The UNKNOWN target doesn't have an associated plugin
      topic[:plugin] = @plugin if @plugin
      ConfigTopic.write(topic, scope: @scope)
    rescue Exception => e
      Logger.error("Error undeploying target model #{@name} in scope #{@scope} due to #{e}")
    end

    ##################################################
    # The following methods are implementation details
    ##################################################

    # Called by the ERB template to render a partial
    def render(template_name, options = {})
      raise "Partial name '#{template_name}' must begin with an underscore." if File.basename(template_name)[0] != '_'

      b = binding
      b.local_variable_set(:target_name, @name)
      if options[:locals]
        options[:locals].each { |key, value| b.local_variable_set(key, value) }
      end

      # Assume the file is there. If not we raise a pretty obvious error
      if File.expand_path(template_name) == template_name # absolute path
        path = template_name
      else # relative to the current @filename
        path = File.join(File.dirname(@filename), template_name)
      end

      data = File.read(path, mode: "rb")
      erb_disabled = check_disable_erb(path)
      begin
        if erb_disabled
          return data
        else
          OpenC3.set_working_dir(File.dirname(path)) do
            return ERB.new(data.force_encoding("UTF-8").comment_erb(), trim_mode: "-").result(b)
          end
        end
      rescue => e
        raise "ERB error parsing: #{path}: #{e.formatted}"
      end
    end

    def build_target_archive(temp_dir, target_folder)
      target_files = []
      Find.find(target_folder) { |file| target_files << file }
      target_files.sort!
      @id = OpenC3.hash_files(target_files, nil, 'SHA256').hexdigest
      File.open(File.join(target_folder, 'target_id.txt'), 'wb') { |file| file.write(@id) }
      key = "#{@scope}/targets/#{@name}/target_id.txt"
      @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key, body: @id)

      # Create target archive zip file
      prefix = File.dirname(target_folder) + '/'
      output_file = File.join(temp_dir, @name + '_' + @id + '.zip')
      Zip.continue_on_exists_proc = true
      Zip::File.open(output_file, create: true) do |zipfile|
        target_files.each do |target_file|
          zip_file_path = target_file.delete_prefix(prefix)
          if File.directory?(target_file)
            zipfile.mkdir(zip_file_path)
          else
            zipfile.add(zip_file_path, target_file)
          end
        end
      end

      # Write Target Archive to bucket
      File.open(output_file, 'rb') do |file|
        bucket_key = key = "#{@scope}/target_archives/#{@name}/#{@name}_current.zip"
        @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: bucket_key, body: file)
      end
      File.open(output_file, 'rb') do |file|
        bucket_key = key = "#{@scope}/target_archives/#{@name}/#{@name}_#{@id}.zip"
        @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: bucket_key, body: file)
      end
    end

    def update_target_model(system)
      target = system.targets[@name]

      # Add in the information from the target and update
      @requires = target.requires
      @ignored_parameters = target.ignored_parameters
      @ignored_items = target.ignored_items
      @cmd_tlm_files = target.cmd_tlm_files
      @cmd_unique_id_mode = target.cmd_unique_id_mode
      @tlm_unique_id_mode = target.tlm_unique_id_mode
      @limits_groups = system.limits.groups.keys
      update()
    end

    def update_store_telemetry(packet_hash, clear_old: true)
      packet_hash.each do |target_name, packets|
        if clear_old
          Store.del("#{@scope}__openc3tlm__#{target_name}")
          Store.del("#{@scope}__openc3tlm__#{target_name}__allitems")
          Store.del("#{@scope}__TELEMETRYCNTS__{#{target_name}}")
        end
        packets.each do |packet_name, packet|
          Logger.debug "Configuring tlm packet: #{target_name} #{packet_name}"
          begin
            Store.hset("#{@scope}__openc3tlm__#{target_name}", packet_name, JSON.generate(packet.as_json, allow_nan: true))
          rescue JSON::GeneratorError => e
            Logger.error("Invalid text present in #{target_name} #{packet_name} tlm packet")
            raise e
          end
          json_hash = {}
          packet.sorted_items.each do |item|
            json_hash[item.name] = nil
            TargetModel.add_to_target_allitems_list(target_name, item.name, scope: @scope)
          end
          CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: @scope)
        end
      end
    end

    def update_store_commands(packet_hash, clear_old: true)
      packet_hash.each do |target_name, packets|
        if clear_old
          Store.del("#{@scope}__openc3cmd__#{target_name}")
          Store.del("#{@scope}__COMMANDCNTS__{#{target_name}}")
        end
        packets.each do |packet_name, packet|
          Logger.debug "Configuring cmd packet: #{target_name} #{packet_name}"
          begin
            Store.hset("#{@scope}__openc3cmd__#{target_name}", packet_name, JSON.generate(packet.as_json, allow_nan: true))
          rescue JSON::GeneratorError => e
            Logger.error("Invalid text present in #{target_name} #{packet_name} cmd packet")
            raise e
          end
        end
      end
    end

    def update_store_limits_groups(system)
      system.limits.groups.each do |group, items|
        begin
          Store.hset("#{@scope}__limits_groups", group, JSON.generate(items, allow_nan: true))
        rescue JSON::GeneratorError => e
          Logger.error("Invalid text present in #{group} limits group")
          raise e
        end
      end
    end

    def update_store_limits_sets(system)
      sets = Store.hgetall("#{@scope}__limits_sets")
      sets ||= {}
      system.limits.sets.each do |set|
        sets[set.to_s] = "false" unless sets.key?(set.to_s)
      end
      Store.hmset("#{@scope}__limits_sets", *sets)
    end

    def update_store_item_map
      # Create item_map
      item_map_key = "#{@scope}__#{@name}__item_to_packet_map"
      item_map = self.class.build_item_to_packet_map(@name, scope: @scope)
      Store.set(item_map_key, JSON.generate(item_map, allow_nan: true))
      @@item_map_cache[@name] = [Time.now, item_map]
    end

    def update_store(system, clear_old: true)
      update_target_model(system)
      update_store_telemetry(system.telemetry.all, clear_old: clear_old)
      update_store_commands(system.commands.all, clear_old: clear_old)
      update_store_limits_groups(system)
      update_store_limits_sets(system)
      update_store_item_map()
      return system
    end

    # NOTE: If you call dynamic_update multiple times you should specify a different
    # filename parameter or the last one will be overwritten
    def dynamic_update(packets, cmd_or_tlm = :TELEMETRY, filename = "dynamic_tlm.txt")
      # Build hash of targets/packets
      packet_hash = {}
      packets.each do |packet|
        target_name = packet.target_name.upcase
        packet_hash[target_name] ||= {}
        packet_name = packet.packet_name.upcase
        packet_hash[target_name][packet_name] = packet
      end

      # Update Redis
      if cmd_or_tlm == :TELEMETRY
        update_store_telemetry(packet_hash, clear_old: false)
        update_store_item_map()
      else
        update_store_commands(packet_hash, clear_old: false)
      end

      # Build dynamic file for cmd_tlm
      configs = {}
      packets.each do |packet|
        target_name = packet.target_name.upcase
        configs[target_name] ||= ""
        config = configs[target_name]
        config << packet.to_config(cmd_or_tlm)
        config << "\n"
      end
      configs.each do |target_name, config|
        bucket_key = "#{@scope}/targets_modified/#{target_name}/cmd_tlm/#{filename}"
        client = Bucket.getClient()
        client.put_object(
          # Use targets_modified to save modifications
          # This keeps the original target clean (read-only)
          bucket: ENV['OPENC3_CONFIG_BUCKET'],
          key: bucket_key,
          body: config
        )
      end

      # Inform microservices of new topics
      # Need to tell loggers to log, and decom to decom
      # We do this for no downtime
      raw_topics = []
      decom_topics = []
      packets.each do |packet|
        if cmd_or_tlm == :TELEMETRY
          raw_topics << "#{@scope}__TELEMETRY__{#{@name}}__#{packet.packet_name.upcase}"
          decom_topics << "#{@scope}__DECOM__{#{@name}}__#{packet.packet_name.upcase}"
        else
          raw_topics << "#{@scope}__COMMAND__{#{@name}}__#{packet.packet_name.upcase}"
          decom_topics << "#{@scope}__DECOMCMD__{#{@name}}__#{packet.packet_name.upcase}"
        end
      end
      if cmd_or_tlm == :TELEMETRY
        Topic.write_topic("MICROSERVICE__#{@scope}__PACKETLOG__#{@name}", {'command' => 'ADD_TOPICS', 'topics' => raw_topics.as_json.to_json})
        add_topics_to_microservice("#{@scope}__PACKETLOG__#{@name}", raw_topics)
        Topic.write_topic("MICROSERVICE__#{@scope}__DECOMLOG__#{@name}", {'command' => 'ADD_TOPICS', 'topics' => decom_topics.as_json.to_json})
        add_topics_to_microservice("#{@scope}__DECOMLOG__#{@name}", decom_topics)
        Topic.write_topic("MICROSERVICE__#{@scope}__DECOM__#{@name}", {'command' => 'ADD_TOPICS', 'topics' => raw_topics.as_json.to_json})
        add_topics_to_microservice("#{@scope}__DECOM__#{@name}", raw_topics)
      else
        Topic.write_topic("MICROSERVICE__#{@scope}__COMMANDLOG__#{@name}", {'command' => 'ADD_TOPICS', 'topics' => raw_topics.as_json.to_json})
        add_topics_to_microservice("#{@scope}__COMMANDLOG__#{@name}", raw_topics)
        Topic.write_topic("MICROSERVICE__#{@scope}__DECOMCMDLOG__#{@name}", {'command' => 'ADD_TOPICS', 'topics' => decom_topics.as_json.to_json})
        add_topics_to_microservice("#{@scope}__DECOMCMDLOG__#{@name}", decom_topics)
      end
    end

    def add_topics_to_microservice(microservice_name, topics)
      model = MicroserviceModel.get_model(name: microservice_name, scope: @scope)
      model.topics.concat(topics)
      model.topics.uniq!
      model.ignore_changes = true # Don't restart the microservice right now
      model.update
    end

    def deploy_commmandlog_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__COMMANDLOG#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "CMD"],
          ["CYCLE_TIME", @cmd_log_cycle_time],
          ["CYCLE_SIZE", @cmd_log_cycle_size],
          ["BUFFER_DEPTH", @cmd_buffer_depth]
        ],
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_decomcmdlog_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__DECOMCMDLOG#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "DECOM"],
          ["CMD_OR_TLM", "CMD"],
          ["CYCLE_TIME", @cmd_decom_log_cycle_time],
          ["CYCLE_SIZE", @cmd_decom_log_cycle_size],
          ["BUFFER_DEPTH", @cmd_buffer_depth]
        ],
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_packetlog_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__PACKETLOG#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "TLM"],
          ["CYCLE_TIME", @tlm_log_cycle_time],
          ["CYCLE_SIZE", @tlm_log_cycle_size],
          ["BUFFER_DEPTH", @tlm_buffer_depth]
        ],
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_decomlog_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__DECOMLOG#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "DECOM"],
          ["CMD_OR_TLM", "TLM"],
          ["CYCLE_TIME", @tlm_decom_log_cycle_time],
          ["CYCLE_SIZE", @tlm_decom_log_cycle_size],
          ["BUFFER_DEPTH", @tlm_buffer_depth]
        ],
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_decom_microservice(target, gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__DECOM#{instance}__#{@name}"
      # Assume Ruby initially
      filename = 'decom_microservice.rb'
      work_dir = '/openc3/lib/openc3/microservices'
      if target.language == 'python'
        filename = 'decom_microservice.py'
        work_dir.sub!('openc3/lib', 'openc3/python')
        parent = nil
      end
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: [target.language, filename, microservice_name],
        work_dir: work_dir,
        topics: topics,
        target_names: [@name],
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_tsdb_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__TSDB#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["python", "tsdb_microservice.py", microservice_name],
        work_dir: "/openc3/python/openc3/microservices",
        topics: topics,
        plugin: @plugin,
        parent: nil,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_reducer_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__REDUCER#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "reducer_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["MAX_CPU_UTILIZATION", @reducer_max_cpu_utilization],
          ["BUFFER_DEPTH", @tlm_buffer_depth]
        ],
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_cleanup_microservice(gem_path, variables, instance = nil, parent = nil)
      microservice_name = "#{@scope}__CLEANUP#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "cleanup_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        plugin: @plugin,
        parent: parent,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_multi_microservice(gem_path, variables, instance = nil)
      if @children.length > 0
        microservice_name = "#{@scope}__MULTI#{instance}__#{@name}"
        microservice = MicroserviceModel.new(
          name: microservice_name,
          cmd: ["ruby", "multi_microservice.rb", *@children],
          work_dir: '/openc3/lib/openc3/microservices',
          plugin: @plugin,
          needs_dependencies: @needs_dependencies,
          shard: @shard,
          scope: @scope
        )
        microservice.create
        microservice.deploy(gem_path, variables)
        Logger.info "Configured microservice #{microservice_name}"
      end
    end

    def deploy_target_microservices(type, base_topic_list, topic_prefix)
      target_microservices = @target_microservices[type]
      if target_microservices
        # These are stand alone microservice(s) ... not part of MULTI
        if base_topic_list
          # Only create the microservice if there are topics
          # This prevents creation of DECOM with no TLM Packets (for example)
          deploy_count = 0
          all_topics = base_topic_list.dup

          # Figure out if there are individual packets assigned to this microservice
          target_microservices.sort! {|a, b| a.length <=> b.length}
          target_microservices.each_with_index do |packet_names, _index|
            topics = []
            packet_names.each do |packet_name|
              topics << "#{topic_prefix}__#{packet_name}"
            end
            topics = all_topics.dup if topics.length <= 0
            if topics.length > 0
              instance = nil
              instance = deploy_count unless deploy_count == 0
              yield topics, instance, nil
              deploy_count += 1
              topics.each do |topic|
                all_topics.delete(topic)
              end
            end
          end
          # If there are any topics (packets) left over that haven't been
          # explicitly handled above, spawn another microservice
          if all_topics.length > 0
            instance = nil
            instance = deploy_count unless deploy_count == 0
            yield all_topics, instance, nil
          end
        else
          # Do not spawn the microservice
          yield nil, nil, nil
        end
      else
        # Not a stand alone microservice ... part of MULTI
        yield base_topic_list, nil, @parent if not base_topic_list or base_topic_list.length > 0
      end
    end

    def deploy_microservices(gem_path, variables, system)
      command_topic_list = []
      decom_command_topic_list = []
      packet_topic_list = []
      decom_topic_list = []
      begin
        system.commands.packets(@name).each do |packet_name, _packet|
          command_topic_list << "#{@scope}__COMMAND__{#{@name}}__#{packet_name}"
          decom_command_topic_list << "#{@scope}__DECOMCMD__{#{@name}}__#{packet_name}"
        end
      rescue
        # No command packets for this target
      end
      begin
        system.telemetry.packets(@name).each do |packet_name, _packet|
          packet_topic_list << "#{@scope}__TELEMETRY__{#{@name}}__#{packet_name}"
          decom_topic_list  << "#{@scope}__DECOM__{#{@name}}__#{packet_name}"
        end
      rescue
        # No telemetry packets for this target
      end

      @parent = nil
      %w(DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP).each do |type|
        unless @target_microservices[type]
          @parent = "#{@scope}__MULTI__#{@name}"
          break
        end
      end

      unless command_topic_list.empty?
        # CommandLog Microservice
        deploy_target_microservices('COMMANDLOG', command_topic_list, "#{@scope}__COMMAND__{#{@name}}") do |topics, instance, parent|
          deploy_commmandlog_microservice(gem_path, variables, topics, instance, parent)
        end

        # DecomCmdLog Microservice
        deploy_target_microservices('DECOMCMDLOG', decom_command_topic_list, "#{@scope}__DECOMCMD__{#{@name}}") do |topics, instance, parent|
          deploy_decomcmdlog_microservice(gem_path, variables, topics, instance, parent)
        end
      end

      unless packet_topic_list.empty?
        # PacketLog Microservice
        deploy_target_microservices('PACKETLOG', packet_topic_list, "#{@scope}__TELEMETRY__{#{@name}}") do |topics, instance, parent|
          deploy_packetlog_microservice(gem_path, variables, topics, instance, parent)
        end

        # DecomLog Microservice
        deploy_target_microservices('DECOMLOG', decom_topic_list, "#{@scope}__DECOM__{#{@name}}") do |topics, instance, parent|
          deploy_decomlog_microservice(gem_path, variables, topics, instance, parent)
        end

        # Decommutation Microservice
        deploy_target_microservices('DECOM', packet_topic_list, "#{@scope}__TELEMETRY__{#{@name}}") do |topics, instance, parent|
          deploy_decom_microservice(system.targets[@name], gem_path, variables, topics, instance, parent)
        end

        # TSDB Microservice
        if ENV['OPENC3_TSDB_HOSTNAME'] and ENV['OPENC3_TSDB_QUERY_PORT'] and ENV['OPENC3_TSDB_INGEST_PORT'] and ENV['OPENC3_TSDB_USERNAME'] and ENV['OPENC3_TSDB_PASSWORD']
          deploy_target_microservices('TSDB', decom_topic_list, "#{@scope}__DECOM__{#{@name}}") do |topics, instance, parent|
            deploy_tsdb_microservice(gem_path, variables, topics, instance, parent)
          end
        end

        # Reducer Microservice
        unless @reducer_disable
          # TODO: Does Reducer even need a topic list?
          deploy_target_microservices('REDUCER', decom_topic_list, "#{@scope}__DECOM__{#{@name}}") do |topics, instance, parent|
            deploy_reducer_microservice(gem_path, variables, topics, instance, parent)
          end
        end
      end

      if @cmd_log_retain_time or @cmd_decom_log_retain_time or @tlm_log_retain_time or @tlm_decom_log_retain_time or
         @reduced_minute_log_retain_time or @reduced_hour_log_retain_time or @reduced_day_log_retain_time
        # Cleanup Microservice
        deploy_target_microservices('CLEANUP', nil, nil) do |_, instance, parent|
          deploy_cleanup_microservice(gem_path, variables, instance, parent)
        end
      end

      if @parent
        # Multi Microservice to parent other target microservices
        deploy_multi_microservice(gem_path, variables)
      end
    end

    def self.increment_telemetry_count(target_name, packet_name, count, scope:)
      result = Store.hincrby("#{scope}__TELEMETRYCNTS__{#{target_name}}", packet_name, count)
      if String === result
        return result.to_i
      else
        return result
      end
    end

    def self.get_all_telemetry_counts(target_name, scope:)
      result = {}
      get_all = Store.hgetall("#{scope}__TELEMETRYCNTS__{#{target_name}}")
      if Hash === get_all
        get_all.each do |key, value|
          result[key] = value.to_i
        end
      else
        return result
      end
    end

    def self.get_telemetry_count(target_name, packet_name, scope:)
      value = Store.hget("#{scope}__TELEMETRYCNTS__{#{target_name}}", packet_name)
      if String === value
        return value.to_i
      elsif value.nil?
        return 0 # Return 0 if the key doesn't exist
      else
        return value
      end
    end

    def self.get_telemetry_counts(target_packets, scope:)
      result = []
      if $openc3_redis_cluster
        # No pipelining for cluster mode
        # because it requires using the same shard for all keys
        target_packets.each do |target_name, packet_name|
          target_name = target_name.upcase
          packet_name = packet_name.upcase
          result << Store.hget("#{scope}__TELEMETRYCNTS__{#{target_name}}", packet_name)
        end
      else
        result = Store.redis_pool.pipelined do
          target_packets.each do |target_name, packet_name|
            target_name = target_name.upcase
            packet_name = packet_name.upcase
            Store.hget("#{scope}__TELEMETRYCNTS__{#{target_name}}", packet_name)
          end
        end
      end
      counts = []
      result.each do |count|
        if count
          counts << count.to_i
        else
          counts << 0
        end
      end
      return counts
    end

    def self.increment_command_count(target_name, packet_name, count, scope:)
      result = Store.hincrby("#{scope}__COMMANDCNTS__{#{target_name}}", packet_name, count)
      if String === result
        return result.to_i
      else
        return result
      end
    end

    def self.get_all_command_counts(target_name, scope:)
      result = {}
      get_all = Store.hgetall("#{scope}__COMMANDCNTS__{#{target_name}}")
      if Hash === get_all
        get_all.each do |key, value|
          result[key] = value.to_i
        end
      else
        return result
      end
    end

    def self.get_command_count(target_name, packet_name, scope:)
      value = Store.hget("#{scope}__COMMANDCNTS__{#{target_name}}", packet_name)
      if String === value
        return value.to_i
      elsif value.nil?
        return 0 # Return 0 if the key doesn't exist
      else
        return value
      end
    end

    def self.get_command_counts(target_packets, scope:)
      result = []
      if $openc3_redis_cluster
        # No pipelining for cluster mode
        # because it requires using the same shard for all keys
        target_packets.each do |target_name, packet_name|
          target_name = target_name.upcase
          packet_name = packet_name.upcase
          result << Store.hget("#{scope}__COMMANDCNTS__{#{target_name}}", packet_name)
        end
      else
        result = Store.redis_pool.pipelined do
          target_packets.each do |target_name, packet_name|
            target_name = target_name.upcase
            packet_name = packet_name.upcase
            Store.hget("#{scope}__COMMANDCNTS__{#{target_name}}", packet_name)
          end
        end
      end
      counts = []
      result.each do |count|
        if count
          counts << count.to_i
        else
          counts << 0
        end
      end
      return counts
    end
  end
end
