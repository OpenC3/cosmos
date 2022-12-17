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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/cvt_model'

module OpenC3
  describe CvtModel do
    def update_temp1(time: Time.now)
      json_hash = {}
      json_hash["TEMP1"]    = 1
      json_hash["TEMP1__C"] = 2
      json_hash["TEMP1__F"] = "2.00"
      json_hash["TEMP1__U"] = "2.00 C"
      json_hash["TEMP1__L"] = :GREEN
      json_hash["RECEIVED_TIMESECONDS"] = time.to_f
      CvtModel.set(json_hash, target_name: "INST", packet_name: "HEALTH_STATUS", scope: "DEFAULT")
    end

    def check_temp1
      expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 1
      expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 2
      expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "2.00"
      expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "2.00 C"
    end

    before(:each) do
      mock_redis()
      setup_system()
    end

    describe "self.set" do
      it "sets multiple values in the CVT" do
        update_temp1()
        check_temp1()
      end

      it "decoms and sets" do
        packet = Packet.new("TGT", "PKT", :BIG_ENDIAN, 'packet', "\x01\x02\x00\x01\x02\x03\x04")
        packet.append_item("ary", 8, :UINT, 16)
        i = packet.get_item("ARY")
        i.read_conversion = GenericConversion.new("value * 2")
        i.format_string = "0x%x"
        i.units = 'V'
        packet.append_item("block", 40, :BLOCK)

        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: 'DEFAULT')

        expect(CvtModel.get_item("TGT", "PKT", "ARY", type: :RAW, scope: "DEFAULT")).to eql [1, 2]
        expect(CvtModel.get_item("TGT", "PKT", "ARY", type: :CONVERTED, scope: "DEFAULT")).to eql [2, 4]
        expect(CvtModel.get_item("TGT", "PKT", "ARY", type: :FORMATTED, scope: "DEFAULT")).to eql '["0x2", "0x4"]'
        expect(CvtModel.get_item("TGT", "PKT", "ARY", type: :WITH_UNITS, scope: "DEFAULT")).to eql '["0x2 V", "0x4 V"]'
        expect(CvtModel.get_item("TGT", "PKT", "BLOCK", type: :RAW, scope: "DEFAULT")).to eql "\x00\x01\x02\x03\x04"
      end
    end

    describe "self.del" do
      it "deletes a target / packet from the CVT" do
        update_temp1()
        expect(Store.hkeys("DEFAULT__tlm__INST")).to eql ["HEALTH_STATUS"]
        CvtModel.del(target_name: "INST", packet_name: "HEALTH_STATUS", scope: "DEFAULT")
        expect(Store.hkeys("DEFAULT__tlm__INST")).to eql []
      end
    end

    describe "self.set_item" do
      it "raises for an unknown type" do
        expect { CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type 'OTHER'/)
      end

      it "temporarily sets a single value in the CVT" do
        update_temp1()

        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type: :RAW, scope: "DEFAULT")
        # Verify the :RAW value changed
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 0
        # Verify none of the other values change
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 2
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "2.00"
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "2.00 C"

        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type: :CONVERTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 0
        # Even thought we set 0 (Integer) we should get back a string "0"
        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type: :FORMATTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "0"
        # Even thought we set 0 (Integer) we should get back a string "0"
        CvtModel.set_item("INST", "HEALTH_STATUS", "TEMP1", 0, type: :WITH_UNITS, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "0"

        # Simulate TEMP1 being updated by a new packet
        update_temp1()
        # Verify we're all back to normal
        check_temp1()
      end
    end

    describe "self.get_item" do
      it "raises for an unknown type" do
        expect { CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type 'OTHER'/)
      end

      it "falls down to the next type value if the requested type doesn't exist" do
        json_hash = {}
        # TEMP2 is RAW, CONVERTED, FORMATTED only
        json_hash["TEMP2"]    = 3 # Values must be JSON encoded
        json_hash["TEMP2__C"] = 4
        json_hash["TEMP2__F"] = "4.00"
        # TEMP3 is RAW, CONVERTED only
        json_hash["TEMP3"]    = 5 # Values must be JSON encoded
        json_hash["TEMP3__C"] = 6
        # TEMP3 is RAW only
        json_hash["TEMP4"]    = 7 # Values must be JSON encoded
        CvtModel.set(json_hash, target_name: "INST", packet_name: "HEALTH_STATUS", scope: "DEFAULT")

        # Verify TEMP2
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type: :RAW, scope: "DEFAULT")).to eql 3
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type: :CONVERTED, scope: "DEFAULT")).to eql 4
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type: :FORMATTED, scope: "DEFAULT")).to eql "4.00"
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP2", type: :WITH_UNITS, scope: "DEFAULT")).to eql "4.00" # Same as FORMATTED
        # Verify TEMP3
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type: :RAW, scope: "DEFAULT")).to eql 5
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type: :CONVERTED, scope: "DEFAULT")).to eql 6
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type: :FORMATTED, scope: "DEFAULT")).to eql "6" # Same as CONVERTED but String
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP3", type: :WITH_UNITS, scope: "DEFAULT")).to eql "6" # Same as CONVERTED but String
        # Verify TEMP4
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type: :RAW, scope: "DEFAULT")).to eql 7
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type: :CONVERTED, scope: "DEFAULT")).to eql 7 # Same as RAW
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type: :FORMATTED, scope: "DEFAULT")).to eql "7" # Same as RAW but String
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP4", type: :WITH_UNITS, scope: "DEFAULT")).to eql "7" # Same as RAW but String
      end
    end

    describe "self.get_tlm_values" do
      it "returns an empty array with no values" do
        expect(CvtModel.get_tlm_values([])).to eql([])
      end

      it "raises on invalid packets" do
        expect { CvtModel.get_tlm_values(["NOPE__BLAH__TEMP1__RAW"]) }.to raise_error("Packet 'NOPE BLAH' does not exist")
      end

      it "raises on invalid items" do
        update_temp1()
        expect { CvtModel.get_tlm_values(["INST__HEALTH_STATUS__NOPE__RAW"]) }.to raise_error("Item 'INST HEALTH_STATUS NOPE' does not exist")
      end

      it "raises on invalid types" do
        update_temp1()
        expect { CvtModel.get_tlm_values(["INST__HEALTH_STATUS__TEMP1__NOPE"]) }.to raise_error("Unknown value type 'NOPE'")
      end

      it "gets different value types from the CVT" do
        update_temp1()
        values = %w(INST__HEALTH_STATUS__TEMP1__RAW INST__HEALTH_STATUS__TEMP1__CONVERTED INST__HEALTH_STATUS__TEMP1__FORMATTED INST__HEALTH_STATUS__TEMP1__WITH_UNITS)
        result = CvtModel.get_tlm_values(values)
        expect(result[0][0]).to eql 1
        expect(result[0][1]).to eql :GREEN
        expect(result[1][0]).to eql 2
        expect(result[1][1]).to eql :GREEN
        expect(result[2][0]).to eql "2.00"
        expect(result[2][1]).to eql :GREEN
        expect(result[3][0]).to eql "2.00 C"
        expect(result[3][1]).to eql :GREEN
      end

      it "marks values stale" do
        update_temp1(time: Time.now - 10)
        values = %w(INST__HEALTH_STATUS__TEMP1__RAW)
        result = CvtModel.get_tlm_values(values, stale_time: 9)
        expect(result[0][0]).to eql 1
        expect(result[0][1]).to eql :STALE
        result = CvtModel.get_tlm_values(values, stale_time: 11)
        expect(result[0][0]).to eql 1
        expect(result[0][1]).to eql :GREEN
      end

      it "returns overridden values" do
        update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :RAW, scope: "DEFAULT")
        values = %w(INST__HEALTH_STATUS__TEMP1__RAW INST__HEALTH_STATUS__TEMP1__CONVERTED)
        result = CvtModel.get_tlm_values(values)
        expect(result[0][0]).to eql 0
        expect(result[0][1]).to be_nil
        expect(result[1][0]).to eql 2
        expect(result[1][1]).to eql :GREEN
      end
    end

    describe "override" do
      it "raises for an unknown type" do
        expect { CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type 'OTHER'/)
      end

      it "overrides a value in the CVT" do
        update_temp1()
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 1
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :RAW, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 0
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 2
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :CONVERTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 0
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "2.00"
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :FORMATTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "0"
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "2.00 C"
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :WITH_UNITS, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "0"
        # Simulate TEMP1 being updated by a new packet
        update_temp1()
        # Verify we're still over-ridden
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 0
      end

      it "overrides all value in the CVT" do
        update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, scope: "DEFAULT") # default is ALL
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 0
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 0
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql '0'
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql '0'
      end
    end

    describe "normalize" do
      it "raises for an unknown type" do
        expect { CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type 'OTHER'/)
      end

      it "does nothing if no value overriden" do
        update_temp1()
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")
        check_temp1()
      end

      it "normalizes an override value type in the CVT" do
        update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 0, type: :ALL, scope: "DEFAULT")
        # This is an implementation detail but it matters that we clear it once all overrides are clear
        expect(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS")).not_to be_nil

        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 1
        # The rest are still overriden
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 0
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "0"
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "0"

        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "2.00 C"
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 2
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "2.00"
        # Once the last override is gone the key should be cleared
        expect(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS")).to be_nil
      end

      it "normalizes every value type in the CVT" do
        update_temp1()
        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 10, type: :ALL, scope: "DEFAULT")
        # This is an implementation detail but it matters that we clear it once all overrides are clear
        expect(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS")).not_to be_nil
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :RAW, scope: "DEFAULT")).to eql 10
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED, scope: "DEFAULT")).to eql 10
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED, scope: "DEFAULT")).to eql "10"
        expect(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type: :WITH_UNITS, scope: "DEFAULT")).to eql "10"
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type: :ALL, scope: "DEFAULT")
        # Once the last override is gone the key should be cleared
        expect(Store.hget("DEFAULT__override__INST", "HEALTH_STATUS")).to be_nil
        check_temp1()
      end
    end
  end
end
