# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/script/suite_results'

module OpenC3
  describe SuiteResults do
    describe "#write and #puts" do
      let(:suite_results) { SuiteResults.new }

      it "formats timestamp as UTC with Z suffix" do
        # Initialize report array
        suite_results.instance_variable_set(:@report, [])
        suite_results.puts("Test message")
        report = suite_results.report

        # Should contain a timestamp in UTC format with Z suffix
        expect(report).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Test message/)
      end

      it "appends messages to the report" do
        # Initialize report array
        suite_results.instance_variable_set(:@report, [])
        suite_results.puts("First message")
        suite_results.puts("Second message")
        report = suite_results.report

        expect(report).to include("First message")
        expect(report).to include("Second message")
      end

      it "write method also uses UTC timestamp with Z suffix" do
        # Initialize report array
        suite_results.instance_variable_set(:@report, [])
        suite_results.write("Test write message")
        report = suite_results.report

        # Should contain a timestamp in UTC format with Z suffix
        expect(report).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Test write message/)
      end

      it "uses Z suffix instead of +0000 offset" do
        # Initialize report array
        suite_results.instance_variable_set(:@report, [])
        suite_results.puts("Test message")
        report = suite_results.report

        # Should use Z suffix
        expect(report).to include("Z:")
        # Should NOT use +0000 offset
        expect(report).not_to include("+0000")
      end
    end

    describe "#report" do
      let(:suite_results) { SuiteResults.new }

      it "returns all lines joined with newlines" do
        suite_results.instance_variable_set(:@report, ["Line 1", "Line 2", "Line 3"])
        report = suite_results.report

        expect(report).to eq("Line 1\nLine 2\nLine 3")
      end
    end

    describe "integration tests" do
      let(:suite_results) { SuiteResults.new }

      it "includes formatted timestamps in the full report" do
        # Simulate a test run
        class TestSuiteClass
          def self.name
            "TestSuite"
          end
        end

        suite_results.start("Test", TestSuiteClass)
        suite_results.puts("Running test 1")
        suite_results.puts("Running test 2")
        suite_results.complete

        report = suite_results.report

        expect(report).to include("--- Script Report ---")
        expect(report).to include("Results:")
        expect(report).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Executing/)
        expect(report).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Running test 1/)
        expect(report).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Running test 2/)
      end
    end
  end
end
