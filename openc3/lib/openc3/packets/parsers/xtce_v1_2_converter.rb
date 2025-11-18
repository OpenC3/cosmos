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

require 'nokogiri'
require 'openc3/packets/parsers/xtce_parser'
require 'fileutils'

DYNAMIC_STRING_LEN = 2048
INVALID_CHARS = '[]./'
REPLACEMENT_CHAR = '_'
ALIAS_NAMESPACE = 'COSMOS'

COMBINED_NAME = "COMBINED"

module OpenC3
  class Xtcev1_2Converter
    attr_accessor :current_target_name

    # Output a previously parsed definition file into the XTCE format
    #
    # @param commands [Hash<String=>Packet>] Hash of all the command packets
    #   keyed by the packet name.
    # @param telemetry [Hash<String=>Packet>] Hash of all the telemetry packets
    #   keyed by the packet name.
    #   that were created while parsing the configuration
    # @param output_dir [String] The name of the output directory to generate
    #   the XTCE files. A file is generated for each target.
    def self.convert(commands, telemetry, output_dir)
      Xtcev1_2Converter.new(commands, telemetry, output_dir)
    end

    def self.combine_output_xtce(output_dir, root_target_name = nil)
      combined_file_directory = File.join(output_dir, 'TARGETS_COMBINED', 'cmd_tlm')
      begin
        FileUtils.rm_rf(combined_file_directory)
      rescue
        # doesn't exist
      end
      file_pattern = File.join(output_dir, "**", "*.xtce")
      xml_files = Dir.glob(file_pattern)
      if xml_files.empty?
          puts "No *.xtce files found to combine. Aborting xtce unification."
      elsif xml_files.length == 1
          puts "Output directory contains single target. Aborting xtce unification."
      else
        puts "Multiple targets found. Creating Unified XTCE representation."
        FileUtils.mkdir_p(combined_file_directory)
        file_basename = "combined"
        xml_files.each do |file_path|
          file_basename += "_#{File.basename(file_path, ".*")}"
        end
        full_file_name = File.join(combined_file_directory, file_basename.downcase + '.xtce')
        begin
          File.delete(full_file_name)
        rescue
          # Doesn't exist
        end
        xml_files.each do |file_path|
          file_basename += File.basename(file_path, ".*")
        end
        root_builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
          xml['xtce'].SpaceSystem("xmlns:xtce" => "http://www.omg.org/spec/XTCE/20180204",
                                  "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                  "name" => root_target_name ? root_target_name : "root",
                                  "xsi:schemaLocation" => "http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd")
        end 
        new_doc = root_builder.doc
        new_root = new_doc.root
        xml_files.each do |file_path|
          source_doc = Nokogiri::XML(File.open(file_path))
          target_root = source_doc.root
          target_root.attributes.each do |name, attr|
            unless name == "name"
              attr.remove
            end
          end
          if root_target_name == target_root["name"]
            nodes_to_add_reversed = target_root.children.to_a.reverse
            nodes_to_add_reversed.each do |child_node|
              new_root.prepend_child(child_node)
            end
          else
            new_root.add_child(target_root)
          end
          #else
          #end
        end
        File.open(full_file_name, 'w') do |file|
          file.puts new_doc.to_xml
        end
        full_file_name
      end
    end

    private

    def initialize(commands, telemetry, output_dir)
      FileUtils.mkdir_p(output_dir)

      # Build target list
      targets = []
      telemetry.each { |target_name, packets| targets << target_name }
      commands.each { |target_name, packets| targets << target_name }
      targets.uniq!

      targets.each do |target_name|
        next if target_name == 'UNKNOWN'

        # Reverse order of packets for the target so things are expected (reverse) order for xtce
        XtceParser.reverse_packet_order(target_name, commands)
        XtceParser.reverse_packet_order(target_name, telemetry)

        FileUtils.mkdir_p(File.join(output_dir, target_name, 'cmd_tlm'))
        filename = File.join(output_dir, target_name, 'cmd_tlm', target_name.downcase + '.xtce')
        begin
          File.delete(filename)
        rescue
          # Doesn't exist
        end

        # Create the xtce file for this target
        builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
          xml['xtce'].SpaceSystem("xmlns:xtce" => "http://www.omg.org/spec/XTCE/20180204",
                                  "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                  "name" => target_name,
                                  "xsi:schemaLocation" => "http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd") do
            create_telemetry(xml, telemetry, target_name)
            create_commands(xml, commands, target_name)
          end # SpaceSystem
        end # builder
        File.open(filename, 'w') do |file|
          file.puts builder.to_xml
        end
      end
    end

    def create_telemetry(xml, telemetry, target_name)
      # Gather and make unique all the packet items
      unique_items = telemetry[target_name] ? get_unique(telemetry[target_name]) : {}

      xml['xtce'].TelemetryMetaData do
        xml['xtce'].ParameterTypeSet do
          unique_items.each do |item_name, item|
            to_xtce_type(item, 'Parameter', xml)
          end
        end

        xml['xtce'].ParameterSet do
          unique_items.each do |item_name, item|
            to_xtce_item(item, 'Parameter', xml)
          end
        end

        if telemetry[target_name]
          xml['xtce'].ContainerSet do
            telemetry[target_name].each do |packet_name, packet|
              # Replaces invalid characters if any exist
              attrs = { :name => packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR) }
              attrs['shortDescription'] = packet.description if packet.description
              xml['xtce'].SequenceContainer(attrs) do
                # Adds an alias if any invalid characters exist
                if packet_name.count(INVALID_CHARS) > 0
                  xml['xtce'].AliasSet do
                    xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => packet_name)
                  end
                end
                if packet.short_buffer_allowed
                  xml['xtce'].AncillaryDataSet do
                    xml['xtce'].AncillaryData("true", :name => "ALLOW_SHORT")
                  end
                end
                process_entry_list(xml, packet, :TELEMETRY)
                xml['xtce'].BaseContainer(:containerRef => (packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR))) do
                  if packet.id_items && packet.id_items.length > 0
                    xml['xtce'].RestrictionCriteria do
                      xml['xtce'].ComparisonList do
                        packet.id_items.each do |item|
                          xml['xtce'].Comparison(:parameterRef => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR), :value => item.id_value)
                        end
                      end
                    end
                  end
                end
              end # SequenceContainer
            end # telemetry.each
          end # ContainerSet
        end # if telemetry[target_name]
      end # TelemetryMetaData
    end

    def create_commands(xml, commands, target_name)
      return unless commands[target_name]

      xml['xtce'].CommandMetaData do
        unique_id_items = get_unique_id_items(commands[target_name])
        # Create Parameters for any ID item so it can be used in a comparison.
        #TODO: fix it so it doesn't overlap with the tlm id parameter
        xml['xtce'].ParameterTypeSet do
          unique_id_items.each do |item_name, item|
            to_xtce_type(item, 'Parameter', xml)
          end
        end
        xml['xtce'].ParameterSet do
          unique_id_items.each do |item_name, item|
            to_xtce_item(item, 'Parameter', xml)
          end
        end
        unique_command_args_without_ids = get_unique_without_ids(commands[target_name])
        if unique_command_args_without_ids.size > 0
          xml['xtce'].ArgumentTypeSet do
            unique_command_args_without_ids.each do |arg_name, arg|
              next if unique_id_items.key?(arg_name)
              to_xtce_type(arg, 'Argument', xml)
            end
          end
        end
        xml['xtce'].MetaCommandSet do
          commands[target_name].each do |packet_name, packet|
            attrs = { :name => packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR) }
            attrs['shortDescription'] = packet.description if packet.description
            xml['xtce'].MetaCommand(attrs) do
              if packet_name.count(INVALID_CHARS) > 0
                xml['xtce'].AliasSet do
                  xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => packet_name)
                end # AliasSet
              end # If packet contains invalid chars
              #TODO: remove Argument list if only derived or only id
              argument_list_sorted_items = get_sorted_items_without_id_or_derived(packet.sorted_items)
              if argument_list_sorted_items.size > 0
                xml['xtce'].ArgumentList do
                  argument_list_sorted_items.each do |item|
                    to_xtce_item(item, 'Argument', xml)
                  end
                end # ArgumentList
              end # If Aguments List is greater than 0
              xml['xtce'].CommandContainer(:name => "#{packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_Commands") do
                process_entry_list(xml, packet, :COMMAND)
                  #xml['xtce'].BaseContainer(:containerRef => "#{target_name}_#{packet_name}_CommandContainer")
                if packet.id_items && packet.id_items.length > 0
                  packet.id_items.each do |item|
                    xml['xtce'].BaseContainer(:containerRef => "#{packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_Commands") do
                      xml['xtce'].RestrictionCriteria do
                        xml['xtce'].ComparisonList do
                          xml['xtce'].Comparison(:parameterRef => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR),:value => item.id_value)
                        end
                      end # Restriction Criteria
                    end # Base Container
                  end # for each packet ID item
                end # If id items
              end # Command Container
            end # MetaCommand
          end # each command packet
        end # MetaCommandSet
      end # CommandMetaData
    end

    def get_unique(items)
      unique = {}
      items.each do |packet_name, packet|
        packet.sorted_items.each do |item|
          next if item.data_type == :DERIVED
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] ||= []
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] << item
        end
      end
      unique.each do |item_name, unique_items|
        if unique_items.length <= 1
          unique[item_name] = unique_items[0]
          next
        end
        # TODO: need to make sure all the items in the array are exactly the same
        unique[item_name] = unique_items[0]
      end
      unique
    end

    def get_unique_without_ids(items)
      unique = {}
      items.each do |packet_name, packet|
        packet.sorted_items.each do |item|
          next if item.data_type == :DERIVED
          next if item.id_value
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] ||= []
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] << item
        end
      end
      unique.each do |item_name, unique_items|
        if unique_items.length <= 1
          unique[item_name] = unique_items[0]
          next
        end
        # TODO: need to make sure all the items in the array are exactly the same
        unique[item_name] = unique_items[0]
      end
      unique
    end

    def get_sorted_items_without_id_or_derived(items)
      sorted_items = []
      items.each do |item|
        next if item.data_type == :DERIVED
        next if item.id_value 
        sorted_items.push(item)
      end
      sorted_items
    end

    def get_unique_id_items(items)
      unique = {}
      items.each do |packet_name, packet|
        packet.id_items.each do |item|
          next if item.data_type == :DERIVED
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] ||= []
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] << item
        end
      end
      unique.each do |item_name, unique_items|
        if unique_items.length <= 1
          unique[item_name] = unique_items[0]
          next
        end
        # TODO: need to make sure all the items in the array are exactly the same
        unique[item_name] = unique_items[0]
      end
      unique
    end

    # This method is almost the same for commands and telemetry except for the
    # XML element name: [Array]ArgumentRefEntry vs [Array]ParameterRefEntry,
    # and XML reference: argumentRef vs parameterRef.
    # Thus we build the name and use send to dynamically dispatch.
    def process_entry_list(xml, packet, cmd_vs_tlm)
      if cmd_vs_tlm == :COMMAND
        type = "Argument"
      else # :TELEMETRY
        type = "Parameter"
      end
      xml['xtce'].EntryList do
        packed = packet.packed?
        packet.sorted_items.each do |item|
          next if item.data_type == :DERIVED
          # TODO: Handle nonunique item names
          temp_type = item.id_value ? "Parameter" : type
          if item.array_size
            reference_symbol = "#{temp_type.downcase}Ref".to_sym
            # Requiring parameterRef for argument arrays appears to be a defect in the schema
            xml['xtce'].public_send("Array#{temp_type}RefEntry".intern, reference_symbol => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)) do
              set_fixed_value(xml, item) if !packed
              xml['xtce'].DimensionList do
                xml['xtce'].Dimension do
                  xml['xtce'].StartingIndex do
                    xml['xtce'].FixedValue(0)
                  end
                  xml['xtce'].EndingIndex do
                    xml['xtce'].FixedValue((item.array_size / item.bit_size) - 1)
                  end
                end
              end
            end
          else
            if packed
              xml['xtce'].public_send("#{temp_type}RefEntry".intern, "#{temp_type.downcase}Ref".intern => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR))
            else
              xml['xtce'].public_send("#{temp_type}RefEntry".intern, "#{temp_type.downcase}Ref".intern => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)) do
                set_fixed_value(xml, item)
              end
            end
          end
        end
      end
    end

    def set_fixed_value(xml, item)
      if item.bit_offset >= 0
        xml['xtce'].LocationInContainerInBits(:referenceLocation => 'containerStart') do
          xml['xtce'].FixedValue(item.bit_offset)
        end
      else
        xml['xtce'].LocationInContainerInBits(:referenceLocation => 'containerEnd') do
          xml['xtce'].FixedValue(-item.bit_offset)
        end
      end
    end

    def to_xtce_type(item, param_or_arg, xml)
      # TODO: Spline Conversions
      case item.data_type
      when :INT, :UINT
        to_xtce_int(item, param_or_arg, xml)
      when :FLOAT
        to_xtce_float(item, param_or_arg, xml)
      when :STRING
        to_xtce_string(item, param_or_arg, xml, 'String')
      when :BLOCK
        to_xtce_string(item, param_or_arg, xml, 'Binary')
      when :DERIVED
        raise "DERIVED data type not supported in XTCE"
      end

      # Handle arrays
      if item.array_size
        # The above will have created the type for the array entries.   Now we create the type for the actual array.

        attrs = { :name => (item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_ArrayType') }
        attrs[:shortDescription] = item.description if item.description
        attrs[:arrayTypeRef] = (item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type')
        xml['xtce'].public_send('Array' + param_or_arg + 'Type', attrs) do
          xml['xtce'].DimensionList do
            xml['xtce'].Dimension do
              xml['xtce'].StartingIndex do
                xml['xtce'].FixedValue do
                  xml['xtce'].text 0
                end # FixedValue
              end # StartingIndex                
              xml['xtce'].EndingIndex do
                xml['xtce'].FixedValue do
                  xml['xtce'].text 0 # OpenC3 Only supports one-dimensional arrays
                end # FixedValue
              end # EndingIndex
            end # Dimension
          end # DimensionList
        end # Array<param_or_arg>Type
      end
    end

    def to_xtce_limits(item, xml)
      return unless item.limits && item.limits.values

      item.limits.values.each do |limits_set, limits_values|
        if limits_set == :DEFAULT
          xml['xtce'].DefaultAlarm do
            xml['xtce'].StaticAlarmRanges do
              xml['xtce'].WarningRange(:minInclusive => limits_values[1], :maxInclusive => limits_values[2])
              xml['xtce'].CriticalRange(:minInclusive => limits_values[0], :maxInclusive => limits_values[3])
            end
          end
        end
      end
    end

    def to_xtce_int(item, param_or_arg, xml)
      attrs = { :name => (item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type') }
      attrs[:initialValue] = item.default if item.default and !item.array_size
      attrs[:shortDescription] = item.description if item.description
      if attrs[:initialValue] == "1970-01-01T00:00:00Z"
        attrs[:initialValue] = "0"
      end
      if item.states and item.default and item.states.key(item.default)
        attrs[:initialValue] = item.states.key(item.default) and !item.array_size
      end
      if item.data_type == :INT
        signed = 'true'
        encoding = 'twosComplement'
      else
        signed = 'false'
        encoding = 'unsigned'
      end
      if item.states
        xml['xtce'].public_send('Enumerated' + param_or_arg + 'Type', attrs) do
          to_xtce_units(item, xml)
          if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
            xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding, :byteOrder => "leastSignificantByteFirst")
          else
            xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding)
          end
          xml['xtce'].EnumerationList do
            item.states.each do |state_name, state_value|
              # Skip the special OpenC3 'ANY' enumerated state
              next if state_value == 'ANY'

              xml['xtce'].Enumeration(:value => state_value, :label => state_name)
            end
          end
        end
      else
        if (item.read_conversion and item.read_conversion.class == PolynomialConversion) or (item.write_conversion and item.write_conversion.class == PolynomialConversion)
          type_string = 'Float' + param_or_arg + 'Type'
        else
          type_string = 'Integer' + param_or_arg + 'Type'
          attrs[:signed] = signed
        end
        xml['xtce'].public_send(type_string, attrs) do
          to_xtce_units(item, xml)
          if (item.read_conversion and item.read_conversion.class == PolynomialConversion) or (item.write_conversion and item.write_conversion.class == PolynomialConversion)
            if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding, :byteOrder => "leastSignificantByteFirst") do
                to_xtce_conversion(item, xml)
              end
            else
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding) do
                to_xtce_conversion(item, xml)
              end
            end
          else
            if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding, :byteOrder => "leastSignificantByteFirst")
            else
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding)
            end          
          end
          to_xtce_limits(item, xml)
          # TODO just don't do the default max and min
          if item.range and item.range.last < 18446744073709551615
            if param_or_arg == "Parameter"
              xml['xtce'].ValidRange(:minInclusive => item.range.first, :maxInclusive => item.range.last)
            else
              xml['xtce'].ValidRangeSet do
                xml['xtce'].ValidRange(:minInclusive => item.range.first, :maxInclusive => item.range.last)
              end
            end
          end
        end # Type
      end # if item.states
    end

    def to_xtce_float(item, param_or_arg, xml)
      attrs = { :name => (item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type'), :sizeInBits => item.bit_size }
      attrs[:initialValue] = item.default if item.default and !item.array_size
      attrs[:shortDescription] = item.description if item.description
      xml['xtce'].public_send('Float' + param_or_arg + 'Type', attrs) do
        to_xtce_units(item, xml)
        if (item.read_conversion and item.read_conversion.class == PolynomialConversion) or (item.write_conversion and item.write_conversion.class == PolynomialConversion)
          if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985', :byteOrder => "leastSignificantByteFirst") do
            to_xtce_conversion(item, xml)
          end
          else
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985') do            
              to_xtce_conversion(item, xml)
            end
          end
        else
          if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985', :byteOrder => "leastSignificantByteFirst")
          else
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985')
          end        
        end
        to_xtce_limits(item, xml)
        if item.range and item.range.last < 18446744073709551615
          if param_or_arg == "Parameter"
            xml['xtce'].ValidRange(:minInclusive => item.range.first, :maxInclusive => item.range.last)
          else
            xml['xtce'].ValidRangeSet do
                xml['xtce'].ValidRange(:minInclusive => item.range.first, :maxInclusive => item.range.last)
            end        
          end
        end
      end
    end

    def to_xtce_string(item, param_or_arg, xml, string_or_binary)
      # TODO: OpenC3 Variably sized strings are not supported in XTCE
      attrs = { :name => (item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type') }
      attrs[:characterWidth] = 8 if string_or_binary == 'String'
      if item.default && !item.array_size
        unless item.default.is_printable?
          #attrs[:initialValue] = '0x' + item.default.simple_formatted
          attrs[:initialValue] = item.default.simple_formatted
        else
          if string_or_binary == 'String'
            attrs[:initialValue] = item.default.inspect
          else
            # TODO: verify hexBinary is just two hex values nothing else 
            attrs[:initialValue] = item.default.inspect.unpack('H*').first
          end         
        end
      end
      attrs[:shortDescription] = item.description if item.description
      xml['xtce'].public_send(string_or_binary + param_or_arg + 'Type', attrs) do
        # Don't call to_xtce_endianness for Strings or Blocks
        to_xtce_units(item, xml)
        if string_or_binary == 'String'
          xml['xtce'].StringDataEncoding(:encoding => 'UTF-8') do
            xml['xtce'].SizeInBits do
              xml['xtce'].Fixed do
                if item.bit_size != 0
                  xml['xtce'].FixedValue(item.bit_size.to_s)
                else
                  xml['xtce'].FixedValue(DYNAMIC_STRING_LEN)
                end # if statement
              end # </Fixed>
              xml['xtce'].TerminationChar("00")
            end # </SizeInBits>
          end # </StringDataEncoding>
        else
          xml['xtce'].BinaryDataEncoding do
            xml['xtce'].SizeInBits do
              xml['xtce'].FixedValue(item.bit_size.to_s)
            end
          end
        end
      end
    end

    def to_xtce_item(item, param_or_arg, xml)
      if item.name.count(INVALID_CHARS) > 0
        replaced_item_name = item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)
        if item.array_size
          xml['xtce'].public_send(param_or_arg, :name => replaced_item_name, "#{param_or_arg.downcase}TypeRef" => replaced_item_name + '_ArrayType') do
            xml['xtce'].AliasSet do
              xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => item.name)
            end
          end
        else
          xml['xtce'].public_send(param_or_arg, :name => replaced_item_name, "#{param_or_arg.downcase}TypeRef" => replaced_item_name + '_Type') do
            xml['xtce'].AliasSet do
              xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => item.name)
            end
          end
        end
      else
        if item.array_size
          xml['xtce'].public_send(param_or_arg, :name => item.name, "#{param_or_arg.downcase}TypeRef" => item.name + '_ArrayType')
        else
          xml['xtce'].public_send(param_or_arg, :name => item.name, "#{param_or_arg.downcase}TypeRef" => item.name + '_Type')
        end
      end
    end

    def to_xtce_units(item, xml)
      if item.units
        xml['xtce'].UnitSet do
          xml['xtce'].Unit(item.units, :description => item.units_full)
        end
      else
        xml['xtce'].UnitSet
      end
    end

    def to_xtce_endianness(item, xml)
      if item.endianness == :LITTLE_ENDIAN and item.bit_size > 8
        xml['xtce'].ByteOrderList do
          (((item.bit_size - 1) / 8) + 1).times do |byte_significance|
            xml['xtce'].Byte(:byteSignificance => byte_significance)
          end
        end
      end
    end

    def to_xtce_conversion(item, xml)
      if item.read_conversion
        conversion = item.read_conversion
      else
        conversion = item.write_conversion
      end
      if conversion && conversion.class == PolynomialConversion
        xml['xtce'].DefaultCalibrator do
          xml['xtce'].PolynomialCalibrator do
            conversion.coeffs.each_with_index do |coeff, index|
              xml['xtce'].Term(:coefficient => coeff, :exponent => index)
            end # for each loop
          end # </PolynomialCalibrator>
        end # </DefaultCalibrator>
        #TODO: do derivation work
      end # if PolynomialConversion
    end
  end
end
