# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require "spec_helper"
require "openc3/utilities/authentication"

module OpenC3
  describe OpenC3Authentication do
    describe "initialize" do
      it "raises an error if OPENC3_API_PASSWORD is not set" do
        old_password = ENV['OPENC3_API_PASSWORD']
        ENV.delete('OPENC3_API_PASSWORD')
        expect { OpenC3Authentication.new }.to raise_error(OpenC3AuthenticationError, /Authentication requires environment variable/)
        ENV['OPENC3_API_PASSWORD'] = old_password
      end

      it "initializes with OPENC3_API_PASSWORD" do
        ENV['OPENC3_API_PASSWORD'] = 'test_password'
        auth = OpenC3Authentication.new
        expect(auth.token).to eq('test_password')
      end
    end

    describe "token" do
      it "returns the token from environment" do
        ENV['OPENC3_API_PASSWORD'] = 'my_token'
        auth = OpenC3Authentication.new
        expect(auth.token).to eq('my_token')
      end
    end
  end

  describe OpenC3KeycloakAuthentication do
    let(:test_url) { "http://test-keycloak.local" }
    let(:mock_http) { instance_double(Faraday::Connection) }

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
      ENV.delete('OPENC3_KEYCLOAK_REALM')
      ENV.delete('OPENC3_API_CLIENT')
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
            # Error message should contain obfuscated password
            expect(error.message).to include('password=***')
            # Error message should NOT contain actual password
            expect(error.message).not_to include('password=testpassword')
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
          expect(stdout.string).not_to include('password=testpassword')
        end

        it "preserves other parameters in logs" do
          expect {
            auth.token
          }.to raise_error(OpenC3AuthenticationError) do |error|
            # Other parameters should still be visible
            expect(error.message).to include('username=testuser')
            expect(error.message).to include('grant_type=password')
            expect(error.message).to include('client_id=api')
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

          # In debug mode, STDOUT should contain the actual password
          expect(stdout.string).to include('password=testpassword')
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
            # Refresh token should be obfuscated
            expect(error.message).to include('refresh_token=***')
            # Error message should NOT contain actual refresh token
            expect(error.message).not_to include('refresh_token=test_refresh_token')
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

          # In debug mode, STDOUT should contain the actual refresh token
          expect(stdout.string).to include('refresh_token=test_refresh_token')
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
  end
end
