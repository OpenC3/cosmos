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
        # Empty frames are normal end-of-stream signals when ActionCable / anycable-go
        # closes the connection. Returning nil (rather than "") lets canonical
        # `while (resp = api.read)` consumer loops terminate cleanly.
        it "returns nil without attempting to parse JSON" do
          allow(mock_stream).to receive(:read).and_return("")

          expect { api.read }.not_to raise_error
          expect(api.read).to be_nil
        end

        it "handles empty string after valid messages" do
          messages = [
            '{"type":"confirm_subscription"}',
            '{"message":{"data":"test"}}',
            ""
          ]
          allow(mock_stream).to receive(:read).and_return(*messages)

          expect(api.read).to eq({ "data" => "test" })
          expect(api.read).to be_nil
        end
      end

      context "when receiving nil from WebSocket" do
        it "returns nil without attempting to parse" do
          allow(mock_stream).to receive(:read).and_return(nil)
          expect(api.read).to be_nil
        end
      end

      context "when receiving a malformed (non-empty) frame" do
        # Defense-in-depth: a non-empty but malformed frame should not crash
        # cli_script_monitor either — surface it as end-of-stream.
        it "returns nil instead of raising JSON::ParserError" do
          allow(mock_stream).to receive(:read).and_return("not json{")
          expect { api.read }.not_to raise_error
          expect(api.read).to be_nil
        end
      end

      context "when receiving valid JSON messages" do
        it "parses and returns message content" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"confirm_subscription"}',
            '{"message":{"level":"INFO","text":"test"}}'
          )
          expect(api.read).to eq({ "level" => "INFO", "text" => "test" })
        end

        it "ignores protocol messages by default" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"ping"}',
            '{"type":"welcome"}',
            '{"message":{"data":"actual_data"}}'
          )
          expect(api.read).to eq({ "data" => "actual_data" })
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
          expect(Time.now - start_time).to be >= 0.1
        end

        it "returns data before timeout expires" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"ping"}',
            '{"message":{"data":"quick_response"}}'
          )
          expect(api.read(timeout: 5.0)).to eq({ "data" => "quick_response" })
        end
      end

      context "with ignore_protocol_messages parameter" do
        it "returns protocol messages when set to false" do
          allow(mock_stream).to receive(:read).and_return(
            '{"type":"welcome","message":{"server":"test"}}'
          )
          expect(api.read(ignore_protocol_messages: false)).to eq({ "server" => "test" })
        end
      end
    end

    describe "#subscribe" do
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
        # subscribe() now blocks until the server confirms the subscription
        allow(mock_stream).to receive(:read).and_return('{"type":"confirm_subscription"}')
      end

      # ActionCable derives `params` (which the server uses for
      # authenticate_subscription!) from the channel identifier JSON, NOT from
      # the `data` field. Putting the token in `data` silently broke every CLI
      # subscription — see commit 8cabbb341.
      it "puts the token inside the identifier so server params[:token] resolves" do
        written = nil
        expect(mock_stream).to receive(:write) { |msg| written = msg }
        api.subscribe
        outer = JSON.parse(written)
        expect(outer["command"]).to eq("subscribe")
        expect(outer).not_to have_key("data")
        identifier = JSON.parse(outer["identifier"])
        expect(identifier["channel"]).to eq("TestChannel")
        expect(identifier["token"]).to eq("test_token")
      end

      it "does not send a second subscribe once already subscribed" do
        expect(mock_stream).to receive(:write).once
        api.subscribe
        api.subscribe
      end

      # Regression: write_action must subscribe (which injects the token into the
      # identifier) BEFORE serializing the identifier, so the message command's
      # identifier matches the subscription's. Otherwise ActionCable silently
      # ignores the action and no data ever streams.
      it "includes the token in the action identifier so it matches the subscription" do
        writes = []
        allow(mock_stream).to receive(:write) { |msg| writes << msg }
        api.write_action({ 'action' => 'add' })
        message = writes.map { |w| JSON.parse(w) }.find { |f| f['command'] == 'message' }
        identifier = JSON.parse(message['identifier'])
        expect(identifier['token']).to eq('test_token')
      end
    end
  end

  describe RunningScriptWebSocketApi do
    # The tail protocol: live script events only flow once the client performs
    # the 'tail' channel action (see RunningScriptChannel#tail). subscribe()
    # blocks until confirm_subscription, so sending 'tail' immediately after
    # guarantees the gateway has registered the stream and the arm cannot race
    # a broadcast.
    describe "#subscribe" do
      let(:api) do
        RunningScriptWebSocketApi.new(
          id: "spec-script-1",
          url: "ws://test.com/script-api/cable",
          authentication: double("auth", token: "test_token")
        )
      end

      let(:mock_stream) { double("stream") }
      let(:writes) { [] }
      let(:frames) { writes.map { |w| JSON.parse(w) } }

      before do
        api.instance_variable_set(:@stream, mock_stream)
        allow(mock_stream).to receive(:read).and_return('{"type":"confirm_subscription"}')
        allow(mock_stream).to receive(:write) { |msg| writes << msg }
      end

      it "arms the tail exactly once, after the subscription is confirmed" do
        api.subscribe
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message'])
        tail = frames.last
        expect(JSON.parse(tail['data'])).to eq({ 'action' => 'tail' })
      end

      it "sends the tail action with the subscription's identifier" do
        api.subscribe
        subscribe_identifier = frames.first['identifier']
        tail_identifier = frames.last['identifier']
        # Must match exactly: ActionCable routes 'message' commands to a
        # subscription by comparing the raw identifier string
        expect(tail_identifier).to eq(subscribe_identifier)
        identifier = JSON.parse(tail_identifier)
        expect(identifier['channel']).to eq('RunningScriptChannel')
        expect(identifier['id']).to eq('spec-script-1')
        expect(identifier['token']).to eq('test_token')
      end

      it "does not re-send tail on subsequent subscribes" do
        api.subscribe
        api.subscribe
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message'])
      end

      # write_action calls subscribe() internally, which on the first call is
      # the overridden subscribe that itself calls write_action for tail. Prove
      # this does not recurse or duplicate frames and preserves ordering.
      it "orders frames subscribe, tail, action when an action triggers the first subscribe" do
        api.write_action({ 'action' => 'other' })
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message', 'message'])
        expect(JSON.parse(frames[1]['data'])).to eq({ 'action' => 'tail' })
        expect(JSON.parse(frames[2]['data'])).to eq({ 'action' => 'other' })
      end

      it "re-arms the tail after an unsubscribe/resubscribe cycle" do
        api.subscribe
        # unsubscribe writes its own frame and clears @subscribed
        api.unsubscribe
        api.subscribe
        commands = frames.map { |f| f['command'] }
        expect(commands).to eq(['subscribe', 'message', 'unsubscribe', 'subscribe', 'message'])
        expect(JSON.parse(frames.last['data'])).to eq({ 'action' => 'tail' })
      end
    end
  end
end
