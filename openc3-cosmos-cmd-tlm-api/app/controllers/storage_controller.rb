# encoding: utf-8

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'
require 'openc3/utilities/ctrf'
require 'openc3/utilities/questdb_client'
require 'openc3/utilities/reingest_job'
require 'openc3/logs/packet_log_reader'
require 'openc3/models/reingest_job_model'
require 'openc3/topics/telemetry_topic'
require 'fileutils'
require 'securerandom'
begin
  require 'openc3-enterprise/version'
  STORAGE_VERSION = OPENC3_ENTERPRISE_VERSION
rescue LoadError
  require 'openc3/version'
  STORAGE_VERSION = OPENC3_VERSION
end

class StorageController < ApplicationController
  class StorageError < StandardError; end

  # Check if a bucket requires RBAC (config and logs do, tools does not)
  def bucket_requires_rbac?(bucket_param)
    # Tools bucket is accessible to all users with system permission
    return false if bucket_param == 'OPENC3_TOOLS_BUCKET'
    # Config and logs buckets require scope-based RBAC
    return true if bucket_param == 'OPENC3_CONFIG_BUCKET' || bucket_param == 'OPENC3_LOGS_BUCKET'
    # Default to requiring RBAC for unknown buckets
    true
  end

  # Extract the scope from a bucket path (first component)
  # Returns nil if path is empty or at bucket root
  def extract_scope_from_path(path)
    return nil if path.nil? || path.empty? || path == '/'
    parts = path.split('/').reject(&:empty?)
    return nil if parts.empty?
    parts[0]
  end

  # Directories in the config bucket that contain target subdirectories
  CONFIG_TARGET_DIRECTORIES = ['targets', 'targets_modified', 'target_archives'].freeze

  # Extract the target name from a bucket path based on known path patterns
  # Config bucket: {SCOPE}/targets/{TARGET_NAME}/... or {SCOPE}/targets_modified/{TARGET_NAME}/... or {SCOPE}/target_archives/{TARGET_NAME}/...
  # Logs bucket: {SCOPE}/raw_logs/{tlm|cmd}/{TARGET_NAME}/...
  # Returns nil if target cannot be determined from the path
  def extract_target_from_path(bucket_param, path)
    return nil if path.nil? || path.empty?
    parts = path.split('/').reject(&:empty?)
    return nil if parts.length < 3 # Need at least scope/folder/target

    if bucket_param == 'OPENC3_CONFIG_BUCKET'
      # Config bucket: {SCOPE}/targets/{TARGET_NAME}/... or {SCOPE}/targets_modified/{TARGET_NAME}/... or {SCOPE}/target_archives/{TARGET_NAME}/...
      if CONFIG_TARGET_DIRECTORIES.include?(parts[1])
        return parts[2] if parts.length >= 3
      end
    elsif bucket_param == 'OPENC3_LOGS_BUCKET'
      # Logs bucket: {SCOPE}/{type}_logs/{tlm|cmd}/{TARGET_NAME}/...
      # Examples: DEFAULT/decom_logs/tlm/INST/..., DEFAULT/raw_logs/cmd/INST/...
      if parts[1] =~ /_logs$/ && (parts[2] == 'tlm' || parts[2] == 'cmd')
        return parts[3] if parts.length >= 4
      end
    end
    nil
  end

  # Get the path depth where targets are listed (for filtering)
  # Returns the index in the path parts array where target names appear
  def target_list_depth(bucket_param, path)
    return nil if path.nil? || path.empty?
    parts = path.split('/').reject(&:empty?)

    if bucket_param == 'OPENC3_CONFIG_BUCKET'
      # Targets are listed at depth 2: {SCOPE}/targets/ or {SCOPE}/targets_modified/ or {SCOPE}/target_archives/
      if parts.length == 2 && CONFIG_TARGET_DIRECTORIES.include?(parts[1])
        return 2
      end
    elsif bucket_param == 'OPENC3_LOGS_BUCKET'
      # Targets are listed at depth 3: {SCOPE}/{type}_logs/{tlm|cmd}/
      if parts.length == 3 && parts[1] =~ /_logs$/ && (parts[2] == 'tlm' || parts[2] == 'cmd')
        return 3
      end
    end
    nil
  end

  # Authorize access to a bucket path based on scope and optionally target
  # Returns true if authorized, false otherwise
  # For tools bucket: always authorized (with basic system permission)
  # For config/logs buckets: checks if user has access to the scope and target in the path
  # When a target is in the path, uses 'tlm' permission as the baseline for access
  def authorize_bucket_path(bucket_param, path, permission: 'system')
    # Tools bucket doesn't require scope-based RBAC
    return true unless bucket_requires_rbac?(bucket_param)

    # Extract scope from the path
    path_scope = extract_scope_from_path(path)

    # If no scope in path (listing root), allow listing - filtering happens in the method
    return true if path_scope.nil?

    # Extract target from the path (may be nil if not at target level)
    target_name = extract_target_from_path(bucket_param, path)

    # When accessing target-specific paths, use 'tlm' permission as the baseline
    # since most bucket files are telemetry-related (logs, configs)
    effective_permission = target_name ? 'tlm' : permission

    # Check authorization for the specific scope (and target if present) in the path
    begin
      authorize(
        permission: effective_permission,
        target_name: target_name,
        scope: path_scope,
        token: request.headers['HTTP_AUTHORIZATION'],
      )
      return true
    rescue OpenC3::AuthError, OpenC3::ForbiddenError
      return false
    end
  end

  # Filter a list of targets based on user authorization
  # Uses 'tlm' permission as the baseline for target access since most bucket
  # files are telemetry-related (logs, configs). Users who can view telemetry
  # for a target should be able to browse that target's bucket files.
  def filter_authorized_targets(targets, scope, permission: 'tlm')
    targets.select do |target_name|
      begin
        authorize(
          permission: permission,
          target_name: target_name,
          scope: scope,
          token: request.headers['HTTP_AUTHORIZATION'],
        )
        true
      rescue OpenC3::AuthError, OpenC3::ForbiddenError
        false
      end
    end
  end

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
    root = ENV.fetch(params[:root]) { |name| raise StorageError, "Unknown bucket / volume #{name}" }
    results = []
    if params[:root].include?('_BUCKET')
      bucket = OpenC3::Bucket.getClient()
      path = sanitize_path(params[:path])
      path = '/' if path.empty?

      # Check scope-based RBAC for config and logs buckets
      if bucket_requires_rbac?(params[:root])
        path_scope = extract_scope_from_path(path)
        if path_scope
          # Accessing a specific scope - verify authorization
          unless authorize_bucket_path(params[:root], path)
            render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
            return
          end
        end
        # If at root level (no scope), we'll filter the results below
      end

      # if user wants metadata returned
      metadata = params[:metadata].present? ? true : false
      results = bucket.list_files(bucket: root, path: path, metadata: metadata)

      # Filter results based on RBAC
      if bucket_requires_rbac?(params[:root])
        if path == '/' || path.empty?
          # At bucket root level - filter to only show scopes the user has access to
          # results[0] contains directories (scopes at root level)
          if results[0].is_a?(Array)
            results[0] = results[0].select do |dir_name|
              begin
                authorize(
                  permission: 'system',
                  scope: dir_name,
                  token: request.headers['HTTP_AUTHORIZATION'],
                )
                true
              rescue OpenC3::AuthError, OpenC3::ForbiddenError
                false
              end
            end
          end
        else
          # Check if we're at a target listing level and filter targets
          target_depth = target_list_depth(params[:root], path)
          if target_depth && results[0].is_a?(Array)
            path_scope = extract_scope_from_path(path)
            results[0] = filter_authorized_targets(results[0], path_scope)
          end
        end
      end
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
      raise StorageError, "Unknown root #{params[:root]}"
    end
    render json: results
  rescue OpenC3::Bucket::NotFound => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :not_found
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("File listing failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def exists
    return unless authorization('system')
    params.require(:bucket)
    bucket_name = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }
    path = sanitize_path(params[:object_id])

    # Check scope-based RBAC for config and logs buckets
    if bucket_requires_rbac?(params[:bucket])
      unless authorize_bucket_path(params[:bucket], path)
        path_scope = extract_scope_from_path(path)
        render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
        return
      end
    end

    bucket = OpenC3::Bucket.getClient()
    # Returns true or false if the object is found
    result = bucket.check_object(bucket: bucket_name,
                                 key: path,
                                 retries: false)
    if result
      render json: result
    else
      render json: result, status: :not_found
    end
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("File exists request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def download_file
    return unless authorization('system')
    tmp_dir = nil

    begin
      storage_type, storage_name = validate_storage_source
      object_id = sanitize_path(params[:object_id])

      # Check scope-based RBAC for bucket downloads
      if storage_type == :bucket && params[:bucket] && bucket_requires_rbac?(params[:bucket])
        unless authorize_bucket_path(params[:bucket], object_id)
          path_scope = extract_scope_from_path(object_id)
          render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
          return
        end
      end

      filename = if storage_type == :volume
        sanitize_path("/#{storage_name}/#{object_id}")
      else
        tmp_dir = Dir.mktmpdir
        temp_path = File.join(tmp_dir, object_id)
        FileUtils.mkdir_p(File.dirname(temp_path))
        OpenC3::Bucket.getClient().get_object(bucket: storage_name, key: object_id, path: temp_path)
        temp_path
      end

      file = File.read(filename, mode: 'rb')

      # Check if CTRF conversion is requested
      if params[:format] == 'ctrf'
        file_content = file.force_encoding('UTF-8')
        ctrf_data = OpenC3::Ctrf.convert_report(file_content, version: STORAGE_VERSION)
        render json: { filename: "#{File.basename(params[:object_id], '.*')}.ctrf.json", contents: Base64.encode64(ctrf_data.to_json) }
      else
        render json: { filename: params[:object_id], contents: Base64.encode64(file) }
      end
    rescue Exception => e
      log_error(e)
      OpenC3::Logger.error("Download failed: #{e.message}", user: username())
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    ensure
      FileUtils.remove_entry_secure(tmp_dir, true) if tmp_dir
    end
  end

  def download_multiple_files
    return unless authorization('system')
    tmp_dir = Dir.mktmpdir
    zip_path = File.join(tmp_dir, 'download.zip')

    begin
      files = params[:files] || []
      raise StorageError, "No files specified" if files.empty?

      path = sanitize_path(params[:path] || '')
      storage_type, storage_name = validate_storage_source

      # Check scope-based RBAC for bucket downloads
      if storage_type == :bucket && params[:bucket] && bucket_requires_rbac?(params[:bucket])
        unless authorize_bucket_path(params[:bucket], path)
          path_scope = extract_scope_from_path(path)
          render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
          return
        end
      end

      # Create zip file with files from storage
      Zip::File.open(zip_path, create: true) do |zipfile|
        if storage_type == :volume
          add_volume_files_to_zip(zipfile, storage_name, path, files)
        else
          add_bucket_files_to_zip(zipfile, storage_name, path, files, tmp_dir)
        end
      end

      # Read the zip file and encode it
      zip_data = File.read(zip_path, mode: 'rb')
      zip_filename = "download_#{Time.now.strftime('%Y%m%d_%H%M%S')}.zip"

      render json: { filename: zip_filename, contents: Base64.encode64(zip_data) }
    rescue Exception => e
      log_error(e)
      OpenC3::Logger.error("Multiple file download failed: #{e.message}", user: username())
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    ensure
      FileUtils.remove_entry_secure(tmp_dir, true) if tmp_dir
    end
  end

  def get_download_presigned_request
    return unless authorization('system')
    params.require(:bucket)
    bucket_name = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }
    path = sanitize_path(params[:object_id])

    # Check scope-based RBAC for config and logs buckets
    if bucket_requires_rbac?(params[:bucket])
      unless authorize_bucket_path(params[:bucket], path)
        path_scope = extract_scope_from_path(path)
        render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
        return
      end
    end

    bucket = OpenC3::Bucket.getClient()
    result = bucket.presigned_request(bucket: bucket_name,
                                      key: path,
                                      method: :get_object,
                                      internal: params[:internal])
    render json: result, status: :created
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Download request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def get_upload_presigned_request
    return unless authorization('system_set')
    params.require(:bucket)
    bucket_name = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')

    # Check scope-based RBAC for config and logs buckets
    if bucket_requires_rbac?(params[:bucket])
      unless authorize_bucket_path(params[:bucket], path, permission: 'system_set')
        path_scope = extract_scope_from_path(path)
        render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
        return
      end
    end

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
    render json: result, status: :created
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Upload request failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
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
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def delete_directory
    return unless authorization('system_set')
    if params[:bucket].presence
      return unless delete_bucket_directory(params)
    elsif params[:volume].presence
      return unless delete_volume_directory(params)
    else
      raise StorageError, "Must pass bucket or volume parameter!"
    end
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Delete directory failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def reingest_files
    return unless authorization('admin')

    files = params[:files] || []
    raise StorageError, "No files specified" if files.empty?

    invalid = files.reject { |f| f.end_with?('.bin.gz') }
    raise StorageError, "Only .bin.gz files can be reingested: #{invalid.join(', ')}" if invalid.any?

    # Reject path traversal, absolute paths, or null bytes in filenames before
    # they reach the job's temp-file layout. sanitize_path already rejects '..'.
    files = files.map do |f|
      raise StorageError, "Invalid filename: #{f}" if f.to_s.empty? || f.to_s.start_with?('/') || f.to_s.include?("\0")
      sanitize_path(f)
    end

    path = sanitize_path(params[:path] || '')
    storage_type, _storage_name = validate_storage_source
    raise StorageError, "Reingest only supported for buckets" unless storage_type == :bucket

    scope = params[:scope] || 'DEFAULT'

    if params[:bucket] && bucket_requires_rbac?(params[:bucket]) && !authorize_bucket_path(params[:bucket], path)
      path_scope = extract_scope_from_path(path)
      render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
      return
    end

    target_version = params[:target_version].to_s
    target_version = 'as_logged' if target_version.empty?
    unless %w[as_logged current].include?(target_version) || target_version.match?(/\A[a-f0-9]{32,}\z/)
      raise StorageError, "Invalid target_version: #{target_version}"
    end

    job_id = SecureRandom.uuid
    job = OpenC3::ReingestJobModel.new(
      name: job_id,
      files: files,
      bucket: params[:bucket],
      path: path,
      target_version: target_version,
      scope: scope,
    )
    job.create

    Thread.new do
      begin
        OpenC3::ReingestJob.new(
          job_id: job_id,
          files: files,
          path: path,
          bucket: params[:bucket],
          scope: scope,
          target_version: target_version,
        ).run
      rescue Exception => e
        OpenC3::Logger.error("Reingest job #{job_id} thread died: #{e.formatted}", user: username())
      end
    end

    OpenC3::Logger.info("Reingest job #{job_id} enqueued: #{files.length} file(s)", user: username())
    render json: { job_id: job_id, state: 'Queued' }, status: :accepted
  rescue Exception => e
    log_error(e)
    OpenC3::Logger.error("Reingest enqueue failed: #{e.message}", user: username())
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def reingest_status
    return unless authorization('admin')
    scope = params[:scope] || 'DEFAULT'
    job = OpenC3::ReingestJobModel.get_model(name: params[:job_id], scope: scope)
    if job.nil?
      render json: { status: 'error', message: "Reingest job not found: #{params[:job_id]}" }, status: :not_found
      return
    end
    render json: job.as_json, status: :ok
  rescue Exception => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def repair_candidates
    return unless authorization('admin')
    scope = params[:scope] || 'DEFAULT'
    target = params[:target].to_s
    cmd_or_tlm = (params[:cmd_or_tlm] || 'TLM').to_s.upcase
    raise StorageError, "cmd_or_tlm must be TLM (CMD repair not yet supported)" unless cmd_or_tlm == 'TLM'
    raise StorageError, "target is required" if target.empty?

    start_time = parse_repair_time(params[:start_time])
    end_time = parse_repair_time(params[:end_time])

    bucket_env = 'OPENC3_LOGS_BUCKET'
    bucket_name = ENV.fetch(bucket_env) { |n| raise StorageError, "Unknown bucket #{n}" }
    prefix = "#{scope}/raw_logs/tlm/#{target}"

    if bucket_requires_rbac?(bucket_env) && !authorize_bucket_path(bucket_env, "#{prefix}/")
      render json: { status: 'error', message: "Not authorized for scope: #{scope}" }, status: :forbidden
      return
    end

    keys = OpenC3::BucketUtilities.files_between_time(
      bucket_name, prefix, start_time, end_time,
      file_suffix: '.bin.gz', overlap: true,
    )

    files = keys.map do |key|
      basename = key.split('/').last
      { 'key' => key, 'filename' => basename }
    end

    render json: {
      bucket: bucket_env,
      path: "#{prefix}/",
      files: files,
    }, status: :ok
  rescue Exception => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
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
      raise StorageError, "Invalid path: #{path}"
    end
    sanitized
  end

  def delete_bucket_item(params)
    params.require(:bucket)
    bucket_name = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }
    path = sanitize_path(params[:object_id])
    key_split = path.split('/')

    # Check scope-based RBAC for config and logs buckets
    if bucket_requires_rbac?(params[:bucket])
      unless authorize_bucket_path(params[:bucket], path, permission: 'system_set')
        path_scope = extract_scope_from_path(path)
        render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
        return false
      end
    end

    # Anywhere other than config/SCOPE/targets_modified or config/SCOPE/tmp requires admin
    authorized = true
    if !(params[:bucket] == 'OPENC3_CONFIG_BUCKET' && (key_split[1] == 'targets_modified' || key_split[1] == 'tmp'))
      authorized = false unless authorization('admin')
    end

    if authorized
      if ENV.fetch('OPENC3_LOCAL_MODE', false)
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
      volume = ENV.fetch(params[:volume]) { |name| raise StorageError, "Unknown volume #{name}" }
      filename = "/#{volume}/#{params[:object_id]}"
      filename = sanitize_path(filename)
      FileUtils.rm filename
      OpenC3::Logger.info("Deleted: #{filename}", scope: params[:scope], user: username())
      return true
    else
      return false
    end
  end

  def delete_bucket_directory(params)
    bucket_name = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }

    path = sanitize_path(params[:object_id])
    path = "#{path}/" unless path.end_with?('/')
    key_split = path.split('/')

    # Check scope-based RBAC
    if bucket_requires_rbac?(params[:bucket]) && !authorize_bucket_path(params[:bucket], path, permission: 'system_set')
      path_scope = extract_scope_from_path(path)
      render json: { status: 'error', message: "Not authorized for scope: #{path_scope}" }, status: :forbidden
      return false
    end

    # Require admin for most bucket directories
    unless (params[:bucket] == 'OPENC3_CONFIG_BUCKET' && (key_split[1] == 'targets_modified' || key_split[1] == 'tmp'))
      return false unless authorization('admin')
    end

    # List all objects under the prefix (same pattern as TargetModel#undeploy)
    bucket = OpenC3::Bucket.getClient()
    objects = bucket.list_objects(bucket: bucket_name, prefix: path)
    keys = objects.map(&:key)

    if keys.empty?
      render json: { deleted_count: 0 }
      return true
    end

    # Delete in batches of 1000 (S3 limit)
    deleted_count = 0
    keys.each_slice(1000) do |key_batch|
      bucket.delete_objects(bucket: bucket_name, keys: key_batch)
      deleted_count += key_batch.length

      # Handle local mode
      if ENV.fetch('OPENC3_LOCAL_MODE', false)
        key_batch.each { |key| OpenC3::LocalMode.delete_local(key) }
      end
    end

    OpenC3::Logger.info("Deleted directory: #{bucket_name}/#{path} (#{deleted_count} files)",
                        scope: params[:scope], user: username())
    render json: { deleted_count: deleted_count }
    true
  end

  def delete_volume_directory(params)
    return false unless authorization('admin')

    volume = ENV.fetch(params[:volume]) { |name| raise StorageError, "Unknown volume #{name}" }

    path = sanitize_path(params[:object_id])
    full_path = "/#{volume}/#{path}"

    unless File.directory?(full_path)
      render json: { status: 'error', message: "Not a directory: #{path}" }, status: :bad_request
      return false
    end

    # Count files before deletion for reporting
    file_count = Dir.glob("#{full_path}/**/*").count { |f| File.file?(f) }

    FileUtils.rm_rf(full_path)

    OpenC3::Logger.info("Deleted directory: #{full_path} (#{file_count} files)",
                        scope: params[:scope], user: username())
    render json: { deleted_count: file_count }
    true
  end

  # Validates and returns storage source information
  # @return [Array<Symbol, String>] Storage type (:volume or :bucket) and storage name
  # Accepts a time param as nsec-from-epoch integer, an ISO8601 string, or nil.
  # Returns a Ruby Time (UTC) or nil.
  def parse_repair_time(value)
    return nil if value.nil? || value.to_s.empty?
    s = value.to_s
    if s.match?(/\A\d+\z/)
      # Raw logs use nsec-from-epoch throughout the codebase; use that.
      Time.from_nsec_from_epoch(s.to_i)
    else
      Time.parse(s).utc
    end
  end

  def validate_storage_source
    if params[:volume]
      volume = ENV.fetch(params[:volume]) { |name| raise StorageError, "Unknown volume #{name}" }
      [:volume, volume]
    elsif params[:bucket]
      bucket = ENV.fetch(params[:bucket]) { |name| raise StorageError, "Unknown bucket #{name}" }
      [:bucket, bucket]
    else
      raise StorageError, "No volume or bucket given"
    end
  end

  # Adds files from a volume to the zip archive
  def add_volume_files_to_zip(zipfile, volume_name, path, files)
    volume_path = "/#{volume_name}"
    files.each do |filename|
      file_path = "#{volume_path}/#{path}#{filename}"
      file_path = sanitize_path(file_path)
      if File.exist?(file_path)
        zipfile.add(filename, file_path)
      else
        OpenC3::Logger.warn("File not found: #{file_path}", user: username())
      end
    end
  end

  # Adds files from a bucket to the zip archive
  def add_bucket_files_to_zip(zipfile, bucket_name, path, files, tmp_dir)
    bucket = OpenC3::Bucket.getClient()
    files.each do |filename|
      key = "#{path}#{filename}"
      key = sanitize_path(key)
      temp_file = File.join(tmp_dir, filename)
      begin
        bucket.get_object(bucket: bucket_name, key: key, path: temp_file)
        zipfile.add(filename, temp_file)
      rescue => e
        OpenC3::Logger.warn("Failed to download #{key}: #{e.message}", user: username())
      end
    end
  end
end
