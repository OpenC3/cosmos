# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
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
require 'openc3/script/web_socket_api'

module OpenC3
  describe WebSocketApi do
    describe "#read" do
      let(:api) do
        api = WebSocketApi.new(
          url: "ws://test.com/cable",
          authentication: double("auth", token: "test_token")
        )
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api
      end

      let(:mock_stream) { double("stream") }

      before do
        api.instance_variable_set(:@stream, mock_stream)
        api.instance_variable_set(:@subscribed, true)
      end

      context "when receiving empty string from WebSocket" do
        it "returns nil without attempting to parse JSON" do
          # Simulate WebSocket returning empty string (connection closing)
          allow(mock_stream).to receive(:read).and_return("")

          # Should not raise JSON::ParserError
          expect { api.read }.not_to raise_error

          # Should return the empty string (not try to parse it)
          result = api.read
          expect(result).to eq("")
        end

        it "handles empty string after valid messages" do
          messages = [
            '{"type":"confirm_subscription"}',
            '{"message":{"data":"test"}}',
            ""  # Connection closed
          ]
          allow(mock_stream).to receive(:read).and_return(*messages)

          # First read gets the data
          result = api.read
          expect(result).to eq({"data" => "test"})

          # Second read gets empty string without error
          result = api.read
          expect(result).to eq("")
        end
      end

      context "when receiving nil from WebSocket" do
        it "returns nil without attempting to parse" do
          allow(mock_stream).to receive(:read).and_return(nil)

          result = api.read
          expect(result).to be_nil
        end
      end

      context "when receiving valid JSON messages" do
        it "parses and returns message content" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"confirm_subscription"}',
            '{"message":{"level":"INFO","text":"test"}}'
          )

          result = api.read
          expect(result).to eq({"level" => "INFO", "text" => "test"})
        end

        it "ignores protocol messages by default" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"ping"}',
            '{"type":"welcome"}',
            '{"message":{"data":"actual_data"}}'
          )

          result = api.read
          expect(result).to eq({"data" => "actual_data"})
        end

        it "raises error on disconnect with unauthorized" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"disconnect","reason":"unauthorized"}'
          )

          expect { api.read }.to raise_error("Unauthorized")
        end

        it "raises error on reject_subscription" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"reject_subscription"}'
          )

          expect { api.read }.to raise_error("Subscription Rejected")
        end
      end

      context "with timeout parameter" do
        it "raises TimeoutError when no data received within timeout" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"ping"}',
            '{"type":"ping"}',
            '{"type":"ping"}'
          )

          start_time = Time.now
          expect {
            api.read(timeout: 0.1)
          }.to raise_error(Timeout::Error, "No Data Timeout")

          elapsed = Time.now - start_time
          expect(elapsed).to be >= 0.1
        end

        it "returns data before timeout expires" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"ping"}',
            '{"message":{"data":"quick_response"}}'
          )

          result = api.read(timeout: 5.0)
          expect(result).to eq({"data" => "quick_response"})
        end
      end

      context "with ignore_protocol_messages parameter" do
        it "returns protocol messages when set to false" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"welcome","message":{"server":"test"}}'
          )

          # With ignore_protocol_messages: false, returns the message directly
          result = api.read(ignore_protocol_messages: false)
          expect(result).to eq({"server" => "test"})
        end
      end
    end
  end
end
