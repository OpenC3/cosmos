# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
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

# IntegerRangeType declares minInclusive / maxInclusive as xs:long, so an integer range
# outside these bounds (a full 64 bit UINT, for example) cannot be expressed as a
# ValidRange. FloatRangeType uses xs:double and needs no such clamp.
XS_LONG_MIN = -9223372036854775808
XS_LONG_MAX = 9223372036854775807
COSMOS_NATIVE_DERIVED_ITEMS = ['PACKET_TIMESECONDS', 'PACKET_TIMEFORMATTED', 'RECEIVED_TIMESECONDS', 'RECEIVED_TIMEFORMATTED', 'RECEIVED_COUNT']

module OpenC3
  class XtceConverter
    attr_accessor :current_target_name

    # The namespace COSMOS exports. Files declaring an older namespace still import.
    XTCE_1_2_NAMESPACE = 'http://www.omg.org/spec/XTCE/20180204'
    # The OMG schema is vendored so validation works with no network, which matters in
    # an air gapped system: the schemaLocation the files declare is an omg.org URL.
    SCHEMA_DIR = File.join(PATH, 'data', 'xtce_schemas')
    SCHEMA_FILE = File.join(SCHEMA_DIR, 'SpaceSystem_20180204.xsd')

    # The XTCE namespace an existing .xtce file declares on its root element
    #
    # @param filename [String] Path to a .xtce file
    # @return [String, nil] The declared namespace, or nil if the file has none
    def self.xtce_namespace(filename)
      Nokogiri::XML(File.read(filename)).root&.namespace&.href
    end

    # Validate an .xtce file against the vendored OMG XTCE 1.2 schema
    #
    # Only meaningful for files declaring XTCE_1_2_NAMESPACE. XTCE 1.0 / 1.1 files
    # import fine but report errors against this schema, so check xtce_namespace first.
    #
    # @param filename [String] Path to a .xtce file
    # @return [Array<String>] Validation error messages, empty when the file is valid
    def self.schema_errors(filename)
      # File.open, not File.read: the schema imports xml.xsd relative to itself, which
      # Nokogiri can only resolve from the IO's path
      @schema ||= File.open(SCHEMA_FILE) { |f| Nokogiri::XML::Schema(f) }
      @schema.validate(Nokogiri::XML(File.read(filename))).map(&:message)
    end

    # Output a previously parsed definition file into the XTCE format
    #
    # @param commands [Hash<String=>Packet>] Hash of all the command packets
    #   keyed by the packet name.
    # @param telemetry [Hash<String=>Packet>] Hash of all the telemetry packets
    #   keyed by the packet name.
    #   that were created while parsing the configuration
    # @param output_dir [String] The name of the output directory to generate
    #   the XTCE files. A file is generated for each target.
    def self.convert(commands, telemetry, output_dir, time_association_name)
      XtceConverter.new(commands, telemetry, output_dir, time_association_name)
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
          puts "No *.xtce files found to combine."
      elsif xml_files.length == 1
          puts "Only one *.xtce file found. No need to unify."
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
        end
        File.open(full_file_name, 'w') do |file|
          file.puts new_doc.to_xml
        end
        full_file_name
      end
    end

    private

    def initialize(commands, telemetry, output_dir, time_association_name)
      FileUtils.mkdir_p(output_dir)

      # Build target list
      targets = []
      telemetry.each { |target_name, packets| targets << target_name }
      commands.each { |target_name, packets| targets << target_name }
      targets.uniq!

      @packet_time_string = time_association_name

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
            # Get the Telemetry items to avoid clashing parameters
            if telemetry[target_name]
              unique_tlm_params = telemetry[target_name] ? get_unique(telemetry[target_name]) : {}
            else
              unique_tlm_params = {}
            end
            create_commands(xml, commands, target_name, unique_tlm_params)
            create_algorithms(xml, telemetry, target_name)
          end # SpaceSystem
        end # builder
        File.open(filename, 'w') do |file|
          file.puts builder.to_xml
        end
      end
    end

    def create_algorithms(xml, telemetry, target_name)
      return unless telemetry[target_name]
      derived = {}
      telemetry[target_name].each do |packet_name, packet|
        packet.sorted_items.each do |item|
          next if item.data_type != :DERIVED
          next if COSMOS_NATIVE_DERIVED_ITEMS.include?(item.name)
          next if item.name == @packet_time_string
          derived[packet_name] = item
        end
      end
      return unless derived.length > 0
      algorithm_xml = Nokogiri::XML::Builder.new do |alg_xml|
        alg_xml.AlgorithmSet do
          derived.each do |packet_name, item|
            rc = item.read_conversion
            # PythonProxy overrides .class to return a String, so handle both cases
            conv_name = if rc
              rc_class = rc.class
              rc_class.is_a?(String) ? rc_class : rc_class.name
            else
              "NoConversion"
            end
            alg_xml.CustomAlgorithm("name" => "#{packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_" \
                                    "#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_#{conv_name}") do
              alg_xml.ExternalAlgorithmSet do
                alg_xml.ExternalAlgorithm("implementationName" => "TODO", "algorithmLocation" => "TODO")
              end
              alg_xml.InputSet do
                alg_xml.InputParameterInstanceRef( :parameterRef => "TODO", :instance => "0", :useCalibratedValue => "TODO")
              end
              alg_xml.OutputSet do
                alg_xml.OutputParameterRef( :parameterRef => "#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}")
              end
              alg_xml.TriggerSet( :name => "triggerSet") do
                alg_xml.OnParameterUpdateTrigger( :parameterRef => "TODO")
              end
            end
          end
        end
      end
      xml['xtce'].comment "TODO \n#{algorithm_xml.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION | Nokogiri::XML::Node::SaveOptions::FORMAT)}\n"
    end

    def create_telemetry(xml, telemetry, target_name)
      # Gather and make unique all the packet items
      return unless telemetry[target_name]

      unique_items = get_unique(telemetry[target_name])
      has_packet_time = unique_items.include?(@packet_time_string)

      xml['xtce'].TelemetryMetaData do
        # The schema requires at least one child in each set, so emit neither when the
        # target's packets hold nothing but DERIVED items. DERIVED items produce a TODO
        # comment at most, never a ParameterType, so they don't count here.
        if unique_items.any? { |_item_name, item| item.data_type != :DERIVED }
          xml['xtce'].ParameterTypeSet do
            unique_items.each do |item_name, item|
              to_xtce_type(item, 'Parameter', xml)
            end
          end

          xml['xtce'].ParameterSet do
            unique_items.each do |item_name, item|
              to_xtce_item(item, 'Parameter', xml, has_packet_time: has_packet_time)
            end
          end
        end

        if telemetry[target_name]
          xml['xtce'].ContainerSet do
            telemetry[target_name].each do |packet_name, packet|
              # Replaces invalid characters if any exist
              attrs = { :name => packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR) }
              attrs['shortDescription'] = packet.description if packet.description
              container_name = packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)
              has_id_items = (packet.id_items && packet.id_items.length > 0)

              # RestrictionCriteria only exists on a BaseContainer, so a packet with ID
              # items needs something to inherit from: an abstract container holding the
              # entries, which the concrete container then restricts. Pointing the
              # BaseContainer at its own container instead would make it inherit from
              # itself, which is a cycle for any consumer that resolves inheritance.
              if has_id_items
                xml['xtce'].SequenceContainer(:name => "#{container_name}_Base", :abstract => "true") do
                  process_entry_list(xml, packet, :TELEMETRY)
                end
              end

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
                if has_id_items
                  # The entries come from the base container. EntryList is required.
                  xml['xtce'].EntryList
                  xml['xtce'].BaseContainer(:containerRef => "#{container_name}_Base") do
                    xml['xtce'].RestrictionCriteria do
                      xml['xtce'].ComparisonList do
                        packet.id_items.each do |item|
                          xml['xtce'].Comparison(:parameterRef => item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR), :value => item.id_value)
                        end
                      end
                    end
                  end
                else
                  process_entry_list(xml, packet, :TELEMETRY)
                end
              end # SequenceContainer
            end # telemetry.each
          end # ContainerSet
        end # if telemetry[target_name]
      end # TelemetryMetaData
    end

    def create_commands(xml, commands, target_name, unique_tlm_params = {})
      return unless commands[target_name]

      xml['xtce'].CommandMetaData do
        unique_id_items = get_unique_id_items(commands[target_name])
        # Create Parameters for any ID item so it can be used in a comparison.
        if unique_id_items.size > 0
          xml['xtce'].ParameterTypeSet do
            unique_id_items.each do |item_name, item|
              prefix = unique_tlm_params.include?(item_name) ? "CMD_" : ""
              to_xtce_type(item, 'Parameter', xml, prefix: prefix)
            end
          end
          xml['xtce'].ParameterSet do
            unique_id_items.each do |item_name, item|
              prefix = unique_tlm_params.include?(item_name) ? "CMD_" : ""
              to_xtce_item(item, 'Parameter', xml, prefix: prefix)
            end
          end
        end
        xml['xtce'].ArgumentTypeSet do
          commands[target_name].each do |packet_name, packet|
            packet.items.each do |arg_name, arg|
              next if arg.data_type == :DERIVED
              next if unique_id_items.key?(arg_name.tr(INVALID_CHARS, REPLACEMENT_CHAR))
              to_xtce_type(arg, 'Argument', xml, prefix: packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + "_")
            end
          end
        end
        xml['xtce'].MetaCommandSet do
          commands[target_name].each do |packet_name, packet|
            command_name = packet_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)
            attrs = { :name => command_name }
            attrs['shortDescription'] = packet.description if packet.description
            argument_list_sorted_items = get_sorted_non_id_items(packet.sorted_items)
            has_id_items = (packet.id_items && packet.id_items.length > 0)

            # Like telemetry above, the ID comparisons live in a RestrictionCriteria,
            # which only exists on a BaseContainer, so emit an abstract MetaCommand
            # holding the arguments and entries for the concrete one to inherit and
            # restrict. Referencing its own CommandContainer would be a cycle.
            if has_id_items
              xml['xtce'].MetaCommand(:name => "#{command_name}_Base", :abstract => "true") do
                if argument_list_sorted_items.size > 0
                  xml['xtce'].ArgumentList do
                    argument_list_sorted_items.each do |item|
                      to_xtce_item(item, 'Argument', xml, prefix: command_name + "_")
                    end
                  end # ArgumentList
                end
                xml['xtce'].CommandContainer(:name => "#{command_name}_CommandsBase") do
                  process_entry_list(xml, packet, :COMMAND, unique_tlm_params)
                end # Command Container
              end # MetaCommand
            end

            xml['xtce'].MetaCommand(attrs) do
              if packet_name.count(INVALID_CHARS) > 0
                xml['xtce'].AliasSet do
                  xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => packet_name)
                end # AliasSet
              end # If packet contains invalid chars
              if has_id_items
                xml['xtce'].BaseMetaCommand(:metaCommandRef => "#{command_name}_Base")
              elsif argument_list_sorted_items.size > 0
                xml['xtce'].ArgumentList do
                  argument_list_sorted_items.each do |item|
                    to_xtce_item(item, 'Argument', xml, prefix: command_name + "_")
                  end
                end # ArgumentList
              end # If Arguments List is greater than 0
              xml['xtce'].CommandContainer(:name => "#{command_name}_Commands") do
                if has_id_items
                  # The entries come from the base container. EntryList is required.
                  xml['xtce'].EntryList
                  # A CommandContainer allows only one BaseContainer, so emit all ID
                  # comparisons in a single RestrictionCriteria/ComparisonList.
                  xml['xtce'].BaseContainer(:containerRef => "#{command_name}_CommandsBase") do
                    xml['xtce'].RestrictionCriteria do
                      xml['xtce'].ComparisonList do
                        packet.id_items.each do |item|
                          item_prefix = unique_tlm_params.include?(item.name) ? "CMD_" : ""
                          xml['xtce'].Comparison(:parameterRef => item_prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR),:value => item.id_value)
                        end
                      end
                    end # Restriction Criteria
                  end # Base Container
                else
                  process_entry_list(xml, packet, :COMMAND, unique_tlm_params)
                end # If id items
              end # Command Container
            end # MetaCommand
          end # each command packet
        end # MetaCommandSet
      end # CommandMetaData
    end

    def get_numerical_item_initial_value(item)
      initial_value = nil
      if item.states && item.default && !item.array_size
        # Invert hash so we can get the initial value. If not found remove the initial value.
        inverted_enum_states = item.states.invert
        if inverted_enum_states.include?(item.default)
          initial_value = inverted_enum_states[item.default]
        end
      elsif item.default && !item.array_size
        initial_value = item.default
      end
      if initial_value == "1970-01-01T00:00:00Z"
      initial_value = 0
      end
      initial_value
    end

    # Ending index of an array item's single dimension. XTCE indices are inclusive, so
    # an array of N elements ends at N - 1. A non-positive bit size means a variable
    # length array whose element count isn't known at export time, reported as a single
    # element.
    def array_ending_index(item)
      return 0 if item.bit_size <= 0 || item.array_size <= 0

      (item.array_size / item.bit_size) - 1
    end

    # Initial value for a String or Binary type. Pass :BLOCK / 'Binary' for binary
    # items and :STRING / 'String' for string items.
    def get_string_or_block_initial_value(item, string_or_binary)
      initial_value = nil
      if item.default && !item.array_size
        if string_or_binary == :BLOCK || string_or_binary == 'Binary'
          # Binary initialValue is xs:hexBinary: raw hex digits, no 0x prefix
          initial_value = item.default.simple_formatted
        elsif !item.default.is_printable?
          initial_value = '0x' + item.default.simple_formatted
        else
          # String initialValue is the value itself. Quoting it (inspect) would make
          # the quotes part of the default for anything but our own importer.
          initial_value = item.default
        end
      end
      initial_value
    end

    def get_unique(items)
      unique = {}
      items.each do |packet_name, packet|
        packet.sorted_items.each do |item|
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] ||= []
          unique[item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] << item
        end
      end
      unique.each do |item_name, unique_items|
        if unique_items.length <= 1
          unique[item_name] = unique_items[0]
          next
        end
        unique[item_name] = unique_items[0]
      end
      unique
    end

    def get_sorted_non_id_items(items)
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
          unique[item_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] = unique_items[0]
          next
        end
        unique[item_name.tr(INVALID_CHARS, REPLACEMENT_CHAR)] = unique_items[0]
      end
      unique
    end

    # This method is almost the same for commands and telemetry except for the
    # XML element name: [Array]ArgumentRefEntry vs [Array]ParameterRefEntry,
    # and XML reference: argumentRef vs parameterRef.
    # Thus we build the name and use send to dynamically dispatch.
    def process_entry_list(xml, packet, cmd_vs_tlm, unique_tlm_params = {})
      if cmd_vs_tlm == :COMMAND
        type = "Argument"
      else # :TELEMETRY
        type = "Parameter"
      end
      xml['xtce'].EntryList do
        packed = packet.packed?
        packet.sorted_items.each do |item|
          next if item.data_type == :DERIVED
          temp_type = item.id_value ? "Parameter" : type
          # Only ID items become Parameters in CommandMetaData, where a name shared with
          # a telemetry parameter is a real collision and gets a CMD_ prefix. Arguments
          # are scoped to their MetaCommand and are declared unprefixed, so prefixing the
          # reference here would point at an Argument that doesn't exist.
          prefix = (temp_type == "Parameter" && cmd_vs_tlm == :COMMAND && unique_tlm_params.include?(item.name)) ? "CMD_" : ""
          if item.array_size
            # XTCE 1.2 defines dedicated argumentRef/parameterRef attributes for
            # Array{Argument,Parameter}RefEntry, so derive the reference from the type.
            reference_symbol = "#{temp_type.downcase}Ref".to_sym
            xml['xtce'].public_send("Array#{temp_type}RefEntry".intern, reference_symbol => prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)) do
              set_fixed_value(xml, item) if !packed
              xml['xtce'].DimensionList do
                xml['xtce'].Dimension do
                  xml['xtce'].StartingIndex do
                    xml['xtce'].FixedValue(0)
                  end
                  xml['xtce'].EndingIndex do
                    xml['xtce'].FixedValue(array_ending_index(item))
                  end
                end
              end
            end
          else
            if packed
              xml['xtce'].public_send("#{temp_type}RefEntry".intern, "#{temp_type.downcase}Ref".intern => prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR))
            else
              xml['xtce'].public_send("#{temp_type}RefEntry".intern, "#{temp_type.downcase}Ref".intern => prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)) do
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

    def to_xtce_type(item, param_or_arg, xml, prefix: "")
      case item.data_type
      when :INT, :UINT
        to_xtce_int(item, param_or_arg, xml, prefix:prefix)
      when :FLOAT
        to_xtce_float(item, param_or_arg, xml, prefix: prefix)
      when :STRING
        to_xtce_string(item, param_or_arg, xml, 'String', prefix: prefix)
      when :BLOCK
        to_xtce_string(item, param_or_arg, xml, 'Binary', prefix: prefix)
      when :DERIVED
        if !COSMOS_NATIVE_DERIVED_ITEMS.include?(item.name)
          to_xtce_derived(item, param_or_arg, xml, prefix: prefix)
        end
      end

      # Handle arrays
      if item.array_size
        # The above will have created the type for the array entries.   Now we create the type for the actual array.

        attrs = { :name => (prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_ArrayType') }
        attrs[:shortDescription] = item.description if item.description
        attrs[:arrayTypeRef] = (prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type')
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
                  # OpenC3 only supports one-dimensional arrays, which is the single
                  # Dimension above. The indices give that dimension's length.
                  xml['xtce'].text array_ending_index(item)
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

    def to_xtce_int(item, param_or_arg, xml, prefix: "")
      attrs = { :name => (prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type') }
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
        # Invert hash so we can get the initial value. If not found remove the initial value.
        inverted_enum_states = item.states.invert
        if inverted_enum_states.include?(item.default)
          attrs[:initialValue] = inverted_enum_states[item.default]
        else
          attrs.delete(:initialValue)
        end
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
            if item.endianness == :LITTLE_ENDIAN and item.bit_size >= 8
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding, :byteOrder => "leastSignificantByteFirst") do
                to_xtce_conversion(item, xml)
              end
            else
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding) do
                to_xtce_conversion(item, xml)
              end
            end
          else
            if item.endianness == :LITTLE_ENDIAN and item.bit_size >= 8
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding, :byteOrder => "leastSignificantByteFirst")
            else
              xml['xtce'].IntegerDataEncoding(:sizeInBits => item.bit_size, :encoding => encoding)
            end
          end
          # ValidRange comes from IntegerDataType and DefaultAlarm from
          # IntegerParameterType, which extends it, so ValidRange must be emitted first.
          to_xtce_valid_range(item, param_or_arg, xml)
          to_xtce_limits(item, xml)
        end # Type
      end # if item.states
    end

    def to_xtce_float(item, param_or_arg, xml, prefix: "")
      attrs = { :name => (prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type'), :sizeInBits => item.bit_size }
      attrs[:initialValue] = item.default if item.default and !item.array_size
      attrs[:shortDescription] = item.description if item.description
      xml['xtce'].public_send('Float' + param_or_arg + 'Type', attrs) do
        to_xtce_units(item, xml)
        if (item.read_conversion and item.read_conversion.class == PolynomialConversion) or (item.write_conversion and item.write_conversion.class == PolynomialConversion)
          if item.endianness == :LITTLE_ENDIAN and item.bit_size >= 8
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985', :byteOrder => "leastSignificantByteFirst") do
            to_xtce_conversion(item, xml)
          end
          else
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985') do
              to_xtce_conversion(item, xml)
            end
          end
        else
          if item.endianness == :LITTLE_ENDIAN and item.bit_size >= 8
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985', :byteOrder => "leastSignificantByteFirst")
          else
            xml['xtce'].FloatDataEncoding(:sizeInBits => item.bit_size, :encoding => 'IEEE754_1985')
          end
        end
        # ValidRange comes from FloatDataType and DefaultAlarm from FloatParameterType,
        # which extends it, so ValidRange must be emitted first.
        to_xtce_valid_range(item, param_or_arg, xml)
        to_xtce_limits(item, xml)
      end
    end

    # Emit the item minimum / maximum as an XTCE ValidRange. Arguments wrap it in a
    # ValidRangeSet; parameters use a bare ValidRange.
    def to_xtce_valid_range(item, param_or_arg, xml)
      return unless item.range

      minimum = item.range.first
      maximum = item.range.last
      if item.data_type == :INT or item.data_type == :UINT
        # IntegerRangeType is xs:long, so a wider range (a full 64 bit UINT, for
        # example) can't be expressed and is dropped rather than emitted invalid.
        return if minimum < XS_LONG_MIN or maximum > XS_LONG_MAX
      else
        # FloatRangeType is xs:double, which covers any finite float. Infinity and NaN
        # have no valid xs:double lexical form here, so skip them.
        return unless minimum.finite? and maximum.finite?
      end

      if param_or_arg == "Parameter"
        xml['xtce'].ValidRange(:minInclusive => minimum, :maxInclusive => maximum)
      else
        xml['xtce'].ValidRangeSet do
          xml['xtce'].ValidRange(:minInclusive => minimum, :maxInclusive => maximum)
        end
      end
    end

    def to_xtce_string(item, param_or_arg, xml, string_or_binary, prefix: "")
      attrs = { :name => (prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR) + '_Type') }
      attrs[:characterWidth] = 8 if string_or_binary == 'String'
      initial_value = get_string_or_block_initial_value(item, string_or_binary)
      attrs[:initialValue] = initial_value if initial_value
      attrs[:shortDescription] = item.description if item.description
      xml['xtce'].public_send(string_or_binary + param_or_arg + 'Type', attrs) do
        # Strings and Blocks don't get a byteOrder
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

    def to_xtce_derived(item, param_or_arg, xml, prefix: "")
      if item.name == @packet_time_string
        xml << "\n<!--TODO: \n" \
               "\t<xtce:AbsoluteTime#{param_or_arg}Type name=\"#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_Type\">\n" \
               "\t\t<TODO/>\n" \
               "\t</xtce:AbsoluteTime#{param_or_arg}Type>"
               "-->\n"
      else
        description_string = item.description ? "shortDescription=\"#{item.description}\"" : ""
        xml << "\n<!--TODO: \n" \
               "\t<xtce:TODO#{param_or_arg}Type name=\"#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_Type\" #{description_string} />\n" \
               "-->\n"
      end
    end

    def to_xtce_item(item, param_or_arg, xml, prefix: "", has_packet_time: false)
      replaced_item_name = prefix + item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)
      if item.array_size
        type_suffix = "_ArrayType"
      else
        type_suffix = "_Type"
      end
      attrs = {:name => replaced_item_name, "#{param_or_arg.downcase}TypeRef" => replaced_item_name + type_suffix}
      needs_alias = item.name.count(INVALID_CHARS) > 0 || !prefix.empty?
      if param_or_arg.downcase == "argument"
        # Set the name to just be the item name since ArgumentsTypes
        # will use the packet name as a prefix but not in the actual argument name.
        # Maintains the individual type between arguments with a shared name.
        needs_alias = item.name.count(INVALID_CHARS) > 0
        attrs[:name] = item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)
        initial_value = case item.data_type
        when :INT, :UINT, :FLOAT
          get_numerical_item_initial_value(item)
        when :STRING, :BLOCK
          get_string_or_block_initial_value(item, item.data_type)
        when :DERIVED
          nil
        end
        attrs[:initialValue] = initial_value
      end
      if item.data_type == :DERIVED
        if COSMOS_NATIVE_DERIVED_ITEMS.include?(item.name)
          return
        end
        parameter_comment = "\n<!-- TODO: \n" \
                 "\t<xtce:#{param_or_arg} name=\"#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}\" #{param_or_arg.downcase}TypeRef=\"#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}_Type\">\n" \
                 "\t\t<xtce:ParameterProperties dataSource=\"derived\"/>\n"

        if needs_alias
          parameter_comment += "\t\t<xtce:AliasSet>\n" \
                 "\t\t\t<xtce:Alias nameSpace=\"COSMOS\" alias=\"#{item.name.tr(INVALID_CHARS, REPLACEMENT_CHAR)}\"/>\n" \
                 "\t\t</xtce:AliasSet>\n"
        end
        parameter_comment += "\t</xtce:#{param_or_arg}>\n-->\n"
        xml << parameter_comment
      else
        xml['xtce'].public_send(param_or_arg, attrs) do
          if needs_alias
            xml['xtce'].AliasSet do
              xml['xtce'].Alias(:nameSpace => ALIAS_NAMESPACE, :alias => item.name)
            end
          end
          # The time item is the source of the association, so it doesn't get one -
          # pointing it at itself says a parameter is its own timestamp.
          if has_packet_time && item.name != @packet_time_string
            xml['xtce'].ParameterProperties do
              xml['xtce'].TimeAssociation(:parameterRef => @packet_time_string)
            end
          end
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
      end # if PolynomialConversion
    end
  end
end
