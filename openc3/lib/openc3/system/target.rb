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

require 'openc3/config/config_parser'
require 'pathname'

module OpenC3
  # Target encapsulates the information about a OpenC3 target. Targets are
  # accessed through interfaces and have command and telemetry definition files
  # which define their access.
  class Target
    # @return [String] Name of the target. This can be overridden when
    #   the system processes the target.
    attr_reader :name

    # @return [String] Programming language. Must be 'ruby' or 'python'.
    attr_reader :language

    # @return [Array<String>] List of filenames that must be required by Ruby
    #   before parsing the command and telemetry definitions for this target
    attr_reader :requires

    # @return [Array<String>] List of parameters that should be ignored. Tools
    #   which access this target should not display or manipulate these
    #   parameters.
    attr_reader :ignored_parameters

    # @return [Array<String>] List of items that should be ignored. Tools
    #   which access this target should not display or manipulate these
    #   items.
    attr_reader :ignored_items

    # @return [Array<String>] List of configuration files which define the
    #   commands and telemetry for this target
    attr_reader :cmd_tlm_files

    # @return [String] Target filename for this target
    attr_reader :filename

    # @return [String] The directory which contains this target
    attr_reader :dir

    # @return [Interface] The interface used to access the target
    attr_accessor :interface

    # @return [Integer] The number of command packets send to this target
    attr_accessor :cmd_cnt

    # @return [Integer] The number of telemetry packets received from this target
    attr_accessor :tlm_cnt

    # @return [String] Id of the target configuration
    attr_accessor :id

    # Creates a new target by processing the target.txt file in the directory
    # given by the path joined with the target_name. Records all the command
    # and telemetry definition files found in the targets cmd_tlm directory.
    # System uses this list and processes them using PacketConfig.
    #
    # @param target_name [String] The name of the target.
    # @param path [String] Path to the target directory
    # @param gem_path [String] Path to the gem file or nil if there is no gem
    def initialize(target_name, path, gem_path = nil)
      @language = 'ruby'
      @requires = []
      @ignored_parameters = []
      @ignored_items = []
      @cmd_tlm_files = []
      @interface = nil
      @routers = []
      @cmd_cnt = 0
      @tlm_cnt = 0
      @name = target_name.clone.upcase.freeze
      get_target_dir(path, gem_path)
      process_target_config_file()

      # If target.txt didn't specify specific cmd/tlm files then add everything
      if @cmd_tlm_files.empty?
        @cmd_tlm_files = add_all_cmd_tlm()
      else
        add_cmd_tlm_partials()
      end
    end

    # Parses the target configuration file
    #
    # @param filename [String] The target configuration file to parse
    def process_file(filename)
      Logger.instance.info "Processing target definition in file '#{filename}'"
      parser = ConfigParser.new("https://docs.openc3.com/docs/configuration/target")
      parser.parse_file(filename) do |keyword, parameters|
        case keyword
        when 'LANGUAGE'
          usage = "#{keyword} <ruby | python>"
          parser.verify_num_parameters(1, 1, usage)
          @language = parameters[0].downcase

        when 'REQUIRE'
          usage = "#{keyword} <FILENAME>"
          parser.verify_num_parameters(1, 1, usage)
          filename = File.join(@dir, 'lib', parameters[0])
          begin
            # Require absolute path to file in target lib folder. Prevents name
            # conflicts at the require step
            OpenC3.disable_warnings do
              OpenC3.require_file(filename, false)
            end
          rescue LoadError
            begin
              # If we couldn't load at the target/lib level check everywhere
              OpenC3.disable_warnings do
                filename = parameters[0]
                OpenC3.require_file(parameters[0])
              end
            rescue Exception => e
              raise parser.error(e.formatted)
            end
          rescue Exception => e
            raise parser.error(e.formatted)
          end

          # This code resolves any relative paths to absolute before putting into the @requires array
          unless Pathname.new(filename).absolute?
            $:.each do |search_path|
              test_filename = File.join(search_path, filename).gsub("\\", "/")
              if File.exist?(test_filename)
                filename = test_filename
                break
              end
            end
          end

          @requires << filename

        when 'IGNORE_PARAMETER', 'IGNORE_ITEM'
          usage = "#{keyword} <#{keyword.split('_')[1]} NAME>"
          parser.verify_num_parameters(1, 1, usage)
          @ignored_parameters << parameters[0].upcase if keyword.include?("PARAMETER")
          @ignored_items << parameters[0].upcase if keyword.include?("ITEM")

        when 'COMMANDS', 'TELEMETRY'
          usage = "#{keyword} <FILENAME>"
          parser.verify_num_parameters(1, 1, usage)
          filename = File.join(@dir, 'cmd_tlm', parameters[0])
          raise parser.error("#{filename} not found") unless File.exist?(filename)

          @cmd_tlm_files << filename

        when 'CMD_UNIQUE_ID_MODE', 'TLM_UNIQUE_ID_MODE'
          # Deprecated - Now autodetected

        else
          # blank lines will have a nil keyword and should not raise an exception
          raise parser.error("Unknown keyword '#{keyword}'") if keyword
        end # case keyword
      end
    end

    def as_json(*_a)
      config = {}
      config['name'] = @name
      config['requires'] = @requires
      config['ignored_parameters'] = @ignored_parameters
      config['ignored_items'] = @ignored_items
      config['cmd_tlm_files'] = @cmd_tlm_files
      config['id'] = @id
      config
    end

    protected

    # Get the target directory and add the target's lib folder to the
    # search path if it exists
    def get_target_dir(path, gem_path)
      if gem_path
        @dir = gem_path
      else
        @dir = File.join(path, @name)
      end
      @dir.gsub!("\\", '/')
      lib_dir = File.join(@dir, 'lib')
      OpenC3.add_to_search_path(lib_dir, false) if File.exist?(lib_dir)
      proc_dir = File.join(@dir, 'procedures')
      OpenC3.add_to_search_path(proc_dir, false) if File.exist?(proc_dir)
    end

    # Process the target's configuration file if it exists
    def process_target_config_file
      @filename = File.join(@dir, 'target.txt')
      if File.exist?(@filename)
        process_file(@filename)
      else
        @filename = nil
      end
      id_filename = File.join(@dir, 'target_id.txt')
      if File.exist?(id_filename)
        File.open(id_filename, 'rb') { |file| @id = file.read.strip }
      else
        @id = nil
      end
    end

    # Automatically add all command and telemetry definitions to the list
    def add_all_cmd_tlm
      cmd_tlm_files = []
      if Dir.exist?(File.join(@dir, 'cmd_tlm'))
        # Grab All *.txt files in the cmd_tlm folder and subfolders
        Dir[File.join(@dir, 'cmd_tlm', '**', '*.txt')].each do |filename|
          cmd_tlm_files << filename
        end
        # Grab All *.xtce files in the cmd_tlm folder and subfolders
        Dir[File.join(@dir, 'cmd_tlm', '**', '*.xtce')].each do |filename|
          cmd_tlm_files << filename
        end
      end
      cmd_tlm_files.sort!
    end

    # Make sure all partials are included in the cmd_tlm list for the hashing sum calculation
    def add_cmd_tlm_partials
      partial_files = []
      if Dir.exist?(File.join(@dir, 'cmd_tlm'))
        # Grab all _*.txt files in the cmd_tlm folder and subfolders
        Dir[File.join(@dir, 'cmd_tlm', '**', '_*.txt')].each do |filename|
          partial_files << filename
        end
      end
      partial_files.sort!
      @cmd_tlm_files.concat(partial_files)
      @cmd_tlm_files.uniq!
    end
  end
end
