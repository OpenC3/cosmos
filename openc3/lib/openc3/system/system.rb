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
require 'openc3/config/config_parser'
require 'openc3/packets/packet_config'
require 'openc3/packets/commands'
# TODO: System requires telemetry and Telemetry require system ... circular reference
require 'openc3/packets/telemetry'
require 'openc3/packets/limits'
require 'openc3/system/target'
require 'openc3/utilities/bucket'
require 'openc3/utilities/zip'
require 'openc3/topics/limits_event_topic'
require 'fileutils'

module OpenC3
  class System
    # @return [Hash<String,Target>] Hash of all the known targets
    instance_attr_reader :targets

    # @return [PacketConfig] Access to the packet configuration
    instance_attr_reader :packet_config

    # @return [Commands] Access to the command definition
    instance_attr_reader :commands

    # @return [Telemetry] Access to the telemetry definition
    instance_attr_reader :telemetry

    # @return [Limits] Access to the limits definition
    instance_attr_reader :limits

    # Variable that holds the singleton instance
    @@instance = nil

    # Mutex used to ensure that only one instance of System is created
    @@instance_mutex = Mutex.new

    # The current limits set
    @@limits_set = nil

    # Callbacks to call once @@instance is created
    @@post_instance_callbacks = []

    # @return [Symbol] The current limits_set of the system returned from Redis
    def self.limits_set
      unless @@limits_set
        @@limits_set = LimitsEventTopic.current_set(scope: $openc3_scope).to_s.intern
      end
      @@limits_set
    end

    def self.limits_set=(value)
      @@limits_set = value.to_s.intern
    end

    def self.add_post_instance_callback(callback)
      if @@instance
        callback.call()
      else
        @@post_instance_callbacks << callback
      end
    end

    def self.setup_targets(target_names, base_dir, scope:)
      # Nothing to do if there are no targets
      return if target_names.nil? or target_names.length == 0
      if @@instance.nil?
        FileUtils.mkdir_p("#{base_dir}/targets")
        bucket = Bucket.getClient()
        target_names.each do |target_name|
          # Retrieve bucket/targets/target_name/target_id.zip
          zip_path = "#{base_dir}/targets/#{target_name}_current.zip"
          FileUtils.mkdir_p(File.dirname(zip_path))
          bucket_key = "#{scope}/target_archives/#{target_name}/#{target_name}_current.zip"
          Logger.info("Retrieving #{bucket_key} from targets bucket")
          bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: bucket_key, path: zip_path)
          Zip::File.open(zip_path) do |zip_file|
            zip_file.each do |entry|
              path = File.join("#{base_dir}/targets", entry.name)
              FileUtils.mkdir_p(File.dirname(path))
              zip_file.extract(entry, path) unless File.exist?(path)
            end
          end

          # Now add any modifications in targets_modified/TARGET/cmd_tlm
          # This adds support for remembering dynamically created packets
          # target.txt must be configured to either use all files in cmd_tlm folder (default)
          # or have a predetermined empty file like dynamic_tlm.txt
          bucket_path = "#{scope}/targets_modified/#{target_name}/cmd_tlm"
          _, files = bucket.list_files(bucket: ENV['OPENC3_CONFIG_BUCKET'], path: bucket_path)
          files.each do |file|
            bucket_key = File.join(bucket_path, file['name'])
            local_path = "#{base_dir}/targets/#{target_name}/cmd_tlm/#{file['name']}"
            bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: bucket_key, path: local_path)
          end
        end

        # Build System from targets
        System.instance(target_names, "#{base_dir}/targets")
      end
    end

    # Get the singleton instance of System
    #
    # @param target_names [Array of target_names]
    # @param target_config_dir Directory where target config folders are
    # @return [System] The System singleton
    def self.instance(target_names = nil, target_config_dir = nil)
      return @@instance if @@instance
      raise "System.instance parameters are required on first call" unless target_names and target_config_dir

      @@instance_mutex.synchronize do
        return @@instance if @@instance
        @@instance ||= self.new(target_names, target_config_dir)
        @@post_instance_callbacks.each do |callback|
          callback.call
        end
        return @@instance
      end
    end

    # Dynamically add packets to the system instance
    #
    # @param dynamic_packets [Array of packets]
    # @param cmd_or_tlm [Symbol] :COMMAND or :TELEMETRY
    # @param affect_ids [Boolean] Whether to affect packet id lookup or not
    def self.dynamic_update(dynamic_packets, cmd_or_tlm = :TELEMETRY, affect_ids: false)
      dynamic_packets.each do |packet|
        if cmd_or_tlm == :TELEMETRY
          @@instance.telemetry.dynamic_add_packet(packet, affect_ids: affect_ids)
        else
          @@instance.commands.dynamic_add_packet(packet, affect_ids: affect_ids)
        end
      end
    end

    # Create a new System object.
    #
    # @param target_names [Array of target names]
    # @param target_config_dir Directory where target config folders are
    def initialize(target_names, target_config_dir)
      OpenC3.add_to_search_path(target_config_dir, true) if target_config_dir
      @targets = {}
      @packet_config = PacketConfig.new
      @commands = Commands.new(@packet_config)
      @telemetry = Telemetry.new(@packet_config)
      @limits = Limits.new(@packet_config)
      target_names.each { |target_name| add_target(target_name, target_config_dir) }
    end

    def add_target(target_name, target_config_dir)
      parser = ConfigParser.new
      folder_name = File.join(target_config_dir, target_name)
      raise parser.error("Target folder must exist '#{folder_name}'.") unless Dir.exist?(folder_name)

      target = Target.new(target_name, target_config_dir)
      @targets[target.name] = target
      errors = [] # Store all errors processing the cmd_tlm files
      target.cmd_tlm_files.each do |cmd_tlm_file|
        @packet_config.process_file(cmd_tlm_file, target.name, target.language)
      rescue Exception => e
        errors << "Error processing #{cmd_tlm_file}:\n#{e.message}"
      end
      unless errors.empty?
        raise errors.join("\n")
      end
    end
  end
end
