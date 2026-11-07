# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rails_helper'

RSpec.describe PanelsController, :type => :controller do
  before(:each) do
    mock_redis()
  end

  describe "index" do
    it "lists the panel types plugins installed" do
      OpenC3::PanelModel.new(name: 'MAP', plugin: 'plugin', scope: 'DEFAULT').create
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eql ['MAP']
    end
  end
end
