# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require "rails_helper"

RSpec.describe UsersController, type: :controller do
  describe "UsersController" do
    it "GET active" do
      get :active
      expect(response).to have_http_status(:ok)
    end

    it "Logout" do
      allow(OpenC3::AuthModel).to receive(:logout)
      put :logout, params: {user: "user"}
      expect(response).to have_http_status(:ok)
    end
  end
end
