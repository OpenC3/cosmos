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

RSpec.describe DashboardsController, :type => :controller do
  before(:each) do
    mock_redis()
    ENV.delete('OPENC3_LOCAL_MODE')
  end

  describe "create" do
    it "requires target" do
      post :create, params: { scope: 'DEFAULT', dashboard: 'TEST', text: 'DASHBOARD' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/target/)
    end

    it "requires dashboard" do
      post :create, params: { scope: 'DEFAULT', target: 'TEST', text: 'DASHBOARD' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/dashboard/)
    end

    it "requires text" do
      post :create, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match(/text/)
    end

    it "creates a dashboard" do
      s3 = instance_double("Aws::S3::Client")
      expect(s3).to receive(:put_object)
      expect(s3).to receive(:wait_until)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)
      post :create, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST', text: 'DASHBOARD' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "path traversal" do
    it "rejects target and dashboard names that would leave the target directory" do
      expect(Dashboard).not_to receive(:create)
      expect(Dashboard).not_to receive(:find)
      expect(Dashboard).not_to receive(:destroy)
      [{ target: '..', dashboard: 'TEST' }, { target: 'INST', dashboard: '../../x' },
       { target: 'INST/../OTHER', dashboard: 'TEST' }, { target: '.', dashboard: 'TEST' }].each do |names|
        post :create, params: { scope: 'DEFAULT', text: 'DASHBOARD' }.merge(names)
        expect(response).to have_http_status(:bad_request)
        get :show, params: { scope: 'DEFAULT' }.merge(names)
        expect(response).to have_http_status(:bad_request)
        delete :destroy, params: { scope: 'DEFAULT' }.merge(names)
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "version history (Enterprise VersionStore)" do
    let(:store) { double('VersionStore') }
    before(:each) { stub_const('VersionStore', store) }

    it "commits each save as a version and returns its id" do
      allow(Dashboard).to receive(:create)
      expect(store).to receive(:commit).with(scope: 'DEFAULT', name: 'INST/dashboards/test.txt', text: 'DASHBOARD', username: anything).and_return('abc123')
      post :create, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST', text: 'DASHBOARD' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['version_id']).to eql 'abc123'
    end

    it "records deletes" do
      allow(Dashboard).to receive(:destroy)
      expect(store).to receive(:delete).with(scope: 'DEFAULT', name: 'INST/dashboards/test.txt', username: anything)
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:ok)
    end

    it "seeds a baseline version when a dashboard is opened" do
      allow(Dashboard).to receive(:find).and_return('DASHBOARD')
      allow(OpenC3::TargetModel).to receive(:plugin_version_label).and_return('openc3-cosmos-demo 1.0')
      expect(store).to receive(:seed_initial_if_empty).with(scope: 'DEFAULT', name: 'INST/dashboards/test.txt', body: 'DASHBOARD', plugin: 'openc3-cosmos-demo 1.0')
      get :show, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "index" do
    it "lists all dashboards for a target" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt'])
    end

    it "filters out dashboards from uninstalled targets" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      # INST is installed (with a modified dashboard marked '*') but OLD is uninstalled
      # with orphaned modified files still present in the bucket.
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt*',
         'OLD/dashboards/orphan.txt', 'OLD/dashboards/orphan2.txt*']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt'])
    end

    it "returns summaries with summary=true" do
      summaries = [{ 'path' => 'INST/dashboards/dash1.txt', 'title' => 'One', 'icon' => nil, 'color' => nil, 'panels' => 1 }]
      expect(Dashboard).to receive(:summaries).with('DEFAULT').and_return(summaries)
      get :index, params: { scope: 'DEFAULT', summary: 'true' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eql(summaries)
    end

    it "ignores partial dashboard files starting with underscore" do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/dashboards/dash1.txt', 'INST/dashboards/_partial.txt']
      )
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(['INST/dashboards/dash1.txt'])
    end
  end

  describe "show" do
    it "returns 404 if not found" do
      allow(Dashboard).to receive(:find).and_return(nil)
      get :show, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:not_found)
    end

    it "returns the dashboard" do
      allow(Dashboard).to receive(:find).and_return("DASHBOARD")
      get :show, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eql 'DASHBOARD'
    end
  end

  describe "destroy" do
    it "returns ok" do
      allow(Dashboard).to receive(:destroy).and_return(nil)
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:ok)
    end

    it "handles exceptions" do
      allow(Dashboard).to receive(:destroy).and_raise('whoops')
      delete :destroy, params: { scope: 'DEFAULT', target: 'INST', dashboard: 'TEST' }
      expect(response).to have_http_status(:error)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['message']).to eql 'whoops'
    end
  end
end
