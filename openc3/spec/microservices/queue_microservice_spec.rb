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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/microservices/queue_microservice'
require 'openc3/models/queue_model'
require 'openc3/topics/queue_topic'
require 'openc3/models/offline_access_model'

module OpenC3
  describe QueueProcessor do
    let(:name) { 'TEST__OPENC3__QUEUE' }
    let(:logger) { Logger.new(STDOUT) }
    let(:scope) { 'TEST' }
    let(:processor) { QueueProcessor.new(name: name, state: 'HOLD', logger: logger, scope: scope) }

    before(:each) do
      allow(ENV).to receive(:[]).and_call_original
    end

    describe '#initialize' do
      it 'initializes with correct attributes' do
        expect(processor.name).to eq(name)
        expect(processor.scope).to eq(scope)
        expect(processor.state).to eq('HOLD')
      end
    end

    describe '#run' do
      it 'processes commands when state is RELEASE' do
        processor.state = 'RELEASE'
        allow(processor).to receive(:process_queued_commands)
        allow(processor).to receive(:sleep)

        thread = Thread.new do
          processor.run
        end

        sleep 0.1
        processor.shutdown
        thread.join

        expect(processor).to have_received(:process_queued_commands).at_least(:once)
      end

      it 'sleeps when state is HOLD' do
        processor.state = 'HOLD'
        allow(processor).to receive(:sleep)

        thread = Thread.new do
          processor.run
        end

        sleep 0.1
        processor.shutdown
        thread.join

        expect(processor).to have_received(:sleep).at_least(:once)
      end

      it 'exits when shutdown is called' do
        processor.state = 'RELEASE'
        allow(processor).to receive(:process_queued_commands)

        thread = Thread.new do
          processor.run
        end

        processor.shutdown
        thread.join

        expect(thread.alive?).to be false
      end
    end

    describe '#process_queued_commands' do
      let(:command1) { { 'username' => 'test_user', 'value' => 'cmd("TARGET", "COMMAND", {"PARAM": 1})' } }
      let(:command2) { { 'username' => 'test_user', 'value' => 'cmd("TARGET", "COMMAND2", {"PARAM": 2})' } }

      before do
        allow(processor).to receive(:cmd)
        processor.state = 'RELEASE'
      end

      it 'processes all queued commands and removes them from queue' do
        call_count = 0
        allow(Store).to receive(:bzpopmin) do
          call_count += 1
          case call_count
          when 1
            ["#{scope}:QUEUE", command1.to_json, 0]
          when 2
            ["#{scope}:QUEUE", command2.to_json, 0]
          else
            # After processing all commands, change state to exit loop
            processor.state = 'HOLD'
            nil
          end
        end

        processor.process_queued_commands

        expect(Store).to have_received(:bzpopmin).exactly(3).times
        expect(processor).to have_received(:cmd)
          .with(command1['value'], queue: false, scope: scope)
        expect(processor).to have_received(:cmd)
          .with(command2['value'], queue: false, scope: scope)
      end

      it 'stops processing when queue is empty' do
        allow(Store).to receive(:bzpopmin) do
          processor.state = 'HOLD'
          nil
        end

        processor.process_queued_commands

        expect(Store).to have_received(:bzpopmin).once
        expect(processor).not_to have_received(:cmd)
      end

      it 'handles errors and continues processing when cmd fails' do
        allow(Store).to receive(:bzpopmin) do
          processor.state = 'HOLD' if processor.state == 'RELEASE'
          ["#{scope}:QUEUE", command1.to_json, 0]
        end
        allow(processor).to receive(:cmd).and_raise(StandardError.new('Command failed'))
        expect(logger).to receive(:error).with(/QueueProcessor failed to process command from queue/)

        processor.process_queued_commands
      end
    end

    describe '#shutdown' do
      it 'sets cancel_thread to true' do
        processor.shutdown
        expect(processor.instance_variable_get(:@cancel_thread)).to be true
      end
    end
  end

  describe QueueMicroservice do
    let(:name) { 'TEST__OPENC3__QUEUE' }
    let(:logger) { Logger.new(STDOUT) }
    let(:scope) { 'TEST' }
    let(:microservice) { QueueMicroservice.new(name) }

    before(:each) do
      mock_redis()
      allow(microservice).to receive(:setup_microservice_topic)
      allow(microservice).to receive(:setup_share_names)
      allow(microservice).to receive(:logger).and_return(logger)
      allow(microservice).to receive(:scope).and_return(scope)
      # Mock the config to provide options
      microservice.instance_variable_set(:@config, { 'options' => [] })
    end

    after(:each) do
      microservice.shutdown
      ThreadManager.instance.shutdown
    end

    describe '#initialize' do
      it 'creates a QueueProcessor' do
        expect(microservice.processor).to be_a(QueueProcessor)
        expect(microservice.processor.name).to eq(name.split('__').last)
        expect(microservice.processor.scope).to eq(scope)
      end

      it 'initializes processor_thread as nil' do
        expect(microservice.processor_thread).to be_nil
      end

      it 'sets initial state to HOLD by default' do
        expect(microservice.processor.state).to eq('HOLD')
      end

      context 'with options' do
        it 'sets processor state to RELEASE when QUEUE_STATE is RELEASE' do
          config_with_release = { 'options' => [['QUEUE_STATE', 'RELEASE']] }

          # Mock the entire parent initialization since options are processed there
          allow(MicroserviceModel).to receive(:get).with(name: name, scope: scope).and_return(config_with_release)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_microservice_topic)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_share_names)

          new_microservice = QueueMicroservice.new(name)
          expect(new_microservice.processor.state).to eq('RELEASE')

          new_microservice.shutdown
        end

        it 'sets processor state to HOLD when QUEUE_STATE is HOLD' do
          config_with_hold = { 'options' => [['QUEUE_STATE', 'HOLD']] }

          # Mock the entire parent initialization since options are processed there
          allow(MicroserviceModel).to receive(:get).with(name: name, scope: scope).and_return(config_with_hold)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_microservice_topic)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_share_names)

          new_microservice = QueueMicroservice.new(name)
          expect(new_microservice.processor.state).to eq('HOLD')

          new_microservice.shutdown
        end

        it 'logs error for unknown options' do
          config_with_unknown = { 'options' => [['UNKNOWN_OPTION', 'value']] }

          # Mock the entire parent initialization since options are processed there
          allow(MicroserviceModel).to receive(:get).with(name: name, scope: scope).and_return(config_with_unknown)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_microservice_topic)
          allow_any_instance_of(QueueMicroservice).to receive(:setup_share_names)
          expect_any_instance_of(Logger).to receive(:error).with(/Unknown option passed to microservice #{name}: \["UNKNOWN_OPTION", "value"\]/)

          new_microservice = QueueMicroservice.new(name)
          new_microservice.shutdown
        end
      end
    end

    describe '#run' do
      before do
        allow(QueueTopic).to receive(:write_notification)
        allow(microservice).to receive(:block_for_updates)
        allow(microservice.processor).to receive(:run)
        allow(microservice.processor).to receive(:shutdown)
        allow(Thread).to receive(:new).and_yield.and_return(double('Thread', join: nil))
      end

      it 'writes deployed notification' do
        allow(microservice).to receive(:loop).and_yield

        microservice.run

        expect(QueueTopic).to have_received(:write_notification) do |notification, options|
          expect(notification['kind']).to eq('deployed')
          expect(options[:scope]).to eq(scope)
          data = JSON.parse(notification['data'])
          expect(data['name']).to eq(name)
          expect(data['updated_at']).to be_a(Integer)
        end
      end

      it 'starts processor thread' do
        allow(microservice).to receive(:loop).and_yield

        microservice.run

        expect(Thread).to have_received(:new)
      end

      it 'calls block_for_updates in loop' do
        allow(microservice).to receive(:loop).and_yield

        microservice.run

        expect(microservice).to have_received(:block_for_updates)
      end

      it 'shuts down processor when exiting' do
        allow(microservice).to receive(:loop)

        microservice.run

        expect(microservice.processor).to have_received(:shutdown)
      end
    end

    describe '#block_for_updates' do
      let(:topics) { ['TEST__OPENC3__QUEUE'] }
      let(:msg_hash) { { 'kind' => 'updated', 'data' => '{"name": "' + name + '", "state": "RELEASE"}' } }

      before(:each) do
        allow(microservice).to receive(:puts)
        microservice.instance_variable_set(:@topics, topics)
      end

      it 'reads topics and updates processor state' do
        allow(QueueTopic).to receive(:read_topics).with(topics).and_yield('topic', 'msg_id', msg_hash, 'redis')

        thread = Thread.new { microservice.block_for_updates }
        sleep 0.1
        microservice.shutdown
        thread.join

        expect(microservice.processor.state).to eq('HOLD')
      end

      it 'handles exceptions and logs errors' do
        allow(QueueTopic).to receive(:read_topics).and_raise(StandardError.new('test error'))

        capture_io do |stdout|
          thread = Thread.new { microservice.block_for_updates }
          sleep 0.1
          microservice.shutdown
          thread.join
          expect(stdout.string).to include(/QueueMicroservice failed to read topics/)
        end
      end
    end

    describe '#shutdown' do
      it 'shuts down processor' do
        allow(microservice).to receive(:super)
        allow(microservice.processor).to receive(:shutdown)

        microservice.shutdown

        expect(microservice.processor).to have_received(:shutdown)
      end
    end
  end
end