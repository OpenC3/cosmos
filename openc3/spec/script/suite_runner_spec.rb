# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/script/suite'
require 'openc3/script/suite_runner'

module OpenC3
  describe SuiteRunner do
    describe "self.build_suites" do
      it "supports no suites" do
        suites = SuiteRunner.build_suites
        expect(suites).to eql "No Suite or no Group classes found"
      end

      it "creates a list of suites" do
        contents = <<~DOC
          class TestGroup < OpenC3::Group
            def test_test
              wait
            end
          end
          class TestSuite < OpenC3::Suite
            def initialize
              add_group('TestGroup')
            end
          end
        DOC
        temp = Tempfile.new(%w[suite .rb])
        temp.write(contents)
        temp.close
        pp temp.path
        require temp.path
        temp.unlink

        suites = SuiteRunner.build_suites
        expect(suites.keys).to eql %w(TestSuite)
        expect(suites["TestSuite"].keys).to eql %i(setup teardown groups)
        expect(suites["TestSuite"][:groups].keys).to eql %w(TestGroup)
        expect(suites["TestSuite"][:groups]["TestGroup"].keys).to eql %i(setup teardown scripts)
        expect(suites["TestSuite"][:groups]["TestGroup"][:scripts]).to eql %w(test_test)
      end
    end
  end
end
