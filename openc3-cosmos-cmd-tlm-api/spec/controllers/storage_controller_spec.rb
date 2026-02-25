# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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

    describe "CTRF conversion" do
      let(:ruby_report) do
        <<~REPORT
          --- Script Report ---

          Settings:
          Manual = true
          Pause on Error = true
          Continue After Error = true
          Abort After Error = false
          Loop = false
          Break Loop On Error = false

          Results:
          2025-11-09T20:34:42.801269Z: Executing MySuite
          2025-11-09T20:34:42.902886Z: MySuite:setup:PASS
          2025-11-09T20:34:43.003754Z: ExampleGroup:setup:PASS
          2025-11-09T20:34:47.350900Z: ExampleGroup:script_2:PASS
            This test verifies requirement 2
          2025-11-09T20:34:47.553037Z: ExampleGroup:script_3:SKIP
            OpenC3::SkipScript
          2025-11-09T20:34:48.501775Z: ExampleGroup:script_run_method_with_long_name:FAIL
            This test verifies requirement 1
            Exceptions:
              RuntimeError : error
              INST/procedures/my_script_suite.rb:12:in `script_run_method_with_long_name'
              <internal:kernel>:187:in `loop'
          2025-11-09T20:34:48.602889Z: ExampleGroup:teardown:PASS
          2025-11-09T20:34:48.603213Z: Completed MySuite

          --- Test Summary ---

          Run Time: 5.80 seconds
          Total Tests: 6
          Pass: 4
          Skip: 1
          Fail: 1
        REPORT
      end

      let (:python_report) do
        <<~REPORT
          --- Script Report ---

          Settings:
          Manual = True
          Pause on Error = True
          Continue After Error = True
          Abort After Error = False
          Loop = False
          Break Loop On Error = False

          Results:
          2025-11-09T20:10:09.354186Z: Executing MySuite
          2025-11-09T20:10:09.454926Z: MySuite:setup:PASS
          2025-11-09T20:10:09.555864Z: ExampleGroup:setup:PASS
          2025-11-09T20:10:14.933055Z: ExampleGroup:script_2:PASS
            This test verifies requirement 2

          2025-11-09T20:10:15.134456Z: ExampleGroup:script_3:SKIP
          2025-11-09T20:10:16.597934Z: ExampleGroup:script_run_method_with_long_name:FAIL
            This test verifies requirement 1

            Exceptions:
          Traceback (most recent call last):
            File "INST2/procedures/my_script_suite.py", line 17, in script_run_method_with_long_name
              from openc3.script.suite_runner import SuiteRunner
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^
          RuntimeError: error

          2025-11-09T20:10:16.698836Z: ExampleGroup:teardown:PASS
          2025-11-09T20:10:16.699300Z: Completed MySuite

          --- Test Summary ---

          Run Time: 7.345119476318359
          Total Tests: 6
          Pass: 4
          Skip: 1
          Fail: 1
        REPORT
      end

      before do
        bucket_client = instance_double(OpenC3::Bucket)
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
        allow(bucket_client).to receive(:get_object)
        allow(Dir).to receive(:mktmpdir).and_return("/tmp/dir")
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_rf)
      end

      it "converts ruby test reports to CTRF format" do
        allow(File).to receive(:read).and_return(ruby_report)

        get :download_file, params: {
          bucket: "OPENC3_LOGS_BUCKET",
          object_id: "test_report.txt",
          format: "ctrf",
          scope: "DEFAULT"
        }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)

        # Verify filename transformation
        expect(result["filename"]).to eq("test_report.ctrf.json")

        # Decode and parse the CTRF content
        ctrf_content = JSON.parse(Base64.decode64(result["contents"]))

        # Verify CTRF structure
        expect(ctrf_content).to have_key("results")

        results = ctrf_content["results"]
        expect(results).to have_key("tool")
        expect(results).to have_key("summary")
        expect(results).to have_key("tests")

        # Verify tool information
        expect(results["tool"]["name"]).to eq("COSMOS Script Runner")

        # Verify summary
        summary = results["summary"]
        expect(summary["tests"]).to eq(6)
        expect(summary["passed"]).to eq(4)
        expect(summary["failed"]).to eq(1)
        expect(summary["skipped"]).to eq(1)
        expect(summary["pending"]).to eq(0)
        expect(summary["other"]).to eq(0)
        expect(summary).to have_key("start")
        expect(summary).to have_key("stop")

        # Verify individual tests
        tests = results["tests"]
        expect(tests.length).to eq(6)

        # Test 1: MySuite:setup
        test = tests[0]
        expect(test["name"]).to eq("MySuite:setup")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10 # Time between executing and setup

        # Test 2: ExampleGroup:setup
        test = tests[1]
        expect(test["name"]).to eq("ExampleGroup:setup")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10 # Time between setup and next setup

        # Test 3: ExampleGroup:script_2
        test = tests[2]
        expect(test["name"]).to eq("ExampleGroup:script_2")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 2000

        # Test 4: ExampleGroup:script_3
        test = tests[3]
        expect(test["name"]).to eq("ExampleGroup:script_3")
        expect(test["status"]).to eq("skipped")
        expect(test["duration"]).to be > 10
        # Test 5: ExampleGroup:script_run_method_with_long_name
        test = tests[4]
        expect(test["name"]).to eq("ExampleGroup:script_run_method_with_long_name")
        expect(test["status"]).to eq("failed")
        expect(test["duration"]).to be > 100

        # Test 6: ExampleGroup:teardown
        test = tests[5]
        expect(test["name"]).to eq("ExampleGroup:teardown")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10
      end

      it "converts python test reports to CTRF format" do
        allow(File).to receive(:read).and_return(python_report)

        get :download_file, params: {
          bucket: "OPENC3_LOGS_BUCKET",
          object_id: "test_report.txt",
          format: "ctrf",
          scope: "DEFAULT"
        }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)

        # Verify filename transformation
        expect(result["filename"]).to eq("test_report.ctrf.json")

        # Decode and parse the CTRF content
        ctrf_content = JSON.parse(Base64.decode64(result["contents"]))

        # Verify CTRF structure
        expect(ctrf_content).to have_key("results")

        results = ctrf_content["results"]
        expect(results).to have_key("tool")
        expect(results).to have_key("summary")
        expect(results).to have_key("tests")

        # Verify tool information
        expect(results["tool"]["name"]).to eq("COSMOS Script Runner")

        # Verify summary
        summary = results["summary"]
        expect(summary["tests"]).to eq(6)
        expect(summary["passed"]).to eq(4)
        expect(summary["failed"]).to eq(1)
        expect(summary["skipped"]).to eq(1)
        expect(summary["pending"]).to eq(0)
        expect(summary["other"]).to eq(0)
        expect(summary).to have_key("start")
        expect(summary).to have_key("stop")

        # Verify individual tests
        tests = results["tests"]
        expect(tests.length).to eq(6)

        # Test 1: MySuite:setup
        test = tests[0]
        expect(test["name"]).to eq("MySuite:setup")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10 # Time between executing and setup

        # Test 2: ExampleGroup:setup
        test = tests[1]
        expect(test["name"]).to eq("ExampleGroup:setup")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10

        # Test 3: ExampleGroup:script_2
        test = tests[2]
        expect(test["name"]).to eq("ExampleGroup:script_2")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 2000

        # Test 4: ExampleGroup:script_3
        test = tests[3]
        expect(test["name"]).to eq("ExampleGroup:script_3")
        expect(test["status"]).to eq("skipped")
        expect(test["duration"]).to be > 10

        # Test 5: ExampleGroup:script_run_method_with_long_name
        test = tests[4]
        expect(test["name"]).to eq("ExampleGroup:script_run_method_with_long_name")
        expect(test["status"]).to eq("failed")
        expect(test["duration"]).to be > 100

        # Test 6: ExampleGroup:teardown
        test = tests[5]
        expect(test["name"]).to eq("ExampleGroup:teardown")
        expect(test["status"]).to eq("passed")
        expect(test["duration"]).to be > 10
      end
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

  describe "POST download_multiple_files" do
    let(:tmp_dir) { "/tmp/test_dir" }
    let(:zip_path) { "#{tmp_dir}/download.zip" }
    let(:zip_data) { "zip file contents" }
    let(:encoded_zip) { Base64.encode64(zip_data) }
    let(:zipfile) { instance_double(Zip::File) }

    before(:each) do
      allow(Dir).to receive(:mktmpdir).and_return(tmp_dir)
      allow(FileUtils).to receive(:rm_rf)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(zip_path, mode: 'rb').and_return(zip_data)
      allow(Base64).to receive(:encode64).with(zip_data).and_return(encoded_zip)
      allow(Zip::File).to receive(:open).with(zip_path, create: true).and_yield(zipfile)
      allow(zipfile).to receive(:add)
    end

    shared_examples "successful download" do |storage_type|
      it "downloads multiple files from a #{storage_type}" do
        post :download_multiple_files, params: params.merge(scope: "DEFAULT")

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["filename"]).to match(/download_\d{8}_\d{6}\.zip/)
        expect(result["contents"]).to eq(encoded_zip)
      end
    end

    context "with bucket" do
      let(:bucket_client) { instance_double(OpenC3::Bucket) }
      let(:params) { { bucket: "OPENC3_CONFIG_BUCKET", path: "test/", files: ["file1.txt", "file2.txt"] } }

      before do
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
        allow(bucket_client).to receive(:get_object)
      end

      include_examples "successful download", "bucket"

      it "handles empty path" do
        post :download_multiple_files, params: { bucket: "OPENC3_CONFIG_BUCKET", files: ["file1.txt"], scope: "DEFAULT" }
        expect(response).to have_http_status(:ok)
        expect(bucket_client).to have_received(:get_object).with(hash_including(key: "file1.txt"))
      end
    end

    context "with volume" do
      let(:params) { { volume: "OPENC3_DATA_VOLUME", path: "test/", files: ["file1.txt", "file2.txt"] } }

      before { allow(File).to receive(:exist?).and_return(true) }

      include_examples "successful download", "volume"
    end

    context "error handling" do
      it "returns errors for invalid input" do
        test_cases = [
          { params: { bucket: "OPENC3_CONFIG_BUCKET", path: "test/", files: [] }, message: "No files specified" },
          { params: { bucket: "OPENC3_CONFIG_BUCKET", path: "test/" }, message: "No files specified" },
          { params: { path: "test/", files: ["file1.txt"] }, message: "No volume or bucket given" }
        ]

        test_cases.each do |test_case|
          post :download_multiple_files, params: test_case[:params].merge(scope: "DEFAULT")
          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)["message"]).to eq(test_case[:message])
        end
      end

      it "returns errors for unknown storage" do
        [
          { bucket: "OPENC3_UNKNOWN_BUCKET", message: "Unknown bucket OPENC3_UNKNOWN_BUCKET" },
          { volume: "OPENC3_UNKNOWN_VOLUME", message: "Unknown volume OPENC3_UNKNOWN_VOLUME" }
        ].each do |test_case|
          storage_key = test_case.keys.first
          allow(ENV).to receive(:[]).with(test_case[storage_key]).and_return(nil)

          post :download_multiple_files, params: test_case.merge(path: "test/", files: ["file1.txt"], scope: "DEFAULT")
          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)["message"]).to eq(test_case[:message])
        end
      end

      it "handles general errors and cleans up" do
        allow(Zip::File).to receive(:open).and_raise(StandardError.new("Zip error"))

        post :download_multiple_files, params: { bucket: "OPENC3_CONFIG_BUCKET", path: "test/", files: ["file1.txt"], scope: "DEFAULT" }

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["message"]).to eq("Zip error")
        expect(FileUtils).to have_received(:rm_rf).with(tmp_dir)
      end
    end

    it "requires authorization" do
      post :download_multiple_files, params: { bucket: "OPENC3_CONFIG_BUCKET", path: "test/", files: ["file1.txt"] }
      expect(response).to have_http_status(:unauthorized)
    end

    it "generates timestamped zip filenames" do
      allow(OpenC3::Bucket).to receive(:getClient).and_return(instance_double(OpenC3::Bucket, get_object: nil))
      allow(Time).to receive(:now).and_return(Time.new(2025, 11, 20, 15, 30, 45))

      post :download_multiple_files, params: { bucket: "OPENC3_CONFIG_BUCKET", path: "test/", files: ["file1.txt"], scope: "DEFAULT" }

      expect(JSON.parse(response.body)["filename"]).to eq("download_20251120_153045.zip")
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
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENC3_CONFIG_BUCKET").and_raise(StandardError.new("General error"))

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

  describe "DELETE delete_directory" do
    describe "bucket directory deletion" do
      let(:bucket_client) { instance_double(OpenC3::Bucket) }

      before do
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
      end

      it "deletes a bucket directory with admin authorization" do
        ENV["OPENC3_LOCAL_MODE"] = nil
        objects = [
          double(key: "scope/targets_modified/INST/file1.txt"),
          double(key: "scope/targets_modified/INST/file2.txt"),
        ]
        allow(bucket_client).to receive(:list_objects).and_return(objects)
        allow(bucket_client).to receive(:delete_objects)

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(2)
      end

      it "deletes an empty directory and returns 0 count" do
        allow(bucket_client).to receive(:list_objects).and_return([])

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/EMPTY", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(0)
      end

      it "deletes directory in batches for large directories" do
        ENV["OPENC3_LOCAL_MODE"] = nil
        # Create 1500 objects to test batching
        objects = (1..1500).map { |i| double(key: "scope/targets_modified/INST/file#{i}.txt") }
        allow(bucket_client).to receive(:list_objects).and_return(objects)
        allow(bucket_client).to receive(:delete_objects)

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(1500)
        # Should have been called twice (1000 + 500)
        expect(bucket_client).to have_received(:delete_objects).twice
      end

      it "handles local mode for bucket directories" do
        ENV["OPENC3_LOCAL_MODE"] = "true"
        objects = [double(key: "scope/targets_modified/INST/file1.txt")]
        allow(bucket_client).to receive(:list_objects).and_return(objects)
        allow(bucket_client).to receive(:delete_objects)
        allow(OpenC3::LocalMode).to receive(:delete_local)

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        expect(OpenC3::LocalMode).to have_received(:delete_local).with("scope/targets_modified/INST/file1.txt")
      end

      it "requires admin for most bucket directories" do
        # Non-targets_modified or tmp directories require admin
        # Without admin auth, it returns unauthorized (handled by authorization method)
        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets/INST"}
        expect(response).to have_http_status(:unauthorized)
      end

      it "allows non-admin for targets_modified directories" do
        objects = [double(key: "scope/targets_modified/INST/file1.txt")]
        allow(bucket_client).to receive(:list_objects).and_return(objects)
        allow(bucket_client).to receive(:delete_objects)

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(1)
      end

      it "allows non-admin for tmp directories" do
        objects = [double(key: "scope/tmp/tempfile.txt")]
        allow(bucket_client).to receive(:list_objects).and_return(objects)
        allow(bucket_client).to receive(:delete_objects)

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/tmp", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(1)
      end

      it "returns 403 for unauthorized scope" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "SCOPE2/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["message"]).to eq("Not authorized for scope: SCOPE2")
      end

      it "returns nothing without authorization" do
        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST"}
        expect(response).to have_http_status(:unauthorized)
      end

      it "handles errors" do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("OPENC3_CONFIG_BUCKET").and_raise(StandardError.new("General error"))

        delete :delete_directory, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "scope/targets_modified/INST", scope: "DEFAULT"}
        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)["message"]).to eq("General error")
      end
    end

    describe "volume directory deletion" do
      it "deletes a volume directory with admin authorization" do
        allow(File).to receive(:directory?).and_return(true)
        allow(Dir).to receive(:glob).and_return(["/data-volume/test/file1.txt", "/data-volume/test/file2.txt"])
        allow(File).to receive(:file?).and_return(true)
        allow(FileUtils).to receive(:rm_rf)

        delete :delete_directory, params: {volume: "OPENC3_DATA_VOLUME", object_id: "test", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["deleted_count"]).to eq(2)
      end

      it "returns 400 for non-directory path on volume" do
        allow(File).to receive(:directory?).and_return(false)

        delete :delete_directory, params: {volume: "OPENC3_DATA_VOLUME", object_id: "file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["message"]).to eq("Not a directory: file.txt")
      end

      it "returns nothing without admin authorization for volume delete" do
        delete :delete_directory, params: {volume: "OPENC3_DATA_VOLUME", object_id: "test"}
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "requires bucket or volume parameter" do
      delete :delete_directory, params: {object_id: "test", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("Must pass bucket or volume parameter!")
    end
  end

  describe "RBAC enforcement" do
    describe "bucket_requires_rbac?" do
      it "returns false for tools bucket" do
        expect(controller.send(:bucket_requires_rbac?, 'OPENC3_TOOLS_BUCKET')).to be false
      end

      it "returns true for config bucket" do
        expect(controller.send(:bucket_requires_rbac?, 'OPENC3_CONFIG_BUCKET')).to be true
      end

      it "returns true for logs bucket" do
        expect(controller.send(:bucket_requires_rbac?, 'OPENC3_LOGS_BUCKET')).to be true
      end

      it "returns true for unknown buckets" do
        expect(controller.send(:bucket_requires_rbac?, 'OPENC3_UNKNOWN_BUCKET')).to be true
      end
    end

    describe "extract_scope_from_path" do
      it "returns nil for empty path" do
        expect(controller.send(:extract_scope_from_path, '')).to be_nil
        expect(controller.send(:extract_scope_from_path, nil)).to be_nil
        expect(controller.send(:extract_scope_from_path, '/')).to be_nil
      end

      it "extracts scope from path" do
        expect(controller.send(:extract_scope_from_path, 'DEFAULT/targets/INST')).to eq('DEFAULT')
        expect(controller.send(:extract_scope_from_path, '/DEFAULT/targets/INST')).to eq('DEFAULT')
        expect(controller.send(:extract_scope_from_path, 'SCOPE1/logs/20251220')).to eq('SCOPE1')
      end
    end

    describe "extract_target_from_path" do
      it "returns nil for paths without target" do
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', '')).to be_nil
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT')).to be_nil
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets')).to be_nil
      end

      it "extracts target from config bucket paths" do
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets/INST')).to eq('INST')
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets/INST/cmd_tlm')).to eq('INST')
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets_modified/INST2/screens')).to eq('INST2')
        expect(controller.send(:extract_target_from_path, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/target_archives/INST/20251220')).to eq('INST')
      end

      it "extracts target from logs bucket paths" do
        expect(controller.send(:extract_target_from_path, 'OPENC3_LOGS_BUCKET', 'DEFAULT/decom_logs/tlm/INST')).to eq('INST')
        expect(controller.send(:extract_target_from_path, 'OPENC3_LOGS_BUCKET', 'DEFAULT/raw_logs/cmd/INST/20251220')).to eq('INST')
      end

      it "returns nil for non-target paths in logs bucket" do
        expect(controller.send(:extract_target_from_path, 'OPENC3_LOGS_BUCKET', 'DEFAULT/text_logs/messages')).to be_nil
      end
    end

    describe "target_list_depth" do
      it "returns 2 for config bucket target directories" do
        expect(controller.send(:target_list_depth, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets')).to eq(2)
        expect(controller.send(:target_list_depth, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets_modified')).to eq(2)
        expect(controller.send(:target_list_depth, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/target_archives')).to eq(2)
      end

      it "returns 3 for logs bucket target directories" do
        expect(controller.send(:target_list_depth, 'OPENC3_LOGS_BUCKET', 'DEFAULT/decom_logs/tlm')).to eq(3)
        expect(controller.send(:target_list_depth, 'OPENC3_LOGS_BUCKET', 'DEFAULT/raw_logs/cmd')).to eq(3)
      end

      it "returns nil for non-target listing paths" do
        expect(controller.send(:target_list_depth, 'OPENC3_CONFIG_BUCKET', 'DEFAULT')).to be_nil
        expect(controller.send(:target_list_depth, 'OPENC3_CONFIG_BUCKET', 'DEFAULT/targets/INST')).to be_nil
        expect(controller.send(:target_list_depth, 'OPENC3_LOGS_BUCKET', 'DEFAULT/text_logs')).to be_nil
      end
    end

    describe "GET files with RBAC" do
      let(:bucket_client) { instance_double(OpenC3::Bucket) }

      before do
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
      end

      it "allows access to tools bucket without scope check" do
        allow(bucket_client).to receive(:list_files).and_return([['dir1'], []])

        get :files, params: {root: "OPENC3_TOOLS_BUCKET", path: "somepath", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
      end

      it "filters scopes at bucket root for config bucket" do
        # At root level, returns list of scopes
        allow(bucket_client).to receive(:list_files).and_return([['DEFAULT', 'SCOPE2', 'SCOPE3'], []])

        # Mock authorize to only allow DEFAULT scope
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "/", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)

        result = JSON.parse(response.body)
        # Only DEFAULT should be returned
        expect(result[0]).to eq(['DEFAULT'])
      end

      it "returns 403 when accessing unauthorized scope in config bucket" do
        # Mock authorize to reject non-DEFAULT scopes
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "SCOPE2/targets", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["message"]).to eq("Not authorized for scope: SCOPE2")
      end

      it "allows access to authorized scope in config bucket" do
        allow(bucket_client).to receive(:list_files).and_return([['targets', 'targets_modified'], []])

        get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "DEFAULT/", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
      end

      it "filters targets when listing target directory" do
        # Listing DEFAULT/targets/ should filter targets based on authorization
        allow(bucket_client).to receive(:list_files).and_return([['INST', 'INST2', 'SYSTEM'], []])

        # Mock authorize to only allow INST target with tlm permission
        allow(controller).to receive(:authorize) do |args|
          # Allow system permission for scope-level access, tlm permission for INST target only
          if args[:permission] == 'system' && args[:target_name].nil?
            'authorized_user'
          elsif args[:permission] == 'tlm' && args[:target_name] == 'INST'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for target: #{args[:target_name]}")
          end
        end

        get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "DEFAULT/targets", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)

        result = JSON.parse(response.body)
        # Only INST should be returned
        expect(result[0]).to eq(['INST'])
      end

      it "returns 403 when accessing unauthorized target files" do
        # Mock authorize to reject INST2 target (user only has tlm permission for INST)
        allow(controller).to receive(:authorize) do |args|
          if args[:permission] == 'system' && args[:target_name].nil?
            'authorized_user'
          elsif args[:permission] == 'tlm' && args[:target_name] == 'INST'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for target: #{args[:target_name]}")
          end
        end

        get :files, params: {root: "OPENC3_CONFIG_BUCKET", path: "DEFAULT/targets/INST2/cmd_tlm", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
      end

      it "filters targets in logs bucket decom_logs directory" do
        allow(bucket_client).to receive(:list_files).and_return([['INST', 'INST2'], []])

        # Mock authorize to only allow INST target with tlm permission
        allow(controller).to receive(:authorize) do |args|
          if args[:permission] == 'system' && args[:target_name].nil?
            'authorized_user'
          elsif args[:permission] == 'tlm' && args[:target_name] == 'INST'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for target: #{args[:target_name]}")
          end
        end

        get :files, params: {root: "OPENC3_LOGS_BUCKET", path: "DEFAULT/decom_logs/tlm", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)

        result = JSON.parse(response.body)
        expect(result[0]).to eq(['INST'])
      end
    end

    describe "GET download_file with RBAC" do
      it "returns 403 for unauthorized scope in config bucket" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "SCOPE2/targets/INST/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 for unauthorized target in config bucket" do
        # User has tlm permission for INST only
        allow(controller).to receive(:authorize) do |args|
          if args[:permission] == 'system' && args[:target_name].nil?
            'authorized_user'
          elsif args[:permission] == 'tlm' && args[:target_name] == 'INST'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for target: #{args[:target_name]}")
          end
        end

        get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "DEFAULT/targets/INST2/cmd_tlm/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
      end

      it "allows download from authorized target" do
        bucket_client = instance_double(OpenC3::Bucket)
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
        allow(bucket_client).to receive(:get_object)
        allow(Dir).to receive(:mktmpdir).and_return("/tmp/dir")
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_rf)
        allow(File).to receive(:read).and_return("file content")

        # Mock authorize to allow INST target with tlm permission
        allow(controller).to receive(:authorize) do |args|
          if args[:permission] == 'system' && args[:target_name].nil?
            'authorized_user'
          elsif args[:permission] == 'tlm' && args[:target_name] == 'INST'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for target: #{args[:target_name]}")
          end
        end

        get :download_file, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "DEFAULT/targets/INST/cmd_tlm/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
      end

      it "allows download from tools bucket without scope check" do
        bucket_client = instance_double(OpenC3::Bucket)
        allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket_client)
        allow(bucket_client).to receive(:get_object)
        allow(Dir).to receive(:mktmpdir).and_return("/tmp/dir")
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:rm_rf)
        allow(File).to receive(:read).and_return("file content")

        get :download_file, params: {bucket: "OPENC3_TOOLS_BUCKET", object_id: "tool/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET exists with RBAC" do
      it "returns 403 for unauthorized scope in logs bucket" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        get :exists, params: {bucket: "OPENC3_LOGS_BUCKET", object_id: "SCOPE2/20251220/log.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["message"]).to eq("Not authorized for scope: SCOPE2")
      end
    end

    describe "GET get_download_presigned_request with RBAC" do
      it "returns 403 for unauthorized scope" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        get :get_download_presigned_request, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "SCOPE2/targets/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST download_multiple_files with RBAC" do
      it "returns 403 for unauthorized scope" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        post :download_multiple_files, params: {bucket: "OPENC3_CONFIG_BUCKET", path: "SCOPE2/targets/", files: ["file1.txt"], scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "DELETE delete with RBAC" do
      it "returns 403 for unauthorized scope in config bucket" do
        allow(controller).to receive(:authorize) do |args|
          if args[:scope] == 'DEFAULT'
            'authorized_user'
          else
            raise OpenC3::ForbiddenError.new("Not authorized for scope: #{args[:scope]}")
          end
        end

        delete :delete, params: {bucket: "OPENC3_CONFIG_BUCKET", object_id: "SCOPE2/targets_modified/file.txt", scope: "DEFAULT"}
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["message"]).to eq("Not authorized for scope: SCOPE2")
      end
    end
  end
end
