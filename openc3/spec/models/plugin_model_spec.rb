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

require 'spec_helper'
require 'openc3/models/plugin_model'
require 'openc3/models/scope_model'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe PluginModel do
    # Simple URL that is valid for testing (starts with /)
    URL = "URL /myurl"

    before(:each) do
      mock_redis()
    end

    # Bucket access is a side effect of install_phase2 that none of these
    # examples assert on.
    def stub_s3_client
      allow(Aws::S3::Client).to receive(:new).and_return(instance_double("Aws::S3::Client").as_null_object)
    end

    # install_phase2 reads eight fields off the gemspec and the examples differ
    # only in the two that decide needs_dependencies and img_path.
    def gem_spec_double(runtime_dependencies: [], metadata: {})
      spec = double("spec")
      allow(spec).to receive(:name).and_return("test-plugin")
      allow(spec).to receive(:version).and_return("1.0.0")
      allow(spec).to receive(:runtime_dependencies).and_return(runtime_dependencies)
      allow(spec).to receive(:metadata).and_return(metadata)
      allow(spec).to receive(:summary).and_return("Test plugin")
      allow(spec).to receive(:description).and_return("Test plugin description")
      allow(spec).to receive(:licenses).and_return([])
      allow(spec).to receive(:homepage).and_return(nil)
      spec
    end

    # These examples are about what install_phase2 records, not about what
    # deploying a tool or a target does.
    def expect_tool_and_target_deploy(variables = {"scope" => 'DEFAULT'})
      expect_any_instance_of(ToolModel).to receive(:deploy).with(anything, variables, validate_only: false).and_return(nil)
      expect_any_instance_of(TargetModel).to receive(:deploy).with(anything, variables, validate_only: false, upgrade_context: nil).and_return(nil)
    end

    describe "self.get" do
      it "returns the specified plugin" do
        model = PluginModel.new(name: "TEST1", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "TEST2", scope: "OTHER")
        model.create
        names = PluginModel.names(scope: "DEFAULT")
        plugin = PluginModel.get(name: names[0], scope: "DEFAULT")
        expect(plugin["name"]).to eq("TEST1__0")
      end
    end

    describe "self.names" do
      it "returns all plugin names" do
        model = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "SPEC", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "OTHER", scope: "OTHER")
        model.create
        names = PluginModel.names(scope: "DEFAULT")
        # contain_exactly doesn't care about ordering and neither do we
        expect(names).to contain_exactly("TEST__0", "SPEC__0")
        names = PluginModel.names(scope: "OTHER")
        expect(names).to contain_exactly("OTHER__0")
      end
    end

    describe "self.all" do
      it "returns all the parsed plugins" do
        model = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "SPEC", scope: "DEFAULT")
        model.create
        all = PluginModel.all(scope: "DEFAULT")
        expect(all.keys).to contain_exactly("TEST__0", "SPEC__0")
      end
    end

    describe "self.install_phase1" do
      it "parses the plugin variables" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE VAR1 10"
            file.puts "VARIABLE VAR2 HI THERE"
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, scope: "DEFAULT")
        expect(model['name']).to eql File.basename(__FILE__)
        expect(model['variables']['VAR1']).to eq({ 'value' => '10' })
        expect(model['variables']['VAR2']).to eq({ 'value' => 'HI THERE' })
      end

      it "parses VARIABLE_DESCRIPTION" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE port 8080"
            file.puts '  VARIABLE_DESCRIPTION "TCP port for the connection"'
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, scope: "DEFAULT")
        expect(model['variables']['port']).to eq({
          'value' => '8080',
          'description' => 'TCP port for the connection'
        })
      end

      it "parses VARIABLE_STATE" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE my_target INST"
            file.puts '  VARIABLE_DESCRIPTION "Select the target"'
            file.puts '  VARIABLE_STATE "Primary instrument" INST'
            file.puts '  VARIABLE_STATE "Secondary instrument" INST2'
            file.puts '  VARIABLE_STATE "Another"'
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, scope: "DEFAULT")
        expect(model['variables']['my_target']).to eq({
          'value' => 'INST',
          'description' => 'Select the target',
          'options' => [
            { 'value' => 'INST', 'text' => 'Primary instrument' },
            { 'value' => 'INST2', 'text' => 'Secondary instrument' },
            { 'value' => 'Another', 'text' => 'Another' }
          ]
        })
      end

      it "parses VARIABLE_STATE_SHOW" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE interface_type tcp"
            file.puts '  VARIABLE_STATE "TCP/IP" tcp'
            file.puts '    VARIABLE_STATE_SHOW hostname port'
            file.puts '    VARIABLE_STATE_SHOW port'
            file.puts '  VARIABLE_STATE "Serial" serial'
            file.puts '    VARIABLE_STATE_SHOW serial_port'
            file.puts '  VARIABLE_STATE "None" none'
            file.puts "VARIABLE hostname 127.0.0.1"
            file.puts "VARIABLE port 8080"
            file.puts "VARIABLE serial_port /dev/ttyUSB0"
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, scope: "DEFAULT")
        expect(model['variables']['interface_type']).to eq({
          'value' => 'tcp',
          'options' => [
            { 'value' => 'tcp', 'text' => 'TCP/IP', 'show' => ['hostname', 'port'] },
            { 'value' => 'serial', 'text' => 'Serial', 'show' => ['serial_port'] },
            { 'value' => 'none', 'text' => 'None' }
          ]
        })
        expect(model['variables']['hostname']).to eq({ 'value' => '127.0.0.1' })
      end

      it "parses VARIABLE_STATE_SET and applies the selected state's values" do
        model = phase1_with_plugin_txt([
          'VARIABLE interface_type serial',
          '  VARIABLE_STATE "TCP/IP" tcp',
          '    VARIABLE_STATE_SHOW port',
          '    VARIABLE_STATE_SET port 8080',
          '  VARIABLE_STATE "Serial" serial',
          '    VARIABLE_STATE_SHOW port baud_rate',
          '    VARIABLE_STATE_SET port /dev/ttyUSB0',
          '    VARIABLE_STATE_SET baud_rate 9600',
          '    VARIABLE_STATE_SET description Serial port interface',
          'VARIABLE port 0',
          'VARIABLE baud_rate 115200',
          'VARIABLE description none',
        ])
        expect(model['variables']['interface_type']['options'][0]['set']).to eq({ 'port' => '8080' })
        expect(model['variables']['interface_type']['options'][1]['set']).to eq({
          'port' => '/dev/ttyUSB0', 'baud_rate' => '9600', 'description' => 'Serial port interface'
        })
        # Initially selected state is serial so its values are applied
        expect(model['variables']['port']['value']).to eq '/dev/ttyUSB0'
        expect(model['variables']['baud_rate']['value']).to eq '9600'
        expect(model['variables']['description']['value']).to eq 'Serial port interface'
      end

      it "does not override existing variable values with VARIABLE_STATE_SET" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts 'VARIABLE interface_type serial'
            file.puts '  VARIABLE_STATE serial'
            file.puts '    VARIABLE_STATE_SET baud_rate 9600'
            file.puts 'VARIABLE baud_rate 115200'
          end
        end
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, existing_variables: { 'baud_rate' => '19200' }, scope: "DEFAULT")
        expect(model['variables']['baud_rate']['value']).to eq '19200'
      end

      it "raises error for VARIABLE_STATE_SET problems" do
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE_SET other 1', 'VARIABLE other 1']) }.to raise_error(/VARIABLE_STATE_SET must follow a VARIABLE_STATE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_SET missing 1']) }.to raise_error(/references undefined VARIABLE 'missing'/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_SET type udp']) }.to raise_error(/cannot reference itself/)
      end

      it "parses VARIABLE_DISCOVERY" do
        model = phase1_with_plugin_txt([
          'VARIABLE port /dev/ttyUSB0',
          '  VARIABLE_DISCOVERY openc3/discovery/serial_discovery.py',
          'VARIABLE serial_number nil',
          '  VARIABLE_STATE "Any controller" nil',
          '  VARIABLE_DISCOVERY openc3/discovery/hid_discovery.py 0x054C 0x0CE6',
        ])
        expect(model['variables']['port']).to eq({ 'value' => '/dev/ttyUSB0', 'discovery' => [{ 'discovery' => ['openc3/discovery/serial_discovery.py'] }] })
        expect(model['variables']['serial_number']['discovery']).to eq [{ 'discovery' => ['openc3/discovery/hid_discovery.py', '0x054C', '0x0CE6'] }]
        expect(model['variables']['serial_number']['options']).to eq [{ 'value' => 'nil', 'text' => 'Any controller' }]
      end

      it "parses multiple VARIABLE_DISCOVERY with VARIABLE_DISCOVERY_SET" do
        model = phase1_with_plugin_txt([
          'VARIABLE dual_sense_target_name DUALSENSE',
          'VARIABLE dual_sense_version 5',
          '  VARIABLE_STATE 5 5',
          '  VARIABLE_STATE 4 4',
          'VARIABLE dual_sense_serial_num None',
          '  VARIABLE_DISCOVERY openc3.discovery.hid_discovery 0x054C 0x05C4',
          '    VARIABLE_DISCOVERY_SET dual_sense_version 4',
          '  VARIABLE_DISCOVERY openc3.discovery.hid_discovery 0x054C 0x0CE6',
          '    VARIABLE_DISCOVERY_SET dual_sense_version 5',
          '    VARIABLE_DISCOVERY_SET dual_sense_target_name PS5 CONTROLLER',
        ])
        expect(model['variables']['dual_sense_serial_num']['discovery']).to eq [
          { 'discovery' => ['openc3.discovery.hid_discovery', '0x054C', '0x05C4'], 'set' => { 'dual_sense_version' => '4' } },
          { 'discovery' => ['openc3.discovery.hid_discovery', '0x054C', '0x0CE6'], 'set' => { 'dual_sense_version' => '5', 'dual_sense_target_name' => 'PS5 CONTROLLER' } },
        ]
      end

      it "raises error for VARIABLE_DISCOVERY problems" do
        expect { phase1_with_plugin_txt(['VARIABLE_DISCOVERY openc3/discovery/serial_discovery.py']) }.to raise_error(/VARIABLE_DISCOVERY must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE port 1', 'VARIABLE_DISCOVERY serial-discovery']) }.to raise_error(/requires a Python discovery class filename/)
        expect { phase1_with_plugin_txt(['VARIABLE port 1', 'VARIABLE_DISCOVERY openc3/discovery']) }.to raise_error(/requires a Python discovery class filename/)
      end

      it "parses VARIABLE_HIDDEN" do
        model = phase1_with_plugin_txt([
          'VARIABLE device shelly',
          '  VARIABLE_STATE Shelly shelly',
          '    VARIABLE_STATE_SET mdns_types _shelly._tcp.local.',
          '  VARIABLE_STATE Hue hue',
          '    VARIABLE_STATE_SET mdns_types _hue._tcp.local.',
          'VARIABLE mdns_types ""',
          '  VARIABLE_HIDDEN',
        ])
        expect(model['variables']['mdns_types']).to eq({ 'value' => '_shelly._tcp.local.', 'hidden' => true })
        expect { phase1_with_plugin_txt(['VARIABLE_HIDDEN']) }.to raise_error(/VARIABLE_HIDDEN must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_HIDDEN true']) }.to raise_error(/Too many parameters/)
      end

      it "parses VARIABLE_ADVANCED" do
        model = phase1_with_plugin_txt([
          'VARIABLE host 127.0.0.1',
          'VARIABLE timeout 10',
          '  VARIABLE_ADVANCED',
        ])
        expect(model['variables']['host']).to eq({ 'value' => '127.0.0.1' })
        expect(model['variables']['timeout']).to eq({ 'value' => '10', 'advanced' => true })
        expect { phase1_with_plugin_txt(['VARIABLE_ADVANCED']) }.to raise_error(/VARIABLE_ADVANCED must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_ADVANCED true']) }.to raise_error(/Too many parameters/)
      end

      it "sets hidden variables from the selected state on upgrade" do
        lines = [
          'VARIABLE device hue',
          '  VARIABLE_STATE Hue hue',
          '    VARIABLE_STATE_SET mdns_types _hue._tcp.local.',
          '    VARIABLE_STATE_SET host ""',
          'VARIABLE host ""',
          'VARIABLE mdns_types ""',
          '  VARIABLE_HIDDEN',
        ]
        existing = { 'device' => 'hue', 'host' => '10.0.0.5', 'mdns_types' => '_old._tcp.local.' }
        model = phase1_with_plugin_txt(lines, existing_variables: existing)
        # A user entered value is kept but the hidden value follows the new plugin.txt
        expect(model['variables']['host']['value']).to eq('10.0.0.5')
        expect(model['variables']['mdns_types']['value']).to eq('_hue._tcp.local.')
      end

      it "parses VARIABLE_DISCOVERY references to other variables" do
        model = phase1_with_plugin_txt([
          'VARIABLE host ""',
          '  VARIABLE_DISCOVERY openc3/discovery/zeroconf_discovery.py ${mdns_types}',
          'VARIABLE mdns_types _hue._tcp.local.',
          '  VARIABLE_HIDDEN',
        ])
        expect(model['variables']['host']['discovery']).to eq([{ 'discovery' => ['openc3/discovery/zeroconf_discovery.py', '${mdns_types}'] }])
        expect { phase1_with_plugin_txt(['VARIABLE host ""', 'VARIABLE_DISCOVERY a.b ${missing}']) }.to raise_error(/discovery 'a.b \$\{missing\}' references undefined VARIABLE 'missing'/)
        expect { phase1_with_plugin_txt(['VARIABLE host ""', 'VARIABLE_DISCOVERY a.b x${host}']) }.to raise_error(/cannot reference itself/)
      end

      it "raises error for VARIABLE_DISCOVERY_SET problems" do
        expect { phase1_with_plugin_txt(['VARIABLE port 1', 'VARIABLE_DISCOVERY_SET other 1', 'VARIABLE other 1']) }.to raise_error(/VARIABLE_DISCOVERY_SET must follow a VARIABLE_DISCOVERY definition/)
        expect { phase1_with_plugin_txt(['VARIABLE port 1', 'VARIABLE_DISCOVERY a.b', 'VARIABLE_DISCOVERY_SET missing 1']) }.to raise_error(/discovery 'a.b' references undefined VARIABLE 'missing'/)
        expect { phase1_with_plugin_txt(['VARIABLE port 1', 'VARIABLE_DISCOVERY a.b', 'VARIABLE_DISCOVERY_SET port 1']) }.to raise_error(/cannot reference itself/)
      end

      it "parses VARIABLE_BRIDGE" do
        model = phase1_with_plugin_txt([
          'VARIABLE_BRIDGE',
          '  VARIABLE_DESCRIPTION "Bridge to the host with the hardware"',
          'VARIABLE port /dev/ttyUSB0',
        ])
        expect(model['variables']['bridge_name']).to eq({
          'value' => 'DEFAULT', 'bridge' => true, 'description' => 'Bridge to the host with the hardware'
        })
        model = phase1_with_plugin_txt(['VARIABLE_BRIDGE lab'])
        expect(model['variables']['bridge_name']['value']).to eq 'LAB'
      end

      it "keeps the existing bridge_name on upgrade" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') { |file| file.puts 'VARIABLE_BRIDGE' }
        end
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, existing_variables: { 'bridge_name' => { 'value' => 'LAB' } }, scope: "DEFAULT")
        expect(model['variables']['bridge_name']).to eq({ 'value' => 'LAB', 'bridge' => true })
      end

      it "raises error for redefining bridge_name" do
        expect { phase1_with_plugin_txt(['VARIABLE_BRIDGE', 'VARIABLE bridge_name X']) }.to raise_error(/defined by VARIABLE_BRIDGE/)
        expect { phase1_with_plugin_txt(['VARIABLE bridge_name X', 'VARIABLE_BRIDGE']) }.to raise_error(/defined by VARIABLE_BRIDGE/)
        expect { phase1_with_plugin_txt(['VARIABLE_BRIDGE', 'VARIABLE_BRIDGE']) }.to raise_error(/defined by VARIABLE_BRIDGE/)
        expect { phase1_with_plugin_txt(['VARIABLE_BRIDGE A B']) }.to raise_error(/Too many parameters/)
      end

      it "makes bridge_name available to ERB in phase 2" do
        stub_s3_client
        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files)
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)
        expect(GemModel).to receive(:install).and_return(nil)
        variables = { "bridge_name" => { "value" => "LAB", "bridge" => true } }
        expect_any_instance_of(ToolModel).to receive(:deploy).with(anything, { "bridge_name" => "LAB", "scope" => "DEFAULT" }, validate_only: false).and_return(nil)
        PluginModel.install_phase2({"name" => "name", "variables" => variables, "plugin_txt_lines" => ["VARIABLE_BRIDGE", "TOOL <%= bridge_name %> NAME", "  #{URL}"]}, scope: "DEFAULT")
        expect(ToolModel.get(name: "NAME", scope: "DEFAULT")['folder_name']).to eq "LAB"
      end

      it "captures PLUGIN_TEXT_START / PLUGIN_TEXT_END markdown" do
        model = phase1_with_plugin_txt([
          'PLUGIN_TEXT_START',
          '  # Instrument Plugin',
          '',
          '  Select the **interface type** first. Don\'t forget "quotes" \\',
          '    - indented item',
          '  VARIABLE not_a_variable 1',
          'PLUGIN_TEXT_END',
          'VARIABLE port 8080',
          '  PLUGIN_TEXT_START',
          '  Second block',
          '  PLUGIN_TEXT_END',
        ])
        expect(model['plugin_text']).to eq "# Instrument Plugin\n\nSelect the **interface type** first. Don't forget \"quotes\" \\\n  - indented item\nVARIABLE not_a_variable 1\n\nSecond block"
        expect(model['variables'].keys).to eq ['port']
      end

      it "captures VARIABLE_TEXT_START / VARIABLE_TEXT_END markdown for the previous VARIABLE_STATE" do
        model = phase1_with_plugin_txt([
          'VARIABLE type tcp',
          '  VARIABLE_STATE TCP tcp',
          '    VARIABLE_TEXT_START',
          '    ## TCP',
          '    Enter the **host**.',
          '      VARIABLE_STATE_SHOW not_a_keyword',
          '    VARIABLE_TEXT_END',
          '    VARIABLE_TEXT_START',
          '    More',
          '    VARIABLE_TEXT_END',
          '  VARIABLE_STATE Serial serial',
          '    VARIABLE_STATE_SET port 1',
          'VARIABLE port 0',
        ])
        expect(model['variables']['type']['options']).to eq [
          { 'value' => 'tcp', 'text' => 'TCP', 'markdown' => "## TCP\nEnter the **host**.\n  VARIABLE_STATE_SHOW not_a_keyword\n\nMore" },
          { 'value' => 'serial', 'text' => 'Serial', 'set' => { 'port' => '1' } },
        ]
      end

      it "raises error for VARIABLE_TEXT_START / VARIABLE_TEXT_END problems" do
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_TEXT_START', 'VARIABLE_TEXT_END']) }.to raise_error(/VARIABLE_TEXT_START must follow a VARIABLE_STATE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_STATE One 1', 'VARIABLE_TEXT_START', 'Text']) }.to raise_error(/VARIABLE_TEXT_START without a matching VARIABLE_TEXT_END/)
        expect { phase1_with_plugin_txt(['VARIABLE_TEXT_END']) }.to raise_error(/VARIABLE_TEXT_END must follow a VARIABLE_TEXT_START/)
      end

      it "parses VARIABLE_LABEL, VARIABLE_TYPE, VARIABLE_REQUIRED and VARIABLE_PATTERN" do
        model = phase1_with_plugin_txt([
          'VARIABLE port 8080',
          '  VARIABLE_LABEL "TCP Port"',
          '  VARIABLE_TYPE integer',
          '  VARIABLE_REQUIRED',
          'VARIABLE name ""',
          '  VARIABLE_PATTERN "[A-Z_]+" "Use capital letters"',
          'VARIABLE id ""',
          '  VARIABLE_PATTERN "\\d+"',
        ])
        expect(model['variables']['port']).to eq({ 'value' => '8080', 'label' => 'TCP Port', 'type' => 'INTEGER', 'required' => true })
        expect(model['variables']['name']).to eq({ 'value' => '', 'pattern' => '[A-Z_]+', 'pattern_message' => 'Use capital letters' })
        expect(model['variables']['id']).to eq({ 'value' => '', 'pattern' => '\\d+' })
      end

      it "raises error for VARIABLE_LABEL, VARIABLE_TYPE, VARIABLE_REQUIRED and VARIABLE_PATTERN problems" do
        %w(VARIABLE_LABEL VARIABLE_TYPE VARIABLE_REQUIRED VARIABLE_PATTERN).each do |keyword|
          expect { phase1_with_plugin_txt(["#{keyword} x"]) }.to raise_error(/#{keyword} must follow a VARIABLE definition|Too many parameters/)
        end
        expect { phase1_with_plugin_txt(['VARIABLE_REQUIRED']) }.to raise_error(/VARIABLE_REQUIRED must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_TYPE DATE']) }.to raise_error(/VARIABLE_TYPE must be one of TEXT, BOOLEAN/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_PATTERN "("']) }.to raise_error(/not a valid regular expression/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_LABEL']) }.to raise_error(/Not enough parameters/)
      end

      it "parses VARIABLE_MULTIPLE with its default states as an Array" do
        model = phase1_with_plugin_txt([
          'VARIABLE sensors "TEMP1, PRESS"',
          '  VARIABLE_MULTIPLE',
          '  VARIABLE_STATE "Temperature 1" TEMP1',
          '  VARIABLE_STATE "Temperature 2" TEMP2',
          '  VARIABLE_STATE "Pressure" PRESS',
          'VARIABLE none ""',
          '  VARIABLE_MULTIPLE',
          '  VARIABLE_STATE A',
        ])
        expect(model['variables']['sensors']['multiple']).to be true
        expect(model['variables']['sensors']['value']).to eq %w(TEMP1 PRESS)
        expect(model['variables']['none']['value']).to eq []
        erb = PluginModel.erb_variables(model, scope: 'DEFAULT')
        expect(erb['sensors']).to eq %w(TEMP1 PRESS)
        expect(erb['none']).to eq []
      end

      it "applies the VARIABLE_STATE_SETs of every selected VARIABLE_MULTIPLE state" do
        model = phase1_with_plugin_txt([
          'VARIABLE sensors TEMP,PRESS',
          '  VARIABLE_MULTIPLE',
          '  VARIABLE_STATE Temperature TEMP',
          '    VARIABLE_STATE_SET temp_rate 10',
          '  VARIABLE_STATE Pressure PRESS',
          '    VARIABLE_STATE_SET press_rate 5',
          '  VARIABLE_STATE Humidity HUM',
          '    VARIABLE_STATE_SET hum_rate 1',
          'VARIABLE temp_rate 0',
          'VARIABLE press_rate 0',
          'VARIABLE hum_rate 0',
          'VARIABLE preset basic',
          '  VARIABLE_STATE Basic basic',
          '    VARIABLE_STATE_SET extras "HUM, TEMP"',
          'VARIABLE extras ""',
          '  VARIABLE_MULTIPLE',
          '  VARIABLE_STATE Temperature TEMP',
          '  VARIABLE_STATE Humidity HUM',
        ])
        expect(model['variables']['temp_rate']['value']).to eq '10'
        expect(model['variables']['press_rate']['value']).to eq '5'
        expect(model['variables']['hum_rate']['value']).to eq '0'
        # A VARIABLE_STATE_SET of a VARIABLE_MULTIPLE gives its values separated by commas
        expect(model['variables']['extras']['value']).to eq %w(HUM TEMP)
      end

      it "keeps the existing values of a VARIABLE_MULTIPLE that are still states" do
        lines = [
          'VARIABLE sensors TEMP',
          '  VARIABLE_MULTIPLE',
          '  VARIABLE_STATE Temperature TEMP',
          '  VARIABLE_STATE Pressure PRESS',
          'VARIABLE single A',
        ]
        model = phase1_with_plugin_txt(lines, existing_variables: { 'sensors' => { 'value' => %w(PRESS REMOVED) }, 'single' => { 'value' => %w(A B) } })
        expect(model['variables']['sensors']['value']).to eq %w(PRESS)
        # No longer VARIABLE_MULTIPLE
        expect(model['variables']['single']['value']).to eq 'A,B'
        # Not VARIABLE_MULTIPLE before
        model = phase1_with_plugin_txt(lines, existing_variables: { 'sensors' => 'PRESS' })
        expect(model['variables']['sensors']['value']).to eq %w(PRESS)
      end

      it "raises error for VARIABLE_MULTIPLE problems" do
        states = ['  VARIABLE_STATE A', '  VARIABLE_STATE B']
        expect { phase1_with_plugin_txt(['VARIABLE_MULTIPLE']) }.to raise_error(/VARIABLE_MULTIPLE must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE yes'] + states) }.to raise_error(/Too many parameters/)
        expect { phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE']) }.to raise_error(/VARIABLE_MULTIPLE 'x' requires VARIABLE_STATEs/)
        expect { phase1_with_plugin_txt(['VARIABLE x A,C', 'VARIABLE_MULTIPLE'] + states) }.to raise_error(/default 'C' is not one of its VARIABLE_STATE values: A, B/)
        expect { phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE', 'VARIABLE_TYPE TEXT'] + states) }.to raise_error(/cannot use VARIABLE_TYPE/)
        expect { phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE', 'VARIABLE_PATTERN "[AB]"'] + states) }.to raise_error(/cannot use VARIABLE_PATTERN/)
        expect { phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE', 'VARIABLE_DISCOVERY openc3.discovery.serial_discovery'] + states) }.to raise_error(/cannot use VARIABLE_DISCOVERY/)
        expect { phase1_with_plugin_txt(['VARIABLE_BRIDGE', 'VARIABLE_MULTIPLE'] + states) }.to raise_error(/cannot be a VARIABLE_BRIDGE/)
        expect { phase1_with_plugin_txt(['VARIABLE_FILE x data/x.csv', 'VARIABLE_MULTIPLE'] + states) }.to raise_error(/cannot be a VARIABLE_FILE/)
        expect {
          phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE', 'VARIABLE_STATE A', 'VARIABLE_STATE_SET y 1', 'VARIABLE_STATE B', 'VARIABLE_STATE_SET y 2', 'VARIABLE y 0'])
        }.to raise_error(/states 'A' and 'B' both set VARIABLE 'y'/)
        expect {
          phase1_with_plugin_txt(['VARIABLE x A', 'VARIABLE_MULTIPLE'] + states + ['VARIABLE port ""', 'VARIABLE_DISCOVERY openc3.discovery.serial_discovery ${x}'])
        }.to raise_error(/cannot use VARIABLE_MULTIPLE variable 'x' as a parameter/)
      end

      it "parses VARIABLE_GROUP and VARIABLE_TYPE SECRET" do
        model = phase1_with_plugin_txt([
          'VARIABLE host ""',
          '  VARIABLE_GROUP Connection',
          'VARIABLE password_secret ""',
          '  VARIABLE_TYPE secret',
          '  VARIABLE_GROUP "Sign In"',
        ])
        expect(model['variables']['host']).to eq({ 'value' => '', 'group' => 'Connection' })
        expect(model['variables']['password_secret']).to eq({ 'value' => '', 'type' => 'SECRET', 'group' => 'Sign In' })
        expect { phase1_with_plugin_txt(['VARIABLE_GROUP Connection']) }.to raise_error(/VARIABLE_GROUP must follow a VARIABLE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE x 1', 'VARIABLE_GROUP']) }.to raise_error(/Not enough parameters/)
      end

      it "parses VARIABLE_STATE_DESCRIPTION and VARIABLE_STATE_ICON" do
        model = phase1_with_plugin_txt([
          'VARIABLE type tcp',
          '  VARIABLE_STATE "TCP/IP" tcp',
          '    VARIABLE_STATE_DESCRIPTION "Ethernet or Wi-Fi"',
          '    VARIABLE_STATE_ICON mdi-lan',
          '  VARIABLE_STATE Serial serial',
        ])
        expect(model['variables']['type']['options']).to eq [
          { 'value' => 'tcp', 'text' => 'TCP/IP', 'description' => 'Ethernet or Wi-Fi', 'icon' => 'mdi-lan' },
          { 'value' => 'serial', 'text' => 'Serial' },
        ]
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE_ICON mdi-lan']) }.to raise_error(/VARIABLE_STATE_ICON must follow a VARIABLE_STATE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_ICON "<b>"']) }.to raise_error(/not a valid icon name/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE_DESCRIPTION Text']) }.to raise_error(/VARIABLE_STATE_DESCRIPTION must follow a VARIABLE_STATE definition/)
      end

      it "parses VARIABLE_STATE_REQUIRED" do
        model = phase1_with_plugin_txt([
          'VARIABLE type tcp',
          '  VARIABLE_STATE TCP tcp',
          '    VARIABLE_STATE_SHOW host port',
          '    VARIABLE_STATE_REQUIRED host',
          '    VARIABLE_STATE_REQUIRED host port',
          'VARIABLE host ""',
          'VARIABLE port 80',
        ])
        expect(model['variables']['type']['options'][0]['required']).to eq ['host', 'port']
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE_REQUIRED host']) }.to raise_error(/VARIABLE_STATE_REQUIRED must follow a VARIABLE_STATE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_REQUIRED missing']) }.to raise_error(/references undefined VARIABLE 'missing'/)
      end

      it "returns nil plugin_text without PLUGIN_TEXT_START" do
        model = phase1_with_plugin_txt(['VARIABLE port 8080'])
        expect(model['plugin_text']).to be_nil
      end

      it "raises error for unbalanced PLUGIN_TEXT_START / PLUGIN_TEXT_END" do
        expect { phase1_with_plugin_txt(['PLUGIN_TEXT_START', 'Text']) }.to raise_error(/PLUGIN_TEXT_START without a matching PLUGIN_TEXT_END/)
        expect { phase1_with_plugin_txt(['PLUGIN_TEXT_END']) }.to raise_error(/PLUGIN_TEXT_END must follow a PLUGIN_TEXT_START/)
      end

      def phase1_with_plugin_txt(lines, existing_variables: nil)
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            lines.each { |line| file.puts line }
          end
        end
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        PluginModel.install_phase1(__FILE__, existing_variables: existing_variables, scope: "DEFAULT")
      end

      it "raises error for VARIABLE_STATE_SHOW without VARIABLE_STATE" do
        expect { phase1_with_plugin_txt(['VARIABLE_STATE_SHOW other']) }.to raise_error(/VARIABLE_STATE_SHOW must follow a VARIABLE_STATE definition/)
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE_SHOW other', 'VARIABLE other 1']) }.to raise_error(/VARIABLE_STATE_SHOW must follow a VARIABLE_STATE definition/)
      end

      it "raises error for VARIABLE_STATE_SHOW referencing an undefined variable" do
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_SHOW missing']) }.to raise_error(/references undefined VARIABLE 'missing'/)
      end

      it "raises error for VARIABLE_STATE_SHOW referencing itself" do
        expect { phase1_with_plugin_txt(['VARIABLE type tcp', 'VARIABLE_STATE tcp', 'VARIABLE_STATE_SHOW type']) }.to raise_error(/cannot reference itself/)
      end

      it "raises error for VARIABLE_DESCRIPTION without VARIABLE" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts 'VARIABLE_DESCRIPTION "Description"'
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        expect { PluginModel.install_phase1(__FILE__, scope: "DEFAULT") }.to raise_error(/VARIABLE_DESCRIPTION must follow a VARIABLE definition/)
      end

      it "raises error for VARIABLE_STATE without VARIABLE" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts 'VARIABLE_STATE "Display Text" VALUE'
          end
        end
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        expect { PluginModel.install_phase1(__FILE__, scope: "DEFAULT") }.to raise_error(/VARIABLE_STATE must follow a VARIABLE definition/)
      end

      it "processes existing plugin.txt lines" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        # No gem.extract_files because we're using the existing
        existing = []
        existing << "VARIABLE VAR1 11"
        existing << "VARIABLE VAR2 NOPE"
        expect(Gem::Package).to receive(:new).and_return(gem)
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        model = PluginModel.install_phase1(__FILE__, existing_plugin_txt_lines: existing, process_existing: true, scope: "DEFAULT")
        expect(model['name']).to eql File.basename(__FILE__)
        expect(model['variables']['VAR1']).to eq({ 'value' => '11' })
        expect(model['variables']['VAR2']).to eq({ 'value' => 'NOPE' })
      end

      it "processes existing variables in new format" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        # No gem.extract_files because we're using the existing
        existing_plugin_txt = []
        existing_plugin_txt << "VARIABLE VAR1 11"
        existing_plugin_txt << "VARIABLE VAR2 NOPE"
        existing_vars = { "VAR1" => { 'value' => "12" }, "VAR2" => { 'value' => "YES" } }
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        model = PluginModel.install_phase1(__FILE__, existing_variables: existing_vars, existing_plugin_txt_lines: existing_plugin_txt, process_existing: true, scope: "DEFAULT")
        expect(model['name']).to eql File.basename(__FILE__)
        expect(model['variables']['VAR1']['value']).to eq('12')
        expect(model['variables']['VAR2']['value']).to eq('YES')
      end

      it "processes existing variables in old format for backwards compatibility" do
        expect(GemModel).to receive(:put)
        gem = double("gem")
        # No gem.extract_files because we're using the existing
        existing_plugin_txt = []
        existing_plugin_txt << "VARIABLE VAR1 11"
        existing_plugin_txt << "VARIABLE VAR2 NOPE"
        # Old format: simple string values
        existing_vars = { "VAR1" => "12", "VAR2" => "YES" }
        expect(Gem::Package).to receive(:new).and_return(gem)
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        model = PluginModel.install_phase1(__FILE__, existing_variables: existing_vars, existing_plugin_txt_lines: existing_plugin_txt, process_existing: true, scope: "DEFAULT")
        expect(model['name']).to eql File.basename(__FILE__)
        expect(model['variables']['VAR1']['value']).to eq('12')
        expect(model['variables']['VAR2']['value']).to eq('YES')
      end

      it "does not allow reserved VARIABLE names" do
        allow(GemModel).to receive(:put)
        gem = double("gem")
        allow(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE target_name name"
          end
        end
        allow(Gem::Package).to receive(:new).and_return(gem)
        spec = double("spec")
        metadata = { "openc3_cosmos_minimum_version" => "6.0.0" }
        allow(spec).to receive(:metadata).and_return(metadata)
        allow(gem).to receive(:spec).and_return(spec)
        expect { PluginModel.install_phase1(__FILE__, scope: "DEFAULT") }.to raise_error(/VARIABLE name 'target_name' is reserved/)

        allow(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "VARIABLE microservice_name name"
          end
        end
        expect { PluginModel.install_phase1(__FILE__, scope: "DEFAULT") }.to raise_error(/VARIABLE name 'microservice_name' is reserved/)
      end
    end

    describe "self.discovery_claims" do
      def serial_variable(value, discovery = 'openc3/discovery/serial_discovery.py')
        { 'value' => value, 'discovery' => [{ 'discovery' => [discovery] }] }
      end

      before(:each) do
        PluginModel.new(name: "SERIAL__0", scope: "DEFAULT", variables: {
          'port' => serial_variable('/dev/ttyUSB0'),
          'other' => { 'value' => '/dev/ttyUSB9' },
        }).create
        PluginModel.new(name: "SERIAL__1", scope: "DEFAULT", variables: {
          'port' => serial_variable('/dev/ttyUSB1', 'openc3.discovery.serial_discovery'),
        }).create
        PluginModel.new(name: "LAB__0", scope: "DEFAULT", variables: {
          'bridge_name' => { 'value' => 'lab', 'bridge' => true },
          'port' => serial_variable('/dev/ttyUSB2'),
        }).create
        PluginModel.new(name: "HID__0", scope: "DEFAULT", variables: {
          'serial' => { 'value' => 'abc', 'discovery' => [
            { 'discovery' => ['openc3.discovery.hid_discovery', '0x054C', '0x05C4'] },
            { 'discovery' => ['openc3.discovery.hid_discovery', '0x054C', '0x0CE6'] },
          ] },
        }).create
        PluginModel.new(name: "OLD__0", scope: "DEFAULT", variables: { 'port' => '/dev/ttyUSB3' }).create
      end

      it "returns values claimed on the bridge for the discovery class" do
        expect(PluginModel.discovery_claims('DEFAULT', 'openc3.discovery.serial_discovery', scope: 'DEFAULT')).to eq({
          '/dev/ttyUSB0' => 'SERIAL__0', '/dev/ttyUSB1' => 'SERIAL__1'
        })
        expect(PluginModel.discovery_claims('lab', 'openc3/discovery/serial_discovery.py', scope: 'DEFAULT')).to eq({ '/dev/ttyUSB2' => 'LAB__0' })
        expect(PluginModel.discovery_claims('DEFAULT', 'openc3/discovery/hid_discovery.py', scope: 'DEFAULT')).to eq({ 'abc' => 'HID__0' })
      end

      it "excludes the plugin being upgraded" do
        expect(PluginModel.discovery_claims('DEFAULT', 'openc3/discovery/serial_discovery.py', exclude_plugin: 'SERIAL__0', scope: 'DEFAULT')).to eq({ '/dev/ttyUSB1' => 'SERIAL__1' })
      end
    end

    describe "self.discovery_matchers" do
      # Shared with the OpenC3 Store, which derives the same matchers on upload
      fixtures = File.expand_path('../fixtures/discovery_matchers', __dir__)

      def phase1_variables(plugin_txt)
        expect(GemModel).to receive(:put)
        gem = double("gem")
        expect(gem).to receive(:extract_files) { |path| File.write("#{path}/plugin.txt", plugin_txt) }
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        expect(Gem::Package).to receive(:new).and_return(gem)
        PluginModel.install_phase1(__FILE__, scope: "DEFAULT")['variables']
      end

      Dir[File.join(fixtures, '*', 'plugin.txt')].sort.each do |path|
        name = File.basename(File.dirname(path))
        it "derives the #{name} fixture matchers" do
          expected = JSON.parse(File.read(File.join(File.dirname(path), 'expected.json')))
          expect(PluginModel.discovery_matchers(phase1_variables(File.read(path)))).to eq expected
        end
      end

      it "has no matchers without discovery" do
        expect(PluginModel.discovery_matchers(phase1_variables("VARIABLE port 8080\n"))).to eq({ 'format' => 1, 'matchers' => [] })
      end
    end

    describe "self.install_phase2" do
      it "creates the plugin by deploying models in the plugin.txt" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "TOOL <%= folder %> <%= name %>"
            file.puts "  #{URL}"
            file.puts "TARGET <%= folder %> <%= name %>"
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        # Variables in new format with 'value' key
        variables = { "folder" => { "value" => "THE_FOLDER" }, "name" => { "value" => "THE_NAME" } }
        # ERB variables are extracted as simple key-value pairs
        erb_variables = { "folder" => "THE_FOLDER", "name" => "THE_NAME", "scope" => 'DEFAULT' }
        # Just stub the instance deploy method
        expect(GemModel).to receive(:install).and_return(nil)
        expect_tool_and_target_deploy(erb_variables)
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => variables, "plugin_txt_lines" => ["TOOL THE_FOLDER THE_NAME", "  #{URL}", "TARGET THE_FOLDER THE_NAME"]}, scope: "DEFAULT")
        expect(plugin_model['needs_dependencies']).to eql false
      end

      it "previews the plugin.txt install lines with ERB rendered" do
        plugin_txt_lines = [
          "PLUGIN_TEXT_START",
          "  TARGET not_a_target",
          "PLUGIN_TEXT_END",
          "# Comment",
          "VARIABLE folder INST",
          "  VARIABLE_LABEL Folder",
          "  VARIABLE_STATE Inst INST",
          "    VARIABLE_TEXT_START",
          "    INTERFACE not_an_interface",
          "    VARIABLE_TEXT_END",
          "",
          "",
          "TARGET <%= folder %> <%= folder %>_2",
          "<% if folder == 'NONE' %>",
          "INTERFACE NONE_INT",
          "<% end %>",
          "",
        ]
        variables = { "folder" => { "value" => "INST" } }
        result = PluginModel.preview({ "variables" => variables, "plugin_txt_lines" => plugin_txt_lines }, scope: "DEFAULT")
        expect(result).to eq({ 'plugin_txt' => "TARGET INST INST_2" })
        result = PluginModel.preview({ "variables" => variables, "plugin_txt_lines" => ["TARGET A", "", "TARGET <%= missing %> B"] }, scope: "DEFAULT")
        expect(result['error']).to match(/ERB error at line 3: undefined local variable or method .missing/)
      end

      it "skips PLUGIN_TEXT and VARIABLE_TEXT during install and stores plugin_text" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files)
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        variables = { "folder" => { "value" => "THE_FOLDER" }, "name" => { "value" => "THE_NAME" } }
        erb_variables = { "folder" => "THE_FOLDER", "name" => "THE_NAME", "scope" => 'DEFAULT' }
        expect(GemModel).to receive(:install).and_return(nil)
        expect_tool_and_target_deploy(erb_variables)
        plugin_txt_lines = [
          "PLUGIN_TEXT_START",
          "  # Heading",
          "  INTERFACE looks like a keyword \"but isn't",
          "PLUGIN_TEXT_END",
          "VARIABLE folder THE_FOLDER",
          "  VARIABLE_STATE Folder THE_FOLDER",
          "    VARIABLE_TEXT_START",
          "    TARGET looks like a keyword",
          "    VARIABLE_TEXT_END",
          "TOOL THE_FOLDER THE_NAME",
          "  #{URL}",
          "TARGET THE_FOLDER THE_NAME",
        ]
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => variables, "plugin_txt_lines" => plugin_txt_lines, "plugin_text" => "# Heading"}, scope: "DEFAULT")
        expect(plugin_model['plugin_text']).to eql "# Heading"
        expect(PluginModel.get(name: plugin_model['name'], scope: "DEFAULT")['plugin_text']).to eql "# Heading"
      end

      it "threads version_history_files and username into the TargetModel upgrade_context" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "TOOL <%= folder %> <%= name %>"
            file.puts "  #{URL}"
            file.puts "TARGET <%= folder %> <%= name %>"
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        variables = { "folder" => { "value" => "THE_FOLDER" }, "name" => { "value" => "THE_NAME" } }
        erb_variables = { "folder" => "THE_FOLDER", "name" => "THE_NAME", "scope" => 'DEFAULT' }
        expect(GemModel).to receive(:install).and_return(nil)
        expect_any_instance_of(ToolModel).to receive(:deploy).with(anything, erb_variables, validate_only: false).and_return(nil)
        # The upgrade hints (username + version_history_files) are stripped from
        # the plugin_hash and rebuilt into the TargetModel upgrade_context with
        # the resolved "name version" plugin label.
        expect_any_instance_of(TargetModel).to receive(:deploy).with(
          anything, erb_variables, validate_only: false,
          upgrade_context: { username: "upgrader",
                             plugin: "test-plugin 1.0.0",
                             version_files: ["THE_NAME/screen.txt"] }
        ).and_return(nil)
        PluginModel.install_phase2({"name" => "name", "variables" => variables,
          "username" => "upgrader", "version_history_files" => ["THE_NAME/screen.txt"],
          "plugin_txt_lines" => ["TOOL THE_FOLDER THE_NAME", "  #{URL}", "TARGET THE_FOLDER THE_NAME"]}, scope: "DEFAULT")
      end

      it "passes a diff_collector upgrade_context and makes no side effects when diff_only" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            file.puts "TARGET <%= folder %> <%= name %>"
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        variables = { "folder" => { "value" => "THE_FOLDER" }, "name" => { "value" => "THE_NAME" } }
        erb_variables = { "folder" => "THE_FOLDER", "name" => "THE_NAME", "scope" => 'DEFAULT' }
        # Dry run: no gem install and the deploy is validate_only with a
        # diff_collector array for the target to append modified files into.
        expect(GemModel).to_not receive(:install)
        expect(GemModel).to_not receive(:destroy_all_other_versions)
        expect_any_instance_of(TargetModel).to receive(:deploy).with(
          anything, erb_variables, validate_only: true,
          upgrade_context: { diff_collector: [] }
        ).and_return(nil)
        result = PluginModel.install_phase2({"name" => "name", "variables" => variables,
          "plugin_txt_lines" => ["TARGET THE_FOLDER THE_NAME"]}, scope: "DEFAULT", diff_only: true)
        # Returns the (deduped) collected diff list rather than the plugin json.
        expect(result).to eql([])
      end
    end

    describe "VARIABLE_FILE" do
      UPLOAD = "0f1e2d3c-aaaa-bbbb-cccc-000000000001/icd.csv"

      def phase1(lines, existing_variables: nil)
        allow(GemModel).to receive(:put)
        gem = double("gem")
        allow(gem).to receive(:extract_files) do |path|
          File.write("#{path}/plugin.txt", lines.join("\n"))
        end
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        allow(Gem::Package).to receive(:new).and_return(gem)
        PluginModel.install_phase1(__FILE__, existing_variables: existing_variables, scope: "DEFAULT")
      end

      it "parses a file variable and keeps an existing upload" do
        lines = ["VARIABLE_FILE icd targets/INST/data/icd.csv", "  VARIABLE_LABEL ICD", "  VARIABLE_REQUIRED"]
        variable = phase1(lines)['variables']['icd']
        expect(variable).to eql({ 'value' => '', 'type' => 'FILE', 'file_path' => 'targets/INST/data/icd.csv', 'label' => 'ICD', 'required' => true })
        expect(phase1(lines, existing_variables: { 'icd' => { 'value' => UPLOAD } })['variables']['icd']['value']).to eql UPLOAD
        # Anything else isn't an upload
        expect(phase1(lines, existing_variables: { 'icd' => 'icd.csv' })['variables']['icd']['value']).to eql ''
      end

      it "only copies files inside the plugin" do
        ['/etc/passwd', '../outside.txt', 'targets/../../outside', 'C:/x', ''].each do |path|
          expect { phase1(["VARIABLE_FILE icd #{path}".strip + (path.empty? ? ' ""' : '')]) }.to raise_error(/must be a path inside the plugin/)
        end
        expect { phase1(["VARIABLE_FILE icd a.csv", "  VARIABLE_TYPE TEXT"]) }.to raise_error(/VARIABLE_TYPE cannot be used with a VARIABLE_FILE/)
        expect { phase1(["VARIABLE_FILE scope a.csv"]) }.to raise_error(/VARIABLE name 'scope' is reserved/)
      end

      it "is the file's path in the plugin in ERB, or blank without a file" do
        variables = {
          'icd' => { 'value' => UPLOAD, 'type' => 'FILE', 'file_path' => 'data/icd.csv' },
          'cert' => { 'value' => '', 'type' => 'FILE', 'file_path' => 'data/cert.pem' },
        }
        expect(PluginModel.erb_variables({ 'variables' => variables }, scope: 'DEFAULT')).to eql({ 'icd' => 'data/icd.csv', 'cert' => '', 'scope' => 'DEFAULT' })
      end

      it "stores uploads in the config bucket and copies them into the plugin" do
        bucket = double("bucket")
        allow(Bucket).to receive(:getClient).and_return(bucket)
        stored = {}
        allow(bucket).to receive(:put_object) { |bucket:, key:, body:| stored[key] = body.read }
        allow(bucket).to receive(:get_object) { |bucket:, key:, path:| File.write(path, stored.fetch(key)) if stored.key?(key) }
        allow(bucket).to receive(:delete_object) { |bucket:, key:| stored.delete(key) }

        Tempfile.create('upload') do |file|
          file.write('a,b')
          file.close
          value = PluginModel.store_upload(file.path, '../../icd.csv', scope: 'DEFAULT')
          expect(value).to match(PluginModel::UPLOAD_VALUE)
          expect(value).to end_with('/icd.csv')
          expect(stored.keys).to eql ["DEFAULT/plugin_uploads/#{value}"]

          variables = { 'icd' => { 'value' => value, 'type' => 'FILE', 'file_path' => 'targets/INST/data/icd.csv' } }
          Dir.mktmpdir do |gem_path|
            PluginModel.copy_uploads({ 'variables' => variables }, gem_path, scope: 'DEFAULT')
            expect(File.read(File.join(gem_path, 'targets/INST/data/icd.csv'))).to eql 'a,b'
            # A missing upload fails the install rather than installing without it
            stored.clear
            expect { PluginModel.copy_uploads({ 'variables' => variables }, gem_path + '/other', scope: 'DEFAULT') }.to raise_error(/file uploaded for VARIABLE_FILE icd is missing/)
          end

          # Uninstalling deletes uploads no other plugin uses
          stored["DEFAULT/plugin_uploads/#{value}"] = 'a,b'
          other = PluginModel.new(name: 'other__0', variables: variables, scope: 'DEFAULT')
          other.create
          PluginModel.cleanup_uploads(variables, scope: 'DEFAULT')
          expect(stored.length).to eql 1
          other.destroy
          PluginModel.cleanup_uploads(variables, scope: 'DEFAULT')
          expect(stored).to be_empty
        end
      end
    end

    describe "VARIABLE_TYPE TARGET_NAME" do
      def phase1(lines, existing_variables: nil)
        allow(GemModel).to receive(:put)
        gem = double("gem")
        allow(gem).to receive(:extract_files) do |path|
          File.write("#{path}/plugin.txt", lines.join("\n"))
        end
        spec = double("spec")
        allow(spec).to receive(:metadata).and_return({})
        allow(gem).to receive(:spec).and_return(spec)
        allow(Gem::Package).to receive(:new).and_return(gem)
        PluginModel.install_phase1(__FILE__, existing_variables: existing_variables, scope: "DEFAULT")['variables']
      end

      it "picks a free target name on new installs" do
        lines = [
          "VARIABLE inst_target_name INST", "  VARIABLE_TYPE TARGET_NAME",
          "VARIABLE other_target_name inst", "  VARIABLE_TYPE TARGET_NAME",
          "VARIABLE free_target_name EXAMPLE", "  VARIABLE_TYPE TARGET_NAME",
          "VARIABLE text INST",
        ]
        expect(phase1(lines).transform_values { |variable| variable['value'] }).to eql(
          { 'inst_target_name' => 'INST', 'other_target_name' => 'INST_2', 'free_target_name' => 'EXAMPLE', 'text' => 'INST' }
        )
        allow(TargetModel).to receive(:names).and_return(['INST', 'INST_2'])
        expect(phase1(lines).transform_values { |variable| variable['value'] }).to eql(
          { 'inst_target_name' => 'INST_3', 'other_target_name' => 'INST_4', 'free_target_name' => 'EXAMPLE', 'text' => 'INST' }
        )
        # Changing or upgrading an install keeps its target names
        existing = { 'inst_target_name' => { 'value' => 'INST' }, 'other_target_name' => { 'value' => 'INST_2' } }
        values = phase1(lines, existing_variables: existing).transform_values { |variable| variable['value'] }
        expect(values.slice('inst_target_name', 'other_target_name')).to eql({ 'inst_target_name' => 'INST', 'other_target_name' => 'INST_2' })
      end

      it "numbers names from a numbered name" do
        expect(PluginModel.available_target_name('inst', Set.new)).to eql 'INST'
        expect(PluginModel.available_target_name('INST', Set['INST', 'INST_2'])).to eql 'INST_3'
        expect(PluginModel.available_target_name('INST_2', Set['INST_2'])).to eql 'INST_3'
        expect(PluginModel.available_target_name('', Set['INST'])).to eql ''
      end
    end

    describe "PRE_INSTALL_SCRIPT and POST_INSTALL_SCRIPT" do
      def install(plugin_txt_lines, scripts, **options)
        stub_s3_client
        allow(GemModel).to receive(:get).and_return("my_plugin.gem")
        allow(GemModel).to receive(:install)
        allow(GemModel).to receive(:destroy_all_other_versions)
        gem = double("gem")
        allow(gem).to receive(:extract_files) do |path|
          scripts.each do |name, body|
            FileUtils.mkdir_p(File.dirname(File.join(path, name)))
            File.write(File.join(path, name), body)
          end
        end
        allow(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)
        variables = { "folder" => { "value" => "INST" } }
        PluginModel.install_phase2({ "name" => "name", "variables" => variables, "plugin_txt_lines" => plugin_txt_lines }, scope: "DEFAULT", **options)
      end

      it "runs the scripts before and after installing, in the plugin" do
        Dir.mktmpdir do |dir|
          order = File.join(dir, 'order')
          allow_any_instance_of(TargetModel).to receive(:deploy) do |_target, gem_path, _variables, **_options|
            # The pre-install script generated a file the target uses
            File.open(order, 'a') { |file| file.puts "deploy #{File.read(File.join(gem_path, 'targets/INST/generated.txt'))}" }
          end
          script = <<~RUBY
            require 'json'
            variables = JSON.parse(ENV['OPENC3_PLUGIN_VARIABLES'])
            File.open('#{order}', 'a') { |file| file.puts "\#{ARGV[0]} \#{variables['folder']} \#{ENV['OPENC3_PLUGIN_DRY_RUN']} \#{Dir.pwd == File.realpath(ENV['OPENC3_PLUGIN_PATH'])}" }
            if ARGV[0] == 'pre'
              require 'helper'
              require 'fileutils'
              FileUtils.mkdir_p('targets/INST')
              File.write('targets/INST/generated.txt', Helper.text)
            end
            puts "done \#{ARGV[0]}"
          RUBY
          scripts = { 'scripts/setup.rb' => script, 'lib/helper.rb' => "module Helper; def self.text = 'from lib'; end" }
          lines = ["POST_INSTALL_SCRIPT scripts/setup.rb post", "TARGET <%= folder %> <%= folder %>", "PRE_INSTALL_SCRIPT scripts/setup.rb pre"]
          expect(Logger).to receive(:info).at_least(:once)
          install(lines, scripts)
          expect(File.read(order).lines.map(&:chomp)).to eql ["pre INST false true", "deploy from lib", "post INST false true"]

          # Dry runs run the pre-install script for what it generates, but not the post-install one
          File.delete(order)
          install(lines, scripts, validate_only: true)
          expect(File.read(order).lines.map(&:chomp)).to eql ["pre INST true true", "deploy from lib"]
        end
      end

      it "runs Python scripts" do
        python = `which python3`.strip
        skip "python3 not found" if python.empty?
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('OPENC3_PYTHON_BIN').and_return(python)
        Dir.mktmpdir do |dir|
          out = File.join(dir, 'out')
          script = "import json, os, sys\nopen(#{out.inspect}, 'w').write(json.loads(os.environ['OPENC3_PLUGIN_VARIABLES'])['folder'] + sys.argv[1])\n"
          install(["PRE_INSTALL_SCRIPT gen.py <%= folder %>"], { 'gen.py' => script })
          expect(File.read(out)).to eql 'INSTINST'
        end
      end

      it "fails the install when a script fails" do
        lines = ["PRE_INSTALL_SCRIPT fail.rb", "TARGET INST INST"]
        expect_any_instance_of(TargetModel).to_not receive(:deploy)
        expect { install(lines, { 'fail.rb' => "warn 'bad icd'; exit 3" }) }.to raise_error(/PRE_INSTALL_SCRIPT 'fail.rb' failed with exit status 3/)
        expect(PluginModel.names(scope: 'DEFAULT')).to be_empty
        expect { install(["PRE_INSTALL_SCRIPT missing.rb"], {}) }.to raise_error(/PRE_INSTALL_SCRIPT 'missing.rb' was not found in the plugin/)
        expect { install(["POST_INSTALL_SCRIPT ../x.rb"], {}) }.to raise_error(/must be a path inside the plugin/)
        expect { install(["POST_INSTALL_SCRIPT run.sh"], {}) }.to raise_error(/must be a Ruby \(.rb\) or Python \(.py\) script/)
      end

      it "fails a script that runs too long" do
        stub_const("OpenC3::PluginModel::INSTALL_SCRIPT_TIMEOUT_S", 0.5)
        expect { install(["PRE_INSTALL_SCRIPT slow.rb"], { 'slow.rb' => "sleep 30" }) }.to raise_error(/did not finish within 0.5 seconds/)
      end
    end

    describe "self.modified_diff" do
      it "delegates to install_phase2 with diff_only and returns the file list" do
        expect(PluginModel).to receive(:install_phase2).with(
          hash_including("name" => "name"), scope: "DEFAULT", diff_only: true
        ).and_return(["TGT/screen.txt"])
        expect(PluginModel.modified_diff({"name" => "name"}, scope: "DEFAULT")).to eql(["TGT/screen.txt"])
      end

      it "raises when install_phase2 raises rather than reporting no differences" do
        expect(PluginModel).to receive(:install_phase2).and_raise("boom")
        expect { PluginModel.modified_diff({"name" => "name"}, scope: "DEFAULT") }.to raise_error("boom")
      end
    end

    describe "self.install_phase2 errors" do
      it "raises on non-lowercase screen file names" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          Dir.mkdir(File.join(path, 'screens'))
          File.open("#{path}/screens/SCREEN.txt", 'w') do |file|
            file.puts "SCREEN"
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        expect(GemModel).to receive(:install).and_return(nil)
        expect { PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => []}, scope: "DEFAULT") }.to raise_error(/Screen filenames must be lowercase/)
      end

      it "raise on unknown keywords" do
        stub_s3_client

        plugin_txt_lines = []
        plugin_txt_lines << "  UNKNOWN"

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            plugin_txt_lines.each { |line| file.puts line }
          end
          Dir.mkdir(File.join(path, 'lib')) # This causes needs_dependencies to be true
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        # Just stub the instance deploy method
        expect(GemModel).to receive(:install).and_return(nil)
        expect { PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT") }.to raise_error(/Invalid keyword 'UNKNOWN'/)
      end

      it "needs_dependencies if there is a top level lib folder" do
        stub_s3_client

        plugin_txt_lines = []
        plugin_txt_lines << "  TOOL THE_FOLDER THE_NAME"
        plugin_txt_lines << "    #{URL}"
        plugin_txt_lines << "  TARGET THE_FOLDER THE_NAME"

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            plugin_txt_lines.each { |line| file.puts line }
          end
          Dir.mkdir(File.join(path, 'lib')) # This causes needs_dependencies to be true
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        # Just stub the instance deploy method
        expect(GemModel).to receive(:install).and_return(nil)
        expect_tool_and_target_deploy
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT")
        expect(plugin_model['needs_dependencies']).to eql true
      end

      it "needs_dependencies if runtime_dependencies returns a non-empty list" do
        stub_s3_client

        plugin_txt_lines = []
        plugin_txt_lines << "  TOOL THE_FOLDER THE_NAME"
        plugin_txt_lines << "    #{URL}"
        plugin_txt_lines << "  TARGET THE_FOLDER THE_NAME"

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            plugin_txt_lines.each { |line| file.puts line }
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double(runtime_dependencies: ['something'])) # This causes needs_dependencies to be true

        # Just stub the instance deploy method
        expect(GemModel).to receive(:install).and_return(nil)
        expect_tool_and_target_deploy
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT")
        expect(plugin_model['needs_dependencies']).to eql true
      end

      it "needs_dependencies if NEEDS_DEPENDENCIES is present" do
        stub_s3_client

        plugin_txt_lines = []
        plugin_txt_lines << "  TOOL THE_FOLDER THE_NAME"
        plugin_txt_lines << "    #{URL}"
        plugin_txt_lines << "  TARGET THE_FOLDER THE_NAME"
        plugin_txt_lines << "  NEEDS_DEPENDENCIES"

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') do |file|
            plugin_txt_lines.each { |line| file.puts line }
          end
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        # Just stub the instance deploy method
        expect(GemModel).to receive(:install).and_return(nil)
        expect_tool_and_target_deploy
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT")
        expect(plugin_model['needs_dependencies']).to eql true
      end

      it "leaves img_path nil when openc3_store_image points to a missing file" do
        # The generator-created plugin.gemspec hardcodes
        # "openc3_store_image" => "public/store_img.png" but does not create the
        # file. Install must not record a non-existent img_path or the frontend
        # 500s when fetching it.
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') { |f| f.puts "" }
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double(metadata: { 'openc3_store_image' => 'public/store_img.png' }))

        expect(GemModel).to receive(:install).and_return(nil)
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => []}, scope: "DEFAULT")
        expect(plugin_model['img_path']).to be_nil
      end

      it "records img_path when the store image file exists on disk" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') { |f| f.puts "" }
          FileUtils.mkdir_p(File.join(path, 'public'))
          File.write(File.join(path, 'public', 'store_img.png'), 'fake png bytes')
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double(metadata: { 'openc3_store_image' => 'public/store_img.png' }))

        expect(GemModel).to receive(:install).and_return(nil)
        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => []}, scope: "DEFAULT")
        expect(plugin_model['img_path']).to eql 'gems/test-plugin-1.0.0/public/store_img.png'
      end

      # A ruby plugin ships no pyproject.toml or requirements.txt, so it must not
      # be pushed down the python path: that would build a per-plugin venv, and
      # cost every ruby plugin install a uv run it has no use for.
      it "does not create a per-plugin venv for a plugin with no python dependencies" do
        stub_s3_client

        expect(GemModel).to receive(:get).and_return("my_plugin.gem")
        gem = double("gem")
        expect(gem).to receive(:extract_files) do |path|
          File.open("#{path}/plugin.txt", 'w') { |f| f.puts "" }
        end
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)
        expect(GemModel).to receive(:install).and_return(nil)

        expect(Open3).to_not receive(:capture2e)

        plugin_model = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => []}, scope: "DEFAULT")
        expect(plugin_model['needs_dependencies']).to eql false
      end

      context "with python dependencies" do
        let(:plugin_txt_lines) { [] }
        let(:spec_double) { gem_spec_double }

        before(:each) do
          s3 = instance_double("Aws::S3::Client").as_null_object
          allow(Aws::S3::Client).to receive(:new).and_return(s3)
          allow(PluginModel).to receive(:get_setting).and_return(nil)
        end

        let(:success_status) { double("status", success?: true) }
        let(:failure_status) { double("status", success?: false) }

        # Every example here installs the same plugin gem and differs only in
        # which Python dependency file it ships and what OPENC3_USE_UV is set
        # to, so the shared doubles live here and each example is left with the
        # behavior it actually asserts.
        def stub_plugin_gem(dep_file: 'pyproject.toml', dep_body: '[project]', use_uv: nil, gem_install: true)
          expect(GemModel).to receive(:get).and_return("my_plugin.gem")
          gem = double("gem")
          expect(gem).to receive(:extract_files) do |path|
            File.open("#{path}/plugin.txt", 'w') { |f| f.puts "" }
            File.open("#{path}/#{dep_file}", 'w') { |f| f.puts dep_body }
          end
          expect(Gem::Package).to receive(:new).and_return(gem)
          allow(gem).to receive(:spec).and_return(spec_double)
          if gem_install
            expect(GemModel).to receive(:install).and_return(nil)
          else
            expect(GemModel).to_not receive(:install)
          end

          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('OPENC3_USE_UV').and_return(use_uv)
          allow(ENV).to receive(:[]).with('OPENC3_PYPI_ALLOW_INSECURE').and_return(nil)
          allow(ENV).to receive(:[]).with('PIP_ENABLE_TRUSTED_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('PYPI_URL').and_return(nil)
        end

        def stub_uv_on_path(available)
          allow(PluginModel).to receive(:system).with('which uv > /dev/null 2>&1').and_return(available)
        end

        def install_plugin
          PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT")
        end

        it "uses uvinstall for python packages when UV is available" do
          stub_plugin_gem
          stub_uv_on_path(true)
          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["ok", success_status])
          allow(PythonVenv).to receive(:purge_reserved_packages).and_return([])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        {
          'requirements.txt' => ["-c constraints.txt\n<%= driver %>==1.0", "-c constraints.txt\naioshelly==1.0\n"],
          'pyproject.toml' => ["[project]\ndependencies = [\"<%= driver %>==1.0\"]", "[project]\ndependencies = [\"aioshelly==1.0\"]\n"],
        }.each do |dep_file, (template, expected)|
          it "renders ERB in #{dep_file} with the plugin variables before installing" do
            stub_plugin_gem(dep_file: dep_file, dep_body: template)
            stub_uv_on_path(true)
            allow(PythonVenv).to receive(:purge_reserved_packages).and_return([])
            rendered = nil
            expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything) do |_, _, gem_path, *_|
              rendered = File.read(File.join(gem_path, dep_file))
              ["ok", success_status]
            end

            PluginModel.install_phase2({"name" => "name", "variables" => {"driver" => {"value" => "aioshelly"}}, "plugin_txt_lines" => plugin_txt_lines}, scope: "DEFAULT")
            expect(rendered).to eql(expected)
            # Stored rendered for bridges to provision the host
            key = dep_file == 'requirements.txt' ? 'python_requirements' : 'python_pyproject'
            expect(PluginModel.get(name: "name__0", scope: "DEFAULT")[key]).to eql(expected)
          end
        end

        it "purges a plugin-supplied openc3 from the venv after uvinstall succeeds" do
          stub_plugin_gem
          stub_uv_on_path(true)
          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["ok", success_status])

          # The venv is named "<scope>__<plugin>" so this is where a plugin's
          # own openc3 copy would land and shadow the system library.
          expect(PythonVenv).to receive(:purge_reserved_packages)
            .with("/gems/plugin_venvs/DEFAULT__name__0/.venv").and_return(['openc3'])

          install_plugin
        end

        it "does not purge the venv when uvinstall fails" do
          stub_plugin_gem
          stub_uv_on_path(true)
          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["uv failed", failure_status])
          expect(Open3).to receive(:capture2e).with("/openc3/bin/pipinstall", "--default-index", anything, anything).and_return(["pip ok", success_status])

          expect(PythonVenv).not_to receive(:purge_reserved_packages)

          install_plugin
        end

        it "falls back to pipinstall when uvinstall fails" do
          stub_plugin_gem
          stub_uv_on_path(true)
          allow(PythonVenv).to receive(:purge_reserved_packages).and_return([])

          # uvinstall fails, then pipinstall succeeds
          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["uv failed", failure_status])
          expect(Open3).to receive(:capture2e).with("/openc3/bin/pipinstall", "--default-index", anything, anything).and_return(["pip ok", success_status])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        it "skips UV and uses pipinstall when OPENC3_USE_UV is 'false'" do
          stub_plugin_gem(dep_file: 'requirements.txt', dep_body: 'requests', use_uv: 'false')

          # Should NOT call system for uv check
          expect(PluginModel).not_to receive(:system)

          # Should go straight to pipinstall
          expect(Open3).to receive(:capture2e).with("/openc3/bin/pipinstall", "--default-index", anything, "-r", anything).and_return(["pip ok", success_status])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        # Every other example here matches the index with `anything`, so without
        # this one nothing asserts that a configured index actually reaches uv.
        # --no-config rides along with it: PypiUrl.build_args adds it for any
        # index that is not the public default.
        it "passes a configured pypi_url and --no-config through to uvinstall" do
          stub_plugin_gem
          stub_uv_on_path(true)
          allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("https://mirror.example.com")

          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything,
                                                    "--default-index", "https://mirror.example.com/simple",
                                                    "--no-config").and_return(["ok", success_status])
          allow(PythonVenv).to receive(:purge_reserved_packages).and_return([])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        it "sanitizes an invalid pypi_url setting before invoking uvinstall" do
          stub_plugin_gem
          stub_uv_on_path(true)

          # A user-writable setting must never put shell metacharacters on the uvinstall argv
          allow(OpenC3::Logger).to receive(:error)
          payload = "https://pypi.org ; id > /tmp/PWNED ; #"
          allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return(payload)

          expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", PypiUrl::DEFAULT).and_return(["ok", success_status])
          allow(PythonVenv).to receive(:purge_reserved_packages).and_return([])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        it "falls back to pipinstall when uv is not on PATH" do
          stub_plugin_gem
          stub_uv_on_path(false)

          # Should fall back to pipinstall
          expect(Open3).to receive(:capture2e).with("/openc3/bin/pipinstall", "--default-index", anything, anything).and_return(["pip ok", success_status])

          expect(install_plugin['needs_dependencies']).to eql true
        end

        it "does not install python packages when diff_only" do
          stub_plugin_gem(gem_install: false)
          stub_uv_on_path(true)

          expect(Open3).to_not receive(:capture2e)

          result = PluginModel.install_phase2({"name" => "name", "variables" => {}, "plugin_txt_lines" => plugin_txt_lines},
            scope: "DEFAULT", diff_only: true)
          expect(result).to eql([])
        end
      end
    end

    describe "self.render_python_dependency_erb" do
      it "renders variables and resolves files relative to the dependency file" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'requirements.txt')
          File.write(File.join(dir, 'drivers.json'), '{"shelly": ["aioshelly==13.23.1", "bleak==2.1.1"]}')
          File.write(path, <<~ERB)
            # Comment mentioning <%= not_a_variable %>
            homeassistant==2026.2.3
            <%- require 'json' -%>
            <%= JSON.parse(File.read(File.join(File.dirname(__FILE__), 'drivers.json')))[integration].join("\\n") %>
          ERB
          PluginModel.render_python_dependency_erb(path, {'integration' => 'shelly'})
          expect(File.read(path)).to eql("# Comment mentioning \nhomeassistant==2026.2.3\naioshelly==13.23.1\nbleak==2.1.1\n")
        end
      end

      it "leaves files without ERB untouched" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'requirements.txt')
          File.write(path, "requests\n")
          expect(File).not_to receive(:write)
          PluginModel.render_python_dependency_erb(path, {})
          expect(File.read(path)).to eql("requests\n")
        end
      end
    end

    describe "self.resolve_pypi_url" do
      before(:each) do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('PYPI_URL', nil).and_return(nil)
      end

      it "appends /simple to the pypi_url setting" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("https://custom.pypi.example.com")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql "https://custom.pypi.example.com/simple"
      end

      it "drops a trailing slash from the pypi_url setting" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("https://custom.pypi.example.com/")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql "https://custom.pypi.example.com/simple"
      end

      it "treats the public index with a trailing slash as the default" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("https://pypi.org/")
        pypi_url = PluginModel.resolve_pypi_url(scope: "DEFAULT")
        expect(pypi_url).to eql PypiUrl::DEFAULT
        expect(PluginModel.build_pypi_args(pypi_url)).to_not include("--no-config")
      end

      it "drops a trailing slash from ENV PYPI_URL" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return(nil)
        allow(ENV).to receive(:fetch).with('PYPI_URL', nil).and_return("https://env.pypi.example.com/")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql "https://env.pypi.example.com/simple"
      end

      it "falls back to ENV PYPI_URL when the setting is nil" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return(nil)
        allow(ENV).to receive(:fetch).with('PYPI_URL', nil).and_return("https://env.pypi.example.com")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql "https://env.pypi.example.com/simple"
      end

      it "falls back to the default when the setting and ENV are nil" do
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return(nil)
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql PypiUrl::DEFAULT
      end

      it "logs and falls back to ENV PYPI_URL when get_setting raises" do
        allow(OpenC3::Logger).to receive(:error)
        allow(PluginModel).to receive(:get_setting).and_raise("no redis")
        allow(ENV).to receive(:fetch).with('PYPI_URL', nil).and_return("https://env.pypi.example.com")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql "https://env.pypi.example.com/simple"
        expect(OpenC3::Logger).to have_received(:error).with(/Failed to retrieve pypi_url/)
      end

      it "replaces a value containing shell metacharacters with the default" do
        allow(OpenC3::Logger).to receive(:error)
        payload = "https://pypi.org ; id > /tmp/PWNED ; #"
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return(payload)
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql PypiUrl::DEFAULT
        expect(OpenC3::Logger).to have_received(:error).with(/Invalid pypi_url/)
      end

      it "replaces a non-http scheme with the default" do
        allow(OpenC3::Logger).to receive(:error)
        allow(PluginModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("file:///etc")
        expect(PluginModel.resolve_pypi_url(scope: "DEFAULT")).to eql PypiUrl::DEFAULT
      end
    end

    describe "self.build_pypi_args" do
      before(:each) do
        allow(ENV).to receive(:[]).and_call_original
      end

      it "returns index args without an insecure host by default" do
        allow(ENV).to receive(:[]).with('OPENC3_PYPI_ALLOW_INSECURE').and_return(nil)
        allow(ENV).to receive(:[]).with('PIP_ENABLE_TRUSTED_HOST').and_return(nil)
        expect(PluginModel.build_pypi_args("https://custom.pypi.example.com/simple")).to \
          eql ["--default-index", "https://custom.pypi.example.com/simple", "--no-config"]
      end

      it "adds the insecure host derived from the url when PIP_ENABLE_TRUSTED_HOST is set" do
        allow(ENV).to receive(:[]).with('OPENC3_PYPI_ALLOW_INSECURE').and_return(nil)
        allow(ENV).to receive(:[]).with('PIP_ENABLE_TRUSTED_HOST').and_return('1')
        expect(PluginModel.build_pypi_args("https://custom.pypi.example.com/simple")).to \
          eql ["--default-index", "https://custom.pypi.example.com/simple", "--no-config",
               "--allow-insecure-host", "custom.pypi.example.com"]
      end
    end

    describe "self.undeploy" do
      before(:each) do
        local_s3()
      end

      after(:each) do
        local_s3_unset()
      end

      it "destroys all models associated with the plugin" do
        tool = ToolModel.new(name: "TOOL", folder_name: "TOOL", scope: "DEFAULT", plugin: "PLUG")
        tool.create
        # Create a tool in another plugin which should not get destroyed
        tool2 = ToolModel.new(name: "ANOTHER", folder_name: "ANOTHER", scope: "DEFAULT", plugin: "OTHER")
        tool2.create
        expect_any_instance_of(ToolModel).to receive(:undeploy).once # Only one gets destroyed
        target = TargetModel.new(folder_name: "TEST", name: "TARGET", scope: "DEFAULT", plugin: "PLUG")
        target.create
        expect_any_instance_of(TargetModel).to receive(:undeploy).once
        interface = InterfaceModel.new(name: "TARGET", scope: "DEFAULT", plugin: "PLUG")
        interface.create
        expect_any_instance_of(InterfaceModel).to receive(:undeploy).once
        router = RouterModel.new(name: "TARGET", scope: "DEFAULT", plugin: "PLUG")
        router.create
        expect_any_instance_of(RouterModel).to receive(:undeploy).once
        uservice = MicroserviceModel.new(name: "DEFAULT__TYPE__NAME", scope: "DEFAULT", plugin: "PLUG")
        uservice.create
        expect_any_instance_of(MicroserviceModel).to receive(:undeploy).once

        plugin = PluginModel.new(name: "PLUG", scope: "DEFAULT")
        plugin.undeploy
      end

      it "removes per-plugin Python venv directory when it exists" do
        plugin = PluginModel.new(name: "PLUG", scope: "DEFAULT")
        venv_path = '/gems/plugin_venvs/DEFAULT__PLUG'
        expect(File).to receive(:directory?).with(venv_path).and_return(true)
        expect(FileUtils).to receive(:rm_rf).with(venv_path)
        plugin.undeploy
      end

      it "does not error when per-plugin Python venv directory does not exist" do
        plugin = PluginModel.new(name: "PLUG", scope: "DEFAULT")
        venv_path = '/gems/plugin_venvs/DEFAULT__PLUG'
        expect(File).to receive(:directory?).with(venv_path).and_return(false)
        expect(FileUtils).not_to receive(:rm_rf).with(venv_path)
        expect { plugin.undeploy }.not_to raise_error
      end

      it "sanitizes plugin name for venv directory path" do
        plugin = PluginModel.new(name: "my.plugin@1.0__0", scope: "DEFAULT")
        sanitized_path = '/gems/plugin_venvs/DEFAULT__my_plugin_1_0__0'
        expect(File).to receive(:directory?).with(sanitized_path).and_return(true)
        expect(FileUtils).to receive(:rm_rf).with(sanitized_path)
        plugin.undeploy
      end
    end

    describe "self.gem_names" do
      it "returns all gem_names" do
        # Ensure we have a DEFAULT scope
        ScopeModel.new(name: "DEFAULT").create

        model = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "SPEC", scope: "DEFAULT")
        model.create
        model = PluginModel.new(name: "OTHER", scope: "OTHER")
        model.create

        expect(PluginModel.gem_names).to eql %w(SPEC TEST)
      end
    end

    describe "counter-based naming" do
      it "increments counter for duplicate plugin names" do
        model1 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model1.create
        expect(model1.name).to eq("TEST__0")
        model2 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model2.create
        expect(model2.name).to eq("TEST__1")
        model3 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model3.create
        expect(model3.name).to eq("TEST__2")
        names = PluginModel.names(scope: "DEFAULT")
        expect(names).to contain_exactly("TEST__0", "TEST__1", "TEST__2")
      end

      it "fills gaps in counter sequence" do
        model1 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model1.create
        expect(model1.name).to eq("TEST__0")
        model2 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model2.create
        expect(model2.name).to eq("TEST__1")
        model3 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model3.create
        expect(model3.name).to eq("TEST__2")
        # Destroy the middle one to create a gap
        model2.destroy
        # Now create a new plugin with base name - should fill the gap at __1
        model4 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model4.create
        expect(model4.name).to eq("TEST__1")
        names = PluginModel.names(scope: "DEFAULT")
        expect(names).to contain_exactly("TEST__0", "TEST__1", "TEST__2")
      end

      it "handles backwards compatibility with timestamp-based naming" do
        old_plugin_name = "TEST__20250904175756"
        old_plugin_data = {
          'name' => old_plugin_name,
          'variables' => {},
          'plugin_txt_lines' => [],
          'needs_dependencies' => false,
          'store_plugin_id' => nil,
          'store_version_id' => nil,
          'updated_at' => Time.now.to_nsec_from_epoch
        }
        Store.hset("DEFAULT__openc3_plugins", old_plugin_name, JSON.generate(old_plugin_data))
        model1 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model1.create
        expect(model1.name).to eq("TEST__0")
        model2 = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model2.create
        expect(model2.name).to eq("TEST__1")
        names = PluginModel.names(scope: "DEFAULT")
        expect(names).to contain_exactly("TEST__20250904175756", "TEST__0", "TEST__1")
      end
    end

    describe "self.cleanup_gem" do
      it "removes the gem when no PluginModel references it" do
        ScopeModel.new(name: "DEFAULT").create

        plugin_name = "openc3-cosmos-tool-foo-1.0.0.gem__0"
        # No PluginModel exists for this gem (simulating post-destroy state),
        # so GemModel.destroy should run the uninstaller.
        uninstaller = instance_double("Gem::Uninstaller").as_null_object
        expect(Gem::Uninstaller).to receive(:new).with(
          "openc3-cosmos-tool-foo", hash_including(:version => "1.0.0")
        ).and_return(uninstaller)
        expect(uninstaller).to receive(:uninstall)

        PluginModel.cleanup_gem(plugin_name, scope: "DEFAULT")
      end

      it "skips removal when another PluginModel still references the gem" do
        ScopeModel.new(name: "DEFAULT").create
        ScopeModel.new(name: "OTHER").create

        # A second PluginModel for the same gem exists in another scope.
        other = PluginModel.new(name: "openc3-cosmos-tool-foo-1.0.0.gem", scope: "OTHER")
        other.create
        # Sanity check: the unload target doesn't exist anymore (already destroyed),
        # but the OTHER scope's instance does — so the gem must be preserved.
        expect(PluginModel.gem_names).to include("openc3-cosmos-tool-foo-1.0.0.gem")

        # Gem::Uninstaller must NOT be called.
        expect(Gem::Uninstaller).not_to receive(:new)

        PluginModel.cleanup_gem("openc3-cosmos-tool-foo-1.0.0.gem__0", scope: "DEFAULT")
      end

      it "logs and swallows errors from GemModel.destroy" do
        ScopeModel.new(name: "DEFAULT").create

        allow(GemModel).to receive(:destroy).and_raise(StandardError, "boom")
        expect(Logger).to receive(:warn).with(/Could not remove gem .*boom/, scope: "DEFAULT")

        expect {
          PluginModel.cleanup_gem("openc3-cosmos-tool-foo-1.0.0.gem__0", scope: "DEFAULT")
        }.not_to raise_error
      end
    end

    describe "needs_uv_migration?" do
      it "returns false when needs_dependencies is false" do
        model = PluginModel.new(name: "TEST", needs_dependencies: false, scope: "DEFAULT")
        expect(model.needs_uv_migration?).to be false
      end

      it "returns true when needs_dependencies is true and .uv_managed marker is absent" do
        model = PluginModel.new(name: "TEST", needs_dependencies: true, scope: "DEFAULT")
        allow(File).to receive(:exist?).with('/gems/plugin_venvs/DEFAULT__TEST/.uv_managed').and_return(false)
        expect(model.needs_uv_migration?).to be true
      end

      it "returns false when .uv_managed marker exists" do
        model = PluginModel.new(name: "TEST", needs_dependencies: true, scope: "DEFAULT")
        allow(File).to receive(:exist?).with('/gems/plugin_venvs/DEFAULT__TEST/.uv_managed').and_return(true)
        expect(model.needs_uv_migration?).to be false
      end

      it "sanitizes plugin name for marker path" do
        model = PluginModel.new(name: "my.plugin@1.0", needs_dependencies: true, scope: "DEFAULT")
        allow(File).to receive(:exist?).with('/gems/plugin_venvs/DEFAULT__my_plugin_1_0/.uv_managed').and_return(false)
        expect(model.needs_uv_migration?).to be true
      end
    end

    describe "migrate_to_uv!" do
      # Every example but the first drives the same unmigrated plugin, so the
      # model and the absent .uv_managed marker live here.
      def unmigrated_plugin
        model = PluginModel.new(name: "TEST__0", needs_dependencies: true, scope: "DEFAULT")
        model.create
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/gems/plugin_venvs/DEFAULT__TEST__0/.uv_managed').and_return(false)
        model
      end

      # The gem migrate_to_uv! fetches and extracts. The block receives the
      # extraction directory so an example can lay down its dependency file.
      def stub_migration_gem(&block)
        expect(GemModel).to receive(:get).with("TEST").and_return("/gems/cache/test.gem")
        gem = double("gem")
        expect(Gem::Package).to receive(:new).with("/gems/cache/test.gem").and_return(gem)
        if block
          expect(gem).to receive(:extract_files) { |path| block.call(path) }
        else
          expect(gem).to receive(:extract_files)
        end
        gem
      end

      # No pypi_url setting and no environment override, so resolution falls
      # through to the public default.
      def stub_default_pypi_url
        allow(PluginModel).to receive(:get_setting).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYPI_URL').and_return(nil)
        allow(ENV).to receive(:[]).with('OPENC3_PYPI_ALLOW_INSECURE').and_return(nil)
        allow(ENV).to receive(:[]).with('PIP_ENABLE_TRUSTED_HOST').and_return(nil)
      end

      it "returns true immediately when already migrated (marker exists)" do
        model = PluginModel.new(name: "TEST__0", needs_dependencies: true, scope: "DEFAULT")
        allow(File).to receive(:exist?).with('/gems/plugin_venvs/DEFAULT__TEST__0/.uv_managed').and_return(true)
        expect(model.migrate_to_uv!(scope: "DEFAULT")).to be true
      end

      it "extracts gem, runs uvinstall, and returns true on success" do
        model = unmigrated_plugin
        stub_migration_gem { |path| File.open("#{path}/pyproject.toml", 'w') { |f| f.puts "[project]" } }
        stub_default_pypi_url

        success_status = double("status", success?: true)
        expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["ok", success_status])

        expect(model.migrate_to_uv!(scope: "DEFAULT")).to be true
      end

      it "returns false on uvinstall failure" do
        model = unmigrated_plugin
        stub_migration_gem { |path| File.open("#{path}/requirements.txt", 'w') { |f| f.puts "requests" } }
        stub_default_pypi_url

        failure_status = double("status", success?: false)
        expect(Open3).to receive(:capture2e).with("/openc3/bin/uvinstall", anything, anything, "--default-index", anything).and_return(["fail", failure_status])

        expect(model.migrate_to_uv!(scope: "DEFAULT")).to be false
      end

      it "returns true when no Python dependency files found" do
        model = unmigrated_plugin
        # No pyproject.toml or requirements.txt created during extract
        stub_migration_gem

        expect(model.migrate_to_uv!(scope: "DEFAULT")).to be true
      end

      it "returns false and cleans up temp dir when an exception is raised" do
        model = unmigrated_plugin
        expect(GemModel).to receive(:get).with("TEST").and_return("/gems/cache/test.gem")

        # Gem::Package.new raises inside the begin/rescue block
        expect(Gem::Package).to receive(:new).and_raise(RuntimeError.new("corrupt gem"))
        allow(Logger).to receive(:warn)

        expect(model.migrate_to_uv!(scope: "DEFAULT")).to be false
      end
    end

    describe "destroy, restore" do
      it "destroys and restores the model" do
        expect(GemModel).to receive(:get).and_return('path')
        expect(GemModel).to receive(:install).and_return(nil)
        gem = double("gem")
        expect(gem).to receive(:extract_files)
        expect(Gem::Package).to receive(:new).and_return(gem)
        allow(gem).to receive(:spec).and_return(gem_spec_double)

        model = PluginModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        names = PluginModel.names(scope: "DEFAULT")
        expect(names[0].include?("TEST")).to be true
        model.destroy
        expect(model.destroyed?).to be true
        expect(PluginModel.names(scope: "DEFAULT")).to be_empty
        model.restore
        expect(model.destroyed?).to be false
        names = PluginModel.names(scope: "DEFAULT")
        expect(names[0].include?("TEST")).to be true
      end
    end
  end
end
