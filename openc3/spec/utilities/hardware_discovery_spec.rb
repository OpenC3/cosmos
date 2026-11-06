# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/utilities/hardware_discovery'

module OpenC3
  describe HardwareDiscovery do
    hid = 'openc3.discovery.hid_discovery'
    serial = 'openc3.discovery.serial_discovery'

    let(:dualsense_matchers) do
      [
        { 'class' => hid, 'params' => ['0x054C', '0x0CE6'], 'variable' => 'serial_num', 'set' => { 'version' => '5' }, 'title' => 'DualSense (PS5)' },
        { 'class' => hid, 'params' => ['0x054C', '0x0DF2'], 'variable' => 'serial_num', 'set' => { 'version' => '5edge' }, 'title' => 'DualSense Edge (PS5)' },
      ]
    end
    let(:store) do
      [
        { 'id' => 65, 'current_version_id' => 90, 'title' => 'PS5 DualSense Controller', 'gem_filename' => 'openc3-cosmos-dualsense-1.0.0.gem', 'image_url' => 'img',
          'entitled' => true, 'discovery' => { 'format' => 1, 'matchers' => dualsense_matchers } },
        # A generic USB serial chip, used by many devices
        { 'id' => 15, 'title' => 'Arduino Sensor Kit', 'gem_filename' => 'arduino-1.0.0.gem', 'entitled' => false,
          'discovery' => { 'format' => 1, 'matchers' => [{ 'class' => serial, 'params' => ['1A86'], 'variable' => 'port', 'set' => {} }] } },
        { 'id' => 7, 'title' => 'No discovery', 'gem_filename' => 'plain-1.0.0.gem' },
      ]
    end

    before(:each) do
      described_class.instance_variable_set(:@gem_matchers, {})
      allow(PluginStoreModel).to receive(:all).and_return(store.to_json)
      allow(PluginModel).to receive(:all).and_return({
        'openc3-cosmos-dualsense-1.0.0.gem__1' => { 'store_plugin_id' => 65 },
        'local-plugin-2.0.0.gem__2' => {},
      })
      allow(BridgeModel).to receive(:all).and_return({
        'DEFAULT' => { 'app_public_key' => 'key1' },
        'LAB' => { 'app_public_key' => 'key2' },
        'UNPAIRED' => {},
      })
      allow(PluginModel).to receive(:discovery_claims).and_return({})
      allow(described_class).to receive(:gem_discovery_matchers).and_call_original
      allow(GemModel).to receive(:get) { |gem| "/gems/#{gem}" }
      allow(PluginModel).to receive(:install_phase1).and_return({ 'variables' => {
        'port' => { 'value' => '', 'discovery' => [{ 'discovery' => ['openc3/discovery/serial_discovery.py', '1A86:7523'] }] },
      } })
    end

    def stub_scan(results)
      allow(DiscoveryTopic).to receive(:scan) do |bridge, request, **|
        @requests ||= {}
        @requests[bridge] = request
        result = results.fetch(bridge)
        raise result if result.is_a?(String)
        result
      end
    end

    it "proposes store and installed plugins for the devices found" do
      allow(PluginModel).to receive(:discovery_claims).with('DEFAULT', hid, scope: 'DEFAULT').and_return({ 'claimed' => 'DUALSENSE__1' })
      stub_scan('DEFAULT' => {
        'devices' => [
          { 'class' => hid, 'value' => 'abc', 'text' => 'DualSense (abc)', 'details' => { 'vid' => 1356 }, 'matches' => ['1'] },
          { 'class' => hid, 'value' => 'claimed', 'text' => 'DualSense (claimed)', 'matches' => ['1'] },
          { 'class' => serial, 'value' => '/dev/ttyUSB0', 'text' => 'CH340', 'matches' => ['3', '4'] },
          { 'class' => serial, 'value' => '/dev/ttyS0', 'text' => 'ttyS0', 'matches' => [] },
        ],
        'errors' => { 'openc3.discovery.bluetooth_discovery' => 'RuntimeError: bleak missing' },
        'skipped' => { '9' => 'x' },
      })
      result = described_class.scan(bridge: 'default', scope: 'DEFAULT')

      # Each distinct discovery is checked once, whichever plugins use it
      expect(@requests['DEFAULT']['matchers']).to eql [
        { 'id' => '1', 'class' => hid, 'params' => ['0x054C', '0x0CE6'] },
        { 'id' => '2', 'class' => hid, 'params' => ['0x054C', '0x0DF2'] },
        { 'id' => '3', 'class' => serial, 'params' => ['1A86'] },
        { 'id' => '4', 'class' => serial, 'params' => ['1A86:7523'] },
      ]
      expect(result['store_matchers']).to be true
      expect(result['skipped']).to eql 1
      expect(result['errors']).to eql [{ 'bridge' => 'DEFAULT', 'class' => 'openc3.discovery.bluetooth_discovery', 'message' => 'RuntimeError: bleak missing' }]

      dualsense, claimed, usb, unrecognized = result['devices']
      expect(dualsense).to include('bridge' => 'DEFAULT', 'value' => 'abc', 'text' => 'DualSense (abc)', 'details' => { 'vid' => 1356 }, 'claimed_by' => nil)
      expect(dualsense['candidates']).to eql [{
        'source' => 'store', 'store_id' => 65, 'store_version_id' => 90, 'name' => 'openc3-cosmos-dualsense', 'title' => 'PS5 DualSense Controller',
        'image_url' => 'img', 'entitled' => true, 'installed' => true, 'match_title' => 'DualSense (PS5)',
        'variables' => { 'version' => '5', 'serial_num' => 'abc', 'bridge_name' => 'DEFAULT' }, 'specificity' => 2, 'possible' => false,
      }]
      expect(claimed['claimed_by']).to eql 'DUALSENSE__1'
      # The exact USB product ranks above the generic chip vendor
      expect(usb['candidates'].map { |candidate| [candidate['source'], candidate['name'], candidate['specificity']] }).to eql [
        ['installed', 'local-plugin', 2], ['store', 'arduino', 1],
      ]
      expect(usb['candidates'][0]).to include('gem' => 'local-plugin-2.0.0.gem', 'installed' => true, 'variables' => { 'port' => '/dev/ttyUSB0', 'bridge_name' => 'DEFAULT' })
      expect(usb['candidates'][1]).to include('entitled' => false, 'installed' => false)
      expect(unrecognized['candidates']).to eql []
    end

    it "ignores store matchers in a format it doesn't know" do
      store[0]['discovery']['format'] = 2
      store[1]['discovery']['matchers'] << 'not a matcher' << { 'class' => serial }
      allow(PluginStoreModel).to receive(:all).and_return(store.to_json)
      stub_scan('DEFAULT' => { 'devices' => [] })
      described_class.scan(bridge: 'DEFAULT', scope: 'DEFAULT')
      expect(@requests['DEFAULT']['matchers']).to eql [
        { 'id' => '1', 'class' => serial, 'params' => ['1A86'] },
        { 'id' => '2', 'class' => serial, 'params' => ['1A86:7523'] },
      ]
    end

    it "scans every paired bridge" do
      stub_scan('DEFAULT' => { 'devices' => [{ 'class' => hid, 'value' => 'abc', 'matches' => ['1'] }] }, 'LAB' => 'Timeout waiting for discovery')
      result = described_class.scan(bridge: 'ALL', scope: 'DEFAULT')
      expect(@requests.keys.sort).to eql %w(DEFAULT LAB)
      expect(result['devices'].map { |device| device['bridge'] }).to eql ['DEFAULT']
      expect(result['errors']).to eql [{ 'bridge' => 'LAB', 'message' => 'Timeout waiting for discovery' }]
    end

    it "requires a paired bridge" do
      expect { described_class.scan(bridge: 'UNPAIRED', scope: 'DEFAULT') }.to raise_error("Bridge 'UNPAIRED' is not paired with openc3-app")
      allow(BridgeModel).to receive(:all).and_return({})
      expect { described_class.scan(bridge: 'ALL', scope: 'DEFAULT') }.to raise_error('No bridge is paired with openc3-app')
    end

    it "reads installed plugin matchers once and skips unreadable gems" do
      expect(described_class.gem_discovery_matchers('local-plugin-2.0.0.gem', scope: 'DEFAULT')).to eql [
        { 'class' => serial, 'params' => ['1A86:7523'], 'variable' => 'port', 'set' => {} },
      ]
      described_class.gem_discovery_matchers('local-plugin-2.0.0.gem', scope: 'DEFAULT')
      expect(PluginModel).to have_received(:install_phase1).with('/gems/local-plugin-2.0.0.gem', validate_only: true, scope: 'DEFAULT').once
      expect(described_class.gem_discovery_matchers('local-plugin-2.0.0.gem', scope: 'DEFAULT')[0]['params'][0].encoding).to eql Encoding::UTF_8
      allow(PluginModel).to receive(:install_phase1).and_raise('no plugin.txt')
      expect(described_class.gem_discovery_matchers('library-1.0.0.gem', scope: 'DEFAULT')).to eql []
    end

    it "ranks how specifically matchers identify hardware" do
      expect(described_class.specificity(serial, ['10C4:EA60'])).to eql 2
      expect(described_class.specificity(serial, ['10C4', '10C4:*'])).to eql 1
      expect(described_class.specificity(hid, ['0x054C', '0x0CE6'])).to eql 2
      expect(described_class.specificity(hid, ['0x054C', 'nil'])).to eql 1
      expect(described_class.specificity('openc3.discovery.zeroconf_discovery', ['_hue._tcp.local.', '_hap._tcp.local.|md=BSB002*'])).to eql 2
      expect(described_class.specificity('openc3.discovery.bluetooth_discovery', ['manufacturer_id=76|manufacturer_data_start=0215'])).to eql 2
      expect(described_class.specificity('openc3.discovery.usb_discovery', ['0BDA:2838'])).to eql 2
      expect(described_class.specificity('openc3.discovery.usb_discovery', ['0BDA:*', 'class=0E'])).to eql 1
      expect(described_class.specificity('openc3.discovery.usb_discovery', ['046D:085E|product=BRIO*'])).to eql 3
      expect(described_class.specificity('openc3.discovery.ssdp_discovery', ['manufacturer=Sonos*|modelname=Sonos?Era*'])).to eql 2
      expect(described_class.specificity('openc3.discovery.neighbor_discovery', ['mac=00D02D*'])).to eql 1
    end

    it "rates a match by the parameters the device matched" do
      bluetooth = 'openc3.discovery.bluetooth_discovery'
      source = { 'source' => 'store', 'name' => 'ha', 'title' => 'Home Assistant' }
      govee = { 'class' => bluetooth, 'params' => ['manufacturer_id=60552|service_uuid=0000ec88', 'local_name=Govee*'], 'variable' => 'ha_address', 'title' => 'Govee Bluetooth' }
      switchbot = { 'class' => bluetooth, 'params' => ['manufacturer_id=2409'], 'variable' => 'ha_address', 'title' => 'SwitchBot' }
      candidates_by_id = { '1' => [[source, govee]], '2' => [[source, switchbot]] }
      claims = Hash.new { |hash, key| hash[key] = {} }
      lamp = { 'class' => bluetooth, 'value' => 'AA:01', 'matches' => %w(1 2), 'matched_params' => { '1' => [1] } }
      first, second = described_class.device_proposal('DEFAULT', lamp, candidates_by_id, claims)['candidates']
      # Only Govee's name pattern matched, so it's a possible match, after the others
      expect([first['match_title'], first['possible'], first['specificity']]).to eql ['SwitchBot', false, 1]
      expect([second['match_title'], second['possible'], second['specificity']]).to eql ['Govee Bluetooth', true, 1]
      # A sensor matching the specific parameters isn't
      sensor = lamp.merge('matches' => %w(1), 'matched_params' => { '1' => [0, 1] })
      candidate = described_class.device_proposal('DEFAULT', sensor, candidates_by_id, claims)['candidates'][0]
      expect([candidate['possible'], candidate['specificity']]).to eql [false, 2]
      # Hosts that don't say which parameters matched rate the whole matcher
      older = lamp.merge('matches' => %w(1)).except('matched_params')
      expect(described_class.device_proposal('DEFAULT', older, candidates_by_id, claims)['candidates'][0]['possible']).to be false
    end

    it "recognizes matches by a name pattern alone" do
      expect(described_class.name_pattern_only?('openc3.discovery.bluetooth_discovery', ['local_name=Govee*'])).to be true
      expect(described_class.name_pattern_only?('openc3.discovery.bluetooth_discovery', ['local_name=Govee_H5075'])).to be false
      expect(described_class.name_pattern_only?('openc3.discovery.bluetooth_discovery', ['local_name=Govee*|manufacturer_id=1'])).to be false
      expect(described_class.name_pattern_only?('openc3.discovery.neighbor_discovery', ['hostname=lyric-*'])).to be true
      expect(described_class.name_pattern_only?('openc3.discovery.usb_discovery', ['product=*Camera*'])).to be true
      expect(described_class.name_pattern_only?('openc3.discovery.zeroconf_discovery', ['_http._tcp.local.|name=shelly*'])).to be false
      expect(described_class.name_pattern_only?('openc3.discovery.bluetooth_discovery', [])).to be false
    end

    it "names gems without their version" do
      expect(described_class.gem_name('openc3-cosmos-dualsense-1.0.0.gem')).to eql 'openc3-cosmos-dualsense'
      expect(described_class.gem_name('openc3-cosmos-demo-7.5.0.pre.beta0.gem')).to eql 'openc3-cosmos-demo'
    end
  end
end
