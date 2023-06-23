# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/topics/autonomic_topic'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'
require 'openc3/microservices/trigger_group_microservice'

module OpenC3
  describe TriggerGroupMicroservice do
    TGMI_GROUP = 'GROUP'.freeze

    def generate_trigger_group_model(name: TGMI_GROUP)
      return TriggerGroupModel.new(name: name, scope: $openc3_scope)
    end

    def generate_trigger(
      name: 'TRIG1',
      left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSX', 'valueType' => 'RAW'},
      operator: '<',
      right: {'type' => 'float', 'float' => '42'}
    )
      return TriggerModel.new(
        name: name,
        scope: $openc3_scope,
        group: TGMI_GROUP,
        left: left,
        operator: operator,
        right: right,
        dependents: []
      )
    end

    before(:each) do
      @redis = mock_redis()
      allow(@redis).to receive(:xread).and_wrap_original do |m, *args|
        # Only use the first two arguments as the last argument is keyword block:
        result = m.call(*args[0..1])
        # Create a slight delay to simulate the blocking call
        sleep 0.01 if result and result.length == 0
        result
      end

      setup_system()
      model = generate_trigger_group_model()
      model.create()
      model.deploy()
      # The name here is critical because when we deploy the trigger group model above
      # it creates a MicroserviceModel with name SCOPE__TRIGGER_GROUP__NAME
      # The Microservice base class uses this to setup the topics we read
      @tgm = TriggerGroupMicroservice.new("#{$openc3_scope}__TRIGGER_GROUP__#{TGMI_GROUP}")

      %w(INST SYSTEM).each do |target|
        model = TargetModel.new(folder_name: target, name: target, scope: "DEFAULT")
        model.create
        model.update_store(System.new([target], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end
    end

    describe "TriggerGroupMicroservice" do
      it "starts and stops the TriggerGroupMicroservice" do
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1
        expect(trigger_thread.alive?).to be_truthy()
        expect(@tgm.manager_thread.alive?).to be_truthy()
        for worker in @tgm.manager.thread_pool do
          expect(worker.alive?).to be_truthy()
        end
        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
        expect(trigger_thread.alive?).to be_falsey()
        expect(@tgm.manager_thread.alive?).to be_falsey()
        for worker in @tgm.manager.thread_pool do
          expect(worker.alive?).to be_falsey()
        end
      end

      it "creates and deletes triggers and adds and removes corresponding topics" do
        @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: 'TRIG1',
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSX', 'valueType' => 'RAW'},
          operator: '<',
          right: {'type' => 'float', 'float' => '42'}
        ).create()
        sleep 0.1
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1"])

        generate_trigger(
          name: 'TRIG2',
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSY', 'valueType' => 'CONVERTED'},
          operator: '<',
          right: {'type' => 'float', 'float' => '42'}
        ).create()
        sleep 0.1
        # No topic change because we're listening to the same packet
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1", "TRIG2"])

        trig3 = generate_trigger(
          name: 'TRIG3',
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'COLLECTS', 'valueType' => 'CONVERTED'},
          operator: '<',
          right: {'type' => 'float', 'float' => '42'}
        )
        trig3.create()
        sleep 0.1
        # Add new packet
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1", "TRIG2", "TRIG3"])

        # Modify the trigger to switch the item packet
        trig3.left = {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSZ', 'valueType' => 'CONVERTED'}
        trig3.update()
        sleep 0.1
        # We've now removed the HEALTH_STATUS
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1", "TRIG2", "TRIG3"])
        # Checking triggers_from is rather black box but it is explicitly checking for a previous bug
        triggers = @tgm.share.trigger_base.triggers_from(topic: 'DEFAULT__DECOM__{INST}__ADCS')
        expect(triggers.length).to eql 3
        expect(triggers[0].name).to eql 'TRIG1'
        expect(triggers[1].name).to eql 'TRIG2'
        expect(triggers[2].name).to eql 'TRIG3'
        triggers = @tgm.share.trigger_base.triggers_from(topic: 'DEFAULT__DECOM__{INST}__HEALTH_STATUS')
        expect(triggers.length).to eql 0

        # Modify the trigger to switch the packet back
        trig3.left = {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'DURATION', 'valueType' => 'CONVERTED'}
        trig3.update()
        sleep 0.1
        # HEALTH_STATUS is back
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1", "TRIG2", "TRIG3"])
        # Checking triggers_from is rather black box but it is explicitly checking for a previous bug
        triggers = @tgm.share.trigger_base.triggers_from(topic: 'DEFAULT__DECOM__{INST}__ADCS')
        expect(triggers.length).to eql 2
        expect(triggers[0].name).to eql 'TRIG1'
        expect(triggers[1].name).to eql 'TRIG2'
        triggers = @tgm.share.trigger_base.triggers_from(topic: 'DEFAULT__DECOM__{INST}__HEALTH_STATUS')
        expect(triggers.length).to eql 1
        expect(triggers[0].name).to eql 'TRIG3'

        TriggerModel.delete(name: 'TRIG3', group: TGMI_GROUP, scope: 'DEFAULT')
        sleep 0.1
        # HEALTH_STATUS is gone
        expect(@tgm.manager.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (["TRIG1", "TRIG2"])

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on float comparison" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        %w(== != < > <= >=).each_with_index do |operator, index|
          generate_trigger(
            name: "TRIG#{index + 1}",
            left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSX', 'valueType' => 'RAW'},
            operator: operator,
            right: {'type' => 'float', 'float' => '0'}
          ).create()
        end
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2 TRIG3 TRIG4 TRIG5 TRIG6))

        packet = System.telemetry.packet('INST', 'ADCS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('POSX', 0, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG5'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG6'].state).to be true

        packet.write('POSX', 1, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG5'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG6'].state).to be true

        packet.write('POSX', -1, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG5'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG6'].state).to be false

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on string comparison" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        %w(== !=).each_with_index do |operator, index|
          generate_trigger(
            name: "TRIG#{index + 1}",
            left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'GROUND1STATUS', 'valueType' => 'CONVERTED'},
            operator: operator,
            right: {'type' => 'string', 'string' => 'CONNECTED'}
          ).create()
        end
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('GROUND1STATUS', 'CONNECTED')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false

        packet.write('GROUND1STATUS', 'UNAVAILABLE')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on regex comparison" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        %w(== !=).each_with_index do |operator, index|
          generate_trigger(
            name: "TRIG#{index + 1}",
            left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'ASCIICMD', 'valueType' => 'RAW'},
            operator: operator,
            right: {'type' => 'regex', 'regex' => '\d\dTEST\d\d'}
          ).create()
        end
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('ASCIICMD', '12TEST34')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false

        packet.write('ASCIICMD', '12TEST3')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on item limits states" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP1', 'valueType' => 'CONVERTED'},
          operator: '==',
          right: {'type' => 'limit', 'limit' => 'RED_HIGH'}
        ).create()
        generate_trigger(
          name: "TRIG2",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP1', 'valueType' => 'CONVERTED'},
          operator: '==',
          right: {'type' => 'limit', 'limit' => 'YELLOW_LOW'}
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('TEMP1', 90)
        packet.check_limits
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false

        packet.write('TEMP1', -75)
        packet.check_limits
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true

        packet.write('TEMP1', 0)
        packet.check_limits
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on packet value changing" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP1', 'valueType' => 'RAW'},
          operator: 'CHANGES',
          right: nil,
        ).create()
        generate_trigger(
          name: "TRIG2",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP2', 'valueType' => 'RAW'},
          operator: 'DOES NOT CHANGE',
          right: nil
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('TEMP1', 0, :RAW)
        packet.write('TEMP2', 0, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false # Not enough history
        # The second sample is when we can start doing the comparisons
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true

        packet.write('TEMP1', 1, :RAW)
        packet.write('TEMP2', 1, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should trigger on nested triggers" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP1', 'valueType' => 'RAW'},
          operator: '>',
          right: {'type' => 'float', 'float' => '0'}
        ).create()
        generate_trigger(
          name: "TRIG2",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP2', 'valueType' => 'RAW'},
          operator: '>',
          right: {'type' => 'float', 'float' => '0'}
        ).create()
        generate_trigger(
          name: "TRIG3",
          left: {'type' => 'trigger', 'trigger' => 'TRIG1'},
          operator: 'AND',
          right: {'type' => 'trigger', 'trigger' => 'TRIG2'},
        ).create()
        generate_trigger(
          name: "TRIG4",
          left: {'type' => 'trigger', 'trigger' => 'TRIG1'},
          operator: 'OR',
          right: {'type' => 'trigger', 'trigger' => 'TRIG2'},
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2 TRIG3 TRIG4))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('TEMP1', 0, :RAW)
        packet.write('TEMP2', 0, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be false

        packet.write('TEMP1', 1, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be true

        packet.write('TEMP2', 1, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be true

        packet.write('TEMP1', 0, :RAW)
        packet.write('TEMP2', 0, :RAW)
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG3'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG4'].state).to be false

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should disable bad regex triggers" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'ASCIICMD', 'valueType' => 'RAW'},
          operator: '==',
          right: {'type' => 'regex', 'regex' => '*'} # Not a valid Regex
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('ASCIICMD', '12TEST34')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers).to be_empty # No longer enabled
        expect(@tgm.share.trigger_base.triggers['TRIG1']['enabled']).to eql false
        expect(@tgm.share.trigger_base.triggers['TRIG1']['state']).to eql false

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should disable bad evaluation triggers" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          # NOPE is a bad item which shouldn't be possible due to the front end checks
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'NOPE', 'valueType' => 'RAW'},
          operator: '>',
          right: {'type' => 'float', 'float' => '10'}
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1))

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.stored = false
        packet.write('ASCIICMD', '12TEST34')
        TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers).to be_empty # No longer enabled
        expect(@tgm.share.trigger_base.triggers['TRIG1']['enabled']).to eql false
        expect(@tgm.share.trigger_base.triggers['TRIG1']['state']).to eql false

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end

      it "should handle different rate packets" do
        # @tgm.logger.level = Logger::DEBUG
        trigger_thread = Thread.new { @tgm.run }
        sleep 0.1

        generate_trigger(
          name: "TRIG1",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSX', 'valueType' => 'RAW'},
          operator: '==',
          right: {'type' => 'float', 'float' => '0'}
        ).create()
        generate_trigger(
          name: "TRIG2",
          left: {'type' => 'item', 'target' => 'INST', 'packet' => 'HEALTH_STATUS', 'item' => 'TEMP1', 'valueType' => 'RAW'},
          operator: '!=',
          right: {'type' => 'float', 'float' => '0'}
        ).create()
        sleep 0.1
        expect(@tgm.share.trigger_base.topics).to eql(['DEFAULT__openc3_autonomic', 'DEFAULT__DECOM__{INST}__ADCS', 'DEFAULT__DECOM__{INST}__HEALTH_STATUS'])
        expect(@tgm.share.trigger_base.enabled_triggers.keys).to eql (%w(TRIG1 TRIG2))

        start = Time.now.to_f * 1000 # milliseconds
        adcs_packet = System.telemetry.packet('INST', 'ADCS')
        adcs_packet.received_time = Time.now.sys
        adcs_packet.stored = false
        adcs_packet.write('POSX', 0, :RAW)
        TelemetryDecomTopic.write_packet(adcs_packet, scope: "DEFAULT")
        hs_packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        hs_packet.received_time = Time.now.sys
        hs_packet.stored = false
        hs_packet.write('TEMP1', 1, :RAW)
        TelemetryDecomTopic.write_packet(hs_packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].updated_at / 1_000_000).to be_within(30).of(start)
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].updated_at / 1_000_000).to be_within(30).of(start)

        now = Time.now.to_f * 1000 # milliseconds
        adcs_packet.write('POSX', 1, :RAW)
        TelemetryDecomTopic.write_packet(adcs_packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].updated_at / 1_000_000).to be_within(30).of(now)
        # TRIG2 doesn't change and is not updated
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].updated_at / 1_000_000).to be_within(30).of(start)

        now = Time.now.to_f * 1000 # milliseconds
        adcs_packet.write('POSX', 0, :RAW)
        TelemetryDecomTopic.write_packet(adcs_packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].updated_at / 1_000_000).to be_within(30).of(now)
        # TRIG2 doesn't change and is not updated
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].updated_at / 1_000_000).to be_within(30).of(start)

        now2 = Time.now.to_f * 1000 # milliseconds
        hs_packet.write('TEMP1', 0, :RAW)
        TelemetryDecomTopic.write_packet(hs_packet, scope: "DEFAULT")
        sleep(0.1) # Allow the write to happen
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].state).to be true
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG1'].updated_at / 1_000_000).to be_within(30).of(now)
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].state).to be false
        expect(@tgm.share.trigger_base.enabled_triggers['TRIG2'].updated_at / 1_000_000).to be_within(30).of(now2)

        @tgm.shutdown
        sleep 0.1
        trigger_thread.join
      end
    end
  end
end
