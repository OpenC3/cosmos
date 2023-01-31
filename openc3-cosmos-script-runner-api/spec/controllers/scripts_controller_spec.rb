# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'rails_helper'
require 'openc3/utilities/aws_bucket'

RSpec.describe ScriptsController, :type => :controller do
  describe "create" do
    before(:each) do
      ENV.delete('OPENC3_LOCAL_MODE')
      mock_redis()
    end

    it "creates a script when none exist" do
      s3 = instance_double("Aws::S3::Client")
      expect(s3).to receive(:put_object)
      allow(s3).to receive(:get_object).and_return(nil)
      expect(s3).to receive(:wait_until)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)

      post :create, params: { scope: 'DEFAULT', name: 'script.rb', text: 'text' }
      expect(response).to have_http_status(:ok)
    end

    it "does not save when text is the same" do
      s3 = instance_double("Aws::S3::Client")
      # NOTE: We are NOT expecting put_object because the file is the same
      file = double("file")
      allow(file).to receive_message_chain(:body, read: 'text')
      expect(s3).to receive(:get_object).and_return(file)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)

      post :create, params: { scope: 'DEFAULT', name: 'script.rb', text: 'text' }
      expect(response).to have_http_status(:ok)
    end

    it "does not pass params which aren't permitted" do
      expect(Script).to receive(:create) do |params|
        # Check that we don't pass extra params
        expect(params.keys).to eql(%w(scope name text breakpoints))
      end
      post :create, params: { scope: 'DEFAULT', name: 'script.rb', text: 'text', breakpoints: [1], other: 'nope' }
      expect(response).to have_http_status(:ok)
    end
  end
end
