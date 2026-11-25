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
