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

require 'openc3/utilities/bucket'

# Serves objects from the tools bucket when OPENC3_TOOLS_BUCKET_PRIVATE is enabled.
# Traefik's private-tools configuration routes /tools/* here so the bucket ACL can
# stay closed. This endpoint mirrors the historical public-bucket behavior (open reads
# to anyone who can reach traefik) — the security win is the locked-down S3 ACL, not
# per-request auth. All sensitive operations remain gated behind /openc3-api.
class ToolsBucketController < ApplicationController
  DEFAULT_CACHE_CONTROL = 'public, max-age=300'

  def show
    key = params[:path].to_s
    if key.empty? || key.include?('..')
      head :bad_request
      return
    end

    bucket_name = ENV['OPENC3_TOOLS_BUCKET']
    unless bucket_name && !bucket_name.empty?
      head :service_unavailable
      return
    end

    client = OpenC3::Bucket.getClient()
    object = client.get_object(bucket: bucket_name, key: key)
    if object.nil?
      head :not_found
      return
    end

    etag = object.respond_to?(:etag) ? object.etag : nil
    if etag && request.headers['If-None-Match'] == etag
      response.headers['ETag'] = etag
      head :not_modified
      return
    end

    response.headers['ETag'] = etag if etag
    response.headers['Cache-Control'] =
      (object.respond_to?(:cache_control) && object.cache_control.presence) || DEFAULT_CACHE_CONTROL
    if object.respond_to?(:last_modified) && object.last_modified
      response.headers['Last-Modified'] = object.last_modified.httpdate
    end

    content_type = (object.respond_to?(:content_type) && object.content_type.presence) ||
                   Mime::Type.lookup_by_extension(File.extname(key).delete('.'))&.to_s ||
                   'application/octet-stream'

    body = object.body.read
    send_data(body, type: content_type, disposition: 'inline')
  rescue OpenC3::Bucket::NotFound
    head :not_found
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Tools bucket read failed for '#{params[:path]}': #{e.message}", user: username())
    head :internal_server_error
  end
end
