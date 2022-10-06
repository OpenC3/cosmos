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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'spec_helper'
require 'openc3/operators/operator'

module OpenC3
  describe OperatorProcess do
    describe "start" do
      it "starts the process" do
        spy = spy('ChildProcess')
        expect(spy).to receive(:start)
        expect(ChildProcess).to receive(:build).with('ruby', 'filename.rb', 'DEFAULT__SERVICE__NAME').and_return(spy)

        capture_io do |stdout|
          op = OperatorProcess.new(
            ['ruby', 'filename.rb', 'DEFAULT__SERVICE__NAME'],
            scope: 'DEFAULT',
            config: { 'cmd' => ["ruby", "service_microservice.rb", 'DEFAULT__SERVICE__NAME'] }
          )
          op.start
          expect(stdout.string).to include('Starting: ruby service_microservice.rb DEFAULT__SERVICE__NAME')
        end
      end
    end

    describe "extract_output" do
      it "extracts the top and bottom half of stdout" do
        process = double("process").as_null_object
        stdout = double("stdout").as_null_object
        stderr = double("stderr").as_null_object
        allow(process).to receive_message_chain("io.stdout").and_return(stdout)
        allow(process).to receive_message_chain("io.stderr").and_return(stderr)
        lines = ''
        (1..20).each do |x|
          lines << "Line:#{x}\n"
        end
        expect(stdout).to receive(:read).and_return(lines)
        # expect(stderr).to receive(:read).and_return("ERROR")
        op = OperatorProcess.new(['ruby', 'filename.rb', 'DEFAULT__SERVICE__NAME'], scope: 'DEFAULT')
        op.instance_variable_set(:@process, process)
        output = op.extract_output(10, 0)
        expect(output).to include('Line:1')
        expect(output).to include('Line:5')
        expect(output).not_to include('Line:6')
        expect(output).not_to include('Line:15')
        expect(output).to include('Line:16')
        expect(output).to include('Line:20')
      end

      it "extracts the bottom of stderr" do
        process = double("process").as_null_object
        stdout = double("stdout").as_null_object
        stderr = double("stderr").as_null_object
        allow(process).to receive_message_chain("io.stdout").and_return(stdout)
        allow(process).to receive_message_chain("io.stderr").and_return(stderr)
        lines = ''
        (1..20).each do |x|
          lines << "Line:#{x}\n"
        end
        expect(stderr).to receive(:read).and_return(lines)
        op = OperatorProcess.new(['ruby', 'filename.rb', 'DEFAULT__SERVICE__NAME'], scope: 'DEFAULT')
        op.instance_variable_set(:@process, process)
        output = op.extract_output(0, 10)
        expect(output).not_to include('Line:3') # Line:1 matches Line:10
        expect(output).not_to include('Line:10')
        expect(output).to include('Line:11')
        expect(output).to include('Line:20')
      end

      it "extracts the full amount if less than the max" do
        process = double("process").as_null_object
        stdout = double("stdout").as_null_object
        stderr = double("stderr").as_null_object
        allow(process).to receive_message_chain("io.stdout").and_return(stdout)
        allow(process).to receive_message_chain("io.stderr").and_return(stderr)
        stdout_lines = ''
        (1..10).each do |x|
          stdout_lines << "Out:#{x}\n"
        end
        stderr_lines = ''
        (1..10).each do |x|
          stderr_lines << "Err:#{x}\n"
        end
        expect(stdout).to receive(:read).and_return(stdout_lines)
        expect(stderr).to receive(:read).and_return(stderr_lines)
        op = OperatorProcess.new(['ruby', 'filename.rb', 'DEFAULT__SERVICE__NAME'], scope: 'DEFAULT')
        op.instance_variable_set(:@process, process)
        output = op.extract_output(10, 10)
        expect(output).to include("Stdout:")
        expect(output).to include(stdout_lines.strip)
        expect(output).to include("Stderr:")
        expect(output).to include(stderr_lines.strip)
      end
    end
  end
end
