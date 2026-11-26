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

    def imported_alarm_packet(bounds, inclusive: false, floating: false)
      flags = inclusive.is_a?(Array) ? inclusive : [inclusive] * 4
      attributes = flags.each_with_index.map { |flag, index| "#{index < 2 ? 'min' : 'max'}#{flag ? 'Inclusive' : 'Exclusive'}" }
      type = floating ? 'Float' : 'Integer'
      signed = floating ? '' : ' signed="true"'
      encoding = floating ? 'IEEE754_1985' : 'twosComplement'
      xml = <<~XML
        <xtce:SpaceSystem xmlns:xtce="http://www.omg.org/spec/XTCE/20180204" name="INST">
          <xtce:TelemetryMetaData>
            <xtce:ParameterTypeSet>
              <xtce:#{type}ParameterType name="TEMP_Type"#{signed}>
                <xtce:#{type}DataEncoding sizeInBits="64" encoding="#{encoding}"/>
                <xtce:DefaultAlarm><xtce:StaticAlarmRanges>
                  <xtce:WarningRange #{attributes[1]}="#{bounds[1]}" #{attributes[2]}="#{bounds[2]}"/>
                  <xtce:CriticalRange #{attributes[0]}="#{bounds[0]}" #{attributes[3]}="#{bounds[3]}"/>
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

    it 'rejects conflicting signedness before replacing an existing export' do
      config = parse_definition(<<~TXT)
        TELEMETRY INST UNSIGNED BIG_ENDIAN "Unsigned channel"
          APPEND_ITEM VALUE 16 UINT "Unsigned reading"
        TELEMETRY INST SIGNED BIG_ENDIAN "Signed channel"
          APPEND_ITEM VALUE 16 INT "Signed reading"
      TXT
      Dir.mktmpdir do |directory|
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, 'previous export')
        expect { XtceConverter.convert(config.commands, config.telemetry, directory, nil) }
          .to raise_error(/conflicting XTCE definitions/)
        expect(File.read(file)).to eq('previous export')
      end
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
        XtceConverter.convert(config.commands, config.telemetry, directory, nil)
        file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
        expect(XtceConverter.schema_errors(file)).to be_empty
        document = Nokogiri::XML(File.read(file))
        ns = { 'x' => XtceConverter::XTCE_1_2_NAMESPACE }
        expect(document.xpath("//x:Parameter[@name='VALUE']", ns).length).to eq(1)
        expect(document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", ns).length).to eq(2)
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
          XtceConverter.convert(config.commands, config.telemetry, directory, nil)
          file = File.join(directory, 'INST/cmd_tlm/inst.xtce')
          expect(XtceConverter.schema_errors(file)).to be_empty
          document = Nokogiri::XML(File.read(file))
          ns = { 'x' => XtceConverter::XTCE_1_2_NAMESPACE }
          expect(document.xpath("//x:Parameter[@name='VALUE']", ns).length).to eq(1)
          expect(document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", ns).length).to eq(1)
        end
      end
    end

    it 'keeps inclusive integer alarm boundaries in the less severe state' do
      packet = imported_alarm_packet([-80, -70, 60, 80], inclusive: true)
      { -81 => :RED_LOW, -80 => :YELLOW_LOW, -70 => :GREEN, 60 => :GREEN, 80 => :YELLOW_HIGH, 81 => :RED_HIGH }.each do |value, state|
        expect(alarm_state(packet, value)).to eq(state)
      end
    end

    it 'keeps inclusive floating alarm boundaries and their immediate neighbors distinct' do
      packet = imported_alarm_packet([-80, -70, 60, 80], inclusive: true, floating: true)
      { (-80.0).prev_float => :RED_LOW, -80.0 => :YELLOW_LOW, -70.0 => :GREEN,
        60.0 => :GREEN, 60.0.next_float => :YELLOW_HIGH, 80.0 => :YELLOW_HIGH, 80.0.next_float => :RED_HIGH }.each do |value, state|
        expect(alarm_state(packet, value, floating: true)).to eq(state)
      end
    end

    it 'handles inclusive and exclusive boundaries independently' do
      packet = imported_alarm_packet([-80, -70, 60, 80], inclusive: [true, false, true, false])
      { -80 => :YELLOW_LOW, -70 => :YELLOW_LOW, 60 => :GREEN, 80 => :RED_HIGH }.each do |value, state|
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

    it 'does not skip integer readings next to a large inclusive bound' do
      [2**53, 2**53 + 2, 2**54, 2**54 + 4, 2**63 - 1024].each do |upper|
        packet = imported_alarm_packet([-upper, -upper / 2, upper / 2, upper], inclusive: true)
        expect(alarm_state(packet, upper)).to eq(:YELLOW_HIGH)
        expect(alarm_state(packet, upper + 1)).to eq(:RED_HIGH)
        expect(alarm_state(packet, -upper)).to eq(:YELLOW_LOW)
        expect(alarm_state(packet, -upper - 1)).to eq(:RED_LOW)
      end
    end

    it 'retains float handling for small and fractional exclusive bounds' do
      bounds = [-80.5, -70.5, 60.5, 80.5]
      packet = imported_alarm_packet(bounds, floating: true)
      expect(packet.get_item('TEMP').limits.values[:DEFAULT]).to eq(bounds)
      expect(packet.get_item('TEMP').limits.values[:DEFAULT]).to all(be_a(Float))
      expect(alarm_state(packet, 80.5, floating: true)).to eq(:RED_HIGH)
    end

    it 'rejects non-finite inclusive bounds that have no representable neighbor' do
      expect { imported_alarm_packet([-80, -70, 60, '1e309'], inclusive: true) }
        .to raise_error(/Non-finite inclusive XTCE alarm bounds/)
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
  end
end
