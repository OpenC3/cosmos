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
require 'openc3/models/script_lifecycle_model'

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
      breakpoints = Script.get_breakpoints(scope, name)
      lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
      results = {
        contents: file,
        breakpoints: breakpoints,
        version_id: lifecycle.latest_version_id,
        lifecycle: lifecycle.latest_record,
        locked_for_review: lifecycle.locked_for_review?
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

    # Refuse to overwrite a reviewed version unless the caller explicitly
    # opts into tainting it. The frontend confirms with the user before retrying
    # with force_taint=true.
    lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
    force_taint = params[:force_taint].to_s == 'true'
    if lifecycle.locked_for_review? && !force_taint
      prior_reviewed = lifecycle.latest_record&.dig('reviewed') || {}
      render json: {
        status: 'locked_for_review',
        reviewed: prior_reviewed,
        version_id: lifecycle.latest_version_id
      }, status: :conflict
      return
    end

    prev_reviewed_version_id = lifecycle.latest_version_id if lifecycle.locked_for_review?
    prev_reviewer = lifecycle.latest_record&.dig('reviewed', 'by') if lifecycle.locked_for_review?

    write_result = Script.create(args)
    results = {}
    if write_result.is_a?(String)
      results['version_id'] = write_result
      if force_taint && prev_reviewed_version_id
        lifecycle.record_taint(
          version_id: write_result,
          username: username(),
          prev_version_id: prev_reviewed_version_id,
          prev_reviewer: prev_reviewer
        )
      else
        lifecycle.record_save(version_id: write_result, username: username())
      end

      # Auto-validate inline so every saved version acquires a validated
      # block. Combines syntax + mnemonic check; pass/fail and any error
      # lines are recorded for the UI's validated badge.
      validation = inline_validate(name, params[:text])
      results['validation'] = validation
      lifecycle.record_validation(
        version_id: write_result,
        passed: validation[:passed],
        errors: validation[:errors] || [],
        username: username()
      )
    end

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
      lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
      if lifecycle.latest_version_id
        lifecycle.record_execution(
          version_id: lifecycle.latest_version_id,
          username: username(),
          disconnect: disconnect,
          environment: environment,
          suite_runner: suite_runner,
          running_script_id: running_script_id
        )
      end
      render plain: running_script_id.to_s
    else
      head :not_found
    end
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
    body = request.body.read
    script = Script.syntax(name, body)
    if script
      # Update the validated block on the latest version when an explicit
      # syntax check is invoked from the UI. Scope is optional on this route
      # (path has only the name); skip recording when absent.
      if params[:scope]
        passed = script['title'].to_s.include?('Successful')
        errors = []
        unless passed
          desc = script['description']
          lines = desc.is_a?(String) ? (JSON.parse(desc) rescue [desc]) : Array(desc)
          errors.concat(lines.compact.map(&:to_s))
        end
        lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: params[:scope])
        if lifecycle.latest_version_id
          lifecycle.record_validation(
            version_id: lifecycle.latest_version_id,
            passed: passed,
            errors: errors,
            username: username()
          )
        end
      end
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

  # GET /scripts/*name/versions — list S3 versions merged with lifecycle data.
  # Returns versions newest-first.
  def versions
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    bucket_name = ENV['OPENC3_CONFIG_BUCKET']
    key = "#{scope}/targets_modified/#{name}"
    bucket = OpenC3::Bucket.getClient()
    s3 = bucket.list_object_versions(bucket: bucket_name, prefix: key)
    lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
    versions = s3[:versions].select { |v| v.key == key }.map do |v|
      record = lifecycle.versions[v.version_id] || {}
      {
        version_id: v.version_id,
        size: v.size,
        last_modified: v.last_modified,
        is_latest: v.is_latest,
        etag: v.etag,
        state: lifecycle.state_of(v.version_id),
        saved_by: record['saved_by'],
        saved_at: record['saved_at'],
        validated: record['validated'],
        reviewed: record['reviewed'],
        executions: record['executions'] || [],
        tainted: record['tainted'] == true,
        tainted_from_version_id: record['tainted_from_version_id'],
        tainted_from_reviewed_by: record['tainted_from_reviewed_by'],
        restored_from_version_id: record['restored_from_version_id']
      }
    end
    delete_markers = s3[:delete_markers].select { |dm| dm.key == key }.map do |dm|
      { version_id: dm.version_id, last_modified: dm.last_modified, is_latest: dm.is_latest, deleted: true }
    end
    render json: { versions: versions, delete_markers: delete_markers, latest_version_id: lifecycle.latest_version_id }
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
    resp = bucket.get_object(
      bucket: ENV['OPENC3_CONFIG_BUCKET'],
      key: "#{scope}/targets_modified/#{name}",
      version_id: version_id
    )
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

  # POST /scripts/*name/restore body {version_id, force_taint?} — re-PUT the
  # body of an old version. Same review-lock semantics as save: refused with
  # 409 if the latest version is reviewed unless force_taint=true, in which
  # case the new (restored) version is marked tainted with provenance.
  def restore
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    version_id = params[:version_id]
    if version_id.nil? || version_id.empty?
      render json: { status: 'error', message: 'version_id required' }, status: :bad_request
      return
    end

    lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
    force_taint = params[:force_taint].to_s == 'true'
    if lifecycle.locked_for_review? && !force_taint
      prior_reviewed = lifecycle.latest_record&.dig('reviewed') || {}
      render json: {
        status: 'locked_for_review',
        reviewed: prior_reviewed,
        version_id: lifecycle.latest_version_id
      }, status: :conflict
      return
    end

    prev_reviewed_version_id = lifecycle.latest_version_id if lifecycle.locked_for_review?
    prev_reviewer = lifecycle.latest_record&.dig('reviewed', 'by') if lifecycle.locked_for_review?

    bucket = OpenC3::Bucket.getClient()
    bucket_name = ENV['OPENC3_CONFIG_BUCKET']
    key = "#{scope}/targets_modified/#{name}"
    src = bucket.get_object(bucket: bucket_name, key: key, version_id: version_id)
    if src.nil? || src.body.nil?
      head :not_found
      return
    end
    body = src.body.read

    write_result = OpenC3::TargetFile.create(scope, name, body, username: username())
    new_version_id = write_result.is_a?(String) ? write_result : nil

    if new_version_id
      if force_taint && prev_reviewed_version_id
        lifecycle.record_taint(
          version_id: new_version_id,
          username: username(),
          prev_version_id: prev_reviewed_version_id,
          prev_reviewer: prev_reviewer
        )
        # record_taint sets latest_version_id; layer the restore provenance on top
        lifecycle.versions[new_version_id]['restored_from_version_id'] = version_id
        lifecycle.persist
      else
        lifecycle.record_restore(
          version_id: new_version_id,
          username: username(),
          restored_from_version_id: version_id
        )
      end
    end

    OpenC3::Logger.info("Script restored: #{name} from #{version_id}", scope: scope, user: username())
    render json: { version_id: new_version_id, restored_from_version_id: version_id }
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  # POST /scripts/*name/review body {version_id, notes} — sign off on the
  # specified version. The version_id must match the current latest_version_id
  # (otherwise the script has been edited since the reviewer loaded it, and
  # they'd be signing off on a different version than they reviewed).
  def review
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope

    unless can_approve_script?(scope: scope, token: request.headers['HTTP_AUTHORIZATION'])
      render json: { status: 'error', message: 'not authorized to approve scripts' }, status: :forbidden
      return
    end

    version_id = params[:version_id]
    if version_id.nil? || version_id.empty?
      render json: { status: 'error', message: 'version_id required' }, status: :bad_request
      return
    end
    notes = params[:notes]

    lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: scope)
    if lifecycle.latest_version_id != version_id
      render json: {
        status: 'version_mismatch',
        message: 'A newer version exists; reload before signing off',
        latest_version_id: lifecycle.latest_version_id
      }, status: :conflict
      return
    end

    lifecycle.record_review(version_id: version_id, username: username(), notes: notes)
    OpenC3::Logger.info("Script reviewed: #{name} #{version_id}", scope: scope, user: username())
    render json: {
      version_id: version_id,
      reviewed: lifecycle.versions[version_id]['reviewed']
    }
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  private

  # Combined syntax + mnemonic check used to decide whether to mark a save as
  # validated. Mnemonic check is a hard fail when applicable (script-engine
  # languages); for ruby/python it's still browser-side, so this method only
  # exercises the syntax check for those. Returns a hash with :passed,
  # :errors (flattened lines from both checks for the UI), :syntax, :mnemonics.
  def inline_validate(name, text)
    return { passed: false, errors: ['no text'], syntax: nil, mnemonics: nil } if text.nil?
    syntax = Script.syntax(name, text)
    syntax_passed = syntax && syntax['title'].to_s.include?('Successful')

    mnemonics_passed = true
    mnemonics = nil
    extension = File.extname(name).to_s.downcase
    if extension != '.rb' && extension != '.py'
      begin
        mnemonics = Script.mnemonics(name, text)
        mnemonics_passed = mnemonics && mnemonics['title'].to_s.include?('Successful')
      rescue => e
        mnemonics = { 'title' => 'Mnemonics Check Skipped', 'description' => e.message }
        mnemonics_passed = false
      end
    end

    errors = []
    if syntax && !syntax_passed
      desc = syntax['description']
      lines = desc.is_a?(String) ? (JSON.parse(desc) rescue [desc]) : Array(desc)
      errors.concat(lines.compact.map(&:to_s))
    end
    if mnemonics && !mnemonics_passed
      desc = mnemonics['description']
      lines = desc.is_a?(String) ? (JSON.parse(desc) rescue [desc]) : Array(desc)
      errors.concat(lines.compact.map(&:to_s))
    end

    { passed: syntax_passed && mnemonics_passed, errors: errors, syntax: syntax, mnemonics: mnemonics }
  rescue => e
    { passed: false, errors: [e.message] }
  end
end
