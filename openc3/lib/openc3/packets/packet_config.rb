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
require 'openc3/packets/packet'
require 'openc3/packets/parsers/packet_parser'
require 'openc3/packets/parsers/packet_item_parser'
require 'openc3/packets/parsers/limits_parser'
require 'openc3/packets/parsers/limits_response_parser'
require 'openc3/packets/parsers/state_parser'
require 'openc3/packets/parsers/format_string_parser'
require 'openc3/packets/parsers/processor_parser'
require 'openc3/packets/parsers/xtce_parser'
require 'openc3/packets/parsers/xtce_converter'
require 'openc3/utilities/python_proxy'
require 'openc3/conversions'
require 'openc3/processors'
require 'openc3/accessors'
require 'nokogiri'
require 'ostruct'
require 'fileutils'
require 'tempfile'

module OpenC3
  # Reads a command or telemetry configuration file and builds a hash of packets.
  class PacketConfig
    # @return [String] The name of this configuration. To be used by higher
    #   level classes to store information about the current PacketConfig.
    attr_accessor :name

    # @return [Hash<String=>Packet>] Hash of all the telemetry packets
    #   keyed by the packet name.
    attr_reader :telemetry

    # @return [Hash<String=>Packet>] Hash of all the command packets
    #   keyed by the packet name.
    attr_reader :commands

    # @return [Hash<String=>Array(String, String, String)>] Hash of all the
    #   limits groups keyed by the group name. The value is a three element
    #   array consisting of the target_name, packet_name, and item_name.
    attr_reader :limits_groups

    # @return [Array<Symbol>] The defined limits sets for all items in the
    #   packet. This will always include :DEFAULT.
    attr_reader :limits_sets

    # @return [Array<String>] Array of strings listing all the warnings
    #   that were created while parsing the configuration file.
    attr_reader :warnings

    # @return [Hash<String=>Hash<String=>Array(Packet)>>] Hash of hashes keyed
    #   first by the target name and then by the item name. This results in an
    #   array of packets containing that target and item. This structure is
    #   used to perform lookups when the packet and item are known but the
    #   packet is not.
    attr_reader :latest_data

    # @return [Hash<String>=>Hash<Array>=>Packet] Hash keyed by target name
    # that returns a hash keyed by an array of id values. The id values resolve to the packet
    # defined by that identification. Command version
    attr_reader :cmd_id_value_hash

    # @return [Hash<String>=>Hash<Array>=>Packet] Hash keyed by target name
    # that returns a hash keyed by an array of id values. The id values resolve to the packet
    # defined by that identification. Telemetry version
    attr_reader :tlm_id_value_hash

    # @return [String] Language of current target (ruby or python)
    attr_reader :language

    COMMAND = "Command"
    TELEMETRY = "Telemetry"

    def initialize
      @name = nil
      @telemetry = {}
      @commands = {}
      @limits_groups = {}
      @limits_sets = [:DEFAULT]
      # Hash of Hashes. First index by target name and then item name.
      # Returns an array of packets with that target and item.
      @latest_data = {}
      @warnings = []
      @cmd_id_value_hash = {}
      @tlm_id_value_hash = {}

      # Create unknown packets
      @commands['UNKNOWN'] = {}
      @commands['UNKNOWN']['UNKNOWN'] = Packet.new('UNKNOWN', 'UNKNOWN', :BIG_ENDIAN)
      @telemetry['UNKNOWN'] = {}
      @telemetry['UNKNOWN']['UNKNOWN'] = Packet.new('UNKNOWN', 'UNKNOWN', :BIG_ENDIAN)

      reset_processing_variables()
    end

    #########################################################################
    # The following methods process a command or telemetry packet config file
    #########################################################################

    # Processes a OpenC3 configuration file and uses the keywords to build up
    # knowledge of the commands, telemetry, and limits groups.
    #
    # @param filename [String] The name of the configuration file
    # @param process_target_name [String] The target name. Pass nil when parsing
    #   an xtce file to automatically determine the target name.
    def process_file(filename, process_target_name, language = 'ruby')
      # Handle .xtce files
      extension = File.extname(filename).to_s.downcase
      if extension == ".xtce" or extension == ".xml"
        XtceParser.process(@commands, @telemetry, @warnings, filename, process_target_name)
        return
      end

      # Partial files are included into another file and thus aren't directly processed
      return if File.basename(filename)[0] == '_' # Partials start with underscore

      @language = language
      @converted_type = nil
      @converted_bit_size = nil
      @proc_text = ''
      @building_generic_conversion = false

      process_target_name = process_target_name.upcase
      parser = ConfigParser.new("https://docs.openc3.com/docs")
      parser.instance_variable_set(:@target_name, process_target_name)
      parser.parse_file(filename) do |keyword, params|
        if @building_generic_conversion
          case keyword
          # Complete a generic conversion
          when 'GENERIC_READ_CONVERSION_END', 'GENERIC_WRITE_CONVERSION_END'
            parser.verify_num_parameters(0, 0, keyword)
            @current_item.read_conversion =
              GenericConversion.new(@proc_text,
                                    @converted_type,
                                    @converted_bit_size) if keyword.include? "READ"
            @current_item.write_conversion =
              GenericConversion.new(@proc_text,
                                    @converted_type,
                                    @converted_bit_size) if keyword.include? "WRITE"
            @building_generic_conversion = false
          # Add the current config.line to the conversion being built
          else
            @proc_text << parser.line << "\n"
          end # case keyword

        else # not building generic conversion

          case keyword

          # Start a new packet
          when 'COMMAND'
            finish_packet()
            @current_packet = PacketParser.parse_command(parser, process_target_name, @commands, @warnings)
            @current_cmd_or_tlm = COMMAND

          when 'TELEMETRY'
            finish_packet()
            @current_packet = PacketParser.parse_telemetry(parser, process_target_name, @telemetry, @latest_data, @warnings)
            @current_cmd_or_tlm = TELEMETRY

          # Select an existing packet for editing
          when 'SELECT_COMMAND', 'SELECT_TELEMETRY'
            usage = "#{keyword} <TARGET NAME> <PACKET NAME>"
            finish_packet()
            parser.verify_num_parameters(2, 2, usage)
            target_name = process_target_name
            target_name = params[0].upcase if target_name == 'SYSTEM'
            packet_name = params[1].upcase

            @current_packet = nil
            if keyword.include?('COMMAND')
              @current_cmd_or_tlm = COMMAND
              if @commands[target_name]
                @current_packet = @commands[target_name][packet_name]
              end
            else
              @current_cmd_or_tlm = TELEMETRY
              if @telemetry[target_name]
                @current_packet = @telemetry[target_name][packet_name]
              end
            end
            raise parser.error("Packet not found", usage) unless @current_packet

          # Start the creation of a new limits group
          when 'LIMITS_GROUP'
            usage = "LIMITS_GROUP <GROUP NAME>"
            parser.verify_num_parameters(1, 1, usage)
            @current_limits_group = params[0].to_s.upcase
            @limits_groups[@current_limits_group] = [] unless @limits_groups.include?(@current_limits_group)

          # Add a telemetry item to the limits group
          when 'LIMITS_GROUP_ITEM'
            usage = "LIMITS_GROUP_ITEM <TARGET NAME> <PACKET NAME> <ITEM NAME>"
            parser.verify_num_parameters(3, 3, usage)
            @limits_groups[@current_limits_group] << [params[0].to_s.upcase, params[1].to_s.upcase, params[2].to_s.upcase] if @current_limits_group

          #######################################################################
          # All the following keywords must have a current packet defined
          #######################################################################
          when 'SELECT_ITEM', 'SELECT_PARAMETER', 'DELETE_ITEM', 'DELETE_PARAMETER', 'ITEM',\
              'PARAMETER', 'ID_ITEM', 'ID_PARAMETER', 'ARRAY_ITEM', 'ARRAY_PARAMETER', 'APPEND_ITEM',\
              'APPEND_PARAMETER', 'APPEND_ID_ITEM', 'APPEND_ID_PARAMETER', 'APPEND_ARRAY_ITEM',\
              'APPEND_ARRAY_PARAMETER', 'ALLOW_SHORT', 'HAZARDOUS', 'PROCESSOR', 'META',\
              'DISABLE_MESSAGES', 'HIDDEN', 'DISABLED', 'VIRTUAL', 'RESTRICTED', 'ACCESSOR', 'TEMPLATE', 'TEMPLATE_FILE',\
              'RESPONSE', 'ERROR_RESPONSE', 'SCREEN', 'RELATED_ITEM', 'IGNORE_OVERLAP', 'VALIDATOR'
            raise parser.error("No current packet for #{keyword}") unless @current_packet

            process_current_packet(parser, keyword, params)

          #######################################################################
          # All the following keywords must have a current item defined
          #######################################################################
          when 'STATE', 'READ_CONVERSION', 'WRITE_CONVERSION', 'POLY_READ_CONVERSION',\
              'POLY_WRITE_CONVERSION', 'SEG_POLY_READ_CONVERSION', 'SEG_POLY_WRITE_CONVERSION',\
              'GENERIC_READ_CONVERSION_START', 'GENERIC_WRITE_CONVERSION_START', 'REQUIRED',\
              'LIMITS', 'LIMITS_RESPONSE', 'UNITS', 'FORMAT_STRING', 'DESCRIPTION',\
              'MINIMUM_VALUE', 'MAXIMUM_VALUE', 'DEFAULT_VALUE', 'OVERFLOW', 'OVERLAP', 'KEY', 'VARIABLE_BIT_SIZE',\
              'OBFUSCATE'
            raise parser.error("No current item for #{keyword}") unless @current_item

            process_current_item(parser, keyword, params)

          else
            # blank config.lines will have a nil keyword and should not raise an exception
            raise parser.error("Unknown keyword '#{keyword}'") if keyword
          end # case keyword

        end # if building_generic_conversion
      end

      # Complete the last defined packet
      finish_packet()
    end

    # Convert the PacketConfig back to OpenC3 configuration files for each target
    def to_config(output_dir)
      FileUtils.mkdir_p(output_dir)

      @telemetry.each do |target_name, packets|
        next if target_name == 'UNKNOWN'

        FileUtils.mkdir_p(File.join(output_dir, target_name, 'cmd_tlm'))
        filename = File.join(output_dir, target_name, 'cmd_tlm', target_name.downcase + '_tlm.txt')
        begin
          File.delete(filename)
        rescue
          # Doesn't exist
        end
        packets.each do |_packet_name, packet|
          File.open(filename, 'a') do |file|
            file.puts packet.to_config(:TELEMETRY)
            file.puts ""
          end
        end
      end

      @commands.each do |target_name, packets|
        next if target_name == 'UNKNOWN'

        FileUtils.mkdir_p(File.join(output_dir, target_name, 'cmd_tlm'))
        filename = File.join(output_dir, target_name, 'cmd_tlm', target_name.downcase + '_cmd.txt')
        begin
          File.delete(filename)
        rescue
          # Doesn't exist
        end
        packets.each do |_packet_name, packet|
          File.open(filename, 'a') do |file|
            file.puts packet.to_config(:COMMAND)
            file.puts ""
          end
        end
      end

      # Put limits groups into SYSTEM target
      if @limits_groups.length > 0
        FileUtils.mkdir_p(File.join(output_dir, 'SYSTEM', 'cmd_tlm'))
        filename = File.join(output_dir, 'SYSTEM', 'cmd_tlm', 'limits_groups.txt')
        File.open(filename, 'w') do |file|
          @limits_groups.each do |limits_group_name, limits_group_items|
            file.puts "LIMITS_GROUP #{limits_group_name.to_s.quote_if_necessary}"
            limits_group_items.each do |target_name, packet_name, item_name|
              file.puts "  LIMITS_GROUP_ITEM #{target_name.to_s.quote_if_necessary} #{packet_name.to_s.quote_if_necessary} #{item_name.to_s.quote_if_necessary}"
            end
            file.puts ""
          end
        end
      end
    end # def to_config

    def to_xtce(output_dir)
      XtceConverter.convert(@commands, @telemetry, output_dir)
    end

    # Add current packet into hash if it exists
    def finish_packet
      finish_item()
      if @current_packet
        @warnings += @current_packet.check_bit_offsets
        if @current_cmd_or_tlm == COMMAND
          PacketParser.check_item_data_types(@current_packet)
          @commands[@current_packet.target_name][@current_packet.packet_name] = @current_packet
          unless @current_packet.virtual
            hash = @cmd_id_value_hash[@current_packet.target_name]
            hash = {} unless hash
            @cmd_id_value_hash[@current_packet.target_name] = hash
            update_id_value_hash(@current_packet, hash)
          end
        else
          @telemetry[@current_packet.target_name][@current_packet.packet_name] = @current_packet
          unless @current_packet.virtual
            hash = @tlm_id_value_hash[@current_packet.target_name]
            hash = {} unless hash
            @tlm_id_value_hash[@current_packet.target_name] = hash
            update_id_value_hash(@current_packet, hash)
          end
        end
        @current_packet = nil
        @current_item = nil
      end
    end

    def dynamic_add_packet(packet, cmd_or_tlm = :TELEMETRY, affect_ids: false)
      if cmd_or_tlm == :COMMAND
        @commands[packet.target_name][packet.packet_name] = packet

        if affect_ids and not packet.virtual
          hash = @cmd_id_value_hash[packet.target_name]
          hash = {} unless hash
          @cmd_id_value_hash[packet.target_name] = hash
          update_id_value_hash(packet, hash)
        end
      else
        @telemetry[packet.target_name][packet.packet_name] = packet

        # Update latest_data lookup for telemetry
        packet.sorted_items.each do |item|
          target_latest_data = @latest_data[packet.target_name]
          target_latest_data[item.name] ||= []
          latest_data_packets = target_latest_data[item.name]
          latest_data_packets << packet unless latest_data_packets.include?(packet)
        end

        if affect_ids and not packet.virtual
          hash = @tlm_id_value_hash[packet.target_name]
          hash = {} unless hash
          @tlm_id_value_hash[packet.target_name] = hash
          update_id_value_hash(packet, hash)
        end
      end
    end

    # This method provides way to quickly test packet configs
    #
    # require 'openc3/packets/packet_config'
    #
    # config = <<END
    #   ...
    # END
    #
    # pc = PacketConfig.from_config(config, "MYTARGET")
    # c = pc.commands['CMDADCS']['SET_POINTING_CMD']
    # c.restore_defaults()
    # c.write("MYITEM", 5)
    # puts c.buffer.formatted
    def self.from_config(config, process_target_name, language = 'ruby')
      pc = self.new
      tf = Tempfile.new("pc.txt")
      tf.write(config)
      tf.close
      begin
        pc.process_file(tf.path, process_target_name, language)
      ensure
        tf.unlink
      end
      return pc
    end

    protected

    def update_id_value_hash(packet, hash)
      if packet.id_items.length > 0
        key = []
        packet.id_items.each do |item|
          key << item.id_value
        end
        hash[key] = packet
      else
        hash['CATCHALL'.freeze] = packet
      end
    end

    def reset_processing_variables
      @current_cmd_or_tlm = nil
      @current_packet = nil
      @current_item = nil
      @current_limits_group = nil
    end

    def process_current_packet(parser, keyword, params)
      case keyword

      # Select or delete an item in the current packet
      when 'SELECT_PARAMETER', 'SELECT_ITEM', 'DELETE_PARAMETER', 'DELETE_ITEM'
        if (@current_cmd_or_tlm == COMMAND) && (keyword.split('_')[1] == 'ITEM')
          raise parser.error("#{keyword} only applies to telemetry packets")
        end
        if (@current_cmd_or_tlm == TELEMETRY) && (keyword.split('_')[1] == 'PARAMETER')
          raise parser.error("#{keyword} only applies to command packets")
        end

        usage = "#{keyword} <#{keyword.split('_')[1]} NAME>"
        finish_item()
        parser.verify_num_parameters(1, 1, usage)
        begin
          if keyword.include?("SELECT")
            @current_item = @current_packet.get_item(params[0])
          else # DELETE
            @current_packet.delete_item(params[0])
          end
        rescue # Rescue the default exception to provide a nicer error message
          raise parser.error("#{params[0]} not found in #{@current_cmd_or_tlm.downcase} packet #{@current_packet.target_name} #{@current_packet.packet_name}", usage)
        end

      # Start a new telemetry item in the current packet
      when 'ITEM', 'PARAMETER', 'ID_ITEM', 'ID_PARAMETER', 'ARRAY_ITEM', 'ARRAY_PARAMETER',\
          'APPEND_ITEM', 'APPEND_PARAMETER', 'APPEND_ID_ITEM', 'APPEND_ID_PARAMETER',\
          'APPEND_ARRAY_ITEM', 'APPEND_ARRAY_PARAMETER'
        start_item(parser)

      # Allow this packet to be received with less data than the defined length
      # without generating a warning.
      when 'ALLOW_SHORT'
        @current_packet.short_buffer_allowed = true

      # Mark the current command as hazardous
      when 'HAZARDOUS'
        usage = "HAZARDOUS <HAZARDOUS DESCRIPTION (Optional)>"
        parser.verify_num_parameters(0, 1, usage)
        @current_packet.hazardous = true
        @current_packet.hazardous_description = params[0] if params[0]

      # Define a processor class that will be called once when a packet is received
      when 'PROCESSOR'
        ProcessorParser.parse(parser, @current_packet, @current_cmd_or_tlm, @language)

      when 'DISABLE_MESSAGES'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.messages_disabled = true

      # Store user defined metadata for the packet or a packet item
      when 'META'
        usage = "META <META NAME> <META VALUES (optional)>"
        parser.verify_num_parameters(1, nil, usage)
        if params.length > 1
          meta_values = params[1..-1]
        else
          meta_values = []
        end
        meta_values.each_with_index do |value, index|
          if String === value
            meta_values[index] = value.to_utf8
          end
        end
        if @current_item
          # Item META
          @current_item.meta[params[0].to_s.upcase] = meta_values
        else
          # Packet META
          @current_packet.meta[params[0].to_s.upcase] = meta_values
        end

      when 'HIDDEN'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.hidden = true

      when 'DISABLED'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.hidden = true
        @current_packet.disabled = true

      when 'VIRTUAL'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.hidden = true
        @current_packet.disabled = true
        @current_packet.virtual = true

      when 'RESTRICTED'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.restricted = true

      when 'ACCESSOR', 'VALIDATOR'
        usage = "#{keyword} <Class name> <Optional parameters> ..."
        parser.verify_num_parameters(1, nil, usage)
        begin
          keyword_equals = "#{keyword.downcase}=".to_sym
          if @language == 'ruby'
            klass = OpenC3.require_class(params[0])
            if params.length > 1
              @current_packet.public_send(keyword_equals, klass.new(@current_packet, *params[1..-1]))
            else
              @current_packet.public_send(keyword_equals, klass.new(@current_packet))
            end
          else
            if params.length > 1
              @current_packet.public_send(keyword_equals, PythonProxy.new(keyword.capitalize, params[0], @current_packet, *params[1..-1]))
            else
              @current_packet.public_send(keyword_equals, PythonProxy.new(keyword.capitalize, params[0], @current_packet))
            end
          end
        rescue Exception => e
          raise parser.error(e.formatted)
        end

      when 'TEMPLATE'
        usage = "#{keyword} <Template string>"
        parser.verify_num_parameters(1, 1, usage)
        @current_packet.template = params[0]

      when 'TEMPLATE_FILE'
        usage = "#{keyword} <Template file path>"
        parser.verify_num_parameters(1, 1, usage)

        begin
          @current_packet.template = parser.read_file(params[0])
        rescue Exception => e
          raise parser.error(e.formatted)
        end

      when 'RESPONSE'
        usage = "#{keyword} <Target Name> <Packet Name>"
        parser.verify_num_parameters(2, 2, usage)
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command packets")
        end
        @current_packet.response = [params[0].upcase, params[1].upcase]

      when 'ERROR_RESPONSE'
        usage = "#{keyword} <Target Name> <Packet Name>"
        parser.verify_num_parameters(2, 2, usage)
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command packets")
        end
        @current_packet.error_response = [params[0].upcase, params[1].upcase]

      when 'SCREEN'
        usage = "#{keyword} <Target Name> <Screen Name>"
        parser.verify_num_parameters(2, 2, usage)
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command packets")
        end
        @current_packet.screen = [params[0].upcase, params[1].upcase]

      when 'RELATED_ITEM'
        usage = "#{keyword} <Target Name> <Packet Name> <Item Name>"
        parser.verify_num_parameters(3, 3, usage)
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command packets")
        end
        @current_packet.related_items ||= []
        @current_packet.related_items << [params[0].upcase, params[1].upcase, params[2].upcase]

      when 'IGNORE_OVERLAP'
        usage = "#{keyword}"
        parser.verify_num_parameters(0, 0, usage)
        @current_packet.ignore_overlap = true

      end

    end

    def process_current_item(parser, keyword, params)
      case keyword

      # Add a state to the current telemety item
      when 'STATE'
        StateParser.parse(parser, @current_packet, @current_cmd_or_tlm, @current_item, @warnings)

      # Apply a conversion to the current item after it is read to or
      # written from the packet
      when 'READ_CONVERSION', 'WRITE_CONVERSION'
        usage = "#{keyword} <conversion class filename> <custom parameters> ..."
        parser.verify_num_parameters(1, nil, usage)
        begin
          if @language == 'ruby'
            klass = OpenC3.require_class(params[0])
            conversion = klass.new(*params[1..(params.length - 1)])
            @current_item.public_send("#{keyword.downcase}=".to_sym, conversion)
            if klass != ProcessorConversion and (conversion.converted_type.nil? or conversion.converted_bit_size.nil?)
              msg = "Read Conversion #{params[0]} on item #{@current_item.name} does not specify converted type or bit size"
              @warnings << msg
              Logger.instance.warn @warnings[-1]
            end
          else
            conversion = PythonProxy.new('Conversion', params[0], *params[1..(params.length - 1)])
            @current_item.public_send("#{keyword.downcase}=".to_sym, conversion)
          end
        end

      # Apply a polynomial conversion to the current item
      when 'POLY_READ_CONVERSION', 'POLY_WRITE_CONVERSION'
        usage = "#{keyword} <C0> <C1> <C2> ..."
        parser.verify_num_parameters(1, nil, usage)
        @current_item.read_conversion = PolynomialConversion.new(*params) if keyword.include? "READ"
        @current_item.write_conversion = PolynomialConversion.new(*params) if keyword.include? "WRITE"

      # Apply a segmented polynomial conversion to the current item
      # after it is read from the telemetry packet
      when 'SEG_POLY_READ_CONVERSION'
        usage = "SEG_POLY_READ_CONVERSION <Lower Bound> <C0> <C1> <C2> ..."
        parser.verify_num_parameters(2, nil, usage)
        if !(@current_item.read_conversion &&
             SegmentedPolynomialConversion === @current_item.read_conversion)
          @current_item.read_conversion = SegmentedPolynomialConversion.new
        end
        @current_item.read_conversion.add_segment(params[0].to_f, *params[1..-1])

      # Apply a segmented polynomial conversion to the current item
      # before it is written to the telemetry packet
      when 'SEG_POLY_WRITE_CONVERSION'
        usage = "SEG_POLY_WRITE_CONVERSION <Lower Bound> <C0> <C1> <C2> ..."
        parser.verify_num_parameters(2, nil, usage)
        if !(@current_item.write_conversion &&
             SegmentedPolynomialConversion === @current_item.write_conversion)
          @current_item.write_conversion = SegmentedPolynomialConversion.new
        end
        @current_item.write_conversion.add_segment(params[0].to_f, *params[1..-1])

      # Start the definition of a generic conversion.
      # All config.lines following this config.line are considered part
      # of the conversion until an end of conversion marker is found
      when 'GENERIC_READ_CONVERSION_START', 'GENERIC_WRITE_CONVERSION_START'
        usage = "#{keyword} <Converted Type (optional)> <Converted Bit Size (optional)>"
        parser.verify_num_parameters(0, 2, usage)
        @proc_text = ''
        @building_generic_conversion = true
        @converted_type = nil
        @converted_bit_size = nil
        if params[0]
          @converted_type = params[0].upcase.intern
          raise parser.error("Invalid converted_type: #{@converted_type}.") unless [:INT, :UINT, :FLOAT, :STRING, :BLOCK, :TIME].include? @converted_type
        end
        @converted_bit_size = Integer(params[1]) if params[1]
        if @converted_type.nil? or @converted_bit_size.nil?
          msg = "Generic Conversion on item #{@current_item.name} does not specify converted type or bit size"
          @warnings << msg
          Logger.instance.warn @warnings[-1]
        end

      # Define a set of limits for the current telemetry item
      when 'LIMITS'
        @limits_sets << LimitsParser.parse(parser, @current_packet, @current_cmd_or_tlm, @current_item, @warnings)
        @limits_sets.uniq!

      # Define a response class that will be called when the limits state of the
      # current item changes.
      when 'LIMITS_RESPONSE'
        LimitsResponseParser.parse(parser, @current_item, @current_cmd_or_tlm, @language)

      # Define a printf style formatting string for the current telemetry item
      when 'FORMAT_STRING'
        FormatStringParser.parse(parser, @current_item)

      # Define the units of the current telemetry item
      when 'UNITS'
        usage = "UNITS <FULL UNITS NAME> <ABBREVIATED UNITS NAME>"
        parser.verify_num_parameters(2, 2, usage)
        @current_item.units_full = params[0]
        @current_item.units = params[1]

      # Obfuscate the parameter in logs
      when 'OBFUSCATE'
        usage = "OBFUSCATE"
        parser.verify_num_parameters(0, 0, usage)
        @current_item.obfuscate = true
        @current_packet.update_obfuscated_items_cache(@current_item)

      # Update the description for the current telemetry item
      when 'DESCRIPTION'
        usage = "DESCRIPTION <DESCRIPTION>"
        parser.verify_num_parameters(1, 1, usage)
        @current_item.description = params[0]

      # Mark the current command parameter as required.
      # This means it must be given a value and not just use its default.
      when 'REQUIRED'
        usage = "REQUIRED"
        parser.verify_num_parameters(0, 0, usage)
        if @current_cmd_or_tlm == COMMAND
          @current_item.required = true
        else
          raise parser.error("#{keyword} only applies to command parameters")
        end

      # Update the minimum value for the current command parameter
      when 'MINIMUM_VALUE'
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command parameters")
        end

        usage = "MINIMUM_VALUE <MINIMUM VALUE>"
        parser.verify_num_parameters(1, 1, usage)
        min = ConfigParser.handle_defined_constants(
          params[0].convert_to_value, @current_item.data_type, @current_item.bit_size
        )
        @current_item.range = Range.new(min, @current_item.range.end)

      # Update the maximum value for the current command parameter
      when 'MAXIMUM_VALUE'
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command parameters")
        end

        usage = "MAXIMUM_VALUE <MAXIMUM VALUE>"
        parser.verify_num_parameters(1, 1, usage)
        max = ConfigParser.handle_defined_constants(
          params[0].convert_to_value, @current_item.data_type, @current_item.bit_size
        )
        @current_item.range = Range.new(@current_item.range.begin, max)

      # Update the default value for the current command parameter
      when 'DEFAULT_VALUE'
        if @current_cmd_or_tlm == TELEMETRY
          raise parser.error("#{keyword} only applies to command parameters")
        end

        usage = "DEFAULT_VALUE <DEFAULT VALUE>"
        parser.verify_num_parameters(1, 1, usage)
        if (@current_item.data_type == :STRING) ||
           (@current_item.data_type == :BLOCK)
          @current_item.default = params[0]
        else
          @current_item.default = ConfigParser.handle_defined_constants(
            params[0].convert_to_value, @current_item.data_type, @current_item.bit_size
          )
        end

      # Update the overflow type for the current command parameter
      when 'OVERFLOW'
        usage = "OVERFLOW <OVERFLOW VALUE - ERROR, ERROR_ALLOW_HEX, TRUNCATE, or SATURATE>"
        parser.verify_num_parameters(1, 1, usage)
        @current_item.overflow = params[0].to_s.upcase.intern

      when 'OVERLAP'
        parser.verify_num_parameters(0, 0, 'OVERLAP')
        @current_item.overlap = true

      when 'KEY'
        parser.verify_num_parameters(1, 1, 'KEY <key or path into data>')
        @current_item.key = params[0]

      when 'VARIABLE_BIT_SIZE'
        parser.verify_num_parameters(1, 3, 'VARIABLE_BIT_SIZE <length_item_name> <length_bits_per_count = 8> <length_value_bit_offset = 0>')

        variable_bit_size = {'length_bits_per_count' => 8, 'length_value_bit_offset' => 0}
        variable_bit_size['length_item_name'] = params[0].upcase
        variable_bit_size['length_bits_per_count'] = Integer(params[1]) if params[1]
        variable_bit_size['length_value_bit_offset'] = Integer(params[2]) if params[2]

        @current_item.variable_bit_size = variable_bit_size
      end
    end

    def start_item(parser)
      finish_item()
      @current_item = PacketItemParser.parse(parser, @current_packet, @current_cmd_or_tlm, @warnings)
    end

    # Finish updating packet item
    def finish_item
      if @current_item
        @current_packet.set_item(@current_item)
        if @current_cmd_or_tlm == TELEMETRY
          target_latest_data = @latest_data[@current_packet.target_name]
          target_latest_data[@current_item.name] ||= []
          latest_data_packets = target_latest_data[@current_item.name]
          latest_data_packets << @current_packet unless latest_data_packets.include?(@current_packet)
        end
        @current_item = nil
      end
    end
  end
end
