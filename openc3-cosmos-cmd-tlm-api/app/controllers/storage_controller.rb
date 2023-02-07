# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'

class StorageController < ApplicationController
  def buckets
    # ENV.map returns a big array of mostly nils which is why we compact
    # The non-nil are MatchData objects due to the regex match
    matches = ENV.map { |key, value| key.match(/^OPENC3_(.+)_BUCKET$/) }.compact
    # MatchData [0] is the full text, [1] is the captured group
    # downcase to make it look nicer, BucketExplorer.vue calls toUpperCase on the API requests
    buckets = matches.map { |match| match[1].downcase }.sort
    render :json => buckets, :status => 200
  end

  def files
    return unless authorization('system')
    bucket = OpenC3::Bucket.getClient()
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    path = params[:path]
    path = '/' if path.nil? || path.empty?
    results = bucket.list_files(bucket: bucket_name, path: path)
    render :json => results, :status => 200
  rescue OpenC3::Bucket::NotFound => error
    render :json => { :status => 'error', :message => error.message }, :status => 404
  end

  def get_download_presigned_request
    return unless authorization('system')
    bucket = OpenC3::Bucket.getClient()
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    bucket.check_object(bucket: bucket_name, key: params[:object_id])
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: params[:object_id],
                                      method: :get_object,
                                      internal: params[:internal])
    render :json => result, :status => 201
  end

  def get_upload_presigned_request
    return unless authorization('system_set')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    key_split = params[:object_id].to_s.split('/')
    # Anywhere other than config/SCOPE/targets_modified requires admin
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && key_split[1] == 'targets_modified')
      return unless authorization('admin')
    end

    bucket = OpenC3::Bucket.getClient()
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: params[:object_id],
                                      method: :put_object,
                                      internal: params[:internal])
    OpenC3::Logger.info("S3 upload presigned request generated: #{bucket_name}/#{params[:object_id]}",
        scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    render :json => result, :status => 201
  end

  def delete
    return unless authorization('system_set')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    key_split = params[:object_id].to_s.split('/')
    # Anywhere other than config/SCOPE/targets_modified requires admin
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && key_split[1] == 'targets_modified')
      return unless authorization('admin')
    end

    if ENV['OPENC3_LOCAL_MODE']
      OpenC3::LocalMode.delete_local(params[:object_id])
    end

    OpenC3::Bucket.getClient().delete_object(bucket: bucket_name, key: params[:object_id])
    OpenC3::Logger.info("Deleted: #{bucket_name}/#{params[:object_id]}",
        scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    head :ok
  end
end
