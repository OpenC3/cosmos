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
require 'openc3'
require 'openc3/packets/json_packet'

module OpenC3
  describe JsonPacket do
    before(:all) do
      setup_system()
    end

    describe "initialize" do
      it "creates a JsonPacket" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("COLLECTS", 100)
        json_data = JSON.generate(pkt.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.cmd_or_tlm).to eql :TLM
        expect(p.target_name).to eql "INST"
        expect(p.packet_name).to eql "HEALTH_STATUS"
        expect(p.packet_time).to eql time
        expect(p.stored).to be false
        expect(p.received_time).to eql time
      end
    end

    describe "read" do
      it "reads the basic types" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read("TEMP1", :RAW)).to eql 0
        expect(p.read("TEMP1", :CONVERTED)).to eql -100.0
        expect(p.read("TEMP1")).to eql -100.0
        expect(p.read("TEMP1", :FORMATTED)).to eql '-100.000'
        expect(p.read("TEMP1", :WITH_UNITS)).to eql '-100.000 C'
      end

      it "reads the reduced types" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        # Simulate the reduced values
        json_hash["TEMP1__A"] = 16000
        json_hash["TEMP1__S"] = 0.2
        json_hash["TEMP1__N"] = 0
        json_hash["TEMP1__X"] = 65535
        json_hash["TEMP1__CA"] = 0
        json_hash["TEMP1__CS"] = 0.1
        json_hash["TEMP1__CN"] = -100.0
        json_hash["TEMP1__CX"] = 100.0
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read("TEMP1", :RAW, :AVG)).to eql 16000
        expect(p.read("TEMP1", :RAW, :STDDEV)).to eql 0.2
        expect(p.read("TEMP1", :RAW, :MIN)).to eql 0
        expect(p.read("TEMP1", :RAW, :MAX)).to eql 65535
        expect(p.read("TEMP1", :CONVERTED, :AVG)).to eql 0
        expect(p.read("TEMP1", :CONVERTED, :STDDEV)).to eql 0.1
        expect(p.read("TEMP1", :CONVERTED, :MIN)).to eql -100.0
        expect(p.read("TEMP1", :CONVERTED, :MAX)).to eql 100.0
        expect { p.read("TEMP1", :FORMATTED, :AVG) }.to raise_error(/Reduced types only support RAW or CONVERTED/)
        expect { p.read("TEMP1", :WITH_UNITS, :AVG) }.to raise_error(/Reduced types only support RAW or CONVERTED/)
      end

      it "falls back if values do not exist" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("CCSDSVER", 3, :RAW)
        pkt.write("GROUND1STATUS", 1, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read("CCSDSVER", :RAW)).to eql 3
        expect(p.read("CCSDSVER", :CONVERTED)).to eql 3
        expect(p.read("CCSDSVER")).to eql 3
        expect(p.read("CCSDSVER", :FORMATTED)).to eql '3'
        expect(p.read("CCSDSVER", :WITH_UNITS)).to eql '3'
        expect(p.read("GROUND1STATUS", :RAW)).to eql 1
        expect(p.read("GROUND1STATUS", :CONVERTED)).to eql 'CONNECTED'
        expect(p.read("GROUND1STATUS")).to eql 'CONNECTED'
        expect(p.read("GROUND1STATUS", :FORMATTED)).to eql 'CONNECTED'
        expect(p.read("GROUND1STATUS", :WITH_UNITS)).to eql 'CONNECTED'
      end

      it "returns array elements" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("ARY", [0,1,2,3,4,5,6,7,8,9])
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read("ARY", :RAW)).to eql [0,1,2,3,4,5,6,7,8,9]
        expect(p.read("ARY", :CONVERTED)).to eql [0,1,2,3,4,5,6,7,8,9]
        expect(p.read("ARY")).to eql [0,1,2,3,4,5,6,7,8,9]
        expect(p.read("ARY", :FORMATTED)).to eql '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]'
        expect(p.read("ARY", :WITH_UNITS)).to eql ['0 V', '1 V', '2 V', '3 V', '4 V', '5 V', '6 V', '7 V', '8 V', '9 V']
        (0..9).each do |i|
          expect(p.read("ARY[#{i}]", :RAW)).to eql i
          expect(p.read("ARY[#{i}]", :CONVERTED)).to eql i
          expect(p.read("ARY[#{i}]")).to eql i
          expect(p.read("ARY[#{i}]", :FORMATTED)).to eql i.to_s
          expect(p.read("ARY[#{i}]", :WITH_UNITS)).to eql "#{i} V"
        end
      end

      it "returns nil if the value does not exist" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read("NOPE", :RAW)).to eql nil
        expect(p.read("NOPE", :CONVERTED)).to eql nil
        expect(p.read("NOPE")).to eql nil
        expect(p.read("NOPE", :FORMATTED)).to eql nil
        expect(p.read("NOPE", :WITH_UNITS)).to eql nil
      end
    end

    describe "read_with_limits_state" do
      it "reads the limits state" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_hash['TEMP1__L'] = 'RED_LOW'
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read_with_limits_state("TEMP1", :RAW)).to eql [0, :RED_LOW]
      end

      it "returns nil if the limits state is not set" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        expect(p.read_with_limits_state("TEMP1", :RAW)).to eql [0, nil]
      end
    end

    describe "read_all" do
      it "reads all values" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 1, :RAW)
        pkt.write("TEMP2", 2, :RAW)
        pkt.write("TEMP3", 3, :RAW)
        pkt.write("TEMP4", 4, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all(:RAW)
        expect(all['TEMP1']).to eql 1
        expect(all['TEMP2']).to eql 2
        expect(all['TEMP3']).to eql 3
        expect(all['TEMP4']).to eql 4
        expect(all.keys).to include "CCSDSVER"
        # ... plus a bunch more
      end

      it "reads a list of values" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 1, :RAW)
        pkt.write("TEMP2", 2, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_hash['TEMP1__L'] = 'RED_LOW'
        json_hash['TEMP2__L'] = 'YELLOW_HIGH'
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all(:RAW, nil, ['TEMP1', 'TEMP2'])
        expect(all).to eql({'TEMP1'=>1, 'TEMP2'=>2})
      end
    end

    describe "read_all_with_limits_states" do
      it "reads all values" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_hash['TEMP1__L'] = 'GREEN'
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all_with_limits_states(:RAW)
        expect(all['TEMP1']).to eql [0, :GREEN]
        expect(all.keys).to include "TEMP2"
        expect(all.keys).to include "TEMP3"
        expect(all.keys).to include "TEMP4"
        expect(all.keys).to include "CCSDSVER"
        # ... plus a bunch more
      end

      it "reads a list of values" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 1, :RAW)
        pkt.write("TEMP2", 2, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_hash['TEMP1__L'] = 'RED_LOW'
        json_hash['TEMP2__L'] = 'YELLOW_HIGH'
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all_with_limits_states(:RAW, nil, ['TEMP1', 'TEMP2'])
        expect(all).to eql({'TEMP1'=>[1, :RED_LOW], 'TEMP2'=>[2, :YELLOW_HIGH]})
      end
    end

    describe "read_all_names" do
      it "reads all hash names" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all_names
        expect(all).to include "CCSDSVER"
        expect(all).to include "TEMP1"
        expect(all).to include "TEMP2"
        expect(all).to include "TEMP3"
        expect(all).to include "TEMP4"
        expect(all).to include "GROUND1STATUS"
      end

      it "returns names based on type" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        json_hash = CvtModel.build_json_from_packet(pkt)
        # Simulate the reduced values
        json_hash["TEMP1__A"] = 0
        json_hash["TEMP1__S"] = 0
        json_hash["TEMP1__N"] = 0
        json_hash["TEMP1__X"] = 0
        json_hash["TEMP2__A"] = 0
        json_hash["TEMP2__S"] = 0
        json_hash["TEMP2__N"] = 0
        json_hash["TEMP2__X"] = 0
        json_hash["TEMP1__CA"] = 0
        json_hash["TEMP2__CS"] = 0
        json_hash["TEMP3__CN"] = 0
        json_hash["TEMP4__CX"] = 0
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        all = p.read_all_names(:RAW)
        expect(all).to eql p.read_all_names()
        all = p.read_all_names(:CONVERTED)
        expect(all).to eql %w(CCSDSTYPE CCSDSSHF CCSDSSEQFLAGS TEMP1 TEMP2 TEMP3 TEMP4 COLLECT_TYPE ASCIICMD GROUND1STATUS GROUND2STATUS)
        all = p.read_all_names(:FORMATTED)
        expect(all).to eql %w(PACKET_TIMESECONDS RECEIVED_TIMESECONDS TEMP1 TEMP2 TEMP3 TEMP4)
        all = p.read_all_names(:WITH_UNITS)
        expect(all).to eql %w(TEMP1 TEMP2 TEMP3 TEMP4 ARY ARY2)

        all = p.read_all_names(:RAW, :AVG)
        expect(all).to eql %w(TEMP1 TEMP2)
        all = p.read_all_names(:RAW, :STDDEV)
        expect(all).to eql %w(TEMP1 TEMP2)
        all = p.read_all_names(:RAW, :MIN)
        expect(all).to eql %w(TEMP1 TEMP2)
        all = p.read_all_names(:RAW, :MAX)
        expect(all).to eql %w(TEMP1 TEMP2)
        all = p.read_all_names(:CONVERTED, :AVG)
        expect(all).to eql %w(TEMP1)
        all = p.read_all_names(:CONVERTED, :STDDEV)
        expect(all).to eql %w(TEMP2)
        all = p.read_all_names(:CONVERTED, :MIN)
        expect(all).to eql %w(TEMP3)
        all = p.read_all_names(:CONVERTED, :MAX)
        expect(all).to eql %w(TEMP4)
      end
    end

    describe "formatted" do
      it "formats the packet as a string" do
        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.write("TEMP1", 0, :RAW)
        json_hash = CvtModel.build_json_from_packet(pkt)
        json_data = JSON.generate(json_hash.as_json(:allow_nan => true))
        time = Time.now
        p = JsonPacket.new(:TLM, "INST", "HEALTH_STATUS", time.to_nsec_from_epoch, false, json_data)
        # Check some interesting values
        expect(p.formatted).to include "CCSDSVER: 3"
        expect(p.formatted).to include "CSDSSHF: FALSE"
        expect(p.formatted).to include "TEMP1: -100.0"
        expect(p.formatted).to include "ARY: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]"
        expect(p.formatted).to include "GROUND1STATUS: CONNECTED"
      end
    end
  end
end
