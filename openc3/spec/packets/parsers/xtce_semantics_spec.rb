require 'spec_helper'
require 'openc3'
require 'openc3/packets/packet_config'
require 'openc3/packets/parsers/xtce_converter'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

module OpenC3
  describe 'XTCE semantic preservation' do
    def parse_definition(text)
      config = PacketConfig.new
      Tempfile.create('definition') do |file|
        file.write(text)
        file.flush
        config.process_file(file.path, 'INST')
      end
      config
    end

    def export_parameter_counts(config, directory)
      XtceConverter.convert(config.commands, config.telemetry, directory, nil)
      file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
      expect(XtceConverter.schema_errors(file)).to be_empty
      document = Nokogiri::XML(File.read(file))
      ns = { 'x' => XtceConverter::XTCE_1_2_NAMESPACE }
      [document.xpath("//x:Parameter[@name='VALUE']", ns).length,
       document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", ns).length]
    end

    def imported_alarm_packet(bounds, inclusive: true, floating: false, range_form: 'outside')
      flags = inclusive.is_a?(Array) ? inclusive : [inclusive] * 4
      attributes = flags.each_with_index.map { |flag, index| "#{index < 2 ? 'min' : 'max'}#{flag ? 'Inclusive' : 'Exclusive'}" }
      ranges = { 'WarningRange' => [1, 2], 'CriticalRange' => [0, 3] }.filter_map do |tag, indices|
        attrs = indices.filter_map { |index| "#{attributes[index]}=\"#{bounds[index]}\"" unless bounds[index].nil? }
        "<xtce:#{tag} #{attrs.join(' ')}/>" unless attrs.empty?
      end.join
      type = floating ? 'Float' : 'Integer'
      signed = floating ? '' : ' signed="true"'
      encoding = floating ? 'IEEE754_1985' : 'twosComplement'
      xml = <<~XML
        <xtce:SpaceSystem xmlns:xtce="http://www.omg.org/spec/XTCE/20180204" name="INST">
          <xtce:TelemetryMetaData>
            <xtce:ParameterTypeSet>
              <xtce:#{type}ParameterType name="TEMP_Type"#{signed}>
                <xtce:#{type}DataEncoding sizeInBits="64" encoding="#{encoding}"/>
                <xtce:DefaultAlarm><xtce:StaticAlarmRanges rangeForm="#{range_form}">
                  #{ranges}
                </xtce:StaticAlarmRanges></xtce:DefaultAlarm>
              </xtce:#{type}ParameterType>
            </xtce:ParameterTypeSet>
            <xtce:ParameterSet><xtce:Parameter name="TEMP" parameterTypeRef="TEMP_Type"/></xtce:ParameterSet>
            <xtce:ContainerSet><xtce:SequenceContainer name="STATUS"><xtce:EntryList>
              <xtce:ParameterRefEntry parameterRef="TEMP"/>
            </xtce:EntryList></xtce:SequenceContainer></xtce:ContainerSet>
          </xtce:TelemetryMetaData>
        </xtce:SpaceSystem>
      XML
      config = PacketConfig.new
      Tempfile.create(['alarm', '.xtce']) do |file|
        file.write(xml)
        file.flush
        expect(XtceConverter.schema_errors(file.path)).to be_empty
        config.process_file(file.path, 'INST')
      end
      config.telemetry['INST']['STATUS']
    end

    def alarm_state(packet, value, floating: false)
      packet.buffer = [value].pack(floating ? 'G' : 'q>')
      packet.check_limits
      expect(packet.read('TEMP')).to eq(value)
      packet.get_item('TEMP').limits.state
    end

    def duplicate_integer_definition(kind, data_type, bits: 8, offset: 0)
      %w[BIG_ENDIAN LITTLE_ENDIAN].each_with_index.map do |order, index|
        bit_offset = offset.is_a?(Array) ? offset[index] : offset
        field = if kind == 'COMMAND'
                  "ID_PARAMETER VALUE #{bit_offset} #{bits} #{data_type} MIN MAX #{index + 1} \"Value\""
                else
                  "ITEM VALUE #{bit_offset} #{bits} #{data_type} \"Value\""
                end
        "#{kind} INST PACKET#{index} #{order} \"Packet\"\n  #{field}\n"
      end.join
    end

    def duplicate_limits_definition(first, second)
      [first, second].each_with_index.map do |limits, index|
        "TELEMETRY INST PACKET#{index} BIG_ENDIAN \"Packet\"\n  APPEND_ITEM VALUE 64 INT \"Value\"\n    LIMITS DEFAULT 1 ENABLED #{limits.join(' ')}\n"
      end.join
    end

    def expect_export_rejection(config, message = /conflicting XTCE definitions/)
      Dir.mktmpdir do |directory|
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, 'previous export')
        expect { XtceConverter.convert(config.commands, config.telemetry, directory, nil) }
          .to raise_error(message)
        expect(File.read(file)).to eq('previous export')
      end
    end

    it 'rejects conflicting signedness before replacing an existing export' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST UNSIGNED BIG_ENDIAN "Unsigned channel"
          APPEND_ITEM VALUE 16 UINT "Unsigned reading"
        TELEMETRY INST SIGNED BIG_ENDIAN "Signed channel"
          APPEND_ITEM VALUE 16 INT "Signed reading"
      TXT
      expect_export_rejection(config)
    end

    it 'rejects conflicting limits on an otherwise identical binary type' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST CRITICAL BIG_ENDIAN "Critical channel"
          APPEND_ITEM TEMP 16 INT "Temperature"
            LIMITS DEFAULT 1 ENABLED 0 1 10 20
        TELEMETRY INST RELAXED BIG_ENDIAN "Relaxed channel"
          APPEND_ITEM TEMP 16 INT "Temperature"
            LIMITS DEFAULT 1 ENABLED 0 1 100 200
      TXT
      Dir.mktmpdir do |directory|
        expect { XtceConverter.convert(config.commands, config.telemetry, directory, nil) }
          .to raise_error(/conflicting XTCE definitions/)
      end
    end

    it 'shares equal definitions despite different descriptions' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST FIRST BIG_ENDIAN "First channel"
          APPEND_ITEM VALUE 16 UINT "First description"
        TELEMETRY INST SECOND BIG_ENDIAN "Second channel"
          APPEND_ITEM VALUE 16 UINT "Different description"
      TXT
      Dir.mktmpdir do |directory|
        expect(export_parameter_counts(config, directory)).to eq([1, 2])
      end
    end

    it 'ignores derived items that share a name with an emitted numeric item' do
      definitions = [
        "TELEMETRY INST NUMERIC BIG_ENDIAN \"Numeric\"\n  APPEND_ITEM VALUE 16 UINT \"Reading\"\n",
        "TELEMETRY INST COMPUTED BIG_ENDIAN \"Computed\"\n  APPEND_ITEM OTHER 16 UINT \"Wire field\"\n  APPEND_ITEM VALUE 0 DERIVED \"Computed field\"\n"
      ]
      [definitions, definitions.reverse].each do |ordered|
        config = parse_definition(ordered.join)
        Dir.mktmpdir do |directory|
          expect(export_parameter_counts(config, directory)).to eq([1, 1])
        end
      end
    end

    it 'matches the CCSDS outside-alarm example, including equality' do
      # CCSDS 660.1-G-2 4.3.2.3.7.2.1: inclusive endpoints are alarms.
      packet = imported_alarm_packet([-20, -5, 5, 20])
      { -21 => :RED_LOW, -20 => :RED_LOW, -19 => :YELLOW_LOW,
        -5 => :YELLOW_LOW, -4 => :GREEN, 0 => :GREEN, 4 => :GREEN,
        5 => :YELLOW_HIGH, 19 => :YELLOW_HIGH, 20 => :RED_HIGH }.each do |value, state|
        expect(alarm_state(packet, value)).to eq(state)
      end
    end

    it 'keeps exclusive floating alarm boundaries and their immediate neighbors distinct' do
      packet = imported_alarm_packet([-80, -70, 60, 80], inclusive: false, floating: true)
      { (-80.0).prev_float => :RED_LOW, -80.0 => :YELLOW_LOW, -70.0 => :GREEN,
        60.0 => :GREEN, 60.0.next_float => :YELLOW_HIGH, 80.0 => :YELLOW_HIGH, 80.0.next_float => :RED_HIGH }.each do |value, state|
        expect(alarm_state(packet, value, floating: true)).to eq(state)
      end
    end

    it 'handles inclusive and exclusive boundaries independently' do
      packet = imported_alarm_packet([-80, -70, 60, 80], inclusive: [true, false, true, false])
      { -80 => :RED_LOW, -70 => :GREEN, 60 => :YELLOW_HIGH, 80 => :YELLOW_HIGH }.each do |value, state|
        expect(alarm_state(packet, value)).to eq(state)
      end
    end

    it 'interprets XTCE alarm bounds as xs:double even on integer parameters' do
      # Unlike a COSMOS LIMITS literal, the XML attribute has an xs:double type.
      # 9007199254740993 therefore denotes the binary64 value 9007199254740992.
      packet = imported_alarm_packet([0, 1, 9007199254740990, 9007199254740993])
      expect(packet.get_item('TEMP').limits.values[:DEFAULT]).to eq([0.0, 1.0, 9007199254740990.0, 9007199254740992.0])
      expect(alarm_state(packet, 9007199254740991)).to eq(:YELLOW_HIGH)
      expect(alarm_state(packet, 9007199254740992)).to eq(:RED_HIGH)
    end

    it 'does not skip integer readings next to a large exclusive bound' do
      [2**53, 2**53 + 2, 2**54, 2**54 + 4, 2**63 - 1024].each do |upper|
        packet = imported_alarm_packet([-upper, -upper / 2, upper / 2, upper], inclusive: false)
        expect(alarm_state(packet, upper)).to eq(:YELLOW_HIGH)
        expect(alarm_state(packet, upper + 1)).to eq(:RED_HIGH)
        expect(alarm_state(packet, -upper)).to eq(:YELLOW_LOW)
        expect(alarm_state(packet, -upper - 1)).to eq(:RED_LOW)
      end
    end

    it 'retains float handling for small and fractional inclusive bounds' do
      bounds = [-80.5, -70.5, 60.5, 80.5]
      packet = imported_alarm_packet(bounds, floating: true)
      expect(packet.get_item('TEMP').limits.values[:DEFAULT]).to eq(bounds)
      expect(packet.get_item('TEMP').limits.values[:DEFAULT]).to all(be_a(Float))
      expect(alarm_state(packet, 80.5, floating: true)).to eq(:RED_HIGH)
    end

    it 'rejects non-finite exclusive bounds that have no representable neighbor' do
      expect { imported_alarm_packet([-80, -70, 60, '1e309'], inclusive: false) }
        .to raise_error(/Non-finite exclusive XTCE alarm bounds/)
    end

    it 'leaves absent alarm sides open and honors critical-only and warning-only ranges' do
      [
        [[nil, nil, 60, 80], { -100 => :GREEN, 0 => :GREEN, 60 => :YELLOW_HIGH, 80 => :RED_HIGH }],
        [[-80, -60, nil, nil], { 100 => :GREEN, 0 => :GREEN, -60 => :YELLOW_LOW, -80 => :RED_LOW }],
        [[nil, nil, nil, 80], { -100 => :GREEN, 0 => :GREEN, 79 => :GREEN, 80 => :RED_HIGH }],
        [[nil, nil, 60, nil], { -100 => :GREEN, 0 => :GREEN, 60 => :YELLOW_HIGH, 100 => :YELLOW_HIGH }]
      ].each do |bounds, observations|
        packet = imported_alarm_packet(bounds)
        observations.each { |value, state| expect(alarm_state(packet, value)).to eq(state) }
        # Open sides survive a native export/import rather than becoming zero.
        Dir.mktmpdir do |directory|
          XtceConverter.convert({}, { 'INST' => { 'STATUS' => packet } }, directory, nil)
          path = File.join(directory, 'INST/cmd_tlm/inst.xtce')
          expect(XtceConverter.schema_errors(path)).to be_empty
          config = PacketConfig.new
          config.process_file(path, 'INST')
          observations.each { |value, state| expect(alarm_state(config.telemetry['INST']['STATUS'], value)).to eq(state) }
        end
      end
    end

    it 'rejects inside or non-nested alarms instead of silently changing their meaning' do
      expect { imported_alarm_packet([-80, -70, 60, 80], range_form: 'inside') }
        .to raise_error(/inside alarm ranges are not supported/)
      expect { imported_alarm_packet([-80, -90, 60, 80]) }
        .to raise_error(/must be nested outside ranges/)
    end

    it 'rejects lossy integer alarm exports and preserves the previous output' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST STATUS BIG_ENDIAN "Large integer"
          APPEND_ITEM TEMP 64 INT "Temperature"
            LIMITS DEFAULT 1 ENABLED 0 1 9007199254740990 9007199254740993
      TXT
      Dir.mktmpdir do |directory|
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, 'previous export')
        expect { XtceConverter.convert(config.commands, config.telemetry, directory, nil) }
          .to raise_error(/cannot be represented exactly as an XTCE xs:double/)
        expect(File.read(file)).to eq('previous export')
        config.telemetry['INST']['STATUS'].get_item('TEMP').limits.values[:DEFAULT][3] = 9007199254740994
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        expect(XtceConverter.schema_errors(file)).to be_empty
        imported = PacketConfig.new
        imported.process_file(file, 'INST')
        expect(alarm_state(imported.telemetry['INST']['STATUS'], 9007199254740993)).to eq(:YELLOW_HIGH)
        expect(alarm_state(imported.telemetry['INST']['STATUS'], 9007199254740994)).to eq(:RED_HIGH)
      end
    end

    it 'rejects conflicting command ID wire types before replacing an existing export' do
      config = parse_definition(<<~TXT)
        COMMAND INST FIRST BIG_ENDIAN "First"
          APPEND_ID_PARAMETER OPCODE 8 UINT 1 1 1 "Opcode"
        COMMAND INST SECOND BIG_ENDIAN "Second"
          APPEND_ID_PARAMETER OPCODE 16 UINT 2 2 2 "Opcode"
      TXT
      expect_export_rejection(config, /Command ID 'OPCODE' has conflicting XTCE definitions/)
    end

    it 'preserves different command ID constants and command-scoped argument types' do
      config = parse_definition(<<~TXT)
        COMMAND INST FIRST BIG_ENDIAN "First"
          APPEND_ID_PARAMETER OPCODE 8 UINT 1 1 1 "Opcode"
          APPEND_PARAMETER VALUE 8 UINT 0 10 3 "Value"
        COMMAND INST SECOND BIG_ENDIAN "Second"
          APPEND_ID_PARAMETER OPCODE 8 UINT 2 2 2 "Opcode"
          APPEND_PARAMETER VALUE 16 UINT 0 1000 300 "Value"
      TXT
      Dir.mktmpdir do |directory|
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        expect(XtceConverter.schema_errors(file)).to be_empty
        imported = PacketConfig.new
        imported.process_file(file, 'INST')
        { 'FIRST' => [1, 8, 3], 'SECOND' => [2, 16, 300] }.each do |name, (id, bits, default)|
          packet = imported.commands['INST'][name]
          expect(packet.get_item('OPCODE').id_value).to eq(id)
          expect(packet.get_item('VALUE').bit_size).to eq(bits)
          expect(packet.get_item('VALUE').default).to eq(default)
        end
      end
    end

    it 'activates imported numeric alarms, including on cloned packets' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST STATUS BIG_ENDIAN "Temperature"
          APPEND_ITEM TEMP 16 INT "Temperature"
            LIMITS DEFAULT 1 ENABLED -80 -70 60 80
      TXT
      Dir.mktmpdir do |directory|
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        imported = PacketConfig.new
        imported.process_file(File.join(directory, 'INST/cmd_tlm/inst.xtce'), 'INST')
        packet = imported.telemetry['INST']['STATUS']
        [packet, packet.clone].each do |copy|
          copy.buffer = [81].pack('s>')
          copy.check_limits
          expect(copy.get_item('TEMP').limits.enabled).to be(true)
          expect(copy.get_item('TEMP').limits.state).to eq(:RED_HIGH)
          expect(copy.out_of_limits).to eq([['INST', 'STATUS', 'TEMP', :RED_HIGH]])
        end
      end
    end

    it 'preserves all boundary states through a native export and import' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST STATUS BIG_ENDIAN "Temperature"
          APPEND_ITEM TEMP 16 INT "Temperature"
            LIMITS DEFAULT 1 ENABLED -80 -70 60 80
      TXT
      source = config.telemetry['INST']['STATUS']
      Dir.mktmpdir do |directory|
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        imported = PacketConfig.new
        imported.process_file(File.join(directory, 'INST/cmd_tlm/inst.xtce'), 'INST')
        destination = imported.telemetry['INST']['STATUS']
        [-81, -80, -79, -70, -69, 0, 59, 60, 61, 79, 80, 81].each do |value|
          source.buffer = [value].pack('s>')
          destination.buffer = [value].pack('s>')
          source.check_limits
          destination.check_limits
          expect(destination.get_item('TEMP').limits.state).to eq(source.get_item('TEMP').limits.state)
        end
      end
    end

    it 'rejects inexact integer alarm exports without replacing an existing file' do
      [-1, 1].each do |sign|
        4.times do |index|
          limits = [0, 4, 8, 12].map { |offset| sign * 2**54 + offset }
          limits[index] += 1
          config = parse_definition("TELEMETRY INST STATUS BIG_ENDIAN \"Counter\"\n  APPEND_ITEM COUNT 64 INT \"Counter\"\n    LIMITS DEFAULT 1 ENABLED #{limits.join(' ')}\n")
          expect_export_rejection(config, /cannot be represented exactly as (?:an )?XTCE xs:double/)
        end
      end
    end

    it 'allows shared command ID encodings with different comparison values' do
      config = parse_definition(<<~TXT)
        COMMAND INST FIRST BIG_ENDIAN "First command"
          APPEND_ID_PARAMETER ID 8 UINT 0 255 1 "ID"
        COMMAND INST SECOND BIG_ENDIAN "Second command"
          APPEND_ID_PARAMETER ID 8 UINT 0 255 2 "ID"
      TXT
      Dir.mktmpdir do |directory|
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        expect(XtceConverter.schema_errors(file)).to be_empty
      end
    end

    it 'rejects colliding scoped command types before replacing an export' do
      config = parse_definition(<<~TXT)
        COMMAND INST FIRST_PART BIG_ENDIAN "First command"
          APPEND_PARAMETER VALUE 8 UINT 0 10 0 "First argument"
        COMMAND INST FIRST BIG_ENDIAN "Second command"
          APPEND_PARAMETER PART_VALUE 16 UINT 0 20 0 "Second argument"
      TXT
      expect_export_rejection(config)
    end

    it 'shares equivalent colliding scoped command types' do
      config = parse_definition(<<~TXT)
        COMMAND INST FIRST_PART BIG_ENDIAN "First command"
          APPEND_PARAMETER VALUE 8 UINT 0 10 0 "First argument"
        COMMAND INST FIRST BIG_ENDIAN "Second command"
          APPEND_PARAMETER PART_VALUE 8 UINT 0 10 0 "Second argument"
      TXT
      Dir.mktmpdir do |directory|
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        expect(XtceConverter.schema_errors(file)).to be_empty
        document = Nokogiri::XML(File.read(file))
        types = document.xpath("//*[local-name()='IntegerArgumentType']/@name").map(&:value)
        expect(types).to eq(['FIRST_PART_VALUE_Type'])
      end
    end
    it 'shares byte-aligned one-byte integer definitions across byte orders' do
      %w[TELEMETRY COMMAND].product(%w[INT UINT]).each do |kind, data_type|
        config = parse_definition(duplicate_integer_definition(kind, data_type))
        Dir.mktmpdir do |directory|
          XtceConverter.convert(config.commands, config.telemetry, directory, nil)
          file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
          expect(XtceConverter.schema_errors(file)).to be_empty
          document = Nokogiri::XML(File.read(file))
          expect(document.xpath("//*[local-name()='IntegerParameterType']").length).to eq(1)
        end
      end
    end

    it 'retains byte-order conflicts for unaligned and multi-byte integer fields' do
      %w[TELEMETRY COMMAND].product([[8, 9], [16, 0]]).each do |kind, (bits, offset)|
        config = parse_definition(duplicate_integer_definition(kind, 'UINT', bits: bits, offset: offset))
        expect_export_rejection(config)
      end
    end

    it 'retains endian conflicts when only one shared field is byte aligned' do
      %w[TELEMETRY COMMAND].each do |kind|
        definitions = duplicate_integer_definition(kind, 'UINT', offset: [9, 0]).lines.each_slice(2).map(&:join)
        [definitions, definitions.reverse].each do |ordered|
          expect_export_rejection(parse_definition(ordered.join))
        end
      end
    end

    it 'shares matching byte order across aligned and unaligned one-byte fields' do
      %w[TELEMETRY COMMAND].product(%w[BIG_ENDIAN LITTLE_ENDIAN]).each do |kind, order|
        definition = duplicate_integer_definition(kind, 'UINT', offset: [9, 0]).gsub(/BIG_ENDIAN|LITTLE_ENDIAN/, order)
        config = parse_definition(definition)
        Dir.mktmpdir do |directory|
          XtceConverter.convert(config.commands, config.telemetry, directory, nil)
          expect(XtceConverter.schema_errors(File.join(directory, 'INST/cmd_tlm/inst.xtce'))).to be_empty
        end
      end
    end

    it 'compares every colliding scoped command type when an argument is unaligned' do
      fields = [['FIRST_PART_MORE_VALUE', 'ITEM', 'LITTLE_ENDIAN', 0],
                ['FIRST_PART_MORE', 'VALUE_ITEM', 'BIG_ENDIAN', 0],
                ['FIRST_PART', 'MORE_VALUE_ITEM', 'LITTLE_ENDIAN', 9],
                ['FIRST', 'PART_MORE_VALUE_ITEM', 'LITTLE_ENDIAN', 0]]
      %w[INT UINT].each do |data_type|
        fields.permutation.each do |ordered|
          definition = ordered.map do |packet_name, item_name, order, offset|
            "COMMAND INST #{packet_name} #{order} \"Packet\"\n  PARAMETER #{item_name} #{offset} 8 #{data_type} 0 127 0 \"Value\"\n"
          end.join
          expect_export_rejection(parse_definition(definition))
        end
      end
    end

    it 'shares numerically equal alarm thresholds regardless of literal spelling' do
      [-1, 1].product((0...4).to_a).each do |sign, index|
        first = [0, 4, 8, 12].map { |offset| sign * 2**54 + offset }
        second = first.map(&:to_s)
        second[index] += '.0'
        config = parse_definition(duplicate_limits_definition(first, second))
        Dir.mktmpdir do |directory|
          expect(export_parameter_counts(config, directory)).to eq([1, 2])
        end
      end
    end

    it 'shares positive and negative zero alarm thresholds' do
      config = parse_definition(duplicate_limits_definition([-10, 0, 10, 20], [-10, '-0.0', 10, 20]))
      Dir.mktmpdir { |directory| expect(export_parameter_counts(config, directory)).to eq([1, 2]) }
    end

    it 'rejects coincident warning bounds that hide an inclusive critical upper endpoint' do
      [false, true].each do |floating|
        expect { imported_alarm_packet([-20, 80, 80, 80], floating: floating) }
          .to raise_error(/Coincident XTCE warning and critical bounds/)
      end
    end

    it 'retains coincident ranges whose native evaluation preserves critical severity' do
      { [-20, -20, 80, 80] => { -20 => :RED_LOW, 0 => :GREEN, 80 => :RED_HIGH },
        [-20, 0, 0, 80] => { -20 => :RED_LOW, 0 => :YELLOW_LOW, 80 => :RED_HIGH },
        [80, 80, 80, 80] => { 79 => :RED_LOW, 80 => :RED_LOW, 81 => :RED_HIGH } }.each do |bounds, observations|
        packet = imported_alarm_packet(bounds)
        observations.each { |value, state| expect(alarm_state(packet, value)).to eq(state) }
      end
    end

  end
end
