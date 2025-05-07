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
require "openc3/utilities/bucket"
require "openc3/utilities/local_mode"

RSpec.describe StorageController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    allow(controller).to receive(:log_error)

    # Set up environment variables for buckets and volumes
    ENV["OPENC3_CONFIG_BUCKET"] = "config-bucket"
    ENV["OPENC3_LOGS_BUCKET"] = "logs-bucket"
    ENV["OPENC3_TOOLS_BUCKET"] = "tools-bucket"
    ENV["OPENC3_DATA_VOLUME"] = "data-volume"
    ENV["OPENC3_TEMP_VOLUME"] = "temp-volume"
  end

  describe "GET buckets" do
    it "returns a list of buckets" do
      get :buckets, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      buckets = JSON.parse(response.body)
      expect(buckets).to include("config")
      expect(buckets).to include("logs")
      expect(buckets).to include("tools")
    end

    it "returns nothing without authorization" do
      get :buckets
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET volumes" do
    it "returns a list of volumes" do
      get :volumes, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      volumes = JSON.parse(response.body)
      expect(volumes).to include("/data")
      expect(volumes).to include("/temp")
    end

    it "returns nothing without authorization" do
      get :volumes
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET files" do
    it "returns bucket files" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      file_list = [{"Key" => "file1.txt", "Size" => 100, "LastModified" => Time.now}]
      allow(bucket_client).to receive(:list_files).and_return(file_list)

      get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "config", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "returns volume files" do
      # Mock the Dir and File operations
      file1 = "/data-volume/config/file1.txt"
      file2 = "/data-volume/config/dir"

      dir_listing = [file1, file2]
      allow(Dir).to receive(:[]).and_return(dir_listing)
      allow(File).to receive(:directory?).with(file1).and_return(false)
      allow(File).to receive(:directory?).with(file2).and_return(true)
      allow(File).to receive(:basename).with(file1).and_return("file1.txt")
      allow(File).to receive(:basename).with(file2).and_return("dir")

      file_stat = instance_double("File::Stat", size: 100, mtime: Time.now)
      allow(File).to receive(:stat).with(file1).and_return(file_stat)

      get :files, params: {root: "OPENC3_DATA_VOLUME", path: "config", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)

      result = JSON.parse(response.body)
      expect(result[0]).to include("dir")
      expect(result[1][0]["name"]).to eq("file1.txt")
    end

    it "handles not found error" do
      allow(controller).to receive(:authorization).and_return(true)
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:list_files).and_raise(OpenC3::Bucket::NotFound.new("Not found"))

      get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "nonexistent", scope: "DEFAULT"}
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["message"]).to eq("Not found")
    end

    it "handles general errors" do
      allow(controller).to receive(:authorization).and_return(true)
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:list_files).and_raise(StandardError.new("General error"))

      get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "config", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end

    it "returns nothing without authorization" do
      get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "config"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET exists" do
    it "returns true if the object exists" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:check_object).and_return(true)

      get :exists, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(true)
    end

    it "returns 404 if the object doesn't exist" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:check_object).and_return(false)

      get :exists, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "nonexistent.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq(false)
    end

    it "handles errors" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:check_object).and_raise(StandardError.new("General error"))

      get :exists, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end

    it "returns nothing without authorization" do
      get :exists, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET download_file" do
    it "downloads a file from a bucket" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:get_object)
      allow(Dir).to receive(:mktmpdir).and_return("/tmp/dir")
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:rm_rf)
      allow(File).to receive(:read).and_return("file content")
      allow(Base64).to receive(:encode64).and_return("encoded_content")

      get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["filename"]).to eq("file.txt")
      expect(result["contents"]).to eq("encoded_content")
    end

    it "downloads a file from a volume" do
      allow(File).to receive(:read).and_return("file content")
      allow(Base64).to receive(:encode64).and_return("encoded_content")

      get :download_file, params: {volume: "OPENC3_DATA_VOLUME", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["filename"]).to eq("file.txt")
      expect(result["contents"]).to eq("encoded_content")
    end

    it "handles errors" do
      allow(Dir).to receive(:mktmpdir).and_raise(StandardError.new("General error"))

      get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end

    it "returns nothing without authorization" do
      get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET get_download_presigned_request" do
    it "returns a presigned request URL" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      presigned_url = {url: "https://bucket.s3.amazonaws.com/file.txt?signature"}
      allow(bucket_client).to receive(:presigned_request).and_return(presigned_url)

      get :get_download_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["url"]).to eq(presigned_url[:url])
    end

    it "handles errors" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:presigned_request).and_raise(StandardError.new("General error"))

      get :get_download_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end

    it "returns nothing without authorization" do
      get :get_download_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET get_upload_presigned_request" do
    it "returns a presigned upload URL for admin" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      presigned_url = {url: "https://bucket.s3.amazonaws.com/file.txt?signature"}
      allow(bucket_client).to receive(:presigned_request).and_return(presigned_url)

      get :get_upload_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["url"]).to eq(presigned_url[:url])
    end

    it "returns nothing without admin authorization" do
      get :get_upload_presigned_request, params: {
        bucket: "OPENC3_CONFIG_BUCKET",
        object_id: "scope/other_folder/file.txt"
      }
      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)

      allow(bucket_client).to receive(:presigned_request).and_raise(StandardError.new("General error"))

      get :get_upload_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end
  end

  describe "DELETE delete" do
    it "deletes a bucket item with admin authorization" do
      ENV["OPENC3_LOCAL_MODE"] = nil
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
      allow(bucket_client).to receive(:delete_object)

      delete :delete, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "deletes a bucket item with local mode" do
      ENV["OPENC3_LOCAL_MODE"] = "true"
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
      allow(bucket_client).to receive(:delete_object)
      allow(OpenC3::LocalMode).to receive(:delete_local)

      delete :delete, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "deletes a volume item with admin authorization" do
      allow(FileUtils).to receive(:rm)

      delete :delete, params: {volume: "OPENC3_DATA_VOLUME", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
    end

    it "returns nothing without admin authorization for bucket delete" do
      delete :delete, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("")
    end

    it "deletes a targets_modified item without admin authorization" do
      bucket_client = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
      allow(bucket_client).to receive(:delete_object)

      delete :delete, params: {
        bucket: "OPENC3_CONFIG_BUCKET",
        object_id: "scope/targets_modified/file.txt"
      }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns nothing without admin authorization for volume delete" do
      delete :delete, params: {volume: "OPENC3_DATA_VOLUME", object_id: "file.txt"}
      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors" do
      allow(ENV).to receive(:[]).with("OPENC3_CONFIG_BUCKET").and_raise(StandardError.new("General error"))

      delete :delete, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("General error")
    end

    it "requires bucket or volume parameter" do
      delete :delete, params: {object_id: "file.txt", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("Must pass bucket or volume parameter!")
    end
  end
end
