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
require 'openc3/conversions/object_write_conversion'

module OpenC3
  describe ObjectWriteConversion do
    before(:each) do
      mock_redis()
      setup_system()
    end

    describe "initialize" do
      it "takes cmd/tlm, target name, packet name" do
        owc = ObjectWriteConversion.new("TLM", "inst", "HEALTH_STATUS")
        expect(owc.instance_variable_get("@cmd_or_tlm")).to eql :TLM
        expect(owc.instance_variable_get("@target_name")).to eql "INST"
        expect(owc.instance_variable_get("@packet_name")).to eql "HEALTH_STATUS"
        expect(owc.converted_type).to eql :OBJECT
        expect(owc.converted_bit_size).to eql 0
      end

      it "complains about invalid cmd/tlm" do
        expect { ObjectWriteConversion.new(:OTHER, "TGT", "PKT") }.to raise_error(ArgumentError, "Unknown type: OTHER")
      end
    end

    describe "call" do
      it "writes the CMD packet, and returns a raw block" do
        values = {}
        values['PKTID'] = 5
        values['CCSDSSEQCNT'] = 10

        # Make the same writes to a stand alone packet
        pkt = System.commands.packet("INST", "ABORT")
        pkt.write("PKTID", 5)
        pkt.write("CCSDSSEQCNT", 10)

        owc = ObjectWriteConversion.new(:CMD, "INST", "ABORT")
        result = owc.call(values, pkt, pkt.buffer)
        expect(result).to be_a String
        expect(result).to eql pkt.buffer
      end

      it "fills the TLM packet, and returns a hash of the converted values" do
        values = {}
        values['CCSDSSEQCNT'] = 11
        values['VALUE0'] = 1
        values['VALUE2'] = 1
        values['VALUE4'] = 1

        # Make the same writes to a stand alone packet
        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.write('CCSDSSEQCNT', 11)
        pkt.write("VALUE0", 1)
        pkt.write("VALUE2", 1)
        pkt.write("VALUE4", 1)

        owc = ObjectWriteConversion.new(:TLM, "INST", "PARAMS")
        result = owc.call(values, pkt, pkt.buffer)
        expect(result).to be_a String
        expect(result).to eql pkt.buffer
      end
    end

    describe "to_s" do
      it "returns the parameters" do
        owc = ObjectWriteConversion.new(:TLM, "INST", "PARAMS").to_s
        expect(owc).to eql "ObjectWriteConversion TLM INST PARAMS"
      end
    end

    describe "to_config" do
      it "returns a read config snippet" do
        owc = ObjectWriteConversion.new(:TLM, "INST", "PARAMS").to_config("WRITE").strip()
        expect(owc).to eql "WRITE_CONVERSION object_write_conversion.rb TLM INST PARAMS"
      end
    end

    describe "as_json" do
      it "creates a reproducible format" do
        owc = ObjectWriteConversion.new(:TLM, "INST", "PARAMS")
        json = owc.as_json(allow_nil: true)
        expect(json['class']).to eql "OpenC3::ObjectWriteConversion"
        expect(json['converted_type']).to eql :OBJECT
        expect(json['converted_bit_size']).to eql 0
        expect(json['params']).to eql ["TLM", "INST", "PARAMS"]
      end
    end
  end
end
