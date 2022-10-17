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

require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'

class StorageController < ApplicationController
  BUCKET_NAME = 'userdata'

  def get_download_presigned_request
    return unless authorization('system')
    @rubys3_client = Aws::S3::Client.new
    # polls in a loop, sleeping between attempts
    @rubys3_client.wait_until(:object_exists,
      {
        bucket: params[:bucket],
        key: params[:object_id]
      },
      {
        max_attempts: 30,
        delay: 0.1, # seconds
      }
    )
    render :json => get_presigned_request(:get_object), :status => 201
  end

  def get_upload_presigned_request
    return unless authorization('system_set')
    result = get_presigned_request(:put_object)
    OpenC3::Logger.info("S3 upload presigned request generated: #{params[:bucket] || BUCKET_NAME}/#{params[:object_id]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    render :json => result, :status => 201
  end

  def delete
    return unless authorization('system_set')

    # Only allow deleting from targets_modified in config bucket
    raise "Invalid bucket: #{params[:bucket]}" if params[:bucket] != 'config'
    key_split = params[:object_id].to_s.split('/')
    raise "Invalid key: #{params[:object_id]}" if key_split[1] != 'targets_modified'

    if ENV['OPENC3_LOCAL_MODE']
      OpenC3::LocalMode.delete_local(params[:object_id])
    end

    Bucket.getClient.delete_object(bucket: params[:bucket], key: params[:object_id])
    OpenC3::Logger.info("Deleted: #{params[:bucket] || BUCKET_NAME}/#{params[:object_id]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    head :ok
  end

  private

  def get_presigned_request(method)
    bucket = params[:bucket]
    bucket ||= BUCKET_NAME
    Bucket.getClient.create_bucket(bucket)
    s3_presigner = Aws::S3::Presigner.new

    if params[:internal]
      prefix = '/'
    else
      prefix = '/files/'
    end

    url, headers = s3_presigner.presigned_request(
      method, bucket: bucket, key: params[:object_id]
    )
    {
      :url => prefix + url.split('/')[3..-1].join('/'),
      :headers => headers,
      :method => method.to_s.split('_')[0],
    }
  end
end
