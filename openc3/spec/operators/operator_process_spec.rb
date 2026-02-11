# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

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
  end
end
