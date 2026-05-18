# encoding: ascii-8bit

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

require 'json'
require 'openc3/utilities/script'

class ScriptsController < ApplicationController
  # This REGEX is also found in running_script.rb
  # Matches the following test cases:
  # class  MySuite  <  TestSuite
  #   class MySuite < OpenC3::Suite
  # class MySuite < Cosmos::TestSuite
  # class MySuite < Suite # comment
  # # class MySuite < Suite # <-- doesn't match commented out
  SUITE_REGEX = /^\s*class\s+\w+\s+<\s+(Cosmos::|OpenC3::)?(Suite|TestSuite)/
  PYTHON_SUITE_REGEX = /^\s*class\s+\w+\s*\(\s*(Suite|TestSuite)\s*\)/

  def ping
    render plain: 'OK'
  end

  def index
    return unless authorization('script_view')
    scope = sanitize_params([:scope])
    return unless scope
    scope = scope[0]
    target = params[:target]
    render json: Script.all(scope, target)
  end

  def delete_temp
    return unless authorization('script_edit')
    scope = sanitize_params([:scope])
    return unless scope
    scope = scope[0]
    render json: Script.delete_temp(scope)
  end

  def body
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope

    file = Script.body(scope, name)
    if file
      locked = Script.locked?(scope, name)
      unless locked
        Script.lock(scope, name, username())
      end
      breakpoints = Script.get_breakpoints(scope, name)
      results = {
        contents: file,
        breakpoints: breakpoints,
        locked: locked
      }
      if ((File.extname(name) == '.py') and (file =~ PYTHON_SUITE_REGEX)) or ((File.extname(name) != '.py') and (file =~ SUITE_REGEX))
        results_suites, results_error, success = Script.process_suite(name, file, username: username(), scope: scope)
        results['suites'] = results_suites
        results['error'] = results_error
        results['success'] = success
      end
      # Using 'render json: results' results in a raw json string like:
      # {"contents":"{\"json_class\":\"String\",\"raw\":[35,226,128...]}","breakpoints":[],"locked":false}
      render plain: JSON.generate(results, allow_nan: true)
    else
      head :not_found
    end
  end

  def create
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    args = params.permit(:text, breakpoints: [])
    args[:scope] = scope
    args[:name] = name
    args[:username] = username()
    write_result = Script.create(args)
    results = {}
    results['version_id'] = write_result if write_result.is_a?(String)
    if ((File.extname(name) == '.py') and (params[:text] =~ PYTHON_SUITE_REGEX)) or ((File.extname(name) != '.py') and (params[:text] =~ SUITE_REGEX))
      results_suites, results_error, success = Script.process_suite(name, params[:text], username: username(), scope: scope)
      results['suites'] = results_suites
      results['error'] = results_error
      results['success'] = success
    end
    OpenC3::Logger.info("Script created: #{name}", scope: scope, user: username()) if success
    render json: results
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def run
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    line_no = params[:line_no] ? params[:line_no].to_i : 1
    end_line_no = params[:end_line_no] ? params[:end_line_no].to_i : nil

    return unless scope
    # Extract the target that this script lives under
    target_name = name.split('/')[0]
    return unless authorization('script_run', target_name: target_name)
    # TODO 7.0: Should suiteRunner be snake case?
    suite_runner = params[:suiteRunner] ? params[:suiteRunner].as_json() : nil
    disconnect = params[:disconnect] == 'disconnect'
    environment = params[:environment]
    running_script_id = Script.run(scope, name, suite_runner, disconnect, environment, user_full_name(), username(), line_no, end_line_no)
    if running_script_id
      OpenC3::Logger.info("Script started: #{name}", scope: scope, user: username())
      render plain: running_script_id.to_s
    else
      head :not_found
    end
  end

  def lock
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    Script.lock(scope, name, username())
    render status: :ok
  end

  def unlock
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    locked_by = Script.locked?(scope, name)
    Script.unlock(scope, name) if username() == locked_by
    render status: :ok
  end

  def destroy
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    Script.destroy(scope, name)
    OpenC3::Logger.info("Script destroyed: #{name}", scope: scope, user: username())
    head :ok
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def mnemonics
    name = sanitize_params([:name], :allow_forward_slash => true)
    return unless name
    name = name[0]
    # Extract the target that this script lives under
    target_name = name.split('/')[0]
    return unless authorization('script_run', target_name: target_name)
    script = Script.mnemonics(name, request.body.read)
    if script
      render json: script
    else
      head :error
    end
  end

  def syntax
    name = sanitize_params([:name], :allow_forward_slash => true)
    return unless name
    name = name[0]
    # Extract the target that this script lives under
    target_name = name.split('/')[0]
    return unless authorization('script_run', target_name: target_name)
    script = Script.syntax(name, request.body.read)
    if script
      render json: script
    else
      head :error
    end
  end

  def instrumented
    return unless authorization('script_view')
    name = sanitize_params([:name], :allow_forward_slash => true)
    return unless name
    name = name[0]
    script = Script.instrumented(name, request.body.read)
    if script
      render json: script
    else
      head :error
    end
  end

  def delete_all_breakpoints
    return unless authorization('script_edit')
    scope = sanitize_params([:scope])
    return unless scope
    scope = scope[0]
    OpenC3::Store.del("#{scope}__script-breakpoints")
    head :ok
  end

  # GET /scripts/*name/versions — list S3 versions for this script body,
  # newest-first. Each entry carries version_id, size, last_modified, is_latest,
  # and etag.
  def versions
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    bucket_name = ENV['OPENC3_CONFIG_BUCKET']
    key = "#{scope}/targets_modified/#{name}"
    bucket = OpenC3::Bucket.getClient()
    s3 = bucket.list_object_versions(bucket: bucket_name, prefix: key)
    versions = s3[:versions].select { |v| v.key == key }.map do |v|
      {
        version_id: v.version_id,
        size: v.size,
        last_modified: v.last_modified,
        is_latest: v.is_latest,
        etag: v.etag
      }
    end
    delete_markers = s3[:delete_markers].select { |dm| dm.key == key }.map do |dm|
      { version_id: dm.version_id, last_modified: dm.last_modified, is_latest: dm.is_latest, deleted: true }
    end
    render json: { versions: versions, delete_markers: delete_markers }
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  # GET /scripts/*name/version?version_id=... — return body of a specific version.
  def version_body
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    version_id = params[:version_id]
    if version_id.nil? || version_id.empty?
      render json: { status: 'error', message: 'version_id required' }, status: :bad_request
      return
    end
    bucket = OpenC3::Bucket.getClient()
    begin
      resp = bucket.get_object(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        key: "#{scope}/targets_modified/#{name}",
        version_id: version_id
      )
    rescue Aws::Errors::ServiceError => e
      # Backends (real AWS S3, etc.) reject lookups with versionIds that
      # aren't valid for the bucket — for example null-version markers
      # returned by list_object_versions on a bucket whose versioning was
      # only just enabled. Surface as 404 rather than 500.
      OpenC3::Logger.warn("get_object(version_id=#{version_id}) failed for #{scope}/#{name}: #{e.message}", scope: scope)
      render json: { status: 'error', message: "Version unavailable: #{e.message}" }, status: :not_found
      return
    end
    if resp && resp.body
      body = File.extname(name) == '.bin' ? (resp.body.binmode; resp.body.read) : resp.body.read.force_encoding('UTF-8')
      render plain: body
    else
      head :not_found
    end
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  # POST /scripts/*name/restore body {version_id} — re-PUT the body of an
  # older version as a new current version. Caller must hold the edit lock
  # the same way a normal save does.
  def restore
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    version_id = params[:version_id]
    if version_id.nil? || version_id.empty?
      render json: { status: 'error', message: 'version_id required' }, status: :bad_request
      return
    end

    bucket = OpenC3::Bucket.getClient()
    bucket_name = ENV['OPENC3_CONFIG_BUCKET']
    key = "#{scope}/targets_modified/#{name}"
    begin
      src = bucket.get_object(bucket: bucket_name, key: key, version_id: version_id)
    rescue Aws::Errors::ServiceError => e
      OpenC3::Logger.warn("restore get_object(version_id=#{version_id}) failed for #{scope}/#{name}: #{e.message}", scope: scope)
      render json: { status: 'error', message: "Version unavailable: #{e.message}" }, status: :not_found
      return
    end
    if src.nil? || src.body.nil?
      head :not_found
      return
    end
    body = src.body.read

    write_result = OpenC3::TargetFile.create(scope, name, body, username: username())
    new_version_id = write_result.is_a?(String) ? write_result : nil

    OpenC3::Logger.info("Script restored: #{name} from #{version_id}", scope: scope, user: username())
    render json: { version_id: new_version_id, restored_from_version_id: version_id }
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end
