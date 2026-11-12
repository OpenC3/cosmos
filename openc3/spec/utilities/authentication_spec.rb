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
        # Initialization calls a method that uses Faraday to get a token from the server.
        # It's mocked to return $openc3_mock_token for unit testing.
        expect(auth.token).to eq($openc3_mock_token)

        # Once initialized, it should be able to get an OTP as well
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

  describe OpenC3KeycloakAuthentication do
    let(:test_url) { "http://test-keycloak.local" }
    let(:mock_http) { instance_double(Faraday::Connection) }
    let(:mock_builder) { instance_double(Faraday::RackBuilder) }

    before(:each) do
      ENV['OPENC3_API_USER'] = 'testuser'
      ENV['OPENC3_API_PASSWORD'] = 'testpassword'
      ENV['OPENC3_KEYCLOAK_REALM'] = 'openc3'
      # Mock Faraday to return our mock connection
      allow(Faraday).to receive(:new).and_return(mock_http)
    end

    after(:each) do
      ENV.delete('OPENC3_API_USER')
      ENV.delete('OPENC3_API_PASSWORD')
      ENV.delete('OPENC3_API_TOKEN')
      ENV.delete('OPENC3_KEYCLOAK_REALM')
      ENV.delete('OPENC3_API_CLIENT')
      ENV.delete('OPENC3_API_CLIENT_SECRET')
    end

    describe "initialize" do
      it "initializes with a URL" do
        auth = OpenC3KeycloakAuthentication.new(test_url)
        expect(auth).to be_a(OpenC3KeycloakAuthentication)
      end
    end

    describe "password obfuscation in logs" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }
      let(:mock_response) do
        instance_double(Faraday::Response,
          status: 401,
          headers: {},
          body: '{"error":"invalid_grant"}'
        )
      end

      before(:each) do
        allow(mock_http).to receive(:post).and_return(mock_response)
      end

      context "when debug mode is disabled" do
        before(:each) do
          allow(JsonDRb).to receive(:debug?).and_return(false)
        end

        it "obfuscates password in error messages" do
          expect {
            auth.token
          }.to raise_error(OpenC3AuthenticationError) do |error|
            # Error message should contain obfuscated password (works with both Ruby 3.2 and 3.3+ inspect formats)
            expect(error.message).to match(/"password"\s*=>\s*"\*\*\*"/)
            # Error message should NOT contain actual password
            expect(error.message).not_to include('testpassword')
          end
        end

        it "obfuscates password in STDOUT logs" do
          stdout = StringIO.new('', 'r+')
          saved_stdout = $stdout
          $stdout = stdout
          saved_stdout_const = Object.const_get(:STDOUT)
          OpenC3.disable_warnings { Object.const_set(:STDOUT, stdout) }

          begin
            expect {
              auth.token
            }.to raise_error(OpenC3AuthenticationError)
          ensure
            $stdout = saved_stdout
            OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout_const) }
          end

          # STDOUT should not contain the actual password
          expect(stdout.string).not_to include('testpassword')
        end

        it "preserves other parameters in logs" do
          expect {
            auth.token
          }.to raise_error(OpenC3AuthenticationError) do |error|
            # Other parameters should still be visible (works with both Ruby 3.2 and 3.3+ inspect formats)
            expect(error.message).to match(/"username"\s*=>\s*"testuser"/)
            expect(error.message).to match(/"grant_type"\s*=>\s*"password"/)
            expect(error.message).to match(/"client_id"\s*=>\s*"api"/)
          end
        end
      end

      context "when debug mode is enabled" do
        before(:each) do
          allow(JsonDRb).to receive(:debug?).and_return(true)
        end

        it "shows actual password in error messages when debug is enabled" do
          stdout = StringIO.new('', 'r+')
          saved_stdout = $stdout
          $stdout = stdout
          saved_stdout_const = Object.const_get(:STDOUT)
          OpenC3.disable_warnings { Object.const_set(:STDOUT, stdout) }

          begin
            expect {
              auth.token
            }.to raise_error(OpenC3AuthenticationError)
          ensure
            $stdout = saved_stdout
            OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout_const) }
          end

          # In debug mode, STDOUT should contain the actual password (works with both Ruby 3.2 and 3.3+ inspect formats)
          expect(stdout.string).to match(/"password"\s*=>\s*"testpassword"/)
        end
      end

      context "with refresh token" do
        let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

        before(:each) do
          ENV.delete('OPENC3_API_USER')
          ENV.delete('OPENC3_API_PASSWORD')
          ENV['OPENC3_API_TOKEN'] = 'test_refresh_token'
          allow(JsonDRb).to receive(:debug?).and_return(false)
        end

        it "obfuscates refresh_token in normal mode" do
          expect {
            auth.token
          }.to raise_error(OpenC3AuthenticationError) do |error|
            # Refresh token should be obfuscated (works with both Ruby 3.2 and 3.3+ inspect formats)
            expect(error.message).to match(/"refresh_token"\s*=>\s*"\*\*\*"/)
            # Error message should NOT contain actual refresh token
            expect(error.message).not_to include('test_refresh_token')
          end
        end

        it "shows actual refresh_token when debug is enabled" do
          allow(JsonDRb).to receive(:debug?).and_return(true)

          stdout = StringIO.new('', 'r+')
          saved_stdout = $stdout
          $stdout = stdout
          saved_stdout_const = Object.const_get(:STDOUT)
          OpenC3.disable_warnings { Object.const_set(:STDOUT, stdout) }

          begin
            expect {
              auth.token
            }.to raise_error(OpenC3AuthenticationError)
          ensure
            $stdout = saved_stdout
            OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout_const) }
          end

          # In debug mode, STDOUT should contain the actual refresh token (works with both Ruby 3.2 and 3.3+ inspect formats)
          expect(stdout.string).to match(/"refresh_token"\s*=>\s*"test_refresh_token"/)
        end
      end

      context "with client credentials" do
        let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }

        before(:each) do
          ENV.delete('OPENC3_API_USER')
          ENV.delete('OPENC3_API_PASSWORD')
          ENV['OPENC3_API_CLIENT'] = 'cosmos-m2m'
          ENV['OPENC3_API_CLIENT_SECRET'] = 'm2m-secret'
          allow(JsonDRb).to receive(:debug?).and_return(false)
        end

        it "obfuscates client_secret in normal mode" do
          expect {
            auth.token
          }.to raise_error(OpenC3AuthenticationError) do |error|
            expect(error.message).to match(/"client_secret"\s*=>\s*"\*\*\*"/)
            expect(error.message).not_to include('m2m-secret')
          end
        end

        it "obfuscates client_secret when debug is enabled" do
          allow(JsonDRb).to receive(:debug?).and_return(true)
          stdout = StringIO.new('', 'r+')
          saved_stdout = $stdout
          $stdout = stdout
          saved_stdout_const = Object.const_get(:STDOUT)
          OpenC3.disable_warnings { Object.const_set(:STDOUT, stdout) }

          begin
            expect {
              auth.token
            }.to raise_error(OpenC3AuthenticationError) do |error|
              expect(error.message).to match(/"client_secret"\s*=>\s*"\*\*\*"/)
              expect(error.message).not_to include('m2m-secret')
            end
          ensure
            $stdout = saved_stdout
            OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout_const) }
          end

          expect(stdout.string).to match(/"client_secret"\s*=>\s*"\*\*\*"/)
          expect(stdout.string).not_to include('m2m-secret')
        end
      end
    end

    describe "successful authentication" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }
      let(:mock_success_response) do
        instance_double(Faraday::Response,
          status: 200,
          headers: {},
          body: JSON.generate({
            "access_token" => "access_token_123",
            "expires_in" => 600,
            "refresh_expires_in" => 1800,
            "refresh_token" => "refresh_token_123",
            "token_type" => "bearer"
          })
        )
      end

      before(:each) do
        allow(JsonDRb).to receive(:debug?).and_return(false)
        allow(mock_http).to receive(:post).and_return(mock_success_response)
      end

      it "returns token with Bearer prefix by default" do
        token = auth.token
        expect(token).to eq("Bearer access_token_123")
      end

      it "returns token without Bearer prefix when requested" do
        token = auth.token(include_bearer: false)
        expect(token).to eq("access_token_123")
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

    describe "retryable errors" do
      let(:auth) { OpenC3KeycloakAuthentication.new(test_url) }
      let(:mock_503_response) do
        instance_double(Faraday::Response,
          status: 503,
          headers: {},
          body: '{"error":"service_unavailable"}'
        )
      end

      before(:each) do
        allow(JsonDRb).to receive(:debug?).and_return(false)
        allow(mock_http).to receive(:post).and_return(mock_503_response)
      end

      it "raises retryable error for 5xx status codes" do
        expect {
          auth.token
        }.to raise_error(OpenC3AuthenticationRetryableError)
      end
    end

    describe "URL encoding of special characters" do
      # This test runs without any mocking to verify Faraday's behavior
      context "Faraday middleware verification" do
        after(:each) do
          RSpec::Mocks.space.proxy_for(Faraday).reset if RSpec::Mocks.space.proxies.any?
        end

        it "verifies Faraday URL encodes hash data" do
          RSpec::Mocks.space.proxy_for(Faraday).reset if RSpec::Mocks.space.proxies.any?

          # Simple test to verify Faraday's url_encoded middleware works
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

          # Restore the mock for other tests
          allow(mock_builder).to receive(:request)
          allow(Faraday).to receive(:new).and_yield(mock_builder).and_return(mock_http)
        end
      end
    end
  end

  describe '.authentication_from_environment' do
    around do |example|
      saved_env = {
        'OPENC3_API_TOKEN' => ENV.fetch('OPENC3_API_TOKEN', nil),
        'OPENC3_API_USER' => ENV.fetch('OPENC3_API_USER', nil),
        'OPENC3_API_PASSWORD' => ENV.fetch('OPENC3_API_PASSWORD', nil),
        'OPENC3_API_CLIENT_SECRET' => ENV.fetch('OPENC3_API_CLIENT_SECRET', nil),
        'OPENC3_KEYCLOAK_URL' => ENV.fetch('OPENC3_KEYCLOAK_URL', nil),
      }
      example.run
    ensure
      saved_env.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end

    it 'uses keycloak authentication for a nonempty client secret' do
      ENV['OPENC3_API_TOKEN'] = nil
      ENV['OPENC3_API_USER'] = nil
      ENV['OPENC3_API_PASSWORD'] = 'password'
      ENV['OPENC3_API_CLIENT_SECRET'] = 'm2m-secret'
      ENV['OPENC3_KEYCLOAK_URL'] = 'http://keycloak:8080'

      expect(OpenC3KeycloakAuthentication).to receive(:new).with('http://keycloak:8080').and_return(:keycloak_auth)
      expect(OpenC3.authentication_from_environment).to eq(:keycloak_auth)
    end

    it 'uses core authentication for an empty client secret with a password' do
      ENV['OPENC3_API_TOKEN'] = nil
      ENV['OPENC3_API_USER'] = nil
      ENV['OPENC3_API_PASSWORD'] = 'password'
      ENV['OPENC3_API_CLIENT_SECRET'] = ''

      expect(OpenC3Authentication).to receive(:new).and_return(:core_auth)
      expect(OpenC3.authentication_from_environment).to eq(:core_auth)
    end

    it 'returns nil when no credentials are configured' do
      ENV['OPENC3_API_TOKEN'] = nil
      ENV['OPENC3_API_USER'] = nil
      ENV['OPENC3_API_PASSWORD'] = nil
      ENV['OPENC3_API_CLIENT_SECRET'] = nil

      expect(OpenC3.authentication_from_environment).to be_nil
    end
  end
end
