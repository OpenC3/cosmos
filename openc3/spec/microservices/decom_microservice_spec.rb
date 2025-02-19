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
require 'openc3/microservices/decom_microservice'
require 'openc3/packets/limits_response'
require 'openc3/models/metric_model'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/limits_event_topic'

module OpenC3
  describe DecomMicroservice do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      redis = mock_redis()
      setup_system()
      allow(redis).to receive(:xread).and_wrap_original do |m, *args|
        # Only use the first two arguments as the last argument is keyword block:
        result = m.call(*args[0..1])
        # Create a slight delay to simulate the blocking call
        sleep 0.001 if result and result.length == 0
        result
      end

      model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: "DEFAULT")
      model.create
      model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      model = MicroserviceModel.new(name: "DEFAULT__DECOM__INST_INT", scope: "DEFAULT", topics: ["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"], target_names: ["INST"])
      model.create
      @dm = DecomMicroservice.new("DEFAULT__DECOM__INST_INT")
      @api = ApiTest.new
      @dm_thread = Thread.new { @dm.run }
      sleep 0.001 # Allow the thread to start
    end

    after(:each) do
      @dm.shutdown()
      @dm_thread.join()
    end

    describe "run" do
      it "decommutates a packet from raw to engineering values" do
        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.extra ||= {}
        packet.extra['STATUS'] = 'OK'
        packet.received_time = Time.now.sys
        capture_io do |stdout|
          TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
          sleep 0.01
          expect(stdout.string).to include("INST HEALTH_STATUS TEMP1 = -100.0 is RED_LOW (-80.0)")
          expect(stdout.string).to include("INST HEALTH_STATUS TEMP2 = -100.0 is RED_LOW (-60.0)")
          expect(stdout.string).to include("INST HEALTH_STATUS TEMP3 = -100.0 is RED_LOW (-25.0)")
          expect(stdout.string).to include("INST HEALTH_STATUS TEMP4 = -100.0 is RED_LOW (-80.0)")
          expect(stdout.string).to include("INST HEALTH_STATUS GROUND1STATUS = UNAVAILABLE is YELLOW")
          expect(stdout.string).to include("INST HEALTH_STATUS GROUND2STATUS = UNAVAILABLE is YELLOW")
        end
        expect(@api.tlm("INST HEALTH_STATUS TEMP1")).to eql(-100.0)
        expect(@api.tlm("INST HEALTH_STATUS TEMP2")).to eql(-100.0)
        expect(@api.tlm("INST HEALTH_STATUS TEMP3")).to eql(-100.0)
        expect(@api.tlm("INST HEALTH_STATUS TEMP4")).to eql(-100.0)

        events = LimitsEventTopic.read(0, scope: "DEFAULT")
        expect(events.length).to eql(6)
        # Check the first one completely
        expect(events[0][1]['type']).to eql("LIMITS_CHANGE")
        expect(events[0][1]['target_name']).to eql("INST")
        expect(events[0][1]['packet_name']).to eql("HEALTH_STATUS")
        expect(events[0][1]['item_name']).to eql("TEMP1")
        expect(events[0][1]['old_limits_state']).to eql("")
        expect(events[0][1]['new_limits_state']).to eql("RED_LOW")
        expect(events[0][1]['time_nsec']).to be > 0
        expect(events[0][1]['message']).to eql("INST HEALTH_STATUS TEMP1 = -100.0 is RED_LOW (-80.0)")
        expect(events[1][1]['message']).to eql("INST HEALTH_STATUS TEMP2 = -100.0 is RED_LOW (-60.0)")
        expect(events[2][1]['message']).to eql("INST HEALTH_STATUS TEMP3 = -100.0 is RED_LOW (-25.0)")
        expect(events[3][1]['message']).to eql("INST HEALTH_STATUS TEMP4 = -100.0 is RED_LOW (-80.0)")
        expect(events[4][1]['message']).to eql("INST HEALTH_STATUS GROUND1STATUS = UNAVAILABLE is YELLOW")
        expect(events[5][1]['message']).to eql("INST HEALTH_STATUS GROUND2STATUS = UNAVAILABLE is YELLOW")

        packet.disable_limits("TEMP3")
        packet.write("TEMP1", 0.0)
        packet.write("TEMP2", 0.0)
        packet.write("TEMP3", 0.0)
        capture_io do |stdout|
          TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
          sleep 0.01
          expect(stdout.string).to match(/INST HEALTH_STATUS TEMP1 = .* is BLUE \(-20.0 to 20.0\)/)
          expect(stdout.string).to match(/INST HEALTH_STATUS TEMP2 = .* is GREEN \(-55.0 to 30.0\)/)
        end

        # Start reading from the last event's ID
        events = LimitsEventTopic.read(events[-1][0], scope: "DEFAULT")
        expect(events.length).to eql(3)
        expect(events[0][1]['type']).to eql("LIMITS_CHANGE")
        expect(events[0][1]['target_name']).to eql("INST")
        expect(events[0][1]['packet_name']).to eql("HEALTH_STATUS")
        expect(events[0][1]['item_name']).to eql("TEMP3")
        expect(events[0][1]['old_limits_state']).to eql("RED_LOW")
        expect(events[0][1]['new_limits_state']).to eql("")
        expect(events[0][1]['time_nsec']).to be > 0
        expect(events[0][1]['message']).to eql("INST HEALTH_STATUS TEMP3 is disabled")
        expect(events[1][1]['message']).to match(/INST HEALTH_STATUS TEMP1 = .* is BLUE \(-20.0 to 20.0\)/)
        expect(events[2][1]['message']).to match(/INST HEALTH_STATUS TEMP2 = .* is GREEN \(-55.0 to 30.0\)/)
      end

      it "handles exceptions in the thread" do
        expect(@dm).to receive(:microservice_cmd).and_raise("Bad command")
        capture_io do |stdout|
          Topic.write_topic("MICROSERVICE__DEFAULT__DECOM__INST_INT", { 'connect' => 'true' }, '*', 100)
          sleep 0.01
          expect(stdout.string).to include("Decom error: RuntimeError : Bad command")
        end
        # This is an implementation detail but we want to ensure the error was logged
        expect(@dm.instance_variable_get("@metric").data['decom_error_total']['value']).to eql(1)
      end

      it "handles exceptions in user processors" do
        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        processor = double(Processor).as_null_object
        expect(processor).to receive(:call).and_raise("Bad processor")
        packet.processors['TEMP1'] = processor
        packet.received_time = Time.now.sys
        capture_io do |stdout|
          TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
          sleep 0.01
          expect(stdout.string).to include("Bad processor")
        end
        # This is an implementation detail but we want to ensure the error was logged
        expect(@dm.instance_variable_get("@metric").data['decom_error_total']['value']).to eql(1)
        # CVT is still set
        expect(@api.tlm("INST HEALTH_STATUS TEMP1")).to eql(-100.0)
        expect(@api.tlm("INST HEALTH_STATUS TEMP2")).to eql(-100.0)
      end

      it "handles limits responses in another thread" do
        class DelayedLimitsResponse < LimitsResponse
          def call(packet, item, old_limits_state)
            sleep 0.1
          end
        end

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        temp1 = packet.get_item("TEMP1")
        temp1.limits.response = DelayedLimitsResponse.new
        packet.received_time = Time.now.sys
        TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
        sleep 0.01
        # Verify that even though the limits response sleeps for 0.1s, the decom thread is not blocked
        expect(@dm.instance_variable_get("@metric").data['decom_duration_seconds']['value']).to be < 0.01
      end

      it "handles exceptions in limits responses" do
        class BadLimitsResponse < LimitsResponse
          def call(packet, item, old_limits_state)
            raise "Bad response"
          end
        end

        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        temp1 = packet.get_item("TEMP1")
        temp1.limits.response = BadLimitsResponse.new
        packet.received_time = Time.now.sys
        capture_io do |stdout|
          TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
          sleep 0.01
          expect(stdout.string).to include("INST HEALTH_STATUS TEMP1 Limits Response Exception!")
          expect(stdout.string).to include("Bad response")
        end
        lrt = @dm.instance_variable_get("@limits_response_thread")
        expect(lrt.instance_variable_get("@metric").data['limits_response_error_total']['value']).to eql(1)
      end
    end
  end
end
