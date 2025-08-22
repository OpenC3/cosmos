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
    let(:processor) { QueueProcessor.new(name: name, logger: logger, scope: scope) }

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

    describe '#get_token' do
      context 'when OPENC3_API_CLIENT is not set' do
        before do
          allow(ENV).to receive(:[]).with('OPENC3_API_CLIENT').and_return(nil)
          allow(ENV).to receive(:[]).with('OPENC3_SERVICE_PASSWORD').and_return('test_password')
          allow(ENV).to receive(:[]=).with('OPENC3_API_PASSWORD', 'test_password')
        end

        it 'uses OpenC3Authentication to get token' do
          auth_double = double('OpenC3Authentication')
          allow(OpenC3Authentication).to receive(:new).and_return(auth_double)
          allow(auth_double).to receive(:token).and_return('test_token')

          token = processor.get_token('test_user')
          expect(token).to eq('test_token')
        end
      end

      context 'when OPENC3_API_CLIENT is set' do
        before do
          allow(ENV).to receive(:[]).with('OPENC3_API_CLIENT').and_return('client')
          allow(ENV).to receive(:[]).with('OPENC3_KEYCLOAK_URL').and_return('http://keycloak.test')
        end

        context 'with valid username and offline access token' do
          it 'returns token from refresh token' do
            model_double = double('OfflineAccessModel')
            allow(model_double).to receive(:offline_access_token).and_return('refresh_token')
            allow(OpenC3::OfflineAccessModel).to receive(:get_model)
              .with(name: 'test_user', scope: scope)
              .and_return(model_double)

            auth_double = double('OpenC3KeycloakAuthentication')
            allow(OpenC3KeycloakAuthentication).to receive(:new)
              .with('http://keycloak.test')
              .and_return(auth_double)
            allow(auth_double).to receive(:get_token_from_refresh_token)
              .with('refresh_token')
              .and_return('access_token')

            token = processor.get_token('test_user')
            expect(token).to eq('access_token')
          end
        end

        context 'with no offline access token' do
          it 'returns nil' do
            model_double = double('OfflineAccessModel')
            allow(model_double).to receive(:offline_access_token).and_return(nil)
            allow(OpenC3::OfflineAccessModel).to receive(:get_model)
              .with(name: 'test_user', scope: scope)
              .and_return(model_double)

            token = processor.get_token('test_user')
            expect(token).to be_nil
          end
        end

        context 'with empty username' do
          it 'returns nil' do
            token = processor.get_token('')
            expect(token).to be_nil
          end
        end
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
        allow(processor).to receive(:get_token).with('test_user').and_return('test_token')
        allow(processor).to receive(:cmd_no_hazardous_check)
        processor.state = 'RELEASE'
      end

      it 'processes all queued commands and removes them from queue' do
        call_count = 0
        allow(Store).to receive(:blpop) do
          call_count += 1
          case call_count
          when 1
            ["#{scope}:QUEUE", command1.to_json]
          when 2
            ["#{scope}:QUEUE", command2.to_json]
          else
            # After processing all commands, change state to exit loop
            processor.state = 'HOLD'
            nil
          end
        end

        processor.process_queued_commands

        expect(Store).to have_received(:blpop).exactly(3).times
        expect(processor).to have_received(:cmd_no_hazardous_check)
          .with(command1['value'], scope: scope, token: 'test_token')
        expect(processor).to have_received(:cmd_no_hazardous_check)
          .with(command2['value'], scope: scope, token: 'test_token')
      end

      it 'stops processing when queue is empty' do
        allow(Store).to receive(:blpop) do
          processor.state = 'HOLD'
          nil
        end

        processor.process_queued_commands

        expect(Store).to have_received(:blpop).once
        expect(processor).not_to have_received(:cmd_no_hazardous_check)
      end

      it 'raises error when no token is available for username' do
        allow(Store).to receive(:blpop) do
          processor.state = 'HOLD' if processor.state == 'RELEASE'
          ["#{scope}:QUEUE", command1.to_json]
        end
        allow(processor).to receive(:get_token).with('test_user').and_return(nil)

        expect { processor.process_queued_commands }.to raise_error("No token available for username: test_user")
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
    end

    after(:each) do
      microservice.shutdown
      ThreadManager.instance.shutdown
    end

    describe '#initialize' do
      it 'creates a QueueProcessor' do
        expect(microservice.processor).to be_a(QueueProcessor)
        expect(microservice.processor.name).to eq(name)
        expect(microservice.processor.scope).to eq(scope)
      end

      it 'initializes processor_thread as nil' do
        expect(microservice.processor_thread).to be_nil
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
      let(:msg_hash) { { 'kind' => 'updated', 'data' => '{"state": "RELEASE"}' } }

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

        expect(microservice.processor.state).to eq('RELEASE')
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