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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'
begin
  require 'openc3-enterprise/version'
  STORAGE_VERSION = OPENC3_ENTERPRISE_VERSION
rescue LoadError
  require 'openc3/version'
  STORAGE_VERSION = OPENC3_VERSION
end

class StorageController < ApplicationController
  def buckets
    return unless authorization('system')
    # ENV.map returns a big array of mostly nils which is why we compact
    # The non-nil are MatchData objects due to the regex match
    matches = ENV.map { |key, _value| key.match(/^OPENC3_(.+)_BUCKET$/) }.compact
    # MatchData [0] is the full text, [1] is the captured group
    # downcase to make it look nicer, BucketExplorer.vue calls toUpperCase on the API requests
    buckets = matches.map { |match| match[1].downcase }.sort
    render json: buckets
  end

  def volumes
    return unless authorization('system')
    # ENV.map returns a big array of mostly nils which is why we compact
    # The non-nil are MatchData objects due to the regex match
    matches = ENV.map { |key, _value| key.match(/^OPENC3_(.+)_VOLUME$/) }.compact
    # MatchData [0] is the full text, [1] is the captured group
    # downcase to make it look nicer, BucketExplorer.vue calls toUpperCase on the API requests
    volumes = matches.map { |match| match[1].downcase }.sort
    # Add a slash prefix to identify volumes separately from buckets
    volumes.map! {|volume| "/#{volume}" }
    render json: volumes
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
    render json: results
  rescue OpenC3::Bucket::NotFound => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: 404
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("File listing failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  def exists
    return unless authorization('system')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    bucket = OpenC3::Bucket.getClient()
    # Returns true or false if the object is found
    result = bucket.check_object(bucket: bucket_name,
                                 key: path,
                                 retries: false)
    if result
      render json: result
    else
      render json: result, status: 404
    end
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("File exists request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  def download_file
    return unless authorization('system')
    tmp_dir = nil
    if params[:volume]
      volume = ENV[params[:volume]] # Get the actual volume name
      raise "Unknown volume #{params[:volume]}" unless volume
      filename = "/#{volume}/#{params[:object_id]}"
      filename = sanitize_path(filename)
    elsif params[:bucket]
      tmp_dir = Dir.mktmpdir
      bucket_name = ENV[params[:bucket]] # Get the actual bucket name
      raise "Unknown bucket #{params[:bucket]}" unless bucket_name
      path = sanitize_path(params[:object_id])
      filename = File.join(tmp_dir, path)
      # Ensure dir structure exists, get_object fails if not
      FileUtils.mkdir_p(File.dirname(filename))
      OpenC3::Bucket.getClient().get_object(bucket: bucket_name, key: path, path: filename)
    else
      raise "No volume or bucket given"
    end
    file = File.read(filename, mode: 'rb')
    FileUtils.rm_rf(tmp_dir) if tmp_dir

    # Check if CTRF conversion is requested
    if params[:format] == 'ctrf'
      file_content = file.force_encoding('UTF-8')
      ctrf_data = convert_to_ctrf(file_content)
      render json: { filename: "#{File.basename(params[:object_id], '.*')}.ctrf.json", contents: Base64.encode64(ctrf_data.to_json) }
    else
      render json: { filename: params[:object_id], contents: Base64.encode64(file) }
    end
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Download failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  def get_download_presigned_request
    return unless authorization('system')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    bucket = OpenC3::Bucket.getClient()
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: path,
                                      method: :get_object,
                                      internal: params[:internal])
    render json: result, status: 201
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Download request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  def get_upload_presigned_request
    return unless authorization('system_set')
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')
    # Anywhere other than config/SCOPE/targets_modified or config/SCOPE/tmp requires admin
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && (key_split[1] == 'targets_modified' || key_split[1] == 'tmp'))
      return unless authorization('admin')
    end

    bucket = OpenC3::Bucket.getClient()
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: path,
                                      method: :put_object,
                                      internal: params[:internal])
    OpenC3::Logger.info("S3 upload presigned request generated: #{bucket_name}/#{path}",
        scope: params[:scope], user: username())
    render json: result, status: 201
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Upload request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  def delete
    return unless authorization('system_set')
    if params[:bucket].presence
      return unless delete_bucket_item(params)
    elsif params[:volume].presence
      return unless delete_volume_item(params)
    else
      raise "Must pass bucket or volume parameter!"
    end
    head :ok
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Delete failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: 500
  end

  private

  def convert_to_ctrf(report_content)
    lines = report_content.split("\n")
    tests = []
    summary = {}
    settings = {}
    inSettings = false
    lastResult = nil
    inSummary = false

    lines.each do |line|
      line_clean = line.strip

      if line_clean == 'Settings:'
        inSettings = true
        next
      end
      if inSettings
        if line_clean.include?('Manual')
          settings[:manual] = line.split('=')[1].strip
          next
        elsif line_clean.include?('Pause on Error')
          settings[:pauseOnError] = line.split('=')[1].strip
          next
        elsif line_clean.include?('Continue After Error')
          settings[:contineAfterError] = line.split('=')[1].strip
          next
        elsif line_clean.include?('Abort After Error')
          settings[:abortAfterError] = line.split('=')[1].strip
          next
        elsif line_clean.include?('Loop =')
          settings[:loop] = line.split('=')[1].strip
          next
        elsif line_clean.include?('Break Loop On Error')
          settings[:breakLoopOnError] = line.split('=')[1].strip
          inSettings = false
          next
        end
      end

      if line_clean == 'Results:'
        lastResult = line_clean
        next
      end

      if lastResult
        # The first line should always have a timestamp and what it is executing
        if lastResult == 'Results:' and line_clean.include?("Executing")
          summary[:startTime] = DateTime.parse(line_clean.split(':')[0]).to_time.to_f * 1000
          lastResult = line_clean
          next
        end

        if line_clean.include?("PASS") or line_clean.include?("SKIP") or line_clean.include?("FAIL")
          date, time, _example = lastResult.split(' ')
          startTime = DateTime.parse("#{date} #{time}").to_time.to_f * 1000
          date, time, example = line_clean.split(' ')
          suiteGroup, name, status = example.split(':')
          endTime = DateTime.parse("#{date} #{time}").to_time.to_f * 1000
          formatStatus = case status
          when 'PASS'
            'passed'
          when 'SKIP'
            'skipped'
          when 'FAIL'
            'failed'
          end
          tests << {
            name: "#{suiteGroup}:#{name}",
            status: formatStatus,
            duration: endTime - startTime,
          }
          lastResult = line_clean
          next
        end

        if line_clean.include?("Completed")
          summary[:stopTime] = DateTime.parse(line_clean.split(':')[0]).to_time.to_f * 1000
          lastResult = nil
          next
        end
      end

      if line_clean == '--- Test Summary ---'
        inSummary = true
        next
      end

      if inSummary
        if line_clean.include?("Total Tests")
          summary[:total] = line_clean.split(':')[1].to_i
        end
        if line_clean.include?("Pass:")
          summary[:passed] = line_clean.split(':')[1].to_i
        end
        if line_clean.include?("Skip:")
          summary[:skipped] = line_clean.split(':')[1].to_i
        end
        if line_clean.include?("Fail:")
          summary[:failed] = line_clean.split(':')[1].to_i
        end
      end
    end

    # Build CTRF report
    return {
      reportFormat: "CTRF",
      specVersion: "0.0.0",
      results: {
        tool: {
          name: "COSMOS Script Runner",
          version: STORAGE_VERSION,
        },
        summary: {
          tests: summary[:total],
          passed: summary[:passed],
          failed: summary[:failed],
          pending: 0,
          skipped: summary[:skipped],
          other: 0,
          start: summary[:startTime],
          stop: summary[:stopTime],
        },
        tests: tests,
        extra: {
          manual: settings[:manual],
          pauseOnError: settings[:pauseOnError],
          contineAfterError: settings[:contineAfterError],
          abortAfterError: settings[:abortAfterError],
          loop: settings[:loop],
          breakLoopOnError: settings[:breakLoopOnError],
        },
      },
    }
  end

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

  def delete_bucket_item(params)
    bucket_name = ENV[params[:bucket]] # Get the actual bucket name
    raise "Unknown bucket #{params[:bucket]}" unless bucket_name
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')
    # Anywhere other than config/SCOPE/targets_modified or config/SCOPE/tmp requires admin
    authorized = true
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && (key_split[1] == 'targets_modified' || key_split[1] == 'tmp'))
      authorized = false unless authorization('admin')
    end

    if authorized
      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.delete_local(path)
      end

      OpenC3::Bucket.getClient().delete_object(bucket: bucket_name, key: path)
      OpenC3::Logger.info("Deleted: #{bucket_name}/#{path}", scope: params[:scope], user: username())
      return true
    else
      return false
    end
  end

  def delete_volume_item(params)
    # Deleting requires admin
    if authorization('admin')
      volume = ENV[params[:volume]] # Get the actual volume name
      raise "Unknown volume #{params[:volume]}" unless volume
      filename = "/#{volume}/#{params[:object_id]}"
      filename = sanitize_path(filename)
      FileUtils.rm filename
      OpenC3::Logger.info("Deleted: #{filename}", scope: params[:scope], user: username())
      return true
    else
      return false
    end
  end
end
