# encoding: utf-8

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
# All changes Copyright 2023, OpenC3, Inc.
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

  def volumes
    # ENV.map returns a big array of mostly nils which is why we compact
    # The non-nil are MatchData objects due to the regex match
    matches = ENV.map { |key, value| key.match(/^OPENC3_(.+)_VOLUME$/) }.compact
    # MatchData [0] is the full text, [1] is the captured group
    # downcase to make it look nicer, BucketExplorer.vue calls toUpperCase on the API requests
    volumes = matches.map { |match| match[1].downcase }.sort
    # Add a slash prefix to identify volumes separately from buckets
    volumes.map! {|volume| "/#{volume}" }
    render :json => volumes, :status => 200
  end

  def files
    return unless authorization('system')
    root = ENV[params[:root]] # Get the actual bucket / volume name
    raise "Unknown bucket / volume #{params[:root]}" unless root
    results = []
    if params[:root].include?('_BUCKET')
      bucket = OpenC3::Bucket.getClient()
      path = sanitize_path(params[:path])
      path = '/' if path.empty?
      # if user wants metadata returned
      metadata = params[:metadata].present? ? true : false
      results = bucket.list_files(bucket: root, path: path, metadata: metadata)
    elsif params[:root].include?('_VOLUME')
      dirs = []
      files = []
      path = sanitize_path(params[:path])
      list = Dir["/#{root}/#{path}/*"] # Ok for path to be blank
      list.each do |file|
        if File.directory?(file)
          dirs << File.basename(file)
        else
          stat = File.stat(file)
          files << { name: File.basename(file), size: stat.size, modified: stat.mtime }
        end
      end
      results << dirs
      results << files
    else
      raise "Unknown root #{params[:root]}"
    end
    render :json => results, :status => 200
  rescue OpenC3::Bucket::NotFound => error
    render :json => { :status => 'error', :message => error.message }, :status => 404
  rescue Exception => e
    OpenC3::Logger.error("File listing failed: #{e.message}", user: username())
    render :json => { status: 'error', message: e.message }, status: 500
  end

  def download_file
    return unless authorization('system')
    volume = ENV[params[:volume]] # Get the actual volume name
    raise "Unknown volume #{params[:volume]}" unless volume
    filename = "/#{volume}/#{params[:object_id]}"
    filename = sanitize_path(filename)
    file = File.read(filename, mode: 'rb')
    render :json => { filename: params[:object_id], contents: Base64.encode64(file) }
  rescue Exception => e
    OpenC3::Logger.error("Download failed: #{e.message}", user: username())
    render :json => { status: 'error', message: e.message }, status: 500
  end

  def get_download_presigned_request
    return unless authorization('system')
    bucket = OpenC3::Bucket.getClient()
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    bucket.check_object(bucket: bucket_name, key: path)
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: path,
                                      method: :get_object,
                                      internal: params[:internal])
    render :json => result, :status => 201
  rescue Exception => e
    OpenC3::Logger.error("Download request failed: #{e.message}", user: username())
    render :json => { status: 'error', message: e.message }, status: 500
  end

  def get_upload_presigned_request
    return unless authorization('system_set')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')
    # Anywhere other than config/SCOPE/targets_modified requires admin
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && key_split[1] == 'targets_modified')
      return unless authorization('admin')
    end

    bucket = OpenC3::Bucket.getClient()
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: path,
                                      method: :put_object,
                                      internal: params[:internal])
    OpenC3::Logger.info("S3 upload presigned request generated: #{bucket_name}/#{path}",
        scope: params[:scope], user: username())
    render :json => result, :status => 201
  rescue Exception => e
    OpenC3::Logger.error("Upload request failed: #{e.message}", user: username())
    render :json => { status: 'error', message: e.message }, status: 500
  end

  def delete
    return unless authorization('system_set')
    if params[:bucket].presence
      deleteBucketItem(params)
    elsif params[:volume].presence
      deleteVolumeItem(params)
    else
      raise "Must pass bucket or volume parameter!"
    end
    head :ok
  rescue Exception => e
    OpenC3::Logger.error("Delete failed: #{e.message}", user: username())
    render :json => { status: 'error', message: e.message }, status: 500
  end

  private

  def sanitize_path(path)
    return '' if path.nil?
    # path is passed as a parameter thus we have to sanitize it or the code scanner detects:
    # "Uncontrolled data used in path expression"
    # This method is taken directly from the Rails source:
    #   https://api.rubyonrails.org/v5.2/classes/ActiveStorage/Filename.html#method-i-sanitized
    # NOTE: I removed the '/' character because we have to allow this in order to traverse the path
    sanitized = path.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").strip.tr("\u{202E}%$|:;\t\r\n\\", "-").gsub('..', '-')
    if sanitized != path
      raise "Invalid path: #{path}"
    end
    sanitized
  end

  def deleteBucketItem(params)
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')
    # Anywhere other than config/SCOPE/targets_modified requires admin
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && key_split[1] == 'targets_modified')
      return unless authorization('admin')
    end

    if ENV['OPENC3_LOCAL_MODE']
      OpenC3::LocalMode.delete_local(path)
    end

    OpenC3::Bucket.getClient().delete_object(bucket: bucket_name, key: path)
    OpenC3::Logger.info("Deleted: #{bucket_name}/#{path}", scope: params[:scope], user: username())
  end

  def deleteVolumeItem(params)
    # Deleting requires admin
    return unless authorization('admin')
    volume = ENV[params[:volume]] # Get the actual volume name
    raise "Unknown volume #{params[:volume]}" unless volume
    filename = "/#{volume}/#{params[:object_id]}"
    filename = sanitize_path(filename)
    FileUtils.rm filename
    OpenC3::Logger.info("Deleted: #{filename}", scope: params[:scope], user: username())
  end
end
