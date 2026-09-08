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
require 'openc3/utilities/target_file'
require 'openc3/utilities/aws_bucket'

RSpec.describe ScreensController, :type => :controller do
  before(:each) do
    mock_redis()
    ENV.delete('OPENC3_LOCAL_MODE')
  end

  describe "create" do
    it "requires target" do
      post :create, params: { scope: 'DEFAULT', screen: 'TEST', text: 'SCREEN' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/target/)
    end

    it "requires screen" do
      post :create, params: { scope: 'DEFAULT', target: 'TEST', text: 'SCREEN' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/screen/)
    end

    it "requires text" do
      post :create, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/text/)
    end

    it "creates a screen" do
      s3 = instance_double("Aws::S3::Client")
      expect(s3).to receive(:put_object)
      expect(s3).to receive(:wait_until)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)
      post :create, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST', text: 'SCREEN' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "index" do
    it "lists all screens for a target" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/screens/screen1.txt', 'INST/screens/screen2.txt']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/screens/screen1.txt', 'INST/screens/screen2.txt'])
    end

    it "filters out screens from uninstalled targets" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      # INST is installed (with a modified screen marked '*') but OLD is uninstalled
      # with orphaned modified files still present in the bucket.
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/screens/screen1.txt', 'INST/screens/screen2.txt*',
         'OLD/screens/orphan.txt', 'OLD/screens/orphan2.txt*']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/screens/screen1.txt', 'INST/screens/screen2.txt'])
    end

    it "ignores partial screen files starting with underscore" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/screens/screen1.txt', 'INST/screens/_partial.txt']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/screens/screen1.txt'])
    end
  end

  describe "show" do
    it "returns 404 if not found" do
      allow(Screen).to receive(:find).and_return(nil)
      get :show, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:not_found)
    end

    it "returns the screen" do
      allow(Screen).to receive(:find).and_return("SCREEN")
      get :show, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eql 'SCREEN'
    end
  end

  describe "destroy" do
    it "returns ok" do
      allow(Screen).to receive(:destroy).and_return(nil)
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:ok)
    end

    it "handles exceptions" do
      allow(Screen).to receive(:destroy).and_raise('whoops')
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['message']).to eql 'whoops'
    end
  end
end
