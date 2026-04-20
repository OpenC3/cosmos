# encoding: utf-8

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

require "rails_helper"
require "openc3/utilities/bucket"

RSpec.describe ToolsBucketController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    allow(controller).to receive(:log_error)
    ENV["OPENC3_TOOLS_BUCKET"] = "tools-bucket"
  end

  # S3 get_object returns a response object. We stub with a struct so the
  # controller can call etag / content_type / cache_control / last_modified / body.read
  def fake_object(body:, etag: '"abc123"', content_type: 'text/html',
                  cache_control: nil, last_modified: Time.utc(2026, 4, 18, 12, 0, 0))
    obj = Struct.new(:body, :etag, :content_type, :cache_control, :last_modified, keyword_init: true)
    obj.new(
      body: StringIO.new(body),
      etag: etag,
      content_type: content_type,
      cache_control: cache_control,
      last_modified: last_modified
    )
  end

  describe "GET show" do
    it "serves the object body with content-type and cache headers" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      expect(bucket).to receive(:get_object)
        .with(bucket: "tools-bucket", key: "base/index.html")
        .and_return(fake_object(body: "<html></html>", content_type: "text/html"))

      get :show, params: { path: "base/index.html", scope: "DEFAULT" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<html></html>")
      expect(response.headers["Content-Type"]).to start_with("text/html")
      expect(response.headers["ETag"]).to eq('"abc123"')
      # Rack normalizes Cache-Control directive order, so compare by token set
      expected_tokens = ToolsBucketController::DEFAULT_CACHE_CONTROL.split(/,\s*/).sort
      expect(response.headers["Cache-Control"].split(/,\s*/).sort).to eq(expected_tokens)
      expect(response.headers["Last-Modified"]).to eq(Time.utc(2026, 4, 18, 12, 0, 0).httpdate)
    end

    it "prefers the bucket-stored Cache-Control when present" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      allow(bucket).to receive(:get_object).and_return(
        fake_object(body: "body", cache_control: "public, max-age=31536000, immutable")
      )

      get :show, params: { path: "base/assets/app-abc.js", scope: "DEFAULT" }

      expect(response.headers["Cache-Control"].split(/,\s*/).sort).to eq(
        ["immutable", "max-age=31536000", "public"]
      )
    end

    it "falls back to mime lookup when content_type is absent" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      allow(bucket).to receive(:get_object).and_return(fake_object(body: "body", content_type: nil))

      get :show, params: { path: "base/app.js", scope: "DEFAULT" }

      expect(response.headers["Content-Type"]).to start_with("text/javascript").or start_with("application/javascript")
    end

    it "returns 304 when If-None-Match matches the object ETag" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      allow(bucket).to receive(:get_object).and_return(fake_object(body: "body", etag: '"abc123"'))

      request.headers["If-None-Match"] = '"abc123"'
      get :show, params: { path: "base/index.html", scope: "DEFAULT" }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(response.headers["ETag"]).to eq('"abc123"')
    end

    it "returns 404 when the key is missing" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      allow(bucket).to receive(:get_object).and_return(nil)

      get :show, params: { path: "missing.js", scope: "DEFAULT" }

      expect(response).to have_http_status(:not_found)
    end

    it "rejects paths containing parent-directory traversal" do
      expect(OpenC3::Bucket).not_to receive(:getClient)

      get :show, params: { path: "base/../secrets.env", scope: "DEFAULT" }

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 503 if the tools bucket env var is missing" do
      ENV.delete("OPENC3_TOOLS_BUCKET")
      get :show, params: { path: "base/index.html", scope: "DEFAULT" }
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns 500 on unexpected errors" do
      bucket = instance_double(OpenC3::Bucket)
      allow(OpenC3::Bucket).to receive(:getClient).and_return(bucket)
      allow(bucket).to receive(:get_object).and_raise(StandardError.new("boom"))

      get :show, params: { path: "base/index.html", scope: "DEFAULT" }

      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
