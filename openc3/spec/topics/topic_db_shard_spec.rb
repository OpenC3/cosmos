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

# Verifies each topic class reads and writes the db_shard it should. Every db_shard
# has its own MockRedis (mock_redis_db_shards) so data on the wrong db_shard is lost.

require 'spec_helper'
require 'openc3/topics/interface_topic'
require 'openc3/topics/router_topic'
require 'openc3/topics/decom_interface_topic'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/system_events_topic'
require 'openc3/packets/packet'

module OpenC3
  describe "Topic db_shard routing" do
    # Raised to break out of the receive_commands and receive_telemetry loops
    class StopReceiving < StandardError; end

    before(:each) do
      mock_redis_db_shards()
      # Topic offsets are kept per thread so don't carry them between tests
      Thread.current[:topic_offsets] = nil
      set_target_db_shard('INST', 0)
      set_target_db_shard('INST2', 1)
      set_model_db_shard('interfaces', 'INST_INT', 2)
      set_model_db_shard('routers', 'ROUTER_INT', 2)
    end

    def shard(db_shard)
      EphemeralStore.instance(db_shard: db_shard)
    end

    # Interfaces and routers are found by their model json on db_shard 0
    def set_model_db_shard(type, name, db_shard, scope: 'DEFAULT')
      Store.instance(db_shard: 0).hset("#{scope}__openc3_#{type}", name, JSON.generate({ 'name' => name, 'db_shard' => db_shard }))
    end

    def messages(topic, db_shard)
      shard(db_shard).xrange(topic).map { |_id, msg_hash| msg_hash }
    end

    # Run a receive loop until expected messages are received. The next read after
    # that raises so the acks for the received messages are written first. Stop
    # after max_reads in case a message is never received.
    def receive_until(expected, max_reads: 10)
      received = []
      reads = 0
      allow(Topic).to receive(:read_topics).and_wrap_original do |original, *args, **kwargs, &block|
        reads += 1
        raise StopReceiving if received.length >= expected or reads > max_reads
        original.call(*args, **kwargs, &block)
      end
      begin
        yield received
      rescue StopReceiving
      end
      received
    end

    # Act as the microservice: read count commands from cmd_topic on db_shard and ack
    # each one on the same db_shard. A command written to any other db_shard is never
    # seen so the caller times out. Returns the commands read.
    def respond(cmd_topic, ack_topic, db_shard, ack = { 'result' => 'SUCCESS' }, count: 1)
      commands = []
      thread = Thread.new do
        id = '0-0'
        start = Time.now
        while commands.length < count and (Time.now - start) < 5
          shard(db_shard).xread([cmd_topic], [id], block: 100).fetch(cmd_topic, []).each do |msg_id, msg_hash|
            commands << msg_hash
            shard(db_shard).write_topic(ack_topic, ack.merge('id' => msg_id))
            id = msg_id
          end
        end
      end
      yield
      commands
    ensure
      thread&.join
    end

    describe InterfaceTopic do
      let(:cmd_topic) { '{DEFAULT__CMD}INTERFACE__INST_INT' }
      let(:ack_topic) { '{DEFAULT__ACKCMD}INTERFACE__INST_INT' }

      describe "receive_commands" do
        it "reads each target's commands from its db_shard and acks them there" do
          interface = double('interface', name: 'INST_INT', cmd_target_names: ['INST', 'INST2'])
          Topic.update_topic_offsets(['{DEFAULT__CMD}TARGET__INST'], db_shard: 0)
          Topic.update_topic_offsets(['{DEFAULT__CMD}TARGET__INST2'], db_shard: 1)
          Topic.update_topic_offsets([cmd_topic, 'OPENC3__SYSTEM__EVENTS'], db_shard: 2)
          Topic.write_topic('{DEFAULT__CMD}TARGET__INST', { 'cmd_name' => 'INST_CMD' }, db_shard: 0)
          Topic.write_topic('{DEFAULT__CMD}TARGET__INST2', { 'cmd_name' => 'INST2_CMD' }, db_shard: 1)
          Topic.write_topic(cmd_topic, { 'connect' => 'true' }, db_shard: 2)
          Topic.write_topic('OPENC3__SYSTEM__EVENTS', { 'event' => '{}' }, db_shard: 2)
          # The interface reads its own topic from its db_shard only
          Topic.write_topic(cmd_topic, { 'connect' => 'wrong db_shard' }, db_shard: 0)

          received = receive_until(4) do |received|
            InterfaceTopic.receive_commands(interface, scope: 'DEFAULT', db_shard: 2) do |topic, _msg_id, msg_hash, _redis|
              received << [topic, msg_hash]
              topic == 'OPENC3__SYSTEM__EVENTS' ? nil : 'SUCCESS'
            end
          end

          expect(received).to contain_exactly(
            ['{DEFAULT__CMD}TARGET__INST', { 'cmd_name' => 'INST_CMD' }],
            ['{DEFAULT__CMD}TARGET__INST2', { 'cmd_name' => 'INST2_CMD' }],
            [cmd_topic, { 'connect' => 'true' }],
            ['OPENC3__SYSTEM__EVENTS', { 'event' => '{}' }],
          )
          expect(messages('{DEFAULT__ACKCMD}TARGET__INST', 0).map { |msg| msg['result'] }).to eql ['SUCCESS']
          expect(messages('{DEFAULT__ACKCMD}TARGET__INST2', 1).map { |msg| msg['result'] }).to eql ['SUCCESS']
          expect(messages(ack_topic, 2).map { |msg| msg['result'] }).to eql ['SUCCESS']
          expect(shard(2).exists('{DEFAULT__ACKCMD}TARGET__INST', '{DEFAULT__ACKCMD}TARGET__INST2')).to eql 0
          expect(shard(0).exists(ack_topic)).to eql 0
        end

        it "reads and acks everything on one db_shard when it's all on that db_shard" do
          set_model_db_shard('interfaces', 'INST_INT', 1)
          interface = double('interface', name: 'INST_INT', cmd_target_names: ['INST2'])
          Topic.update_topic_offsets(['{DEFAULT__CMD}TARGET__INST2', cmd_topic, 'OPENC3__SYSTEM__EVENTS'], db_shard: 1)
          Topic.write_topic('{DEFAULT__CMD}TARGET__INST2', { 'cmd_name' => 'INST2_CMD' }, db_shard: 1)
          Topic.write_topic(cmd_topic, { 'connect' => 'true' }, db_shard: 1)

          received = receive_until(2) do |received|
            InterfaceTopic.receive_commands(interface, scope: 'DEFAULT', db_shard: 1) do |topic, _msg_id, _msg_hash, _redis|
              received << topic
              'SUCCESS'
            end
          end

          expect(received).to contain_exactly('{DEFAULT__CMD}TARGET__INST2', cmd_topic)
          expect(messages('{DEFAULT__ACKCMD}TARGET__INST2', 1).length).to eql 1
          expect(messages(ack_topic, 1).length).to eql 1
          expect(shard(0).exists('{DEFAULT__ACKCMD}TARGET__INST2', ack_topic)).to eql 0
        end
      end

      describe "writers" do
        it "write to the interface's db_shard" do
          interface = double('interface', name: 'INST_INT')
          InterfaceTopic.connect_interface('INST_INT', scope: 'DEFAULT')
          InterfaceTopic.connect_interface('INST_INT', 'localhost', 8080, scope: 'DEFAULT')
          InterfaceTopic.disconnect_interface('INST_INT', scope: 'DEFAULT')
          InterfaceTopic.start_raw_logging('INST_INT', scope: 'DEFAULT')
          InterfaceTopic.stop_raw_logging('INST_INT', scope: 'DEFAULT')
          InterfaceTopic.shutdown(interface, scope: 'DEFAULT')
          InterfaceTopic.interface_cmd('INST_INT', 'CMD', 1, scope: 'DEFAULT')
          InterfaceTopic.protocol_cmd('INST_INT', 'CMD', 1, scope: 'DEFAULT')
          InterfaceTopic.interface_target_enable('INST_INT', 'INST', scope: 'DEFAULT')
          InterfaceTopic.interface_target_disable('INST_INT', 'INST', scope: 'DEFAULT')

          keys = messages(cmd_topic, 2).map { |msg| msg.keys.first }
          expect(keys).to eql ['connect', 'connect', 'disconnect', 'log_stream', 'log_stream', 'shutdown',
                               'interface_cmd', 'protocol_cmd', 'target_control', 'target_control']
          expect(shard(0).exists(cmd_topic)).to eql 0
        end

        it "defaults to db_shard 0 for an unknown interface" do
          InterfaceTopic.connect_interface('OTHER_INT', scope: 'DEFAULT')
          expect(messages('{DEFAULT__CMD}INTERFACE__OTHER_INT', 0).length).to eql 1
        end

        it "waits for the ack on the interface's db_shard" do
          commands = respond(cmd_topic, ack_topic, 2, count: 2) do
            InterfaceTopic.write_raw('INST_INT', "\x00", timeout: 2, scope: 'DEFAULT')
            InterfaceTopic.inject_tlm('INST_INT', 'INST', 'HEALTH_STATUS', { 'TEMP1' => 1 }, timeout: 2, scope: 'DEFAULT')
          end
          expect(commands.map { |msg| msg.keys.first }).to eql ['raw', 'inject_tlm']
          details = nil
          respond(cmd_topic, ack_topic, 2, { 'result' => '{"name":"INST_INT"}' }) do
            details = InterfaceTopic.interface_details('INST_INT', timeout: 2, scope: 'DEFAULT')
          end
          expect(details).to eql({ 'name' => 'INST_INT' })
          expect(shard(0).exists(cmd_topic, ack_topic)).to eql 0
        end
      end
    end

    describe RouterTopic do
      let(:cmd_topic) { '{DEFAULT__CMD}ROUTER__ROUTER_INT' }
      let(:ack_topic) { '{DEFAULT__ACKCMD}ROUTER__ROUTER_INT' }

      def stub_telemetry
        telemetry = double('telemetry')
        allow(telemetry).to receive(:packets).with('INST').and_return({ 'HEALTH_STATUS' => Packet.new('INST', 'HEALTH_STATUS') })
        allow(telemetry).to receive(:packets).with('INST2').and_return({ 'HEALTH_STATUS' => Packet.new('INST2', 'HEALTH_STATUS') })
        allow(System).to receive(:telemetry).and_return(telemetry)
      end

      describe "receive_telemetry" do
        it "reads each target's telemetry from its db_shard and acks router commands on the router's db_shard" do
          stub_telemetry()
          router = double('router', name: 'ROUTER_INT', tlm_target_names: ['INST', 'INST2'])
          Topic.update_topic_offsets(['DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS'], db_shard: 0)
          Topic.update_topic_offsets(['DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS'], db_shard: 1)
          Topic.update_topic_offsets([cmd_topic], db_shard: 2)
          Topic.write_topic('DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS', { 'buffer' => 'INST' }, db_shard: 0)
          Topic.write_topic('DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', { 'buffer' => 'INST2' }, db_shard: 1)
          Topic.write_topic(cmd_topic, { 'connect' => 'true' }, db_shard: 2)
          Topic.write_topic(cmd_topic, { 'connect' => 'wrong db_shard' }, db_shard: 0)

          received = receive_until(3) do |received|
            RouterTopic.receive_telemetry(router, scope: 'DEFAULT', db_shard: 2) do |topic, _msg_id, msg_hash, _redis|
              received << [topic, msg_hash]
              'SUCCESS'
            end
          end

          expect(received).to contain_exactly(
            ['DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS', { 'buffer' => 'INST' }],
            ['DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', { 'buffer' => 'INST2' }],
            [cmd_topic, { 'connect' => 'true' }],
          )
          # Only router commands are acked
          expect(messages(ack_topic, 2).map { |msg| msg['result'] }).to eql ['SUCCESS']
          expect(shard(0).exists('DEFAULT__ACKTELEMETRY__{INST}__HEALTH_STATUS')).to eql 0
          expect(shard(1).exists('DEFAULT__ACKTELEMETRY__{INST2}__HEALTH_STATUS')).to eql 0
        end

        it "reads and acks everything on one db_shard when it's all on that db_shard" do
          stub_telemetry()
          set_model_db_shard('routers', 'ROUTER_INT', 1)
          router = double('router', name: 'ROUTER_INT', tlm_target_names: ['INST2'])
          Topic.update_topic_offsets(['DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', cmd_topic], db_shard: 1)
          Topic.write_topic('DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', { 'buffer' => 'INST2' }, db_shard: 1)
          Topic.write_topic(cmd_topic, { 'connect' => 'true' }, db_shard: 1)

          received = receive_until(2) do |received|
            RouterTopic.receive_telemetry(router, scope: 'DEFAULT', db_shard: 1) do |topic, _msg_id, _msg_hash, _redis|
              received << topic
              'SUCCESS'
            end
          end

          expect(received).to contain_exactly('DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', cmd_topic)
          expect(messages(ack_topic, 1).length).to eql 1
        end
      end

      describe "writers" do
        it "write to the router's db_shard" do
          router = double('router', name: 'ROUTER_INT')
          RouterTopic.connect_router('ROUTER_INT', scope: 'DEFAULT')
          RouterTopic.connect_router('ROUTER_INT', 'localhost', 8080, scope: 'DEFAULT')
          RouterTopic.disconnect_router('ROUTER_INT', scope: 'DEFAULT')
          RouterTopic.start_raw_logging('ROUTER_INT', scope: 'DEFAULT')
          RouterTopic.stop_raw_logging('ROUTER_INT', scope: 'DEFAULT')
          RouterTopic.shutdown(router, scope: 'DEFAULT')
          RouterTopic.router_cmd('ROUTER_INT', 'CMD', 1, scope: 'DEFAULT')
          RouterTopic.protocol_cmd('ROUTER_INT', 'CMD', 1, scope: 'DEFAULT')
          RouterTopic.router_target_enable('ROUTER_INT', 'INST', scope: 'DEFAULT')
          RouterTopic.router_target_disable('ROUTER_INT', 'INST', scope: 'DEFAULT')

          keys = messages(cmd_topic, 2).map { |msg| msg.keys.first }
          expect(keys).to eql ['connect', 'connect', 'disconnect', 'log_stream', 'log_stream', 'shutdown',
                               'router_cmd', 'protocol_cmd', 'target_control', 'target_control']
          expect(shard(0).exists(cmd_topic)).to eql 0
        end

        it "waits for router_details on the router's db_shard" do
          details = nil
          respond(cmd_topic, ack_topic, 2, { 'result' => '{"name":"ROUTER_INT"}' }) do
            details = RouterTopic.router_details('ROUTER_INT', timeout: 2, scope: 'DEFAULT')
          end
          expect(details).to eql({ 'name' => 'ROUTER_INT' })
          expect(shard(0).exists(cmd_topic, ack_topic)).to eql 0
        end
      end
    end

    describe DecomInterfaceTopic do
      let(:decom_topic) { 'DEFAULT__DECOMINTERFACE__{INST2}' }
      let(:ack_topic) { '{DEFAULT__ACKCMD}TARGET__INST2' }

      it "writes to and waits for the ack on the target's db_shard" do
        buffer = nil
        ack = { 'result' => 'SUCCESS', 'stored' => 'false', 'buffer' => "\x01" }
        commands = respond(decom_topic, ack_topic, 1, ack, count: 3) do
          DecomInterfaceTopic.build_cmd('INST2', 'ABORT', {}, true, false, timeout: 2, scope: 'DEFAULT')
          DecomInterfaceTopic.inject_tlm('INST2', 'HEALTH_STATUS', { 'TEMP1' => 1 }, timeout: 2, scope: 'DEFAULT')
          buffer = DecomInterfaceTopic.get_tlm_buffer('INST2', 'HEALTH_STATUS', timeout: 2, scope: 'DEFAULT')['buffer']
        end
        expect(commands.map { |msg| msg.keys.first }).to eql ['build_cmd', 'inject_tlm', 'get_tlm_buffer']
        expect(buffer).to eql "\x01"
        expect(shard(0).exists(decom_topic, ack_topic)).to eql 0
      end
    end

    describe CommandTopic do
      let(:command) { { 'target_name' => 'INST2', 'cmd_name' => 'ABORT', 'cmd_params' => {} } }

      it "sends a command and waits for the ack on the target's db_shard" do
        commands = respond('{DEFAULT__CMD}TARGET__INST2', '{DEFAULT__ACKCMD}TARGET__INST2', 1) do
          CommandTopic.send_command(command, timeout: 2, scope: 'DEFAULT')
        end
        expect(commands.map { |msg| msg['cmd_name'] }).to eql ['ABORT']
        expect(shard(0).exists('{DEFAULT__CMD}TARGET__INST2', '{DEFAULT__ACKCMD}TARGET__INST2')).to eql 0
      end

      it "sends a fire-and-forget command to the target's db_shard" do
        CommandTopic.send_command(command, timeout: 0, scope: 'DEFAULT')
        expect(messages('{DEFAULT__CMD}TARGET__INST2', 1).length).to eql 1
        expect(shard(0).exists('{DEFAULT__CMD}TARGET__INST2')).to eql 0
      end

      it "writes a packet to the target's db_shard" do
        packet = Packet.new('INST2', 'ABORT')
        packet.received_time = Time.now
        CommandTopic.write_packet(packet, scope: 'DEFAULT')
        expect(messages('DEFAULT__COMMAND__{INST2}__ABORT', 1).length).to eql 1
        expect(shard(0).exists('DEFAULT__COMMAND__{INST2}__ABORT')).to eql 0
      end
    end

    describe CommandDecomTopic do
      it "writes and reads a decommutated command on the target's db_shard" do
        packet = Packet.new('INST2', 'ABORT')
        packet.append_item('VALUE', 8, :UINT)
        packet.write('VALUE', 5)
        packet.received_time = Time.now
        CommandDecomTopic.write_packet(packet, scope: 'DEFAULT')
        expect(messages('DEFAULT__DECOMCMD__{INST2}__ABORT', 1).length).to eql 1
        expect(shard(0).exists('DEFAULT__DECOMCMD__{INST2}__ABORT')).to eql 0
        expect(CommandDecomTopic.get_cmd_item('INST2', 'ABORT', 'VALUE', type: :RAW, scope: 'DEFAULT')).to eql 5
      end
    end

    describe TelemetryTopic do
      it "writes a packet to the target's db_shard, queued or not" do
        packet = Packet.new('INST2', 'HEALTH_STATUS')
        packet.received_time = Time.now
        TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
        TelemetryTopic.write_packet(packet, queued: true, scope: 'DEFAULT')
        expect(messages('DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', 1).length).to eql 2
        expect(shard(0).exists('DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS')).to eql 0
      end
    end

    describe TelemetryDecomTopic do
      it "writes a decommutated packet to the target's db_shard" do
        packet = Packet.new('INST2', 'HEALTH_STATUS')
        packet.append_item('VALUE', 8, :UINT)
        packet.received_time = Time.now
        packet.stored = true # Skip the CVT update
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
        expect(messages('DEFAULT__DECOM__{INST2}__HEALTH_STATUS', 1).length).to eql 1
        expect(shard(0).exists('DEFAULT__DECOM__{INST2}__HEALTH_STATUS')).to eql 0
      end
    end

    describe LimitsEventTopic do
      it "writes events to every db_shard with a target in the scope" do
        set_target_db_shard('OTHER', 3, scope: 'OTHER')
        event = { type: :LIMITS_CHANGE, target_name: 'INST2', packet_name: 'HEALTH_STATUS', item_name: 'TEMP1',
                  old_limits_state: :GREEN, new_limits_state: :RED, time_nsec: 0, message: 'test' }
        LimitsEventTopic.write(event, scope: 'DEFAULT')
        expect(messages('DEFAULT__openc3_limits_events', 0).length).to eql 1
        expect(messages('DEFAULT__openc3_limits_events', 1).length).to eql 1
        expect(shard(3).exists('DEFAULT__openc3_limits_events')).to eql 0
      end
    end

    describe SystemEventsTopic do
      it "writes events to every db_shard with a target in any scope" do
        set_target_db_shard('OTHER', 3, scope: 'OTHER')
        SystemEventsTopic.write(:scope, { 'name' => 'DEFAULT' })
        [0, 1, 3].each do |db_shard|
          expect(messages('OPENC3__SYSTEM__EVENTS', db_shard).length).to eql 1
        end
      end

      it "writes events to the db_shard of an interface without a target on it" do
        # INST_INT is on db_shard 2 and reads system events there
        SystemEventsTopic.write(:scope, { 'name' => 'DEFAULT' })
        expect(messages('OPENC3__SYSTEM__EVENTS', 2).length).to eql 1
      end
    end
  end
end
