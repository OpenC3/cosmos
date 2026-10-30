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
