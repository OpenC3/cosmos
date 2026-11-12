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

require "spec_helper"
require "openc3/utilities/authentication"

module OpenC3
  describe OpenC3Authentication do
    describe "initialize" do
      it "raises an error if OPENC3_API_PASSWORD is not set" do
        old_password = ENV.fetch('OPENC3_API_PASSWORD', nil)
        ENV.delete('OPENC3_API_PASSWORD')
        expect { OpenC3Authentication.new }.to raise_error(OpenC3AuthenticationError, /Authentication requires environment variable/)
        ENV['OPENC3_API_PASSWORD'] = old_password
      end

      it "initializes with OPENC3_API_PASSWORD" do
        ENV['OPENC3_API_PASSWORD'] = 'test_password'
        auth = OpenC3Authentication.new
        expect(auth.token).to eq($openc3_mock_token)
        expect(auth.get_otp).to eq($openc3_mock_otp)
      end

      it "retries on Faraday::ConnectionFailed" do
        ENV['OPENC3_API_PASSWORD'] = 'test_password'
        call_count = 0
        mock_response = Object.new
        mock_response.define_singleton_method(:body) { 'retry_token' }
        allow_any_instance_of(OpenC3Authentication).to receive(:_make_auth_request) do
          call_count += 1
          if call_count < 3
            raise Faraday::ConnectionFailed, "Hostname not known"
          end
          mock_response
        end
        allow_any_instance_of(OpenC3Authentication).to receive(:sleep)
        auth = OpenC3Authentication.new
        expect(auth.token).to eq('retry_token')
        expect(call_count).to eq(3)
      end

      it "raises after exhausting retries" do
        ENV['OPENC3_API_PASSWORD'] = 'test_password'
        allow_any_instance_of(OpenC3Authentication).to receive(:_make_auth_request).and_raise(Faraday::ConnectionFailed, "Hostname not known")
        allow_any_instance_of(OpenC3Authentication).to receive(:sleep)
        expect { OpenC3Authentication.new }.to raise_error(Faraday::ConnectionFailed)
      end
    end
  end

  describe '.authentication_from_environment' do
    it 'selects core authentication for password-only configuration' do
      OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                           'OPENC3_API_CLIENT_SECRET' => nil, 'OPENC3_API_PASSWORD' => 'password') do
        expect(OpenC3Authentication).to receive(:new).and_return(:core_auth)
        expect(OpenC3.authentication_from_environment).to eq(:core_auth)
      end
    end

    it 'selects Keycloak authentication for a client secret' do
      OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                           'OPENC3_API_CLIENT_SECRET' => 'm2m_secret', 'OPENC3_KEYCLOAK_URL' => 'http://keycloak') do
        expect(OpenC3KeycloakAuthentication).to receive(:new).with('http://keycloak').and_return(:keycloak_auth)
        expect(OpenC3.authentication_from_environment).to eq(:keycloak_auth)
      end
    end

    it 'treats an empty client secret as unset' do
      OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                           'OPENC3_API_CLIENT_SECRET' => '', 'OPENC3_API_PASSWORD' => 'password') do
        expect(OpenC3Authentication).to receive(:new).and_return(:core_auth)
        expect(OpenC3KeycloakAuthentication).not_to receive(:new)
        expect(OpenC3.authentication_from_environment).to eq(:core_auth)
      end
    end

    it 'returns nil without authentication configuration' do
      OpenC3.spec_with_env('OPENC3_API_TOKEN' => nil, 'OPENC3_API_USER' => nil,
                           'OPENC3_API_CLIENT_SECRET' => nil, 'OPENC3_API_PASSWORD' => nil) do
        expect(OpenC3.authentication_from_environment).to be_nil
      end
    end
  end

  describe OpenC3KeycloakAuthentication do
    let(:test_url) { "http://test-keycloak.local" }
    let(:mock_http) { instance_double(Faraday::Connection) }
    let(:mock_builder) { instance_double(Faraday::RackBuilder) }

    before(:each) do
      ENV['OPENC3_API_USER'] = 'testuser'
      ENV['OPENC3_API_PASSWORD'] = 'testpassword'
      ENV['OPENC3_KEYCLOAK_REALM'] = 'openc3'
      allow(Faraday).to receive(:new).and_return(mock_http)
    end

    after(:each) do
      ENV.delete('OPENC3_API_USER')
      ENV.delete('OPENC3_API_PASSWORD')
      ENV.delete('OPENC3_API_TOKEN')
      ENV.delete('OPENC3_API_CLIENT')
      ENV.delete('OPENC3_API_CLIENT_SECRET')
      ENV.delete('OPENC3_API_TIMEOUT')
      ENV.delete('OPENC3_API_READ_TIMEOUT')
      ENV.delete('OPENC3_KEYCLOAK_REALM')
    end

    def keycloak_success_response(access_token:, expires_in:, refresh_token: nil, refresh_expires_in: nil)
      body = {
        'access_token' => access_token,
        'expires_in' => expires_in,
        'token_type' => 'bearer'
      }
      body['refresh_token'] = refresh_token if refresh_token
      body['refresh_expires_in'] = refresh_expires_in if refresh_expires_in
      instance_double(Faraday::Response, status: 200, headers: {}, body: JSON.generate(body))
    end

    def keycloak_error_response(error:, status: 401)
      instance_double(Faraday::Response, status: status, headers: {}, body: JSON.generate({ 'error' => error }))
    end

    def capture_stdout
      stdout = StringIO.new('', 'r+')
      saved_stdout = $stdout
      saved_stdout_const = Object.const_get(:STDOUT)
      $stdout = stdout
      OpenC3.disable_warnings { Object.const_set(:STDOUT, stdout) }
      yield
      stdout.string
    ensure
      $stdout = saved_stdout
      OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout_const) }
    end

    def expect_redacted_field(text, field)
      expect(text).to match(/"#{field}"\s*=>\s*"\*\*\*"/)
    end

    def expect_redacted_auth_failure(auth:, response:, sensitive_field:, sensitive_value:, debug: false)
      allow(mock_http).to receive(:post).and_return(response)
      allow(JsonDRb).to receive(:debug?).and_return(debug)

      failure_check = proc do
        expect {
          auth.token
        }.to raise_error(OpenC3AuthenticationError) do |error|
          expect_redacted_field(error.message, sensitive_field)
          expect(error.message).not_to include(sensitive_value)
          yield error.message if block_given?
        end
      end

      if debug
        stdout = capture_stdout(&failure_check)
        expect_redacted_field(stdout, sensitive_field)
        expect(stdout).not_to include(sensitive_value)
      else
        failure_check.call
      end
    end

    describe "initialize" do
      it "initializes with a URL" do
        auth = OpenC3KeycloakAuthentication.new(test_url)
        expect(auth).to be_a(OpenC3KeycloakAuthentication)
      end
    end

    describe "password obfuscation in logs" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

      context "when debug mode is disabled" do
        it "obfuscates password in error messages" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_grant'),
            sensitive_field: 'password',
            sensitive_value: 'testpassword'
          ) do |message|
            expect(message).to match(/"username"\s*=>\s*"testuser"/)
            expect(message).to match(/"grant_type"\s*=>\s*"password"/)
            expect(message).to match(/"client_id"\s*=>\s*"api"/)
          end
        end

        it "obfuscates password in STDOUT logs" do
          allow(mock_http).to receive(:post).and_return(keycloak_error_response(error: 'invalid_grant'))
          allow(JsonDRb).to receive(:debug?).and_return(false)

          stdout = capture_stdout do
            expect {
              auth.token
            }.to raise_error(OpenC3AuthenticationError)
          end

          expect(stdout).not_to include('testpassword')
        end
      end

      context "when debug mode is enabled" do
        it "redacts the password in debug logs" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_grant'),
            sensitive_field: 'password',
            sensitive_value: 'testpassword',
            debug: true
          )
        end
      end

      context "with refresh token" do
        let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

        before(:each) do
          ENV.delete('OPENC3_API_USER')
          ENV.delete('OPENC3_API_PASSWORD')
          ENV['OPENC3_API_TOKEN'] = 'test_refresh_token'
        end

        it "obfuscates refresh_token in normal mode" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_grant'),
            sensitive_field: 'refresh_token',
            sensitive_value: 'test_refresh_token'
          )
        end

        it "redacts refresh_token when debug is enabled" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_grant'),
            sensitive_field: 'refresh_token',
            sensitive_value: 'test_refresh_token',
            debug: true
          )
        end
      end

      context "with client credentials" do
        let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

        before(:each) do
          ENV.delete('OPENC3_API_USER')
          ENV.delete('OPENC3_API_PASSWORD')
          ENV['OPENC3_API_CLIENT'] = 'cosmos-m2m'
          ENV['OPENC3_API_CLIENT_SECRET'] = 'm2m-secret'
        end

        it "obfuscates client_secret in normal mode" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_client'),
            sensitive_field: 'client_secret',
            sensitive_value: 'm2m-secret'
          )
        end

        it "obfuscates client_secret when debug is enabled" do
          expect_redacted_auth_failure(
            auth: auth,
            response: keycloak_error_response(error: 'invalid_client'),
            sensitive_field: 'client_secret',
            sensitive_value: 'm2m-secret',
            debug: true
          )
        end
      end
    end

    describe "successful authentication" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }
      let(:mock_success_response) do
        keycloak_success_response(
          access_token: 'access_token_123',
          expires_in: 600,
          refresh_token: 'refresh_token_123',
          refresh_expires_in: 1800
        )
      end

      before(:each) do
        allow(JsonDRb).to receive(:debug?).and_return(false)
        allow(mock_http).to receive(:post).and_return(mock_success_response)
      end

      it "returns token with Bearer prefix by default" do
        expect(auth.token).to eq("Bearer access_token_123")
      end

      it "returns token without Bearer prefix when requested" do
        expect(auth.token(include_bearer: false)).to eq("access_token_123")
      end

      it "uses client_credentials when OPENC3_API_CLIENT_SECRET is set" do
        ENV.delete('OPENC3_API_USER')
        ENV.delete('OPENC3_API_PASSWORD')
        ENV['OPENC3_API_CLIENT'] = 'cosmos-m2m'
        ENV['OPENC3_API_CLIENT_SECRET'] = 'm2m-secret'

        token = auth.token

        expect(token).to eq("Bearer access_token_123")
        expect(mock_http).to have_received(:post).with(
          an_instance_of(URI::HTTP),
          include('client_id=cosmos-m2m', 'client_secret=m2m-secret', 'grant_type=client_credentials', 'scope=openid'),
          hash_including('Content-Type' => 'application/x-www-form-urlencoded')
        )
      end

      it "treats an empty client secret as unset" do
        ENV['OPENC3_API_CLIENT_SECRET'] = ''

        token = auth.token

        expect(token).to eq("Bearer access_token_123")
        expect(mock_http).to have_received(:post).with(
          an_instance_of(URI::HTTP),
          include('username=testuser', 'password=testpassword', 'grant_type=password', 'scope=openid'),
          hash_including('Content-Type' => 'application/x-www-form-urlencoded')
        )
      end
    end

    describe "client_credentials authentication" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }
      let(:mock_success_response) do
        keycloak_success_response(access_token: 'm2m_access_token', expires_in: 300)
      end

      before(:each) do
        ENV['OPENC3_API_CLIENT_SECRET'] = 'm2m_secret'
        ENV['OPENC3_API_CLIENT'] = 'cosmos-m2m'
        allow(JsonDRb).to receive(:debug?).and_return(false)
      end

      it "uses the client_credentials grant" do
        request_body = nil
        allow(mock_http).to receive(:post) do |uri, body, headers|
          request_body = body
          expect(headers['Content-Type']).to eq('application/x-www-form-urlencoded')
          expect(uri.to_s).to eq('http://test-keycloak.local/realms/openc3/protocol/openid-connect/token')
          mock_success_response
        end

        expect(auth.token).to eq('Bearer m2m_access_token')
        expect(request_body).to include('grant_type=client_credentials')
        expect(request_body).to include('client_id=cosmos-m2m')
        expect(request_body).to include('client_secret=m2m_secret')
        expect(auth.refresh_token).to be_nil
      end

      it "prefers client_credentials over password" do
        request_body = nil
        allow(mock_http).to receive(:post) do |_uri, body, _headers, &_block|
          request_body = body
          mock_success_response
        end

        auth.token
        expect(request_body).to include('grant_type=client_credentials')
        expect(request_body).not_to include('password=')
      end

      it "obfuscates the client secret in error messages" do
        expect_redacted_auth_failure(
          auth: auth,
          response: keycloak_error_response(error: 'invalid_client'),
          sensitive_field: 'client_secret',
          sensitive_value: 'm2m_secret'
        )
      end

      it "redacts the client secret in debug logs" do
        expect_redacted_auth_failure(
          auth: auth,
          response: keycloak_error_response(error: 'invalid_client'),
          sensitive_field: 'client_secret',
          sensitive_value: 'm2m_secret',
          debug: true
        )
      end

      it "treats an empty client secret as unset" do
        ENV['OPENC3_API_CLIENT_SECRET'] = ''
        request_body = nil
        allow(mock_http).to receive(:post) do |_uri, body, _headers, &_block|
          request_body = body
          keycloak_success_response(
            access_token: 'access_token_123',
            expires_in: 600,
            refresh_token: 'refresh_token_123',
            refresh_expires_in: 1800
          )
        end

        expect(auth.token).to eq('Bearer access_token_123')
        expect(request_body).to include('grant_type=password')
        expect(request_body).not_to include('client_secret=')
      end
    end

    describe "retryable errors" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

      before(:each) do
        allow(JsonDRb).to receive(:debug?).and_return(false)
        allow(mock_http).to receive(:post).and_return(keycloak_error_response(error: 'service_unavailable', status: 503))
      end

      it "raises retryable error for 5xx status codes" do
        expect {
          auth.token
        }.to raise_error(OpenC3AuthenticationRetryableError)
      end
    end

    describe "URL encoding of special characters" do
      context "Faraday middleware verification" do
        after(:each) do
          RSpec::Mocks.space.proxy_for(Faraday).reset if RSpec::Mocks.space.proxies.any?
        end

        it "verifies Faraday URL encodes hash data" do
          RSpec::Mocks.space.proxy_for(Faraday).reset if RSpec::Mocks.space.proxies.any?

          conn = Faraday.new do |f|
            f.request :url_encoded
            f.adapter :test do |stub|
              stub.post('/test') do |env|
                [200, {}, env[:body]]
              end
            end
          end

          response = conn.post('/test', {'password' => 'my&pass=word%'})
          expect(response.body).to eq('password=my%26pass%3Dword%25')

          allow(mock_builder).to receive(:request)
          allow(Faraday).to receive(:new).and_yield(mock_builder).and_return(mock_http)
        end
      end
    end
  end
end
