# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require "rails_helper"

RSpec.describe InfoController, type: :controller do
  describe "GET Info" do
    it "Gets OpenC3 Version and License info" do
      get :info
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["license"]).to eql("OpenC3")
    end
  end
end
