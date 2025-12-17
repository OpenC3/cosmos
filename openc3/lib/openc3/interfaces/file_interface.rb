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

require 'openc3/interfaces/interface'
require 'openc3/config/config_parser'
require 'openc3/utilities/logger'
require 'thread'
require 'listen'
require 'fileutils'
require 'zlib'

module OpenC3
  class FileInterface < Interface
    attr_reader :filename

    # @param command_write_folder [String] Folder to write command files to - Set to nil to disallow writes
    # @param telemetry_read_folder [String] Folder to read telemetry files from - Set to nil to disallow reads
    # @param telemetry_archive_folder [String] Folder to move read telemetry files to - Set to DELETE to delete files
    # @param file_read_size [Integer] Number of bytes to read from the file at a time
    # @param stored [Boolean] Whether to set stored flag on read telemetry
    # @param protocol_type [String] Name of the protocol to use
    #   with this interface
    # @param protocol_args [Array<String>] Arguments to pass to the protocol
    def initialize(
      command_write_folder,
      telemetry_read_folder,
      telemetry_archive_folder,
      file_read_size = 65536,
      stored = true,
      protocol_type = nil,
      *protocol_args
    )
      super()

      @protocol_type = ConfigParser.handle_nil(protocol_type)
      @protocol_args = protocol_args
      if @protocol_type
        protocol_class_name = protocol_type.to_s.capitalize << 'Protocol'
        klass = OpenC3.require_class(protocol_class_name.class_name_to_filename)
        add_protocol(klass, protocol_args, :PARAMS)
      end

      @command_write_folder = ConfigParser.handle_nil(command_write_folder)
      @telemetry_read_folder = ConfigParser.handle_nil(telemetry_read_folder)
      @telemetry_archive_folder = ConfigParser.handle_nil(telemetry_archive_folder)
      @file_read_size = Integer(file_read_size)
      @stored = ConfigParser.handle_true_false(stored)

      @read_allowed = false unless @telemetry_read_folder
      @write_allowed = false unless @command_write_folder
      @write_raw_allowed = false unless @command_write_folder

      @file = nil
      @filename = ''
      @listener = nil
      @connected = false
      @extension = ".bin"
      @label = "command"
      @queue = Queue.new
      @polling = false
      @recursive = false
      @throttle = nil
      @discard_file_header_bytes = nil
      @sleeper = nil
    end

    def connect
      super() # Reset the protocols

      if @telemetry_read_folder
        @listener = Listen.to(@telemetry_read_folder, force_polling: @polling) do |modified, added, removed|
          @queue << added if added
        end
        @listener.start # starts a listener thread - does not block
      end
      @connected = true
    end

    def connected?
      return @connected
    end

    def disconnect
      @file.close if @file and not @file.closed?
      @file = nil
      @sleeper.cancel if @sleeper
      @listener.stop if @listener
      @listener = nil
      @queue << nil
      super()
      @connected = false
    end

    def read_interface
      while true
        if @file
          # Read more data from existing file
          data = @file.read(@file_read_size)
          # Throttle after each read size
          if @throttle and @sleeper.sleep(@throttle)
            return nil, nil
          end
          if data and data.length > 0
            read_interface_base(data, nil)
            return data, nil
          else
            finish_file()
          end
        end

        # Find the next file to read
        @filename = get_next_telemetry_file()
        if @filename
          if File.extname(@filename) == ".gz"
            @file = Zlib::GzipReader.open(@filename)
          else
            @file = File.open(@filename, "rb")
          end
          if @discard_file_header_bytes
            @file.read(@discard_file_header_bytes)
          end
          next
        end

        # Wait for a file to read
        result = @queue.pop
        return nil, nil unless result
      end
    end

    def write_interface(data, extra = nil)
      # Write this data into its own file
      File.open(create_unique_filename(), 'wb') do |file|
        file.write(data)
      end

      write_interface_base(data, extra)
      return data, extra
    end

    def convert_data_to_packet(data, extra = nil)
      packet = super(data, extra)
      if packet
        packet.stored = @stored
      end
      return packet
    end

    # Supported Options
    # LABEL - Label to add to written files
    # EXTENSION - Extension to add to written files
    # (see Interface#set_option)
    def set_option(option_name, option_values)
      super(option_name, option_values)
      case option_name.upcase
      when 'LABEL'
        @label = option_values[0]
      when 'EXTENSION'
        @extension = option_values[0]
      when 'POLLING'
        @polling = ConfigParser.handle_true_false(option_values[0])
      when 'RECURSIVE'
        @recursive = ConfigParser.handle_true_false(option_values[0])
      when 'THROTTLE'
        @throttle = Float(option_values[0])
        @sleeper = Sleeper.new
      when 'DISCARD_FILE_HEADER_BYTES'
        @discard_file_header_bytes = Integer(option_values[0])
      end
    end

    def finish_file
      path = @file.path
      @file.close
      @file = nil

      # Archive (or DELETE) complete file
      if @telemetry_archive_folder == "DELETE"
        FileUtils.rm(path)
      else
        FileUtils.mv(path, @telemetry_archive_folder)
      end
    end

    def get_next_telemetry_file
      files = []
      if @recursive
        files = Dir.glob("#{@telemetry_read_folder}/**/*")
      else
        files = Dir.glob("#{@telemetry_read_folder}/*")
      end
      # Dir.glob includes directories, so filter them out
      files = files.sort.select { |fn| File.file?(fn) }
      return files[0]
    end

    def create_unique_filename
      # Create a filename that doesn't exist
      attempt = nil
      while true
        filename = File.join(@command_write_folder, File.build_timestamped_filename([@label, attempt], @extension))
        if File.exist?(filename)
          attempt ||= 0
          attempt += 1
        else
          return filename
        end
      end
    end

    def details
      result = super()
      result['command_write_folder'] = @command_write_folder
      result['telemetry_read_folder'] = @telemetry_read_folder
      result['telemetry_archive_folder'] = @telemetry_archive_folder
      result['file_read_size'] = @file_read_size
      result['stored'] = @stored
      result['filename'] = @filename
      result['extension'] = @extension
      result['label'] = @label
      result['queue_length'] = @queue.length
      result['polling'] = @polling
      result['recursive'] = @recursive
      result['throttle'] = @throttle
      result['discard_file_header_bytes'] = @discard_file_header_bytes
      return result
    end
  end
end
