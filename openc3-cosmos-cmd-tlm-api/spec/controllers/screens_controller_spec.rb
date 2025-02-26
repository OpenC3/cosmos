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
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to include("value is empty: target")
    end

    it "requires screen" do
      post :create, params: { scope: 'DEFAULT', target: 'TEST', text: 'SCREEN' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to include("value is empty: screen")
    end

    it "requires text" do
      post :create, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to include("value is empty: text")
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
      class Screen < OpenC3::TargetFile
        def self.all(scope)
          # Override Screen.all to return a fake list of files
          ['INST/screens/screen1.txt','INST/screens/screen2.txt']
        end
      end
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(ret).to eql(['INST/screens/screen1.txt', 'INST/screens/screen2.txt'])
    end
  end

  describe "show" do
    it "returns 404 if not found" do
      class Screen < OpenC3::TargetFile
        def self.find(scope, target, screen)
          # Override Screen.find to return nothing
          nil
        end
      end
      get :show, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:not_found)
    end

    it "returns the screen" do
      class Screen < OpenC3::TargetFile
        def self.find(scope, target, screen)
          # Override Screen.find to return a screen
          "SCREEN"
        end
      end
      get :show, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eql 'SCREEN'
    end
  end

  describe "destroy" do
    it "returns ok" do
      class Screen < OpenC3::TargetFile
        def self.destroy(scope, target, screen)
          # Override Screen.destroy to do nothing
        end
      end
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:ok)
    end

    it "handles exceptions" do
      class Screen < OpenC3::TargetFile
        def self.destroy(scope, target, screen)
          # Override Screen.destroy to raise an exception
          raise 'whoops'
        end
      end
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', screen: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(ret['message']).to eql 'whoops'
    end
  end
end
