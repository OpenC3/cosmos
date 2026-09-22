# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/protocols/protocol'
require 'openc3/interfaces/interface'
require 'openc3/interfaces/stream_interface'

module OpenC3
  describe Protocol do
    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
    end

    describe "initialize" do
      it "handles true, false and nil allow_empty_data" do
        expect(Protocol.new(nil).allow_empty_data).to be_nil
        expect(Protocol.new(true).allow_empty_data).to be true
        expect(Protocol.new(false).allow_empty_data).to be false
        # Config file values come through as strings
        expect(Protocol.new('NIL').allow_empty_data).to be_nil
        expect(Protocol.new('TRUE').allow_empty_data).to be true
        expect(Protocol.new('FALSE').allow_empty_data).to be false
      end
    end

    describe "read_data" do
      it "passes through data which isn't empty" do
        @interface.add_protocol(Protocol, [nil], :READ_WRITE)
        expect(@interface.read_protocols[0].read_data("\x01")).to eql ["\x01", nil]
        expect(@interface.read_protocols[0].read_data("\x01", 'extra')).to eql ["\x01", 'extra']
      end

      it "returns STOP on empty data when allow_empty_data is false" do
        # False means STOP even though this isn't the last protocol in the chain
        @interface.add_protocol(Protocol, [false], :READ_WRITE)
        @interface.add_protocol(Protocol, [nil], :READ_WRITE)
        expect(@interface.read_protocols[0].read_data("")).to eql :STOP
        expect(@interface.read_protocols[0].read_data("\x01")).to eql ["\x01", nil]
      end

      it "passes through empty data when allow_empty_data is true" do
        # True allows the empty string through even as the last protocol in the chain
        @interface.add_protocol(Protocol, [true], :READ_WRITE)
        expect(@interface.read_protocols[-1]).to eql @interface.read_protocols[0]
        expect(@interface.read_protocols[0].read_data("")).to eql ["", nil]
        expect(@interface.read_protocols[0].read_data("", 'extra')).to eql ["", 'extra']
      end

      it "returns STOP on empty data for the last protocol when allow_empty_data is nil" do
        @interface.add_protocol(Protocol, [nil], :READ_WRITE)
        expect(@interface.read_protocols[0].read_data("")).to eql :STOP
        @interface.add_protocol(Protocol, [nil], :READ_WRITE)
        expect(@interface.read_protocols[0].read_data("")).to eql ["", nil]
        expect(@interface.read_protocols[1].read_data("")).to eql :STOP
      end

      it "passes through empty data when allow_empty_data is nil and there is no interface" do
        expect(Protocol.new(nil).read_data("")).to eql ["", nil]
      end
    end

    describe "reset" do
      before(:each) do
        @interface.add_protocol(Protocol, [nil], :READ_WRITE)
        @protocol = @interface.read_protocols[0]
      end

      def capture_data
        @protocol.read_protocol_input_base("\x01")
        @protocol.read_protocol_output_base("\x02")
        @protocol.write_protocol_input_base("\x03")
        @protocol.write_protocol_output_base("\x04")
        @protocol.extra = { 'key' => 'value' }
      end

      def expect_cleared
        read = @protocol.read_details
        expect(read['read_data_input']).to eql ''
        expect(read['read_data_input_time']).to be_nil
        expect(read['read_data_output']).to eql ''
        expect(read['read_data_output_time']).to be_nil
        write = @protocol.write_details
        expect(write['write_data_input']).to eql ''
        expect(write['write_data_input_time']).to be_nil
        expect(write['write_data_output']).to eql ''
        expect(write['write_data_output_time']).to be_nil
        expect(@protocol.extra).to be_nil
      end

      it "initializes the details data to empty strings" do
        expect_cleared()
      end

      it "clears the captured details data and extra" do
        capture_data()
        read = @protocol.read_details
        expect(read['read_data_input']).to eql "\x01"
        expect(read['read_data_input_time']).to_not be_nil
        expect(read['read_data_output']).to eql "\x02"
        expect(read['read_data_output_time']).to_not be_nil
        write = @protocol.write_details
        expect(write['write_data_input']).to eql "\x03"
        expect(write['write_data_input_time']).to_not be_nil
        expect(write['write_data_output']).to eql "\x04"
        expect(write['write_data_output_time']).to_not be_nil
        expect(@protocol.extra).to eql({ 'key' => 'value' })

        @protocol.reset()
        expect_cleared()
      end

      it "is called by connect_reset" do
        capture_data()
        @protocol.connect_reset()
        expect_cleared()
      end

      it "is called by disconnect_reset" do
        capture_data()
        @protocol.disconnect_reset()
        expect_cleared()
      end

      it "does not capture data when save_raw_data is false" do
        @interface.save_raw_data = false
        capture_data()
        @protocol.extra = nil
        expect_cleared()
      end
    end
  end
end
