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
require "openc3/utilities/script_env"

module OpenC3
  describe ScriptEnv do
    describe ".remove_unused" do
      it "sets the unused vars to nil so the child process does not inherit them" do
        environment = { "OPENC3_SCOPE" => "DEFAULT" }
        ScriptEnv.remove_unused(environment)
        expect(environment["OPENC3_SCOPE"]).to eq("DEFAULT")
        ScriptEnv::UNUSED_VARS.each do |key|
          expect(environment).to have_key(key)
          expect(environment[key]).to be_nil
        end
      end
    end

    describe ".key_error" do
      it "allows ordinary variable names" do
        %w[MYVAR my_var _X TARGET2 OPENC3 PATHS HOMEDIR].each do |key|
          expect(ScriptEnv.key_error(key)).to be_nil, "expected #{key} to be allowed"
        end
      end

      it "rejects the variables COSMOS uses to connect scripts" do
        %w[OPENC3_API_HOSTNAME OPENC3_API_PORT OPENC3_API_SCHEMA OPENC3_KEYCLOAK_URL
           OPENC3_REDIS_HOSTNAME OPENC3_BUCKET_URL OPENC3_SCRIPT_API_HOSTNAME
           HTTP_PROXY https_proxy ALL_PROXY no_proxy HOSTALIASES LOCALDOMAIN RES_OPTIONS
           AWS_ENDPOINT_URL SSL_CERT_FILE REQUESTS_CA_BUNDLE].each do |key|
          expect(ScriptEnv.key_error(key)).to include("reserved"), "expected #{key} to be reserved"
        end
      end

      it "rejects the variables that configure the interpreter" do
        %w[LD_PRELOAD ld_library_path DYLD_INSERT_LIBRARIES RUBYOPT RUBYLIB GEM_HOME GEM_PATH
           BUNDLE_GEMFILE PYTHONPATH PYTHONSTARTUP VIRTUAL_ENV PATH HOME BASH_ENV
           OPENSSL_CONF GCONV_PATH].each do |key|
          expect(ScriptEnv.key_error(key)).to include("reserved"), "expected #{key} to be reserved"
        end
      end

      it "rejects names that are not valid identifiers" do
        ["", "1ABC", "A=B", "A B", "A\0B", "A-B", "PATH\n"].each do |key|
          expect(ScriptEnv.key_error(key)).to include("letters, digits and underscores"), "expected #{key.inspect} to be invalid"
        end
        expect(ScriptEnv.key_error(nil)).to include("must be a String")
        expect(ScriptEnv.key_error(5)).to include("must be a String")
      end
    end

    describe ".apply_user_entries" do
      it "applies allowed entries and skips reserved ones with a warning" do
        environment = { "OPENC3_API_HOSTNAME" => nil }
        expect(Logger).to receive(:warn).with(/OPENC3_API_HOSTNAME/, scope: "DEFAULT")
        expect(Logger).to receive(:warn).with(/LD_PRELOAD/, scope: "DEFAULT")
        applied = ScriptEnv.apply_user_entries(environment, [
          { "key" => "MYVAR", "value" => "foo" },
          { "key" => "OPENC3_API_HOSTNAME", "value" => "other.example.com" },
          { "key" => "LD_PRELOAD", "value" => "/tmp/other.so" },
        ], source: "global", scope: "DEFAULT")
        expect(applied).to eql({ "MYVAR" => "foo" })
        expect(environment).to eql({ "OPENC3_API_HOSTNAME" => nil, "MYVAR" => "foo" })
      end

      it "ignores nil and malformed entries" do
        allow(Logger).to receive(:warn)
        environment = {}
        expect(ScriptEnv.apply_user_entries(environment, nil, source: "script")).to eql({})
        expect(ScriptEnv.apply_user_entries(environment, ["MYVAR", 1, nil], source: "script")).to eql({})
        expect(environment).to eql({})
      end
    end

    describe ".clear_credentials" do
      before(:each) do
        @saved = ScriptEnv::CLEARED_VARS.to_h { |key| [key, ENV[key]] }
        @saved["OPENC3_SCOPE"] = ENV["OPENC3_SCOPE"]
      end

      after(:each) do
        @saved.each { |key, value| ENV[key] = value }
      end

      it "connects to the bucket and stores before clearing the vars" do
        ScriptEnv::CLEARED_VARS.each { |key| ENV[key] = "value" }
        ENV["OPENC3_SCOPE"] = "DEFAULT"
        expect(Bucket).to receive(:getClient).ordered
        expect(Store).to receive(:instance).ordered
        expect(EphemeralStore).to receive(:instance).ordered

        ScriptEnv.clear_credentials

        ScriptEnv::CLEARED_VARS.each { |key| expect(ENV).not_to have_key(key) }
        expect(ENV["OPENC3_SCOPE"]).to eq("DEFAULT")
      end

      it "includes all the unused vars" do
        expect(ScriptEnv::CLEARED_VARS).to include(*ScriptEnv::UNUSED_VARS)
      end
    end
  end
end
