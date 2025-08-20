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
        expect(result["commands"]).to be_empty
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
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "DISABLED")
        model.create

        expect(Logger).to receive(:error).with("Queue 'TEST' is disabled. Command 'TGT CMD with PARAM1 \"hello\", PARAM2 10' not queued.")

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")
      end

      it "queues command when queue is in HOLD state" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["commands"]).to contain_exactly({ "username" => "anonymous", "value" => command })
      end

      it "queues command when queue is in RELEASE state" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "RELEASE")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["commands"]).to contain_exactly({ "username" => "anonymous", "value" => command })
      end

      it "updates the updated_at timestamp" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create
        allow(QueueTopic).to receive(:write_notification)

        original_updated_at = QueueModel.get(name: "TEST", scope: "DEFAULT")["updated_at"]
        sleep 0.001  # Ensure timestamp difference

        QueueModel.queue_command("TEST", command: command, username: 'anonymous', scope: "DEFAULT")

        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["updated_at"]).to be > original_updated_at
      end

      it "sends updated notification" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT", state: "HOLD")
        model.create

        expect(QueueTopic).to receive(:write_notification).with(
          hash_including('kind' => 'updated'),
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

        result = QueueModel.get(name: "TEST", scope: "DEFAULT")
        expect(result["commands"]).to contain_exactly({ "username" => "anonymous", "value" => first_command },
          { "username" => "anonymous", "value" => command })
      end
    end

    describe "initialize" do
      it "initializes with correct attributes" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        expect(model.name).to eql "TEST"
        expect(model.state).to eql "HOLD"
        expect(model.commands).to be_empty
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

    describe "as_json" do
      it "returns correct JSON representation" do
        model = QueueModel.new(name: "TEST", scope: "DEFAULT")
        json = model.as_json
        expect(json['name']).to eql "TEST"
        expect(json['scope']).to eql "DEFAULT"
        expect(json['state']).to eql "HOLD"
        expect(json['commands']).to be_empty
        expect(json).to have_key('updated_at')
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
          options: [],
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
  end
end