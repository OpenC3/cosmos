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

    it "Logout terminates only the caller's own session token" do
      request.headers['HTTP_AUTHORIZATION'] = 'ses_mytoken'
      expect(OpenC3::AuthModel).to receive(:terminate).with('ses_mytoken')
      put :logout, params: {user: "user", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end
  end
end
