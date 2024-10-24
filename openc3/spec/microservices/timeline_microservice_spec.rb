# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
require 'openc3/topics/timeline_topic'
require 'openc3/models/timeline_model'
require 'openc3/models/activity_model'
require 'openc3/microservices/timeline_microservice'

module OpenC3
  describe TimelineMicroservice do
    def generate_timeline()
      timeline = TimelineModel.new(
        name: "TEST",
        scope: "DEFAULT"
      )
      timeline.create()
    end

    def generate_activity(start, kind)
      now = Time.now.to_i
      activity = ActivityModel.new(
        name: "TEST",
        scope: "DEFAULT",
        start: now + start,
        stop: now + start + 120,
        kind: kind,
        data: { kind => "INST ABORT" },
        uuid: SecureRandom.uuid
      )
      activity.create()
      return activity
    end

    def generate_json_activity()
      now = Time.now.to_i
      activity = ActivityModel.new(
        name: "TEST",
        scope: "DEFAULT",
        start: now + 500,
        stop: now + 500 + 120,
        kind: "command",
        data: { "command" => "INST ABORT" },
        uuid: SecureRandom.uuid
      )
      return JSON.generate(activity.as_json(:allow_nan => true))
    end

    def valid_events?(events, check)
      ret = false
      events.each do |event|
        ret = (event["event"] == check) ? true : ret
      end
      return ret
    end

    before(:each) do
      @redis = mock_redis()
      setup_system()
      json = JSON.generate({'execEnabled' => true})
      ToolConfigModel.save_config('calendar-settings', 'default', json, local_mode: false, scope: 'DEFAULT')

      # allow(TimelineTopic).to receive(:read_topics) { sleep 5 }.with([]).and_yield(
      #   "topic",
      #   "id-1",
      #   { 'timeline' => 'TEST', 'type' => 'activity', 'kind' => 'create', 'data' => generate_json_activity },
      #   nil
      # ).and_yield(
      #   "topic",
      #   "id-1",
      #   { 'timeline' => 'TEST', 'type' => 'activity', 'kind' => 'delete', 'data' => generate_json_activity },
      #   nil
      # ).and_yield(
      #   "topic",
      #   "id-2",
      #   { 'timeline' => 'FOO', 'type' => 'timeline', 'kind' => 'refresh', 'data' => '{"name":"FOO"}' },
      #   nil
      # ).and_yield(
      #   "topic",
      #   "id-3",
      #   { 'timeline' => 'BAR', 'type' => 'timeline', 'kind' => 'refresh', 'data' => '{"name":"BAR"}' },
      #   nil
      # ).and_yield(
      #   "topic",
      #   "id-4",
      #   { 'timeline' => 'TEST', 'type' => 'timeline', 'kind' => 'refresh', 'data' => '{"name":"TEST"}' },
      #   nil
      # )
      # allow(TimelineTopic).to receive(:write_activity) { sleep 2 }
      # generate_timeline()
      # generate_activity(250, "command")
    end

    after(:each) do
      kill_leftover_threads()
    end

    describe "TimelineMicroservice" do
      it "runs and stops a manager thread and 3 worker threads" do
        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")

        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:info).and_call_original

        Thread.new { tm.run }
        sleep 0.1
        expect(tm.logger).to have_received(:info).with('TEST timeline manager running').once
        expect(tm.logger).to have_received(:info).with('TEST timeline worker running').exactly(3).times
        tm.shutdown
        sleep 1.1
        expect(tm.logger).to have_received(:info).with('TEST timeline manager exiting').once
        expect(tm.logger).to have_received(:info).with('TEST timeline worker exiting').exactly(3).times
      end

      it "adds and processes a command activity" do
        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
        tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:info).and_call_original

        # Stub JsonDRbObject so we can grab calls to cmd_no_hazardous_check
        json = double("JsonDRbObject").as_null_object
        allow(JsonDRbObject).to receive(:new).and_return(json)
        @command = nil
        allow(json).to receive(:method_missing) do |*args, **_kwargs|
          @command = args
        end
        $api_server = ServerProxy.new
        initialize_script()

        Thread.new { tm.run }
        sleep 0.1

        # Create 2 activities at the exact same time to verify they both execute
        now = Time.now.to_f
        activity = ActivityModel.new(
          name: "TEST",
          scope: "DEFAULT",
          start: now + 2,
          stop: now + 2.1,
          kind: 'command',
          data: { "command" => "INST CLEAR" },
          uuid: SecureRandom.uuid
        )
        activity.create()
        activity = ActivityModel.new(
          name: "TEST",
          scope: "DEFAULT",
          start: now + 2,
          stop: now + 2.1,
          kind: 'command',
          data: { "command" => "INST ABORT" },
          uuid: SecureRandom.uuid
        )
        activity.create()

        sleep 3.1
        expect(tm.logger).to have_received(:info).with(/TEST run_command/).twice
        expect(tm.logger).to have_received(:info).with(/INST ABORT/).once
        expect(tm.logger).to have_received(:info).with(/INST CLEAR/).once

        # Check the activity and primarily the events
        all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
        expect(all[0]['name']).to eql('TEST')
        expect(all[0]['fulfillment']).to be true
        expect(all[0]['start']).to eql(now + 2)
        expect(all[0]['stop']).to eql(now + 2.1)
        expect(all[0]['kind']).to eql('command')
        expect(all[0]['data']).to eql({ "command" => "INST CLEAR" })
        expect(all[0]['events'][0]['event']).to eql('created')
        expect(all[0]['events'][1]['event']).to eql('queued')
        expect(all[0]['events'][2]['event']).to eql('completed')
        expect(all[1]['name']).to eql('TEST')
        expect(all[1]['fulfillment']).to be true
        expect(all[1]['start']).to eql(now + 2)
        expect(all[1]['stop']).to eql(now + 2.1)
        expect(all[1]['kind']).to eql('command')
        expect(all[1]['data']).to eql({ "command" => "INST ABORT" })
        expect(all[1]['events'][0]['event']).to eql('created')
        expect(all[1]['events'][1]['event']).to eql('queued')
        expect(all[1]['events'][2]['event']).to eql('completed')

        tm.shutdown()
        shutdown_script()
        sleep 0.1
      end

      # NOTE: I tried to combine this with the above test case but
      # something about the JsonDRbObject double was messing up the test
      it "handles a failed command activity" do
        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
        tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:error).and_call_original

        # Stub JsonDRbObject so we can grab calls to cmd_no_hazardous_check
        json = double("JsonDRbObject").as_null_object
        allow(JsonDRbObject).to receive(:new).and_return(json)
        @command = nil
        allow(json).to receive(:method_missing) do |*args, **_kwargs|
          if args.include?('cmd_no_hazardous_check')
            raise 'error'
          end
        end
        $api_server = ServerProxy.new
        initialize_script()

        Thread.new { tm.run }
        sleep 0.1

        now = Time.now.to_f
        activity = ActivityModel.new(
          name: "TEST",
          scope: "DEFAULT",
          start: now + 2,
          stop: now + 2.1,
          kind: 'command',
          data: { "command" => "INST CLEAR" },
          uuid: SecureRandom.uuid
        )
        activity.create()

        sleep 3.1
        expect(tm.logger).to have_received(:error).with(/TEST run_command failed/).once

        # Check the activity and primarily the events
        all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
        expect(all[0]['name']).to eql('TEST')
        expect(all[0]['fulfillment']).to be false
        expect(all[0]['start']).to eql(now + 2)
        expect(all[0]['stop']).to eql(now + 2.1)
        expect(all[0]['kind']).to eql('command')
        expect(all[0]['data']).to eql({ "command" => "INST CLEAR" })
        expect(all[0]['events'][0]['event']).to eql('created')
        expect(all[0]['events'][1]['event']).to eql('queued')
        expect(all[0]['events'][2]['event']).to eql('failed')

        tm.shutdown()
        shutdown_script()
        sleep 0.1
      end

      # NOTE: I tried to combine this with the above test case but
      # something about the JsonDRbObject double was messing up the test
      it "handles a disabled command activity" do
        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
        tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:warn).and_call_original

        json = JSON.generate({'execEnabled' => false})
        ToolConfigModel.save_config('calendar-settings', 'default', json, local_mode: false, scope: 'DEFAULT')

        Thread.new { tm.run }
        sleep 0.1

        now = Time.now.to_f
        activity = ActivityModel.new(
          name: "TEST",
          scope: "DEFAULT",
          start: now + 2,
          stop: now + 2.1,
          kind: 'command',
          data: { "command" => "INST CLEAR" },
          uuid: SecureRandom.uuid
        )
        activity.create()

        sleep 3.1
        expect(tm.logger).to have_received(:warn).with(/TEST run_command disabled/).once

        # Check the activity and primarily the events
        all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
        expect(all[0]['name']).to eql('TEST')
        expect(all[0]['fulfillment']).to be false
        expect(all[0]['start']).to eql(now + 2)
        expect(all[0]['stop']).to eql(now + 2.1)
        expect(all[0]['kind']).to eql('command')
        expect(all[0]['data']).to eql({ "command" => "INST CLEAR" })
        expect(all[0]['events'][0]['event']).to eql('created')
        expect(all[0]['events'][1]['event']).to eql('queued')
        expect(all[0]['events'][2]['event']).to eql('disabled')

        tm.shutdown
        sleep 0.1
      end

      %w(completed failed disabled).each do |state|
        context state do
          it "adds and processes a script activity" do
            tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
            # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
            tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
            # Setup the spy so we can expect to get output
            allow(tm.logger).to receive(:info).and_call_original
            allow(tm.logger).to receive(:warn).and_call_original
            allow(tm.logger).to receive(:error).and_call_original

            dbl = double("Net::HTTP").as_null_object
            allow(Net::HTTP).to receive(:new).and_return(dbl)
            allow(dbl).to receive(:request) do |args|
              @request = args
              response = OpenStruct.new
              response.body = 'test'
              if state == 'completed'
                response.code = '200'
              else
                response.code = '400'
              end
              response
            end

            if state == 'disabled'
              json = JSON.generate({'execEnabled' => false})
              ToolConfigModel.save_config('calendar-settings', 'default', json, local_mode: false, scope: 'DEFAULT')
            end

            Thread.new { tm.run }
            sleep 0.1

            now = Time.now.to_f
            activity = ActivityModel.new(
              name: "TEST",
              scope: "DEFAULT",
              start: now + 2,
              stop: now + 2.1,
              kind: 'script',
              data: { "script" => "collect.rb" },
              uuid: SecureRandom.uuid
            )
            activity.create()

            sleep 3.1
            if state != 'disabled'
              expect(@request.method).to eql "POST"
              expect(@request.path).to eql "/script-api/scripts/collect.rb/run?scope=DEFAULT"
              expect(tm.logger).to have_received(:info).with(/TEST run_script/).once
            else
              expect(tm.logger).to have_received(:warn).with(/TEST run_script disabled/).once
            end

            # Check the activity and primarily the events
            all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
            expect(all[0]['name']).to eql('TEST')
            if state == 'completed'
              expect(all[0]['fulfillment']).to be true
            else
              expect(all[0]['fulfillment']).to be false
            end
            expect(all[0]['start']).to eql(now + 2)
            expect(all[0]['stop']).to eql(now + 2.1)
            expect(all[0]['kind']).to eql('script')
            expect(all[0]['data']).to eql({ "script" => "collect.rb" })
            expect(all[0]['events'][0]['event']).to eql('created')
            expect(all[0]['events'][1]['event']).to eql('queued')
            expect(all[0]['events'][2]['event']).to eql(state)

            tm.shutdown
            sleep 0.1
          end
        end
      end

      it "adds an expire activity" do
        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:info).and_call_original

        start = Time.now.to_f - (86_400 * 8) # 8 days ago
        past_activity = {
          'name' => 'TEST',
          'updated_at' => Time.now.to_nsec_from_epoch,
          'start' => start,
          'stop' => start + 60,
          'kind' => 'command',
          'scope' => 'DEFAULT',
          'uuid' => SecureRandom.uuid,
        }
        Store.zadd('DEFAULT__openc3_timelines__TEST', start, JSON.generate(past_activity))
        activities = ActivityModel.all(name: "TEST", scope: "DEFAULT")
        expect(activities.length).to eql(1)

        Thread.new { tm.run }
        sleep 1
        expect(tm.logger).to have_received(:info).with(/TEST clear_expired removed 1 items/).once
        tm.shutdown
        sleep 0.1
        activities = ActivityModel.all(name: "TEST", scope: "DEFAULT")
        expect(activities.length).to eql(0)
      end

      it "adds a cmd while microservice is running" do
        allow_any_instance_of(Object).to receive(:cmd_no_hazardous_check)

        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
        tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:info).and_call_original

        Thread.new { tm.run }
        sleep 0.1
        generate_activity(1.5, "command") # should be 1.5 seconds in the future
        array = ActivityModel.all(name: "TEST", scope: "DEFAULT")
        expect(array.length).to eql(1)
        sleep 3
        tm.shutdown
        sleep 0.1
        # Check the activity and primarily the events
        all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
        pp all
        expect(all[0]['name']).to eql('TEST')
        expect(all[0]['fulfillment']).to be true
        expect(all[0]['kind']).to eql('command')
        expect(all[0]['data']).to eql({ "command" => "INST ABORT" })
        expect(all[0]['events'][0]['event']).to eql('created')
        expect(all[0]['events'][1]['event']).to eql('queued')
        expect(all[0]['events'][2]['event']).to eql('completed')
      end

      it "removes a cmd while microservice is running" do
        allow_any_instance_of(Object).to receive(:cmd_no_hazardous_check)

        tm = TimelineMicroservice.new("DEFAULT__TIMELINE__TEST")
        # This is normally configured via passing topics to the MicroserviceModel (see timeline_model.rb)
        tm.instance_variable_set(:@topics, ["DEFAULT__openc3_timelines"])
        # Setup the spy so we can expect to get output
        allow(tm.logger).to receive(:info).and_call_original

        generate_activity(2, "command")
        activities = ActivityModel.all(name: "TEST", scope: "DEFAULT")
        pp activities
        expect(activities.length).to eql(1)

        Thread.new { tm.run }
        sleep 1
        ActivityModel.destroy(name: "TEST", scope: "DEFAULT", score: activities[0]['start'], uuid: activities[0]['uuid'])
        sleep 2
        tm.shutdown
        sleep 0.1

        expect(tm.logger).to_not have_received(:info).with(/TEST run_command/)

        # Check the activity and primarily the events
        all = ActivityModel.all(name: 'TEST', scope: 'DEFAULT')
        expect(all.length).to eql(0)
      end
    end
  end
end
