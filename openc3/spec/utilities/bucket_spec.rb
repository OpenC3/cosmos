# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc
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

require 'spec_helper'
require 'openc3/utilities/bucket'

module OpenC3
  describe Bucket do
    describe "getClient" do
      it "requires the client code" do
        ENV['OPENC3_CLOUD'] = 'AWS'
        client = Bucket.getClient()
        expect(client).to be_a AwsBucket
      end

      it "defaults OPENC3_CLOUD to local" do
        ENV['OPENC3_CLOUD'] = nil
        load 'openc3/utilities/bucket.rb'
        client = Bucket.getClient()
        expect(client).to be_a LocalBucket
      end
    end
  end
end
