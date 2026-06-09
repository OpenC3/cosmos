# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/script/suite'
require 'openc3/script/suite_runner'

# Fixtures for exercising SuiteRunner option validation. OptionsGroup is part
# of OptionsSuite; OtherGroup is intentionally left out of any suite plan.
class SuiteRunnerOptionsGroup < OpenC3::Group
  def test_valid_script
  end
end
class SuiteRunnerOptionsSuite < OpenC3::Suite
  def initialize
    add_group('SuiteRunnerOptionsGroup')
  end
end
class SuiteRunnerOtherGroup < OpenC3::Group
  def test_other
  end
end

module OpenC3
  describe SuiteRunner do
    describe "self.build_suites" do
      it "creates a list of suites" do
        contents = <<~DOC
          class SuiteRunnerSpecGroup < OpenC3::Group
            def test_test
              wait
            end
          end
          class SuiteRunnerSpecSuite < OpenC3::Suite
            def initialize
              add_group('SuiteRunnerSpecGroup')
            end
          end
        DOC
        temp = Tempfile.new(%w[suite .rb])
        temp.write(contents)
        temp.close
        require temp.path
        temp.unlink

        suites = SuiteRunner.build_suites
        expect(suites.keys).to include "SuiteRunnerSpecSuite"
        expect(suites["SuiteRunnerSpecSuite"].keys).to eql %i(setup teardown groups)
        expect(suites["SuiteRunnerSpecSuite"][:groups].keys).to eql %w(SuiteRunnerSpecGroup)
        expect(suites["SuiteRunnerSpecSuite"][:groups]["SuiteRunnerSpecGroup"].keys).to eql %i(setup teardown scripts)
        expect(suites["SuiteRunnerSpecSuite"][:groups]["SuiteRunnerSpecGroup"][:scripts]).to eql %w(test_test)
      end

      it "preserves add_script insertion order" do
        contents = <<~DOC
          class OrderedGroup < OpenC3::Group
            def test_z_last
            end
            def test_a_first
            end
            def test_m_middle
            end
          end
          class OrderedSuite < OpenC3::Suite
            def initialize
              add_script('OrderedGroup', 'test_m_middle')
              add_script('OrderedGroup', 'test_z_last')
              add_script('OrderedGroup', 'test_a_first')
            end
          end
        DOC
        temp = Tempfile.new(%w[suite .rb])
        temp.write(contents)
        temp.close
        require temp.path
        temp.unlink

        suites = SuiteRunner.build_suites
        expect(suites.keys).to include "OrderedSuite"
        # Scripts should be in the order they were added, not alphabetical
        expect(suites["OrderedSuite"][:groups]["OrderedGroup"][:scripts]).to eql %w(test_m_middle test_z_last test_a_first)
      end
    end

    # These validate the suite_runner option combinations that flow through
    # RunningScript#run into SuiteRunner.start / setup / teardown (all of
    # which funnel through SuiteRunner.execute).
    describe "self.start option validation" do
      before(:each) do
        SuiteRunner.build_suites
      end

      it "raises when a script is given without a group" do
        expect { SuiteRunner.start(SuiteRunnerOptionsSuite, nil, 'test_valid_script') }
          .to raise_error(/Script test_valid_script requires a Group/)
      end

      it "raises for an unknown suite" do
        expect { SuiteRunner.start(String) }.to raise_error(/Suite String not found/)
      end

      it "raises for a group not in the suite" do
        expect { SuiteRunner.start(SuiteRunnerOptionsSuite, SuiteRunnerOtherGroup) }
          .to raise_error(/Group SuiteRunnerOtherGroup not found in Suite SuiteRunnerOptionsSuite/)
      end
    end
  end
end
