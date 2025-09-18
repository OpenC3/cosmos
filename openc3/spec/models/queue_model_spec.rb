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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/queue_model'
require 'openc3/models/microservice_model'
require 'openc3/topics/queue_topic'

module OpenC3
  describe QueueModel do
    before(:each) do
      mock_redis()
      local_s3()
    end

    after(:each) do
      local_s3_unset()
    end

    describe "self.get" do
      it "returns the specified queue model" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["name"]).to eql "TEST"
        expect(result["scope"]).to eql "DEFAULT"
        expect(result["state"]).to eql "HOLD"
      end

      it "returns nil for non-existent queue" do
        result = QueueModel.get(name: "NONEXISTENT", scope: "DEFAULT")
        expect(result).to be_nil
      end
    end

    describe "self.names" do
      it "returns all queue model names" do
        model1 = QueueModel.new(name: "TEST1", scope: "DEFAULT")
        model1.create
        model2 = QueueModel.new(name: "TEST2", scope: "DEFAULT")
        model2.create
        names = QueueModel.names(scope: "DEFAULT")
        expect(names).to contain_exactly("TEST1", "TEST2")
      end

      it "returns empty array when no queues exist" do
        names = QueueModel.names(scope: "DEFAULT")
        expect(names).to be_empty
      end
    end

    describe "self.all" do
      it "returns all queue models" do
        model1 = QueueModel.new(name: "TEST1", scope: "DEFAULT")
        model1.create
        model2 = QueueModel.new(name: "TEST2", scope: "DEFAULT")
        model2.create
        all = QueueModel.all(scope: "DEFAULT")
        expect(all.keys).to contain_exactly("TEST1", "TEST2")
        expect(all["TEST1"]["name"]).to eql "TEST1"
        expect(all["TEST2"]["name"]).to eql "TEST2"
      end

      it "returns empty hash when no queues exist" do
        all = QueueModel.all(scope: "DEFAULT")
        expect(all).to be_empty
      end
    end

    describe "self.queue_command" do
      let(:command) { 'TGT CMD with PARAM1 "hello", PARAM2 10' }

      it "raises error when queue does not exist" do
        expect {
          QueueModel.queue_command("NONEXISTENT", command: command, username: 'anonymous', scope: "DEFAULT")
        }.to raise_error(QueueError, "Queue 'NONEXISTENT' not found in scope 'DEFAULT'")
      end

      it "logs error when queue is disabled" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "DISABLE")
        model.create

        expect {
          QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")
        }.to raise_error(QueueError, "Queue 'TEST' is disabled. Command 'TGT CMD with PARAM1 \"hello\", PARAM2 10' not queued.")
      end

      it "queues command when queue is in HOLD state" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        commands = Store.zrange("DEFAULT:TEST", 0, -1).map { |cmd| JSON.parse(cmd) }
        expect(commands).to contain_exactly({ "username" => "anonymous", "value" => command, "timestamp" => anything })
      end

      it "queues command when queue is in RELEASE state" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "RELEASE")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        commands = Store.zrange("DEFAULT:TEST", 0, -1).map { |cmd| JSON.parse(cmd) }
        expect(commands).to contain_exactly({ "username" => "anonymous", "value" => command, "timestamp" => anything })
      end

      it "sends command notification" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'command'),
          scope: "DEFAULT"
        )

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")
      end

      it "adds command to existing commands" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        first_command = "TGT ABORT"
        QueueModel.queue_command("TEST", command: first_command, username: 'anonymous', scope: "DEFAULT")
        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        commands = Store.zrange("DEFAULT:TEST", 0, -1).map { |cmd| JSON.parse(cmd) }
        expect(commands).to contain_exactly({ "username" => "anonymous", "value" => first_command, "timestamp" => anything },
          { "username" => "anonymous", "value" => command, "timestamp" => anything })

        list = model.list()
        expect(list).to contain_exactly({ "username" => "anonymous", "value" => first_command, "timestamp" => anything, "index" => 1.0 },
          { "username" => "anonymous", "value" => command, "timestamp" => anything, "index" => 2.0 })
      end
    end

    describe "initialize" do
      it "initializes with correct attributes" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        expect(model.name).to eql "TEST"
        expect(model.state).to eql "HOLD"
        expect(model.scope).to eql "DEFAULT"
      end

      it "sets microservice name correctly" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        expect(model.instance_variable_get(:@microservice_name)).to eql "DEFAULT__QUEUE__TEST"
      end
    end

    describe "create" do
      it "creates the queue model" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result).not_to be_nil
        expect(result["name"]).to eql "TEST"
      end

      it "sends created notification" do
        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'created'),
          scope: "DEFAULT"
        )
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
      end
    end

    describe "update" do
      it "updates the queue model" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["state"]).to eql "HOLD"
        model = QueueModel.from_json(result, scope: "DEFAULT")
        model.state = "RELEASE"
        model.update()
        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result).not_to be_nil
        expect(result["name"]).to eql "TEST"
        expect(result["state"]).to eql "RELEASE"
      end

      it "sends updated notification" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'updated'),
          scope: "DEFAULT"
        )
        model.update
      end
    end

    describe "destroy" do
      it "removes the queue model, calls undeploy, and removes the redis list" do
        existing_microservice = double("existing_microservice", destroy: nil)
        allow(MicroserviceModel).to receive(:get_model).and_return(existing_microservice)
        allow(QueueTopic).to receive(:write_notification)
        expect(existing_microservice).to receive(:destroy)

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        model.insert_command(1, { username: "anonymous", value: "TGT CMD", timestamp: 12345 })
        model.destroy

        queue = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(queue).to be nil
        commands = Store.zrange("DEFAULT:TEST", 0, -1)
        expect(commands).to be_empty
      end
    end

    describe "as_json" do
      it "returns correct JSON representation" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        json = model.as_json
        expect(json['name']).to eql "TEST"
        expect(json['scope']).to eql "DEFAULT"
        expect(json['state']).to eql "HOLD"
        expect(json).to have_key('updated_at')
      end
    end

    describe "insert_command" do
      it "inserts command data to the store" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command_data = { username: "anonymous", value: "TGT CMD", timestamp: 1 }

        model.insert_command(1, command_data)

        commands = Store.zrange("DEFAULT:TEST", 0, -1).map { |cmd| JSON.parse(cmd) }
        expect(commands).to contain_exactly(command_data.transform_keys(&:to_s))
      end

      it "sends command notification when inserting" do
        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'command'),
          scope: "DEFAULT"
        )
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.insert_command(1, { username: "anonymous", value: "TGT CMD", timestamp: 12345 })
      end

      it "raises error when queue state is DISABLE" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "DISABLE")
        command_data = { "username" => "anonymous", "value" => "TGT CMD", "timestamp" => 1 }

        expect {
          model.insert_command(1, command_data)
        }.to raise_error(QueueError, "Queue 'TEST' is disabled. Command 'TGT CMD' not queued.")
      end
    end

    describe "update_command" do
      it "updates existing command at given index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        original_command = { username: "user1", value: "TGT CMD1", timestamp: 1000 }

        model.insert_command(1.5, original_command)
        model.update_command(index: 1.5, command: "TGT CMD2", username: "user2")

        commands = Store.zrange("DEFAULT:TEST", 0, -1).map { |cmd| JSON.parse(cmd) }
        expect(commands.length).to eq(1)
        expect(commands[0]["username"]).to eq("user2")
        expect(commands[0]["value"]).to eq("TGT CMD2")
        expect(commands[0]["timestamp"]).to be > 1000
      end

      it "raises error when updating non-existent command" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")

        expect {
          model.update_command(index: 1.0, command: "TGT CMD", username: "user1")
        }.to raise_error(QueueError, "No command found at index 1.0 in queue 'TEST'")
      end

      it "sends command notification when updating" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.insert_command(1.0, { username: "user1", value: "TGT CMD1", timestamp: 1000 })

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'command'),
          scope: "DEFAULT"
        )
        model.update_command(index: 1.0, command: "TGT CMD2", username: "user2")
      end

      it "preserves command index when updating" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.insert_command(1.0, { username: "user1", value: "TGT CMD1", timestamp: 1000 })
        model.insert_command(2.0, { username: "user1", value: "TGT CMD3", timestamp: 3000 })

        model.update_command(index: 1.0, command: "TGT CMD2", username: "user2")

        result = model.list
        expect(result.length).to eq(2)
        expect(result[0]["index"]).to eq(1.0)
        expect(result[0]["value"]).to eq("TGT CMD2")
        expect(result[0]["username"]).to eq("user2")
        expect(result[1]["index"]).to eq(2.0)
        expect(result[1]["value"]).to eq("TGT CMD3")
      end

      it "raises error when queue state is DISABLE" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.insert_command(1.0, { username: "user1", value: "TGT CMD1", timestamp: 1000 })

        # Change state to DISABLE after inserting the command
        model.state = "DISABLE"

        expect {
          model.update_command(index: 1.0, command: "TGT CMD2", username: "user2")
        }.to raise_error(QueueError, "Queue 'TEST' is disabled. Command at index 1.0 not updated.")
      end
    end

    describe "list" do
      it "returns empty array when queue is empty" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")

        result = model.list
        expect(result).to eql([])
      end

      it "returns all commands in the queue" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "TGT CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "TGT CMD2", timestamp: 2000 }
        command3 = { username: "user3", value: "TGT CMD3", timestamp: 3000 }

        model.insert_command(1, command1)
        model.insert_command(2, command2)
        model.insert_command(3, command3)

        result = model.list
        expect(result.length).to eql 3
        one = command1.transform_keys(&:to_s)
        one["index"] = 1.0
        two = command2.transform_keys(&:to_s)
        two["index"] = 2.0
        three = command3.transform_keys(&:to_s)
        three["index"] = 3.0
        expect(result[0]).to eql one
        expect(result[1]).to eql two
        expect(result[2]).to eql three
      end

      it "returns commands in FIFO order" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        first_command = { username: "user1", value: "FIRST_CMD", timestamp: 1000 }
        second_command = { username: "user2", value: "SECOND_CMD", timestamp: 2000 }

        model.insert_command(1, first_command)
        model.insert_command(2, second_command)

        result = model.list
        one = first_command.transform_keys(&:to_s)
        one["index"] = 1.0
        two = second_command.transform_keys(&:to_s)
        two["index"] = 2.0
        expect(result[0]).to eql one
        expect(result[1]).to eql two
      end

      it "reflects queue state after remove operations" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "CMD2", timestamp: 2000 }
        command3 = { username: "user3", value: "CMD3", timestamp: 3000 }

        model.insert_command(1, command1)
        model.insert_command(3, command3)
        model.insert_command(2, command2)

        expect(model.list.length).to eql 3

        # Remove the first command
        result_removed = model.remove_command(1)
        expect(result_removed).to_not be_nil
        result = model.list
        expect(result.length).to eql 2
        two = command2.transform_keys(&:to_s)
        two["index"] = 2.0
        three = command3.transform_keys(&:to_s)
        three["index"] = 3.0
        expect(result[0]).to eql two
        expect(result[1]).to eql three
      end
    end

    describe "notify" do
      it "writes notification to queue topic" do
        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'test', 'data' => kind_of(String)),
          scope: "DEFAULT"
        )
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.notify(kind: 'test')
      end

      it "includes JSON data in notification" do
        notification_data = nil
        allow(QueueTopic).to receive(:write_notification) do |notification, opts|
          notification_data = notification
        end
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.notify(kind: 'test')

        expect(notification_data['kind']).to eql 'test'
        parsed_data = JSON.parse(notification_data['data'])
        expect(parsed_data['name']).to eql "TEST"
        expect(parsed_data['state']).to eql "HOLD"
      end
    end

    describe "create_microservice" do
      it "creates a microservice with correct parameters" do
        expect(MicroserviceModel).to receive(:new).with(
          name: "DEFAULT__QUEUE__TEST",
          folder_name: nil,
          cmd: ['ruby', 'queue_microservice.rb', "DEFAULT__QUEUE__TEST"],
          work_dir: '/openc3/lib/openc3/microservices',
          options: [["QUEUE_STATE", "HOLD"]],
          topics: ["DEFAULT__QUEUE__PRIMARY_KEY"],
          target_names: [],
          plugin: nil,
          scope: "DEFAULT"
        ).and_return(double("microservice", create: nil))

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create_microservice(topics: ["DEFAULT__QUEUE__PRIMARY_KEY"])
      end
    end

    describe "deploy" do
      it "creates microservice if it doesn't exist" do
        allow(MicroserviceModel).to receive(:get_model).and_return(nil)
        mock_microservice = double("microservice", create: nil)
        expect(MicroserviceModel).to receive(:new).and_return(mock_microservice)
        expect(mock_microservice).to receive(:create)

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.deploy
      end

      it "doesn't create microservice if it already exists" do
        existing_microservice = double("existing_microservice")
        allow(MicroserviceModel).to receive(:get_model).and_return(existing_microservice)
        expect(MicroserviceModel).not_to receive(:new)

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.deploy
      end
    end

    describe "undeploy" do
      it "destroys microservice if it exists" do
        existing_microservice = double("existing_microservice", destroy: nil)
        allow(MicroserviceModel).to receive(:get_model).and_return(existing_microservice)
        allow(QueueTopic).to receive(:write_notification)
        expect(existing_microservice).to receive(:destroy)

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.undeploy
      end

      it "sends undeployed notification when destroying microservice" do
        existing_microservice = double("existing_microservice", destroy: nil)
        allow(MicroserviceModel).to receive(:get_model).and_return(existing_microservice)

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'undeployed'),
          scope: "DEFAULT"
        )

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.undeploy
      end

      it "includes microservice name and timestamp in undeployed notification" do
        existing_microservice = double("existing_microservice", destroy: nil)
        allow(MicroserviceModel).to receive(:get_model).and_return(existing_microservice)

        notification_data = nil
        allow(QueueTopic).to receive(:write_notification) do |notification, opts|
          notification_data = notification
        end

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.undeploy

        expect(notification_data['kind']).to eql 'undeployed'
        parsed_data = JSON.parse(notification_data['data'])
        expect(parsed_data['name']).to eql "DEFAULT__QUEUE__TEST"
        expect(parsed_data).to have_key('updated_at')
      end

      it "does nothing if microservice doesn't exist" do
        allow(MicroserviceModel).to receive(:get_model).and_return(nil)
        expect(QueueTopic).not_to receive(:write_notification)

        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.undeploy
      end
    end

    describe "remove_command" do
      it "returns nil when queue is empty" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")

        result = model.remove_command
        expect(result).to be_nil
      end

      it "removes the first command when no index is specified" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "CMD2", timestamp: 2000 }
        command3 = { username: "user3", value: "CMD3", timestamp: 3000 }

        model.insert_command(1.0, command1)
        model.insert_command(2.0, command2)
        model.insert_command(3.0, command3)

        result = model.remove_command

        expect(result["username"]).to eq("user1")
        expect(result["value"]).to eq("CMD1")
        expect(result["timestamp"]).to eq(1000)
        expect(result["index"]).to eq(1.0)

        # Verify the command was removed from the queue
        remaining = model.list
        expect(remaining.length).to eq(2)
        expect(remaining[0]["value"]).to eq("CMD2")
        expect(remaining[1]["value"]).to eq("CMD3")
      end

      it "removes command at specific index when index is provided" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "CMD2", timestamp: 2000 }
        command3 = { username: "user3", value: "CMD3", timestamp: 3000 }

        model.insert_command(1.0, command1)
        model.insert_command(2.0, command2)
        model.insert_command(3.0, command3)

        result = model.remove_command(2.0)

        expect(result["username"]).to eq("user2")
        expect(result["value"]).to eq("CMD2")
        expect(result["timestamp"]).to eq(2000)
        expect(result["index"]).to eq(2.0)

        # Verify the middle command was removed from the queue
        remaining = model.list
        expect(remaining.length).to eq(2)
        expect(remaining[0]["value"]).to eq("CMD1")
        expect(remaining[1]["value"]).to eq("CMD3")
      end

      it "returns nil when trying to remove non-existent index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        result = model.remove_command(5.0)
        expect(result).to be_nil

        # Verify the original command is still there
        remaining = model.list
        expect(remaining.length).to eq(1)
        expect(remaining[0]["value"]).to eq("CMD1")
      end

      it "sends command notification when removing without index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'command'),
          scope: "DEFAULT"
        )

        model.remove_command
      end

      it "sends command notification when removing with specific index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "CMD2", timestamp: 2000 }

        model.insert_command(1.0, command1)
        model.insert_command(2.0, command2)

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'command'),
          scope: "DEFAULT"
        )

        model.remove_command(2.0)
      end

      it "does not send notification when removing from empty queue" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")

        expect(QueueTopic).not_to receive(:write_notification)

        result = model.remove_command
        expect(result).to be_nil
      end

      it "does not send notification when removing non-existent index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        expect(QueueTopic).not_to receive(:write_notification)

        result = model.remove_command(5.0)
        expect(result).to be_nil
      end

      it "handles removing from single item queue" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        result = model.remove_command

        expect(result["username"]).to eq("user1")
        expect(result["value"]).to eq("CMD1")
        expect(result["index"]).to eq(1.0)

        # Queue should now be empty
        remaining = model.list
        expect(remaining).to be_empty
      end

      it "removes commands in FIFO order when called multiple times without index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "FIRST", timestamp: 1000 }
        command2 = { username: "user2", value: "SECOND", timestamp: 2000 }
        command3 = { username: "user3", value: "THIRD", timestamp: 3000 }

        model.insert_command(1.0, command1)
        model.insert_command(2.0, command2)
        model.insert_command(3.0, command3)

        first_pop = model.remove_command
        expect(first_pop["value"]).to eq("FIRST")
        expect(first_pop["index"]).to eq(1.0)

        second_pop = model.remove_command
        expect(second_pop["value"]).to eq("SECOND")
        expect(second_pop["index"]).to eq(2.0)

        third_pop = model.remove_command
        expect(third_pop["value"]).to eq("THIRD")
        expect(third_pop["index"]).to eq(3.0)

        # Queue should now be empty
        fourth_pop = model.remove_command
        expect(fourth_pop).to be_nil
      end

      it "handles fractional indices correctly" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }
        command2 = { username: "user2", value: "CMD2", timestamp: 2000 }

        model.insert_command(1.5, command1)
        model.insert_command(2.7, command2)

        result = model.remove_command(1.5)

        expect(result["value"]).to eq("CMD1")
        expect(result["index"]).to eq(1.5)

        remaining = model.list
        expect(remaining.length).to eq(1)
        expect(remaining[0]["index"]).to eq(2.7)
      end

      it "raises error when queue state is DISABLE" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        # Change state to DISABLE after inserting the command
        model.state = "DISABLE"

        expect {
          model.remove_command
        }.to raise_error(QueueError, "Queue 'TEST' is disabled. Command not removed.")
      end

      it "raises error when queue state is DISABLE and removing by index" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        command1 = { username: "user1", value: "CMD1", timestamp: 1000 }

        model.insert_command(1.0, command1)

        # Change state to DISABLE after inserting the command
        model.state = "DISABLE"

        expect {
          model.remove_command(1.0)
        }.to raise_error(QueueError, "Queue 'TEST' is disabled. Command not removed.")
      end
    end

    describe "unique scores" do
      it "ensures commands inserted via insert_command and queue_command have unique scores" do
        allow(QueueTopic).to receive(:write_notification)
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        model.create

        # Add commands using both methods
        model.insert_command(nil, { username: "user1", value: "CMD1", timestamp: 1000 })
        QueueModel.queue_command("TEST", command: "CMD2", username: "user2", scope: "DEFAULT")
        model.insert_command(nil, { username: "user3", value: "CMD3", timestamp: 3000 })
        QueueModel.queue_command("TEST", command: "CMD4", username: "user4", scope: "DEFAULT")
        model.insert_command(nil, { username: "user5", value: "CMD5", timestamp: 5000 })

        # Get all commands with their scores
        commands_withscores = Store.zrange("DEFAULT:TEST", 0, -1, withscores: true)
        scores = commands_withscores.map { |item| item[1] }

        # Verify all scores are unique
        expect(scores.uniq).to eq(scores)
        expect(scores.length).to eq(5)

        # Verify scores are in ascending order
        expect(scores).to eq(scores.sort)
      end
    end
  end
end