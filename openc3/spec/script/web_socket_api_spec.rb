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
require 'openc3/script/exceptions'

# Stands in for the real TCP/WebSocket connection only -- everything above the
# socket (framing, subscription protocol, JSON) is exercised for real. Records
# what was written and replays a queued script of server frames.
class FakeWebSocketStream
  attr_accessor :headers
  attr_reader :writes, :init_args, :connect_count, :disconnect_count

  def initialize(*init_args)
    @init_args = init_args
    @reads = []
    @writes = []
    @connect_count = 0
    @disconnect_count = 0
    @connected = false
  end

  # Queue frames the "server" will return from read, in order
  def queue_read(*messages)
    @reads.concat(messages)
    self
  end

  def connect
    @connect_count += 1
    @connected = true
  end

  def connected?
    @connected
  end

  def disconnect
    @disconnect_count += 1
    @connected = false
  end

  # Returns nil once the queue drains, which the API treats as end-of-stream
  def read
    @reads.shift
  end

  def write(data)
    @writes << data
  end

  # The frames this client sent, parsed
  def frames
    @writes.map { |w| JSON.parse(w) }
  end
end

module OpenC3
  # Set the given environment variables for the duration of the block,
  # restoring the previous values (including "not set") afterwards.
  # A nil value means "ensure this variable is unset".
  def self.spec_with_env(vars)
    saved = {}
    vars.each do |key, value|
      saved[key] = ENV.key?(key) ? ENV[key] : :__unset__
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    saved.each do |key, value|
      if value == :__unset__
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

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

    describe "#initialize" do
      let(:auth) { double("auth", token: "test_token") }

      it "falls back to OPENC3_SCOPE when no scope is given" do
        OpenC3.spec_with_env('OPENC3_SCOPE' => 'OTHER') do
          api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth, scope: nil)
          expect(api.instance_variable_get(:@scope)).to eq('OTHER')
        end
      end

      it "falls back to DEFAULT when neither scope nor OPENC3_SCOPE is set" do
        OpenC3.spec_with_env('OPENC3_SCOPE' => nil) do
          api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth, scope: nil)
          expect(api.instance_variable_get(:@scope)).to eq('DEFAULT')
        end
      end

      it "stores the timeouts for the stream" do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth,
                               write_timeout: 1.0, read_timeout: 2.0, connect_timeout: 3.0)
        expect(api.instance_variable_get(:@write_timeout)).to eq(1.0)
        expect(api.instance_variable_get(:@read_timeout)).to eq(2.0)
        expect(api.instance_variable_get(:@connect_timeout)).to eq(3.0)
        expect(api.instance_variable_get(:@subscribed)).to be false
      end

      context "when given a block" do
        let(:stream) { FakeWebSocketStream.new }

        before do
          allow(WebSocketClientStream).to receive(:new).and_return(stream)
        end

        it "connects, yields itself, then disconnects" do
          yielded = nil
          WebSocketApi.new(url: "ws://test.com/cable", authentication: auth) do |api|
            yielded = api
            expect(stream.connect_count).to eq(1)
            expect(api.connected?).to be true
          end
          expect(yielded).to be_a(WebSocketApi)
          expect(stream.disconnect_count).to eq(1)
        end

        # Guarantees a raising consumer block cannot leak the socket
        it "disconnects even when the block raises" do
          expect {
            WebSocketApi.new(url: "ws://test.com/cable", authentication: auth) do |_api|
              raise "boom"
            end
          }.to raise_error("boom")
          expect(stream.disconnect_count).to eq(1)
        end
      end
    end

    describe "#connect" do
      let(:auth) { double("auth", token: "test_token") }
      let(:stream) { FakeWebSocketStream.new }

      before do
        allow(WebSocketClientStream).to receive(:new) do |*args|
          stream.instance_variable_set(:@init_args, args)
          stream
        end
      end

      it "appends the scope query param and passes the timeouts to the stream" do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth, scope: 'OTHER',
                               write_timeout: 1.0, read_timeout: 2.0, connect_timeout: 3.0)
        api.connect
        expect(stream.init_args).to eq(["ws://test.com/cable?scope=OTHER", 1.0, 2.0, 3.0])
        expect(stream.connect_count).to eq(1)
      end

      # The server negotiates the ActionCable JSON subprotocol from this header;
      # without it anycable-go refuses the upgrade.
      it "sets the actioncable subprotocol and user agent headers" do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth)
        api.connect
        expect(stream.headers['Sec-WebSocket-Protocol']).to eq('actioncable-v1-json, actioncable-unsupported')
        expect(stream.headers['User-Agent']).to eq(WebSocketApi::USER_AGENT)
      end

      it "disconnects an existing connection before reconnecting" do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: auth)
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api.connect
        api.connect
        expect(stream.connect_count).to eq(2)
        expect(stream.disconnect_count).to eq(1)
      end
    end

    describe "#connected?" do
      let(:api) { WebSocketApi.new(url: "ws://test.com/cable", authentication: double("auth", token: "t")) }

      it "is false before a stream exists" do
        expect(api.connected?).to be false
      end

      it "delegates to the stream once connected" do
        stream = FakeWebSocketStream.new
        api.instance_variable_set(:@stream, stream)
        expect(api.connected?).to be false
        stream.connect
        expect(api.connected?).to be true
      end
    end

    describe "#disconnect" do
      let(:api) do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: double("auth", token: "test_token"))
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api
      end
      let(:stream) { FakeWebSocketStream.new }

      before do
        api.instance_variable_set(:@stream, stream)
      end

      it "does nothing when not connected" do
        api.disconnect
        expect(stream.disconnect_count).to eq(0)
      end

      it "sends unsubscribe before closing the stream" do
        stream.connect
        stream.queue_read('{"type":"confirm_subscription"}')
        api.subscribe
        api.disconnect
        expect(stream.frames.map { |f| f['command'] }).to eq(['subscribe', 'unsubscribe'])
        expect(stream.disconnect_count).to eq(1)
        expect(api.instance_variable_get(:@subscribed)).to be false
      end

      # A half-closed socket makes the courtesy unsubscribe fail; the close
      # itself must still happen or the fd leaks.
      it "still closes the stream when unsubscribe raises" do
        stream.connect
        api.instance_variable_set(:@subscribed, true)
        allow(stream).to receive(:write).and_raise(IOError, "closed stream")
        expect { api.disconnect }.not_to raise_error
        expect(stream.disconnect_count).to eq(1)
      end
    end

    describe "#unsubscribe" do
      let(:api) do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: double("auth", token: "test_token"))
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api
      end
      let(:stream) { FakeWebSocketStream.new }

      before do
        api.instance_variable_set(:@stream, stream)
      end

      it "writes nothing when never subscribed" do
        api.unsubscribe
        expect(stream.writes).to be_empty
      end

      it "writes nothing on a second unsubscribe" do
        stream.queue_read('{"type":"confirm_subscription"}')
        api.subscribe
        api.unsubscribe
        api.unsubscribe
        expect(stream.frames.count { |f| f['command'] == 'unsubscribe' }).to eq(1)
      end
    end

    describe "#wait_for_subscribed" do
      let(:api) do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: double("auth", token: "test_token"))
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api
      end
      let(:stream) { FakeWebSocketStream.new }

      before do
        api.instance_variable_set(:@stream, stream)
      end

      it "returns once confirm_subscription arrives, skipping welcome and ping" do
        stream.queue_read('{"type":"welcome"}', '{"type":"ping"}', '{"type":"confirm_subscription"}')
        expect { api.subscribe }.not_to raise_error
        expect(api.instance_variable_get(:@subscribed)).to be true
      end

      it "raises on reject_subscription" do
        stream.queue_read('{"type":"reject_subscription"}')
        expect { api.subscribe }.to raise_error("Subscription Rejected")
      end

      it "raises on an unauthorized disconnect" do
        stream.queue_read('{"type":"disconnect","reason":"unauthorized"}')
        expect { api.subscribe }.to raise_error("Unauthorized")
      end

      # A server-initiated disconnect for any other reason is not fatal here --
      # keep waiting rather than mistaking it for an auth failure.
      it "keeps waiting on a disconnect for another reason" do
        stream.queue_read('{"type":"disconnect","reason":"server_restart"}', '{"type":"confirm_subscription"}')
        expect { api.subscribe }.not_to raise_error
      end

      # Otherwise the client blocks forever reading nil from a dead socket
      it "raises when the socket closes before confirmation" do
        stream.queue_read('{"type":"welcome"}')
        expect { api.subscribe }.to raise_error("WebSocket closed before subscription was confirmed")
      end

      it "raises when the socket returns an empty frame before confirmation" do
        stream.queue_read('')
        expect { api.subscribe }.to raise_error("WebSocket closed before subscription was confirmed")
      end
    end

    describe "#read cooperative stop" do
      let(:api) do
        api = WebSocketApi.new(url: "ws://test.com/cable", authentication: double("auth", token: "test_token"))
        api.instance_variable_set(:@identifier, { "channel" => "TestChannel" })
        api.instance_variable_set(:@subscribed, true)
        api
      end
      let(:stream) { FakeWebSocketStream.new }

      before do
        api.instance_variable_set(:@stream, stream)
        # Script Runner defines RunningScript at the top level, but
        # api_shared_spec leaks an OpenC3::RunningScript that would otherwise
        # win lexical lookup inside module OpenC3 and shadow the stub below.
        hide_const('OpenC3::RunningScript')
      end

      # Inside Script Runner a blocking read on a quiet channel must still honor
      # the user pressing Stop, hence the check on every protocol message.
      it "raises StopScript while idling on protocol messages when the script is stopping" do
        stub_const('RunningScript', double("RunningScript", instance: double("instance", stop?: true)))
        stream.queue_read('{"type":"ping"}')
        expect { api.read }.to raise_error(StopScript)
      end

      it "keeps reading when the script is not stopping" do
        stub_const('RunningScript', double("RunningScript", instance: double("instance", stop?: false)))
        stream.queue_read('{"type":"ping"}', '{"message":{"data":"payload"}}')
        expect(api.read).to eq({ "data" => "payload" })
      end

      it "does not check for stop when there is no running script instance" do
        stub_const('RunningScript', double("RunningScript", instance: nil))
        stream.queue_read('{"type":"ping"}', '{"message":{"data":"payload"}}')
        expect(api.read).to eq({ "data" => "payload" })
      end
    end

    describe "#generate_auth" do
      # allocate avoids running initialize so we test the auth selection alone
      let(:api) { WebSocketApi.allocate }

      it "uses password authentication when only OPENC3_API_PASSWORD is set" do
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => 'password') do
          # Real OpenC3Authentication.new performs an HTTP token request
          expect(OpenC3Authentication).to receive(:new).and_return(:core_auth)
          expect(api.generate_auth).to eq(:core_auth)
        end
      end

      it "raises when no authentication environment variables are set" do
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => nil) do
          expect { api.generate_auth }.to raise_error("Environment Variables Not Set for Authentication")
        end
      end

      it "uses keycloak authentication when OPENC3_API_TOKEN is set" do
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => 'token', 'OPENC3_API_USER' => nil,
                             'OPENC3_KEYCLOAK_URL' => 'http://keycloak:8080') do
          auth = api.generate_auth
          expect(auth).to be_a(OpenC3KeycloakAuthentication)
          expect(auth.instance_variable_get(:@url)).to eq('http://keycloak:8080')
        end
      end

      it "uses keycloak authentication when OPENC3_API_USER is set" do
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => 'user',
                             'OPENC3_KEYCLOAK_URL' => 'http://keycloak:8080') do
          expect(api.generate_auth).to be_a(OpenC3KeycloakAuthentication)
        end
      end

      it "is used automatically when no authentication is passed" do
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => 'token', 'OPENC3_API_USER' => nil,
                             'OPENC3_KEYCLOAK_URL' => 'http://keycloak:8080') do
          api = WebSocketApi.new(url: "ws://test.com/cable")
          expect(api.instance_variable_get(:@authentication)).to be_a(OpenC3KeycloakAuthentication)
        end
      end
    end
  end

  describe RunningScriptWebSocketApi do
    # The ready protocol: live script events only flow once the client performs
    # the 'ready' channel action (see RunningScriptChannel#ready). subscribe()
    # blocks until confirm_subscription, so sending 'ready' immediately after
    # guarantees the gateway has registered the stream and the client cannot
    # report ready in a way that races a broadcast.
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

      it "reports ready to stream events exactly once, after the subscription is confirmed" do
        api.subscribe
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message'])
        ready = frames.last
        expect(JSON.parse(ready['data'])).to eq({ 'action' => 'ready' })
      end

      it "sends the ready action with the subscription's identifier" do
        api.subscribe
        subscribe_identifier = frames.first['identifier']
        ready_identifier = frames.last['identifier']
        # Must match exactly: ActionCable routes 'message' commands to a
        # subscription by comparing the raw identifier string
        expect(ready_identifier).to eq(subscribe_identifier)
        identifier = JSON.parse(ready_identifier)
        expect(identifier['channel']).to eq('RunningScriptChannel')
        expect(identifier['id']).to eq('spec-script-1')
        expect(identifier['token']).to eq('test_token')
      end

      it "does not re-send ready on subsequent subscribes" do
        api.subscribe
        api.subscribe
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message'])
      end

      # write_action calls subscribe() internally, which on the first call is
      # the overridden subscribe that itself calls write_action for ready. Prove
      # this does not recurse or duplicate frames and preserves ordering.
      it "orders frames subscribe, ready, action when an action triggers the first subscribe" do
        api.write_action({ 'action' => 'other' })
        expect(frames.map { |f| f['command'] }).to eq(['subscribe', 'message', 'message'])
        expect(JSON.parse(frames[1]['data'])).to eq({ 'action' => 'ready' })
        expect(JSON.parse(frames[2]['data'])).to eq({ 'action' => 'other' })
      end

      it "reports ready again after an unsubscribe/resubscribe cycle" do
        api.subscribe
        # unsubscribe writes its own frame and clears @subscribed
        api.unsubscribe
        api.subscribe
        commands = frames.map { |f| f['command'] }
        expect(commands).to eq(['subscribe', 'message', 'unsubscribe', 'subscribe', 'message'])
        expect(JSON.parse(frames.last['data'])).to eq({ 'action' => 'ready' })
      end
    end
  end

  describe CmdTlmWebSocketApi do
    describe "#generate_url" do
      # allocate keeps this to pure URL construction with no auth/connect
      let(:api) { CmdTlmWebSocketApi.allocate }
      let(:cleared) do
        { 'OPENC3_API_SCHEMA' => nil, 'OPENC3_API_HOSTNAME' => nil, 'OPENC3_API_CABLE_PORT' => nil,
          'OPENC3_API_PORT' => nil, 'OPENC3_DEVEL' => nil }
      end

      it "defaults to the in-cluster service name and cable port" do
        OpenC3.spec_with_env(cleared) do
          expect(api.generate_url).to eq('http://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable')
        end
      end

      # Outside the cluster the service DNS name does not resolve
      it "uses localhost when OPENC3_DEVEL is set" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_DEVEL' => '../openc3')) do
          expect(api.generate_url).to eq('http://127.0.0.1:3901/openc3-api/cable')
        end
      end

      it "prefers an explicit hostname over the OPENC3_DEVEL default" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_DEVEL' => '../openc3', 'OPENC3_API_HOSTNAME' => 'example.com')) do
          expect(api.generate_url).to eq('http://example.com:3901/openc3-api/cable')
        end
      end

      it "honors the schema override" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_API_SCHEMA' => 'https')) do
          expect(api.generate_url).to eq('https://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable')
        end
      end

      it "falls back to OPENC3_API_PORT when no cable port is set" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_API_PORT' => '2900')) do
          expect(api.generate_url).to eq('http://openc3-cosmos-cmd-tlm-api:2900/openc3-api/cable')
        end
      end

      # Cable traffic can be routed to a different port than the REST API
      it "prefers OPENC3_API_CABLE_PORT over OPENC3_API_PORT" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_API_PORT' => '2900', 'OPENC3_API_CABLE_PORT' => '3901')) do
          expect(api.generate_url).to eq('http://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable')
        end
      end
    end

    it "generates its url when none is given" do
      OpenC3.spec_with_env('OPENC3_API_HOSTNAME' => 'example.com', 'OPENC3_API_CABLE_PORT' => '1234',
                           'OPENC3_API_SCHEMA' => nil, 'OPENC3_DEVEL' => nil) do
        api = CmdTlmWebSocketApi.new(authentication: double("auth", token: "t"))
        expect(api.instance_variable_get(:@url)).to eq('http://example.com:1234/openc3-api/cable')
      end
    end

    it "uses an explicitly passed url unchanged" do
      api = CmdTlmWebSocketApi.new(url: 'http://given:1/cable', authentication: double("auth", token: "t"))
      expect(api.instance_variable_get(:@url)).to eq('http://given:1/cable')
    end
  end

  describe ScriptWebSocketApi do
    describe "#generate_url" do
      let(:api) { ScriptWebSocketApi.allocate }
      let(:cleared) do
        { 'OPENC3_SCRIPT_API_SCHEMA' => nil, 'OPENC3_SCRIPT_API_HOSTNAME' => nil,
          'OPENC3_SCRIPT_API_CABLE_PORT' => nil, 'OPENC3_SCRIPT_API_PORT' => nil, 'OPENC3_DEVEL' => nil }
      end

      it "defaults to the in-cluster script runner service and cable port" do
        OpenC3.spec_with_env(cleared) do
          expect(api.generate_url).to eq('http://openc3-cosmos-script-runner-api:3902/script-api/cable')
        end
      end

      it "uses localhost when OPENC3_DEVEL is set" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_DEVEL' => '../openc3')) do
          expect(api.generate_url).to eq('http://127.0.0.1:3902/script-api/cable')
        end
      end

      it "prefers an explicit hostname over the OPENC3_DEVEL default" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_DEVEL' => '../openc3', 'OPENC3_SCRIPT_API_HOSTNAME' => 'example.com')) do
          expect(api.generate_url).to eq('http://example.com:3902/script-api/cable')
        end
      end

      it "honors the schema override" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_SCRIPT_API_SCHEMA' => 'https')) do
          expect(api.generate_url).to eq('https://openc3-cosmos-script-runner-api:3902/script-api/cable')
        end
      end

      it "falls back to OPENC3_SCRIPT_API_PORT when no cable port is set" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_SCRIPT_API_PORT' => '2900')) do
          expect(api.generate_url).to eq('http://openc3-cosmos-script-runner-api:2900/script-api/cable')
        end
      end

      it "prefers OPENC3_SCRIPT_API_CABLE_PORT over OPENC3_SCRIPT_API_PORT" do
        OpenC3.spec_with_env(cleared.merge('OPENC3_SCRIPT_API_PORT' => '2900', 'OPENC3_SCRIPT_API_CABLE_PORT' => '3902')) do
          expect(api.generate_url).to eq('http://openc3-cosmos-script-runner-api:3902/script-api/cable')
        end
      end
    end

    it "generates its url when none is given" do
      OpenC3.spec_with_env('OPENC3_SCRIPT_API_HOSTNAME' => 'example.com', 'OPENC3_SCRIPT_API_CABLE_PORT' => '1234',
                           'OPENC3_SCRIPT_API_SCHEMA' => nil, 'OPENC3_DEVEL' => nil) do
        api = ScriptWebSocketApi.new(authentication: double("auth", token: "t"))
        expect(api.instance_variable_get(:@url)).to eq('http://example.com:1234/script-api/cable')
      end
    end
  end

  # The channel name in the identifier is what routes the subscription on the
  # server, so a typo here silently yields a rejected or dead subscription.
  describe "channel identifiers" do
    let(:auth) { double("auth", token: "test_token") }

    {
      AutonomicEventsWebSocketApi => 'AutonomicEventsChannel',
      CalendarEventsWebSocketApi => 'CalendarEventsChannel',
      ConfigEventsWebSocketApi => 'ConfigEventsChannel',
      LimitsEventsWebSocketApi => 'LimitsEventsChannel',
      SystemEventsWebSocketApi => 'SystemEventsChannel',
      TimelineEventsWebSocketApi => 'TimelineEventsChannel',
      QueueEventsWebSocketApi => 'QueueEventsChannel',
    }.each do |klass, channel|
      describe klass do
        it "subscribes to #{channel} with a default history_count of 0" do
          api = klass.new(url: 'http://test.com/cable', authentication: auth)
          expect(api.instance_variable_get(:@identifier)).to eq({ channel: channel, history_count: 0 })
        end

        it "passes history_count through" do
          api = klass.new(history_count: 100, url: 'http://test.com/cable', authentication: auth)
          expect(api.instance_variable_get(:@identifier)[:history_count]).to eq(100)
        end

        it "is a cmd-tlm-api websocket" do
          expect(klass.ancestors).to include(CmdTlmWebSocketApi)
        end
      end
    end

    describe AllScriptsWebSocketApi do
      it "subscribes to AllScriptsChannel" do
        api = AllScriptsWebSocketApi.new(url: 'http://test.com/cable', authentication: auth)
        expect(api.instance_variable_get(:@identifier)).to eq({ channel: 'AllScriptsChannel' })
        expect(AllScriptsWebSocketApi.ancestors).to include(ScriptWebSocketApi)
      end
    end

    describe RunningScriptWebSocketApi do
      it "subscribes to RunningScriptChannel for a specific script id" do
        api = RunningScriptWebSocketApi.new(id: 42, url: 'http://test.com/cable', authentication: auth)
        expect(api.instance_variable_get(:@identifier)).to eq({ channel: 'RunningScriptChannel', id: 42 })
        expect(RunningScriptWebSocketApi.ancestors).to include(ScriptWebSocketApi)
      end
    end

    describe MessagesWebSocketApi do
      it "omits the optional filters when they are not given" do
        api = MessagesWebSocketApi.new(url: 'http://test.com/cable', authentication: auth)
        expect(api.instance_variable_get(:@identifier)).to eq({ channel: 'MessagesChannel', history_count: 0 })
      end

      it "includes each filter that is given" do
        api = MessagesWebSocketApi.new(history_count: 10, start_time: 1, end_time: 2, level: 'INFO',
                                       types: ['LOG'], url: 'http://test.com/cable', authentication: auth)
        expect(api.instance_variable_get(:@identifier)).to eq({
          channel: 'MessagesChannel',
          history_count: 10,
          'start_time' => 1,
          'end_time' => 2,
          'level' => 'INFO',
          'types' => ['LOG'],
        })
      end
    end
  end

  describe StreamingWebSocketApi do
    let(:auth) { double("auth", token: "test_token") }
    let(:stream) { FakeWebSocketStream.new }
    let(:api) do
      api = StreamingWebSocketApi.new(url: 'http://test.com/cable', authentication: auth, scope: 'DEFAULT')
      api.instance_variable_set(:@stream, stream)
      api
    end

    # The action data hash, i.e. what StreamingChannel#add / #remove receives
    def action_data
      messages = stream.frames.select { |f| f['command'] == 'message' }
      messages.map { |f| JSON.parse(f['data']) }
    end

    before do
      stream.queue_read('{"type":"confirm_subscription"}')
    end

    it "subscribes to StreamingChannel" do
      expect(api.instance_variable_get(:@identifier)).to eq({ channel: 'StreamingChannel' })
    end

    describe "#add" do
      it "sends the add action with items, scope and token" do
        api.add(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'])
        expect(action_data).to eq([{
          'action' => 'add',
          'items' => ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
          'scope' => 'DEFAULT',
          'token' => 'test_token',
        }])
      end

      it "sends packets when given" do
        api.add(packets: ['DECOM__TLM__INST__HEALTH_STATUS__CONVERTED'])
        expect(action_data.first['packets']).to eq(['DECOM__TLM__INST__HEALTH_STATUS__CONVERTED'])
        expect(action_data.first).not_to have_key('items')
      end

      it "omits items and packets when neither is given (realtime all)" do
        api.add
        expect(action_data.first.keys).to eq(['action', 'scope', 'token'])
      end

      # The channel expects 64-bit nanoseconds from the epoch, not a Time
      it "converts Time start_time and end_time to nanoseconds" do
        start_time = Time.new(2026, 1, 1, 0, 0, 0, "+00:00")
        end_time = Time.new(2026, 1, 2, 0, 0, 0, "+00:00")
        api.add(items: ['ITEM'], start_time: start_time, end_time: end_time)
        expect(action_data.first['start_time']).to eq(start_time.to_nsec_from_epoch)
        expect(action_data.first['end_time']).to eq(end_time.to_nsec_from_epoch)
      end

      it "passes integer nanosecond times through unchanged" do
        api.add(items: ['ITEM'], start_time: 1_000_000_000, end_time: 2_000_000_000)
        expect(action_data.first['start_time']).to eq(1_000_000_000)
        expect(action_data.first['end_time']).to eq(2_000_000_000)
      end

      it "omits the times when not given so the stream is realtime and endless" do
        api.add(items: ['ITEM'])
        expect(action_data.first).not_to have_key('start_time')
        expect(action_data.first).not_to have_key('end_time')
      end

      it "allows overriding the scope per action" do
        api.add(items: ['ITEM'], scope: 'OTHER')
        expect(action_data.first['scope']).to eq('OTHER')
      end

      it "subscribes before sending the action" do
        api.add(items: ['ITEM'])
        expect(stream.frames.map { |f| f['command'] }).to eq(['subscribe', 'message'])
      end
    end

    describe "#remove" do
      it "sends the remove action with items, scope and token" do
        api.remove(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'])
        expect(action_data).to eq([{
          'action' => 'remove',
          'items' => ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
          'scope' => 'DEFAULT',
          'token' => 'test_token',
        }])
      end

      it "sends packets when given" do
        api.remove(packets: ['DECOM__TLM__INST__HEALTH_STATUS__CONVERTED'])
        expect(action_data.first['packets']).to eq(['DECOM__TLM__INST__HEALTH_STATUS__CONVERTED'])
        expect(action_data.first).not_to have_key('items')
      end

      it "allows overriding the scope per action" do
        api.remove(items: ['ITEM'], scope: 'OTHER')
        expect(action_data.first['scope']).to eq('OTHER')
      end
    end

    describe ".read_all" do
      let(:stream) { FakeWebSocketStream.new }

      before do
        allow(WebSocketClientStream).to receive(:new).and_return(stream)
        # read_all takes no authentication argument, so generate_auth runs;
        # stub only the network-touching constructor
        allow(OpenC3Authentication).to receive(:new).and_return(double("auth", token: "test_token"))
      end

      # An empty batch is the end marker the streaming channel sends when the
      # requested time range is exhausted
      it "concatenates batches until an empty batch ends the stream" do
        stream.queue_read(
          '{"type":"confirm_subscription"}',
          '{"message":[{"__time":1},{"__time":2}]}',
          '{"message":[{"__time":3}]}',
          '{"message":[]}',
          '{"message":[{"__time":4}]}' # must never be read
        )
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => 'password') do
          data = StreamingWebSocketApi.read_all(items: ['ITEM'], end_time: 2_000_000_000)
          expect(data).to eq([{ "__time" => 1 }, { "__time" => 2 }, { "__time" => 3 }])
        end
      end

      it "sends the add action for the requested range" do
        stream.queue_read('{"type":"confirm_subscription"}', '{"message":[]}')
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => 'password') do
          StreamingWebSocketApi.read_all(items: ['ITEM'], start_time: 1, end_time: 2, scope: 'OTHER')
        end
        data = stream.frames.select { |f| f['command'] == 'message' }.map { |f| JSON.parse(f['data']) }
        expect(data.first).to include('action' => 'add', 'items' => ['ITEM'],
                                      'start_time' => 1, 'end_time' => 2, 'scope' => 'OTHER')
      end

      # Guards against blocking forever on a stream whose end marker never comes
      it "returns the data collected so far once the timeout elapses" do
        stream.queue_read(
          '{"type":"confirm_subscription"}',
          '{"message":[{"__time":1}]}',
          '{"message":[{"__time":2}]}'
        )
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => 'password') do
          data = StreamingWebSocketApi.read_all(items: ['ITEM'], end_time: 2_000_000_000, timeout: 0.0)
          expect(data).to eq([{ "__time" => 1 }])
        end
      end

      it "disconnects the stream when done" do
        stream.queue_read('{"type":"confirm_subscription"}', '{"message":[]}')
        OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                             'OPENC3_API_PASSWORD' => 'password') do
          StreamingWebSocketApi.read_all(items: ['ITEM'], end_time: 2_000_000_000)
        end
        expect(stream.disconnect_count).to eq(1)
      end
    end
  end
end
