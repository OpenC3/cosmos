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
require "tempfile"

RSpec.describe PackagesController, type: :controller do
  before(:each) do
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
  end

  describe "GET index" do
    it "returns list of installed packages" do
      allow(OpenC3::GemModel).to receive(:names).and_return(["gem1", "gem2"])
      allow(OpenC3::PythonPackageModel).to receive(:names).and_return(["python1", "python2"])

      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["ruby"]).to eq(["gem1", "gem2"])
      expect(json["python"]).to eq(["python1", "python2"])
    end

    it "returns nothing without authorization" do
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST create" do
    before(:each) do
      # Mock file upload
      @file = Tempfile.new(["test", ".gem"])
      @file.write("gem content")
      @file.rewind

      @upload_file = fixture_file_upload(@file.path, "application/octet-stream")
      allow(@upload_file).to receive(:original_filename).and_return("test.gem")

      # Mock directory creation
      allow(Dir).to receive(:mktmpdir).and_return("/tmp/test")
      allow(FileUtils).to receive(:cp)
      allow(FileUtils).to receive(:remove_entry_secure)
    end

    it "installs a ruby gem package" do
      allow(OpenC3::GemModel).to receive(:put).and_return("gem_process")

      post :create, params: {package: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("gem_process")
    end

    it "installs a python package" do
      @python_file = Tempfile.new(["test", ".whl"])
      @python_file.write("python package content")
      @python_file.rewind

      @python_upload = fixture_file_upload(@python_file.path, "application/octet-stream")
      allow(@python_upload).to receive(:original_filename).and_return("test.whl")

      allow(OpenC3::PythonPackageModel).to receive(:put).and_return("python_process")

      post :create, params: {package: @python_upload, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("python_process")
    end

    it "handles error during package installation" do
      allow(OpenC3::GemModel).to receive(:put).and_raise(StandardError.new("Installation error"))

      post :create, params: {package: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Installation error")
    end

    it "returns error if package file is missing" do
      post :create, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Package file as params[:package] is required")
    end

    it "returns nothing without authorization" do
      post :create, params: {package: @upload_file}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE destroy" do
    it "removes a ruby gem package" do
      allow(OpenC3::GemModel).to receive(:destroy)

      delete :destroy, params: {id: "test.gem", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "removes a python package" do
      allow(OpenC3::PythonPackageModel).to receive(:destroy)

      delete :destroy, params: {id: "test.whl", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "handles error during package removal" do
      allow(OpenC3::GemModel).to receive(:destroy).and_raise(StandardError.new("Removal error"))

      delete :destroy, params: {id: "test.gem", scope: "DEFAULT"}
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Removal error")
    end

    it "returns nothing without authorization" do
      delete :destroy, params: {id: "test.gem"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST download" do
    before(:each) do
      allow(File).to receive(:basename).and_return("test.gem")
      allow(File).to receive(:read).and_return("package content")
      allow(Base64).to receive(:encode64).and_return("encoded_content")
    end

    it "downloads a ruby gem package" do
      allow(OpenC3::GemModel).to receive(:get).and_return("/tmp/test.gem")

      post :download, params: {id: "test.gem", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("test.gem")
      expect(json["contents"]).to eq("encoded_content")
    end

    it "downloads a python package" do
      allow(File).to receive(:basename).and_return("test.whl")
      allow(OpenC3::PythonPackageModel).to receive(:get).and_return("/tmp/test.whl")

      post :download, params: {id: "test.whl", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("test.whl")
      expect(json["contents"]).to eq("encoded_content")
    end

    it "handles errors during download" do
      allow(OpenC3::GemModel).to receive(:get).and_raise(StandardError.new("Download error"))

      post :download, params: {id: "test.gem", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Download error")
    end

    it "returns nothing without authorization" do
      post :download, params: {id: "test.gem"}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
