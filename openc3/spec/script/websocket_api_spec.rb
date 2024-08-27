require 'rspec'
require 'webmock/rspec'
require_relative 'path/to/web_socket_api' # Adjust the path as needed

=begin
This test suite covers the main functionality of the `WebSocketApi` class. It includes tests for:

1. Initialization
2. Reading messages
3. Subscribing and unsubscribing
4. Writing actions and data
5. Connecting and disconnecting
6. Authentication generation

To run these tests, you'll need to have RSpec and WebMock installed. You may need to adjust the `require_relative` path to point to the actual location of your `web_socket_api.rb` file.

Note that this test suite uses mocks and stubs to avoid actual network connections. For more thorough testing, you might want to consider integration tests that interact with a real WebSocket server.
=end

module OpenC3
  describe WebSocketApi do
  let(:url) { 'ws://example.com/socket' }
  let(:authentication) { double('authentication', token: 'fake_token') }
  let(:scope) { 'test_scope' }

  subject(:api) do
    described_class.new(
      url: url,
      write_timeout: 5.0,
      read_timeout: 5.0,
      connect_timeout: 2.0,
      authentication: authentication,
      scope: scope
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OPENC3_API_TOKEN').and_return(nil)
    allow(ENV).to receive(:[]).with('OPENC3_API_USER').and_return(nil)
    allow(ENV).to receive(:[]).with('OPENC3_API_PASSWORD').and_return('password')
  end

  describe '#initialize' do
    it 'sets instance variables correctly' do
      expect(api.instance_variable_get(:@url)).to eq(url)
      expect(api.instance_variable_get(:@write_timeout)).to eq(5.0)
      expect(api.instance_variable_get(:@read_timeout)).to eq(5.0)
      expect(api.instance_variable_get(:@connect_timeout)).to eq(2.0)
      expect(api.instance_variable_get(:@authentication)).to eq(authentication)
      expect(api.instance_variable_get(:@scope)).to eq(scope)
    end

    it 'yields self to block if given' do
      expect { |b| described_class.new(url: url, &b) }.to yield_with_args(an_instance_of(described_class))
    end
  end

  describe '#read_message' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:subscribe)
      allow(api).to receive(:instance_variable_get).with(:@stream).and_return(stream)
    end

    it 'subscribes and reads from the stream' do
      expect(api).to receive(:subscribe)
      expect(stream).to receive(:read).and_return('message')
      expect(api.read_message).to eq('message')
    end
  end

  describe '#read' do
    let(:json_message) { { 'message' => 'test_message' }.to_json }

    before do
      allow(api).to receive(:read_message).and_return(json_message)
    end

    it 'parses JSON and returns the message' do
      expect(api.read).to eq('test_message')
    end

    it 'ignores protocol messages by default' do
      protocol_message = { 'type' => 'ping' }.to_json
      allow(api).to receive(:read_message).and_return(protocol_message, json_message)
      expect(api.read).to eq('test_message')
    end

    it 'raises an error for unauthorized messages' do
      unauthorized_message = { 'type' => 'disconnect', 'reason' => 'unauthorized' }.to_json
      allow(api).to receive(:read_message).and_return(unauthorized_message)
      expect { api.read }.to raise_error('Unauthorized')
    end

    it 'raises an error for rejected subscriptions' do
      reject_message = { 'type' => 'reject_subscription' }.to_json
      allow(api).to receive(:read_message).and_return(reject_message)
      expect { api.read }.to raise_error('Subscription Rejected')
    end
  end

  describe '#subscribe' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:instance_variable_get).with(:@stream).and_return(stream)
      allow(api).to receive(:instance_variable_get).with(:@identifier).and_return({ channel: 'test' })
    end

    it 'subscribes if not already subscribed' do
      expect(stream).to receive(:write).with(/{.*"command":"subscribe".*}/)
      api.subscribe
      expect(api.instance_variable_get(:@subscribed)).to be true
    end

    it 'does not subscribe if already subscribed' do
      api.instance_variable_set(:@subscribed, true)
      expect(stream).not_to receive(:write)
      api.subscribe
    end
  end

  describe '#unsubscribe' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:instance_variable_get).with(:@stream).and_return(stream)
      allow(api).to receive(:instance_variable_get).with(:@identifier).and_return({ channel: 'test' })
    end

    it 'unsubscribes if subscribed' do
      api.instance_variable_set(:@subscribed, true)
      expect(stream).to receive(:write).with(/{.*"command":"unsubscribe".*}/)
      api.unsubscribe
      expect(api.instance_variable_get(:@subscribed)).to be false
    end

    it 'does not unsubscribe if not subscribed' do
      expect(stream).not_to receive(:write)
      api.unsubscribe
    end
  end

  describe '#write_action' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:subscribe)
      allow(api).to receive(:instance_variable_get).with(:@stream).and_return(stream)
      allow(api).to receive(:instance_variable_get).with(:@identifier).and_return({ channel: 'test' })
    end

    it 'writes an action message' do
      expect(stream).to receive(:write).with(/{.*"command":"message".*}/)
      api.write_action({ action: 'test' })
    end
  end

  describe '#write' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:subscribe)
      allow(api).to receive(:instance_variable_get).with(:@stream).and_return(stream)
    end

    it 'subscribes and writes data to the stream' do
      expect(api).to receive(:subscribe)
      expect(stream).to receive(:write).with('test_data')
      api.write('test_data')
    end
  end

  describe '#connect' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(OpenC3::WebSocketClientStream).to receive(:new).and_return(stream)
      allow(stream).to receive(:connect)
    end

    it 'creates a new WebSocketClientStream and connects' do
      expect(OpenC3::WebSocketClientStream).to receive(:new).with(
        "#{url}?scope=#{scope}&authorization=fake_token",
        5.0, 5.0, 2.0
      ).and_return(stream)
      expect(stream).to receive(:connect)
      api.connect
    end
  end

  describe '#connected?' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    it 'returns true if connected' do
      api.instance_variable_set(:@stream, stream)
      allow(stream).to receive(:connected?).and_return(true)
      expect(api.connected?).to be true
    end

    it 'returns false if not connected' do
      expect(api.connected?).to be false
    end
  end

  describe '#disconnect' do
    let(:stream) { instance_double(OpenC3::WebSocketClientStream) }

    before do
      allow(api).to receive(:connected?).and_return(true)
      allow(api).to receive(:unsubscribe)
      api.instance_variable_set(:@stream, stream)
    end

    it 'unsubscribes and disconnects if connected' do
      expect(api).to receive(:unsubscribe)
      expect(stream).to receive(:disconnect)
      api.disconnect
    end

    it 'handles errors during unsubscribe' do
      allow(api).to receive(:unsubscribe).and_raise(StandardError)
      expect(stream).to receive(:disconnect)
      expect { api.disconnect }.not_to raise_error
    end
  end

  describe '#generate_auth' do
    context 'when OPENC3_API_TOKEN and OPENC3_API_USER are not set' do
      it 'returns OpenC3Authentication when OPENC3_API_PASSWORD is set' do
        expect(api.send(:generate_auth)).to be_an_instance_of(OpenC3::OpenC3Authentication)
      end

      it 'raises an error when OPENC3_API_PASSWORD is not set' do
        allow(ENV).to receive(:[]).with('OPENC3_API_PASSWORD').and_return(nil)
        expect { api.send(:generate_auth) }.to raise_error('Environment Variables Not Set for Authentication')
      end
    end

    context 'when OPENC3_API_TOKEN or OPENC3_API_USER is set' do
      before do
        allow(ENV).to receive(:[]).with('OPENC3_API_TOKEN').and_return('token')
        allow(ENV).to receive(:[]).with('OPENC3_KEYCLOAK_URL').and_return('http://keycloak.example.com')
      end

      it 'returns OpenC3KeycloakAuthentication' do
        expect(api.send(:generate_auth)).to be_an_instance_of(OpenC3::OpenC3KeycloakAuthentication)
      end
    end
  end
end
