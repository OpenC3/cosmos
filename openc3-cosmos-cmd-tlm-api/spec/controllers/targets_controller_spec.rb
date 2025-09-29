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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rails_helper'
require 'openc3/models/model'
require 'openc3/models/target_model'

RSpec.describe TargetsController, :type => :controller do
  before(:each) do
    mock_redis()
    ENV.delete('OPENC3_LOCAL_MODE')
  end

  describe "all_modified" do
    it "lists all modified targets for a scope" do
      allow(OpenC3::TargetModel).to receive(:all_modified).and_return(["INST"])
      get :all_modified, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST'])
    end

    it "rejects a bad scope param" do
      get :all_modified, params: { scope: '../DEFAULT' }
      expect(response).to have_http_status(:bad_request)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['message']).to eql('Invalid scope: ../DEFAULT')
    end
  end
end
