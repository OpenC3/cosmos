# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require "rails_helper"

RSpec.describe TimeController, type: :controller do
  describe "GET current" do
    it "gets the time" do
      get :get_current
      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result).to have_key("now_nsec")
    end
  end
end
