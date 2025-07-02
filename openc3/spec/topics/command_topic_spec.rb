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

require 'spec_helper'
require 'openc3/topics/command_topic'
require 'openc3/packets/packet'

module OpenC3
  describe CommandTopic do
    before(:each) do
      mock_redis()
      allow(EphemeralStoreQueued).to receive(:write_topic)
      allow(Topic).to receive(:write_topic).and_return('test_cmd_id')
      allow(Topic).to receive(:update_topic_offsets)
      allow(OpenC3).to receive(:inject_context)
    end

    describe "self.write_packet" do
      let(:packet) do
        packet = Packet.new('TARGET', 'COMMAND')
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 1
        packet.stored = true
        packet.buffer = "\x01\x02\x03\x04"
        packet
      end

      it "writes packet to correct topic format" do
        expect(EphemeralStoreQueued).to receive(:write_topic).with(
          "DEFAULT__COMMAND__{TARGET}__COMMAND",
          hash_including(
            target_name: 'TARGET',
            packet_name: 'COMMAND',
            received_count: 1,
            stored: 'true'
          )
        )

        CommandTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "includes time fields in nanoseconds" do
        expect(EphemeralStoreQueued).to receive(:write_topic) do |topic, msg_hash|
          expect(msg_hash[:time]).to be_a(Integer)
          expect(msg_hash[:received_time]).to be_a(Integer)
        end

        CommandTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "includes packet buffer" do
        expect(EphemeralStoreQueued).to receive(:write_topic) do |topic, msg_hash|
          expect(msg_hash[:buffer]).to eq(packet.buffer(false))
        end

        CommandTopic.write_packet(packet, scope: 'DEFAULT')
      end
    end

    describe "self.send_command" do
      let(:command) do
        {
          'target_name' => 'TARGET',
          'cmd_name' => 'COMMAND',
          'cmd_params' => { 'PARAM1' => 1, 'PARAM2' => 'test' },
          'cmd_string' => 'TARGET COMMAND with PARAM1 1, PARAM2 "test"',
          'username' => 'testuser'
        }
      end

      it "returns command struct on success" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id',
          { 'id' => 'test_cmd_id', 'result' => 'SUCCESS' }, 'redis')

        result = CommandTopic.send_command(command, scope: 'DEFAULT')
        expect(result).to eq({"cmd_name"=>"COMMAND", "cmd_params"=>{"PARAM1"=>1, "PARAM2"=>"test"}, "cmd_string"=>"TARGET COMMAND with PARAM1 1, PARAM2 \"test\"", "target_name"=>"TARGET", "username"=>"testuser"})
      end

      it "writes command to correct topic" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id',
          { 'id' => 'test_cmd_id', 'result' => 'SUCCESS' }, 'redis')

        expect(Topic).to receive(:write_topic).with(
          '{DEFAULT__CMD}TARGET__TARGET',
          hash_including('target_name' => 'TARGET', 'cmd_name' => 'COMMAND'),
          '*',
          100
        )

        CommandTopic.send_command(command, scope: 'DEFAULT')
      end

      it "raises timeout error when no acknowledgment received" do
        allow(Topic).to receive(:read_topics).and_return([])

        expect {
          CommandTopic.send_command(command, timeout: 0.1, scope: 'DEFAULT')
        }.to raise_error(/Timeout of 0.1s waiting for cmd ack/)
      end

      it "raises HazardousError when result contains HazardousError" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id', {
          'id' => 'test_cmd_id',
          'result' => "HazardousError\nHazardous command description\nFormatted command"
        }, 'redis')

        expect {
          CommandTopic.send_command(command, scope: 'DEFAULT')
        }.to raise_error(HazardousError) do |error|
          expect(error.target_name).to eq('TARGET')
          expect(error.cmd_name).to eq('COMMAND')
          expect(error.hazardous_description).to eq('Hazardous command description')
          expect(error.formatted).to eq('Formatted command')
        end
      end

      it "raises CriticalCmdError when result contains CriticalCmdError" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id', {
          'id' => 'test_cmd_id',
          'result' => "CriticalCmdError\ntest-uuid-123"
        }, 'redis')

        expect {
          CommandTopic.send_command(command, scope: 'DEFAULT')
        }.to raise_error(CriticalCmdError) do |error|
          expect(error.uuid).to eq('test-uuid-123')
          expect(error.command['target_name']).to eq('TARGET')
          expect(error.command['cmd_name']).to eq('COMMAND')
          expect(error.command['username']).to eq('testuser')
        end
      end

      it "passes obfuscated_items to CriticalCmdError options" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id', {
          'id' => 'test_cmd_id',
          'result' => "CriticalCmdError\ntest-uuid-123"
        }, 'redis')

        obfuscated_items = ['PARAM1', 'PARAM2']
        command['obfuscated_items'] = obfuscated_items
        expect {
          CommandTopic.send_command(command, scope: 'DEFAULT')
        }.to raise_error(CriticalCmdError) do |error|
          expect(error.command['obfuscated_items']).to eq(obfuscated_items)
        end
      end

      it "raises generic error for other error results" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id', {
          'id' => 'test_cmd_id',
          'result' => 'Some other error message'
        }, 'redis')

        expect {
          CommandTopic.send_command(command, scope: 'DEFAULT')
        }.to raise_error('Some other error message')
      end

      it "updates topic offsets for acknowledgment topic" do
        allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id',
          { 'id' => 'test_cmd_id', 'result' => 'SUCCESS' }, 'redis')

        expect(Topic).to receive(:update_topic_offsets).with(['{DEFAULT__ACKCMD}TARGET__TARGET'])

        CommandTopic.send_command(command, scope: 'DEFAULT')
      end
    end

    describe "private methods" do
      let(:command) do
        {
          'target_name' => 'TARGET',
          'cmd_name' => 'COMMAND',
          'cmd_string' => 'TARGET COMMAND',
          'username' => 'testuser',
          'cmd_params' => { 'PARAM1' => 1 }
        }
      end

      describe "self.raise_hazardous_error" do
        it "creates HazardousError with correct attributes" do
          msg_hash = { 'result' => "HazardousError\nDescription\nFormatted" }

          expect {
            CommandTopic.send(:raise_hazardous_error, msg_hash, command)
          }.to raise_error(HazardousError) do |error|
            expect(error.target_name).to eq('TARGET')
            expect(error.cmd_name).to eq('COMMAND')
            expect(error.cmd_params).to eq({ 'PARAM1' => 1 })
            expect(error.hazardous_description).to eq('Description')
            expect(error.formatted).to eq('Formatted')
          end
        end
      end

      describe "self.raise_critical_cmd_error" do
        it "creates CriticalCmdError with correct attributes" do
          msg_hash = { 'result' => "CriticalCmdError\ntest-uuid" }
          expect {
            CommandTopic.send(:raise_critical_cmd_error, msg_hash, command)
          }.to raise_error(CriticalCmdError) do |error|
            expect(error.uuid).to eq('test-uuid')
            expect(error.command['username']).to eq('testuser')
            expect(error.command['target_name']).to eq('TARGET')
            expect(error.command['cmd_name']).to eq('COMMAND')
            expect(error.command['cmd_params']).to eq({ 'PARAM1' => 1 })
            expect(error.command['cmd_string']).to eq('TARGET COMMAND')
          end
        end
      end
    end
  end
end
