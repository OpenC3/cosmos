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
    end
  end
end
