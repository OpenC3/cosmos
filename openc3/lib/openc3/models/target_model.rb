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
require 'openc3/models/cvt_model'
require 'openc3/models/microservice_model'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/config_topic'
require 'openc3/system'
require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'
require 'openc3/utilities/zip'
require 'fileutils'
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
      targets.each { |target_name, target| target['modified'] = false }

      if ENV['OPENC3_LOCAL_MODE']
        modified_targets = OpenC3::LocalMode.modified_targets(scope: scope)
        modified_targets.each do |target_name|
          targets[target_name]['modified'] = true if targets[target_name]
        end
      else
        modified_targets = Bucket.getClient().list_files(bucket: ENV['OPENC3_CONFIG_BUCKET'], path: "DEFAULT/targets_modified/", only_directories: true)
        modified_targets.each do |target_name|
          # A target could have been deleted without removing the modified files
          # Thus we have to check for the existance of the target_name key
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
      tmp_dir = Dir.mktmpdir
      zip_filename = File.join(tmp_dir, "#{target_name}.zip")
      Zip.continue_on_exists_proc = true
      zip = Zip::File.open(zip_filename, Zip::File::CREATE)

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

    # @return [Array] Array of all the packet names
    def self.packet_names(target_name, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name}" unless VALID_TYPES.include?(type)
      # If the key doesn't exist or if there are no packets we return empty array
      Store.hkeys("#{scope}__openc3#{type.to_s.downcase}__#{target_name}").sort
    end

    # @return [Hash] Packet hash or raises an exception
    def self.packet(target_name, packet_name, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name} #{packet_name}" unless VALID_TYPES.include?(type)

      # Assume it exists and just try to get it to avoid an extra call to Store.exist?
      json = Store.hget("#{scope}__openc3#{type.to_s.downcase}__#{target_name}", packet_name)
      raise "Packet '#{target_name} #{packet_name}' does not exist" if json.nil?

      JSON.parse(json, :allow_nan => true, :create_additions => true)
    end

    # @return [Array>Hash>] All packet hashes under the target_name
    def self.packets(target_name, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name}" unless VALID_TYPES.include?(type)
      raise "Target '#{target_name}' does not exist" unless get(name: target_name, scope: scope)

      result = []
      packets = Store.hgetall("#{scope}__openc3#{type.to_s.downcase}__#{target_name}")
      packets.sort.each do |packet_name, packet_json|
        result << JSON.parse(packet_json, :allow_nan => true, :create_additions => true)
      end
      result
    end

    # @return [Array>Hash>] All packet hashes under the target_name
    def self.all_packet_name_descriptions(target_name, type: :TLM, scope:)
      self.packets(target_name, type: type, scope: scope).map! { |hash| hash.slice("packet_name", "description") }
    end

    def self.set_packet(target_name, packet_name, packet, type: :TLM, scope:)
      raise "Unknown type #{type} for #{target_name} #{packet_name}" unless VALID_TYPES.include?(type)

      begin
        Store.hset("#{scope}__openc3#{type.to_s.downcase}__#{target_name}", packet_name, JSON.generate(packet.as_json(:allow_nan => true)))
      rescue JSON::GeneratorError => err
        Logger.error("Invalid text present in #{target_name} #{packet_name} #{type.to_s.downcase} packet")
        raise err
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
        # 'does not exist' not gramatically correct but we use it in every other exception
        raise "Item(s) #{not_found.join(', ')} does not exist"
      end
      found
    end

    # @return [Hash{String => Array<Array<String, String, String>>}]
    def self.limits_groups(scope:)
      groups = Store.hgetall("#{scope}__limits_groups")
      if groups
        groups.map { |group, items| [group, JSON.parse(items, :allow_nan => true, :create_additions => true)] }.to_h
      else
        {}
      end
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
      cleanup_poll_time: 900,
      needs_dependencies: false,
      target_microservices: {'REDUCER' => [[]]},
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
      @bucket = Bucket.getClient()
      @children = []
    end

    def as_json(*a)
      {
        'name' => @name,
        'folder_name' => @folder_name,
        'requires' => @requires,
        'ignored_parameters' => @ignored_parameters,
        'ignored_items' => @ignored_items,
        'limits_groups' => @limits_groups,
        'cmd_tlm_files' => @cmd_tlm_files,
        'cmd_unique_id_mode' => cmd_unique_id_mode,
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
        'target_microservices' => @target_microservices.as_json(:allow_nan => true)
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
          begin
            OpenC3.set_working_dir(File.dirname(filename)) do
              data = ERB.new(data, trim_mode: "-").result(binding.set_variables(variables)) if data.is_printable? and File.basename(filename)[0] != '_'
            end
          rescue => error
            raise "ERB error parsing: #{filename}: #{error.formatted}"
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
        FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
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

      ConfigTopic.write({ kind: 'deleted', type: 'target', name: @name, plugin: @plugin }, scope: @scope)
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

      begin
        OpenC3.set_working_dir(File.dirname(path)) do
          return ERB.new(File.read(path), trim_mode: "-").result(b)
        end
      rescue => error
        raise "ERB error parsing: #{path}: #{error.formatted}"
      end
    end

    def build_target_archive(temp_dir, target_folder)
      target_files = []
      Find.find(target_folder) { |file| target_files << file }
      target_files.sort!
      hash = OpenC3.hash_files(target_files, nil, 'SHA256').hexdigest
      File.open(File.join(target_folder, 'target_id.txt'), 'wb') { |file| file.write(hash) }
      key = "#{@scope}/targets/#{@name}/target_id.txt"
      @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key, body: hash)

      # Create target archive zip file
      prefix = File.dirname(target_folder) + '/'
      output_file = File.join(temp_dir, @name + '_' + hash + '.zip')
      Zip.continue_on_exists_proc = true
      Zip::File.open(output_file, Zip::File::CREATE) do |zipfile|
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
        bucket_key = key = "#{@scope}/target_archives/#{@name}/#{@name}_#{hash}.zip"
        @bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: bucket_key, body: file)
      end
    end

    def update_store(system)
      target = system.targets[@name]

      # Add in the information from the target and update
      @requires = target.requires
      @ignored_parameters = target.ignored_parameters
      @ignored_items = target.ignored_items
      @cmd_tlm_files = target.cmd_tlm_files
      @cmd_unique_id_mode = target.cmd_unique_id_mode
      @tlm_unique_id_mode = target.tlm_unique_id_mode
      @id = target.id
      @limits_groups = system.limits.groups.keys
      update()

      # Store Packet Definitions
      system.telemetry.all.each do |target_name, packets|
        Store.del("#{@scope}__openc3tlm__#{target_name}")
        packets.each do |packet_name, packet|
          Logger.info "Configuring tlm packet: #{target_name} #{packet_name}"
          begin
            Store.hset("#{@scope}__openc3tlm__#{target_name}", packet_name, JSON.generate(packet.as_json(:allow_nan => true)))
          rescue JSON::GeneratorError => err
            Logger.error("Invalid text present in #{target_name} #{packet_name} tlm packet")
            raise err
          end
          json_hash = Hash.new
          packet.sorted_items.each do |item|
            json_hash[item.name] = nil
          end
          CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: @scope)
        end
      end
      system.commands.all.each do |target_name, packets|
        Store.del("#{@scope}__openc3cmd__#{target_name}")
        packets.each do |packet_name, packet|
          Logger.info "Configuring cmd packet: #{target_name} #{packet_name}"
          begin
            Store.hset("#{@scope}__openc3cmd__#{target_name}", packet_name, JSON.generate(packet.as_json(:allow_nan => true)))
          rescue JSON::GeneratorError => err
            Logger.error("Invalid text present in #{target_name} #{packet_name} cmd packet")
            raise err
          end
        end
      end
      # Store Limits Groups
      system.limits.groups.each do |group, items|
        begin
          Store.hset("#{@scope}__limits_groups", group, JSON.generate(items))
        rescue JSON::GeneratorError => err
          Logger.error("Invalid text present in #{group} limits group")
          raise err
        end
      end
      # Merge in Limits Sets
      sets = Store.hgetall("#{@scope}__limits_sets")
      sets ||= {}
      system.limits.sets.each do |set|
        sets[set.to_s] = "false" unless sets.key?(set.to_s)
      end
      Store.hmset("#{@scope}__limits_sets", *sets)

      return system
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
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_decom_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__DECOM#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "decom_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        topics: topics,
        target_names: [@name],
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_reducer_microservice(gem_path, variables, topics, instance = nil, parent = nil)
      microservice_name = "#{@scope}__REDUCER#{instance}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        folder_name: @folder_name,
        cmd: ["ruby", "reducer_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        topics: topics,
        plugin: @plugin,
        parent: parent,
        needs_dependencies: @needs_dependencies,
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
          target_names: [@name],
          plugin: @plugin,
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
        if base_topic_list
          deploy_count = 0
          all_topics = base_topic_list.dup
          target_microservices.sort! {|a, b| a.length <=> b.length}
          target_microservices.each_with_index do |packet_names, index|
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
          if all_topics.length > 0
            instance = nil
            instance = deploy_count unless deploy_count == 0
            yield all_topics, instance, nil
          end
        else
          yield nil, nil, nil
        end
      else
        yield base_topic_list, nil, @parent if not base_topic_list or base_topic_list.length > 0
      end
    end

    def deploy_microservices(gem_path, variables, system)
      command_topic_list = []
      decom_command_topic_list = []
      packet_topic_list = []
      decom_topic_list = []
      reduced_topic_list = []
      begin
        system.commands.packets(@name).each do |packet_name, packet|
          command_topic_list << "#{@scope}__COMMAND__{#{@name}}__#{packet_name}"
          decom_command_topic_list << "#{@scope}__DECOMCMD__{#{@name}}__#{packet_name}"
        end
      rescue
        # No command packets for this target
      end
      begin
        system.telemetry.packets(@name).each do |packet_name, packet|
          packet_topic_list << "#{@scope}__TELEMETRY__{#{@name}}__#{packet_name}"
          decom_topic_list  << "#{@scope}__DECOM__{#{@name}}__#{packet_name}"
          reduced_topic_list << "#{@scope}__REDUCED_MINUTE__{#{@name}}__#{packet_name}"
          reduced_topic_list << "#{@scope}__REDUCED_HOUR__{#{@name}}__#{packet_name}"
          reduced_topic_list << "#{@scope}__REDUCED_DAY__{#{@name}}__#{packet_name}"
        end
      rescue
        # No telemetry packets for this target
      end
      # It's ok to call initialize_streams with an empty array
      Topic.initialize_streams(command_topic_list)
      Topic.initialize_streams(decom_command_topic_list)
      Topic.initialize_streams(packet_topic_list)
      Topic.initialize_streams(decom_topic_list)
      Topic.initialize_streams(reduced_topic_list)

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
          deploy_decom_microservice(gem_path, variables, topics, instance, parent)
        end

        # Reducer Microservice
        deploy_target_microservices('REDUCER', decom_topic_list, "#{@scope}__DECOM__{#{@name}}") do |topics, instance, parent|
          deploy_reducer_microservice(gem_path, variables, topics, instance, parent)
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
  end
end
