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

require "spec_helper"
require "openc3/utilities/bucket"

module OpenC3
  describe Bucket do
    describe "getClient" do
      it "requires the client code" do
        ENV['OPENC3_CLOUD'] = 'AWS'
        client = Bucket.getClient()
        expect(client).to be_a AwsBucket
      end

      it "requires OPENC3_CLOUD to be set" do
        ENV['OPENC3_CLOUD'] = nil
        expect { Bucket.getClient() }.to raise_error("OPENC3_CLOUD environment variable is required")
        ENV['OPENC3_CLOUD'] = 'aws'
      end
    end

    describe "instance methods" do
      let(:bucket) { Bucket.new }

      it "raises on the defined methods" do
        expect { bucket.create({}) }.to raise_error(NotImplementedError)
        expect { bucket.exist?({}) }.to raise_error(NotImplementedError)
        expect { bucket.get_object({}) }.to raise_error(NotImplementedError)
        expect { bucket.put_object({}) }.to raise_error(NotImplementedError)
        expect { bucket.list_objects({}) }.to raise_error(NotImplementedError)
        expect { bucket.check_object({}) }.to raise_error(NotImplementedError)
        expect { bucket.delete_object({}) }.to raise_error(NotImplementedError)
      end
    end
  end
end
