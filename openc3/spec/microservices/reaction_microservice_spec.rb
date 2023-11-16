# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/topics/autonomic_topic'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'
require 'openc3/models/reaction_model'
require 'openc3/microservices/reaction_microservice'

module OpenC3
  describe ReactionMicroservice do
    RMI_GROUP = 'GROUP'.freeze

    def generate_trigger(
      name: 'TRIG1',
      left: {'type' => 'item', 'target' => 'INST', 'packet' => 'ADCS', 'item' => 'POSX', 'valueType' => 'RAW'},
      operator: '<',
      right: {'type' => 'float', 'float' => '42'}
    )
      return TriggerModel.new(
        name: name,
        scope: $openc3_scope,
        group: RMI_GROUP,
        left: left,
        operator: operator,
        right: right,
        dependents: []
      )
    end

    def generate_reaction(
      name: 'REACT1',
      snooze: 10,
      triggers: [{'name' => 'TRIG1', 'group' => RMI_GROUP}],
      triggerLevel: 'EDGE',
      actions: [{'type' => 'command', 'value' => 'COMMAND'}]
    )
      return ReactionModel.new(
        name: name,
        scope: $openc3_scope,
        snooze: snooze,
        triggers: triggers,
        triggerLevel: triggerLevel,
        actions: actions
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

      # Stub JsonDRbObject so we can grab calls to cmd_no_hazardous_check
      json = double("JsonDRbObject").as_null_object
      allow(JsonDRbObject).to receive(:new).and_return(json)
      @command = nil
      allow(json).to receive(:method_missing) do |*args, **kwargs|
        @command = args
      end
      $api_server = ServerProxy.new
      initialize_script()

      # Stub Net::HTTP so we can grab calls to script api
      @script = nil
      net_http_post = double("Net::HTTP::Post").as_null_object
      allow(net_http_post).to receive(:body)
      allow(Net::HTTP::Post).to receive(:new) do |args|
        @script = args
        net_http_post
      end
      net_http = double("Net::HTTP").as_null_object
      response = OpenStruct.new
      response.code = '200'
      allow(net_http).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(net_http)

      # Read the log messages
      @message = nil
      @cancel_notification_read = false
      @read_notification_thread = Thread.new do
        while true
          break if @cancel_notification_read
          topic = "#{$openc3_scope}__openc3_log_messages"
          Topic.read_topics([topic]) do |_topic, _msg_id, msg_hash, _redis|
            @message = msg_hash
          end
        end
      end

      setup_system()
      model = TriggerGroupModel.new(name: RMI_GROUP, scope: $openc3_scope)
      model.create()
    end

    after(:each) do
      shutdown_script()
      @cancel_notification_read = true
      @read_notification_thread.join
    end

    describe "ReactionMicroservice" do
      it "start and stop the TriggerGroupMicroservice" do
        rus = ReactionMicroservice.new("#{$openc3_scope}__OPENC3__REACTION")
        logger = rus.instance_variable_get("@logger")
        logger.instance_variable_set("@no_store", false)
        react_thread = Thread.new { rus.run }
        sleep 0.5
        expect(react_thread.alive?).to be_truthy()
        expect(rus.manager_thread.alive?).to be_truthy()
        rus.manager.thread_pool.each do |worker|
          expect(worker.alive?).to be_truthy()
        end
        rus.shutdown
        sleep 1.1
        react_thread.join
        expect(react_thread.alive?).to be_falsey()
        expect(rus.manager_thread.alive?).to be_falsey()
        rus.manager.thread_pool.each do |worker|
          expect(worker.alive?).to be_falsey()
        end
      end

      it "executes a notification when activated" do
        trig1 = generate_trigger()
        trig1.create()
        react1 = generate_reaction(
          snooze: 2,
          triggerLevel: 'EDGE',
          actions: [{'type' => 'notify', 'value' => 'the message', 'severity' => 'ERROR'}]
        )
        react1.create()
        react1.deploy() # Create the MicroserviceModel
        sleep 0.1
        # The name here is critical and must match the name in reaction_model
        # The Microservice base class uses this to setup the topics we read
        rus = ReactionMicroservice.new("#{$openc3_scope}__OPENC3__REACTION")
        logger = rus.instance_variable_get("@logger")
        logger.instance_variable_set("@no_store", false)
        # rus.logger.level = Logger::DEBUG
        reaction_thread = Thread.new { rus.run }
        sleep 0.1

        begin
          expect(rus.share.reaction_base.reactions.keys).to eql (%w(REACT1))
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 1
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil

          now = Time.now
          trig1.state = true
          sleep 0.1
          expect(@message['message']).to include "REACT1 notify action complete, body: the message"
          expect(@message['level']).to eql "ERROR"
          @message = nil

          expect(rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1').length).to eql 0 # Snoozing
          expect(rus.share.reaction_base.reactions['REACT1']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT1']['snoozed_until']).to be_within(2).of((now + react1.snooze).to_i)

          trig1.state = false
          sleep 1 # Half the snooze
          trig1.state = true
          sleep 0.1
          expect(@message).to be nil
          # No change in reaction ... still snoozing
          expect(rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1').length).to eql 0 # Snoozing
          expect(rus.share.reaction_base.reactions['REACT1']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT1']['snoozed_until']).to be_within(2).of((now + react1.snooze).to_i)

          sleep 2 # Finish the snooze

          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil

          trig1.state = false # Disabling shouldn't do anything
          sleep 0.1
          expect(@message).to be nil
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil

          now = Time.now
          trig1.state = true # Fire again (EDGE)
          sleep 0.1
          expect(@message['message']).to include "REACT1 notify action complete, body: the message"
          expect(@message['level']).to eql "ERROR"
          expect(rus.share.reaction_base.reactions['REACT1']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT1']['snoozed_until']).to be_within(2).of((now + react1.snooze).to_i)
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 0 # Reaction is now snoozed
        ensure
          rus.shutdown
          sleep 1.1
          reaction_thread.join
        end
      end

      it "sends a command and notification when activated" do
        trig1 = generate_trigger()
        trig1.create()
        react1 = generate_reaction(
          name: 'REACT1',
          snooze: 2,
          triggerLevel: 'EDGE',
          actions: [{'type' => 'command', 'value' => 'INST ABORT'}]
        )
        react1.create()
        react1.deploy() # Create the MicroserviceModel
        react2 = generate_reaction(
          name: 'REACT2',
          snooze: 2,
          triggerLevel: 'LEVEL', # Will cause this to go off immediately
          actions: [{'type' => 'notify', 'value' => 'command message', 'severity' => 'WARN'}]
        )
        react2.create()
        react2.deploy() # Create the MicroserviceModel
        sleep 0.1

        # The name here is critical and must match the name in reaction_model
        # The Microservice base class uses this to setup the topics we read
        rus = ReactionMicroservice.new("#{$openc3_scope}__OPENC3__REACTION")
        logger = rus.instance_variable_get("@logger")
        logger.instance_variable_set("@no_store", false)
        # rus.logger.level = Logger::DEBUG
        reaction_thread = Thread.new { rus.run }
        sleep 0.1

        begin
          expect(rus.share.reaction_base.reactions.keys).to eql (%w(REACT1 REACT2))
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 2
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil
          expect(reactions[1].name).to eql 'REACT2'
          expect(reactions[1].enabled).to eql true
          expect(reactions[1].snoozed_until).to be nil

          now = Time.now
          trig1.state = true
          sleep 0.1

          expect(@command).to eql ['cmd_no_hazardous_check', 'INST ABORT']
          expect(@message['message']).to include "REACT2 notify action complete, body: command message"
          expect(@message['level']).to eql "WARN"
          @command = nil
          @message = nil

          expect(rus.share.reaction_base.reactions['REACT1']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT1']['snoozed_until']).to be_within(2).of((now + react1.snooze).to_i)
          expect(rus.share.reaction_base.reactions['REACT2']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT2']['snoozed_until']).to be_within(2).of((now + react2.snooze).to_i)
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 0 # Reactions are now snoozed

          sleep(react1.snooze + 1.1) # Allow the snooze to go off
          now = Time.now
          # REACT1 does not go off (EDGE) but REACT2 does (LEVEL)
          expect(@command).to be nil
          expect(@message['message']).to include "REACT2 notify action complete, body: command message"
          expect(@message['level']).to eql "WARN"

          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 1
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil

          expect(rus.share.reaction_base.reactions['REACT2']['enabled']).to be true
          expect(rus.share.reaction_base.reactions['REACT2']['snoozed_until']).to be_within(2).of((now + react2.snooze).to_i)
        ensure
          rus.shutdown
          sleep 1.1
          reaction_thread.join
        end
      end

      it "executes a script and notification when activated" do
        trig1 = generate_trigger()
        trig1.create()
        trig1.state = true # Start with this enabled to test LEVEL reaction

        react1 = generate_reaction(
          name: 'REACT1',
          snooze: 2,
          triggerLevel: 'EDGE',
          actions: [{'type' => 'script', 'value' => 'INST/procedures/checks.rb'}]
        )
        react1.create()
        react1.deploy() # Create the MicroserviceModel
        sleep 0.1
        # The name here is critical and must match the name in reaction_model
        # The Microservice base class uses this to setup the topics we read
        rus = ReactionMicroservice.new("#{$openc3_scope}__OPENC3__REACTION")
        logger = rus.instance_variable_get("@logger")
        logger.instance_variable_set("@no_store", false)
        # rus.logger.level = Logger::DEBUG
        reaction_thread = Thread.new { rus.run }
        sleep 0.1

        begin
          # Create the reaction after the microservice has been running
          react2 = generate_reaction(
            name: 'REACT2',
            snooze: 0, # No snooze
            triggerLevel: 'LEVEL',
            actions: [{'type' => 'notify', 'value' => 'script message', 'severity' => 'INFO'}]
          )
          react2.create()
          react2.deploy() # Create the MicroserviceModel
          sleep 0.1
          # REACT2 should immediately run
          expect(@message['message']).to include "REACT2 notify action complete, body: script message"
          expect(@message['level']).to eql "INFO"
          @message = nil
          # REACT1 should not run
          expect(@script).to be nil

          trig1.state = false

          expect(rus.share.reaction_base.reactions.keys).to eql (%w(REACT1 REACT2))
          reactions = rus.share.reaction_base.get_reactions(trigger_name: 'TRIG1')
          expect(reactions.length).to eql 2
          expect(reactions[0].name).to eql 'REACT1'
          expect(reactions[0].enabled).to eql true
          expect(reactions[0].snoozed_until).to be nil
          expect(reactions[1].name).to eql 'REACT2'
          expect(reactions[1].enabled).to eql true
          expect(reactions[1].snoozed_until).to be nil

          trig1.state = true
          sleep 0.1
          expect(@script).to include('INST/procedures/checks.rb')
          expect(@message['message']).to include "REACT2 notify action complete, body: script message"
          expect(@message['level']).to eql "INFO"
        ensure
          rus.shutdown
          sleep 1.1
          reaction_thread.join
        end
      end
    end
  end
end
