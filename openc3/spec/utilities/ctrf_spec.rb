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
require "openc3/utilities/ctrf"

module OpenC3
  describe Ctrf do
    describe "convert_report" do
      let(:sample_report) do
        <<~REPORT
          --- Script Report ---

          Settings:
          Manual = False
          Pause on Error = False
          Continue After Error = True
          Abort After Error = False
          Loop = False
          Break Loop On Error = False

          Results:
          2026-04-02T19:45:41.228209Z: Executing MySuite:ExampleGroup:script_1
          2026-04-02T19:45:44.041472Z: ExampleGroup:script_1:PASS
            This test verifies requirement 1

          2026-04-02T19:45:44.044982Z: Completed MySuite:ExampleGroup:script_1

          --- Test Summary ---

          Run Time: 2.8167383670806885
          Total Tests: 1
          Pass: 1
          Skip: 0
          Fail: 0
        REPORT
      end

      let(:multi_test_report) do
        <<~REPORT
          --- Script Report ---

          Settings:
          Manual = False
          Pause on Error = False
          Continue After Error = True
          Abort After Error = False
          Loop = False
          Break Loop On Error = False

          Results:
          2026-04-02T19:45:41.000000Z: Executing TestSuite:TestGroup:test_1
          2026-04-02T19:45:42.000000Z: TestGroup:test_1:PASS
            Test 1 passed
          2026-04-02T19:45:43.000000Z: TestGroup:test_2:SKIP
            Test 2 skipped
          2026-04-02T19:45:44.000000Z: TestGroup:test_3:FAIL
            Test 3 failed
          2026-04-02T19:45:45.000000Z: Completed TestSuite:TestGroup

          --- Test Summary ---

          Run Time: 4.0
          Total Tests: 3
          Pass: 1
          Skip: 1
          Fail: 1
        REPORT
      end

      it "converts a basic script report to CTRF format" do
        result = Ctrf.convert_report(sample_report)

        expect(result).to be_a(Hash)
        expect(result[:reportFormat]).to eq("CTRF")
        expect(result[:results]).to be_a(Hash)
      end

      it "includes correct tool information" do
        result = Ctrf.convert_report(sample_report)

        expect(result[:results][:tool][:name]).to eq("COSMOS Script Runner")
        expect(result[:results][:tool][:version]).to eq(OpenC3::VERSION)
      end

      it "accepts custom version parameter" do
        custom_version = "1.2.3"
        result = Ctrf.convert_report(sample_report, version: custom_version)

        expect(result[:results][:tool][:version]).to eq(custom_version)
      end

      it "parses test summary correctly" do
        result = Ctrf.convert_report(sample_report)
        summary = result[:results][:summary]

        expect(summary[:tests]).to eq(1)
        expect(summary[:passed]).to eq(1)
        expect(summary[:failed]).to eq(0)
        expect(summary[:skipped]).to eq(0)
        expect(summary[:pending]).to eq(0)
        expect(summary[:other]).to eq(0)
      end

      it "parses multiple test results" do
        result = Ctrf.convert_report(multi_test_report)
        summary = result[:results][:summary]

        expect(summary[:tests]).to eq(3)
        expect(summary[:passed]).to eq(1)
        expect(summary[:failed]).to eq(1)
        expect(summary[:skipped]).to eq(1)
      end

      it "parses test cases with correct status" do
        result = Ctrf.convert_report(multi_test_report)
        tests = result[:results][:tests]

        expect(tests.length).to eq(3)

        expect(tests[0][:name]).to eq("TestGroup:test_1")
        expect(tests[0][:status]).to eq("passed")

        expect(tests[1][:name]).to eq("TestGroup:test_2")
        expect(tests[1][:status]).to eq("skipped")

        expect(tests[2][:name]).to eq("TestGroup:test_3")
        expect(tests[2][:status]).to eq("failed")
      end

      it "calculates test duration correctly" do
        result = Ctrf.convert_report(sample_report)
        tests = result[:results][:tests]

        expect(tests.length).to eq(1)
        # Duration should be end_time - start_time in milliseconds
        # 2026-04-02T19:45:44.041472Z - 2026-04-02T19:45:41.228209Z = ~2813.263ms
        expect(tests[0][:duration]).to be_within(1).of(2813.263)
      end

      it "parses timestamps correctly" do
        result = Ctrf.convert_report(sample_report)
        summary = result[:results][:summary]

        # Start: 2026-04-02T19:45:41.228209Z
        expect(summary[:start]).to be_within(1).of(1775159141228.209)
        # Stop: 2026-04-02T19:45:44.044982Z
        expect(summary[:stop]).to be_within(1).of(1775159144044.982)
      end

      it "parses settings into extra metadata" do
        result = Ctrf.convert_report(sample_report)
        extra = result[:results][:extra]

        expect(extra[:manual]).to eq("False")
        expect(extra[:pauseOnError]).to eq("False")
        expect(extra[:continueAfterError]).to eq("True")
        expect(extra[:abortAfterError]).to eq("False")
        expect(extra[:loop]).to eq("False")
        expect(extra[:breakLoopOnError]).to eq("False")
      end

      it "handles reports with missing data gracefully" do
        minimal_report = <<~REPORT
          --- Script Report ---

          Settings:
          Manual = False

          Results:

          --- Test Summary ---

          Total Tests: 0
          Pass: 0
          Skip: 0
          Fail: 0
        REPORT

        result = Ctrf.convert_report(minimal_report)

        expect(result[:results][:summary][:tests]).to eq(0)
        expect(result[:results][:tests]).to be_empty
        expect(result[:results][:extra][:manual]).to eq("False")
      end

      it "handles nil lines in report" do
        report_with_nils = sample_report + "\n\n\n"

        expect {
          Ctrf.convert_report(report_with_nils)
        }.not_to raise_error
      end

      it "handles malformed timestamps gracefully" do
        malformed_report = <<~REPORT
          --- Script Report ---

          Settings:
          Manual = False

          Results:
          invalid-timestamp: Executing Test:Group:script
          another-bad-timestamp: Group:script:PASS

          --- Test Summary ---

          Total Tests: 0
          Pass: 0
          Skip: 0
          Fail: 0
        REPORT

        expect {
          result = Ctrf.convert_report(malformed_report)
          # Should not crash, but may not parse tests correctly
          expect(result[:results][:tests]).to be_a(Array)
        }.not_to raise_error
      end

      it "handles unknown test status" do
        unknown_status_report = <<~REPORT
          --- Script Report ---

          Settings:
          Manual = False

          Results:
          2026-04-02T19:45:41.000000Z: Executing Test:Group:script
          2026-04-02T19:45:42.000000Z: Group:script:UNKNOWN
          2026-04-02T19:45:43.000000Z: Completed Test:Group:script

          --- Test Summary ---

          Total Tests: 1
          Pass: 0
          Skip: 0
          Fail: 0
        REPORT

        result = Ctrf.convert_report(unknown_status_report)
        tests = result[:results][:tests]

        expect(tests.length).to eq(1)
        expect(tests[0][:status]).to eq("unknown")
      end

      it "returns a valid CTRF structure" do
        result = Ctrf.convert_report(sample_report)

        # Validate CTRF structure according to https://ctrf.io/docs/schema/ctrf-report
        expect(result[:results]).to have_key(:tool)
        expect(result[:results]).to have_key(:summary)
        expect(result[:results]).to have_key(:tests)
        expect(result[:results]).to have_key(:extra)

        # Tool section
        expect(result[:results][:tool]).to have_key(:name)
        expect(result[:results][:tool]).to have_key(:version)

        # Summary section
        expect(result[:results][:summary]).to have_key(:tests)
        expect(result[:results][:summary]).to have_key(:passed)
        expect(result[:results][:summary]).to have_key(:failed)
        expect(result[:results][:summary]).to have_key(:skipped)
        expect(result[:results][:summary]).to have_key(:pending)
        expect(result[:results][:summary]).to have_key(:other)
        expect(result[:results][:summary]).to have_key(:start)
        expect(result[:results][:summary]).to have_key(:stop)

        # Tests section
        expect(result[:results][:tests]).to be_an(Array)
        if result[:results][:tests].any?
          expect(result[:results][:tests][0]).to have_key(:name)
          expect(result[:results][:tests][0]).to have_key(:status)
          expect(result[:results][:tests][0]).to have_key(:duration)
        end
      end
    end
  end
end
