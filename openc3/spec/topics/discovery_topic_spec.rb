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
require 'openc3/topics/discovery_topic'

module OpenC3
  describe DiscoveryTopic do
    before(:each) do
      mock_redis()
      allow(SecureRandom).to receive(:uuid).and_return("ID1")
      allow(Topic).to receive(:update_topic_offsets)
      allow(Topic).to receive(:write_topic).and_return("1234-0")
    end

    def stub_result(id, result)
      allow(Topic).to receive(:read_topics) do |_topics, **_kwargs, &block|
        block.call("RESULTTOPIC", "1234-1", { "id" => "OTHER", "result" => '{"results":[]}' }, nil)
        block.call("RESULTTOPIC", "1234-2", { "id" => id, "result" => result.to_json }, nil)
      end
    end

    describe "discover" do
      it "publishes the request and returns the matching results" do
        stub_result("ID1", { 'results' => [{ 'value' => 'COM1', 'text' => 'COM1' }] })
        results = DiscoveryTopic.discover("DEFAULT", ["openc3/discovery/hid_discovery.py", "0x054C"], scope: "DEFAULT")
        expect(results).to eql [{ 'value' => 'COM1', 'text' => 'COM1' }]
        expect(Topic).to have_received(:update_topic_offsets).with(["DEFAULT__DISCOVERY_RESULT__DEFAULT"])
        expect(Topic).to have_received(:write_topic) do |topic, request, id, maxlen|
          expect(topic).to eql "DEFAULT__DISCOVERY__DEFAULT"
          expect(request['id']).to eql "ID1"
          expect(JSON.parse(request['discovery'])).to eql ["openc3/discovery/hid_discovery.py", "0x054C"]
          expect(request['expires_at'].to_f).to be > Time.now.to_f
          expect(id).to eql '*'
          expect(maxlen).to eql 100
        end
      end

      it "raises the host error" do
        stub_result("ID1", { 'error' => 'ModuleNotFoundError: nope' })
        expect { DiscoveryTopic.discover("DEFAULT", ["nope.py"], scope: "DEFAULT") }.to raise_error("ModuleNotFoundError: nope")
      end

      it "times out if the host does not respond" do
        allow(Topic).to receive(:read_topics)
        expect { DiscoveryTopic.discover("BRIDGE2", ["x.py"], timeout: 0.1, scope: "DEFAULT") }.to raise_error(/Timeout of 0.1s waiting for discovery on bridge 'BRIDGE2'/)
      end
    end
  end
end
