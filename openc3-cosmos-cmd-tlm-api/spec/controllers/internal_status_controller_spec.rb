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

require 'rails_helper'

RSpec.describe InternalStatusController, :type => :controller do
  before(:each) do
    mock_redis()
  end

  describe "GET status" do
    it "returns a Hash<string, string> and status code 200" do
      get :status
      expect(JSON.parse(response.body, symbolize_names: true, allow_nan: true)).to include(status: 'UP')
      expect(response).to have_http_status(:ok)
    end
  end
end
