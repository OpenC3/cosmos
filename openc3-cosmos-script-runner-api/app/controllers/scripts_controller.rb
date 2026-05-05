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
      prior = lifecycle.latest_record || {}
      render json: {
        status: 'locked_for_review',
        reviewed_by: prior['reviewed_by'],
        reviewed_at: prior['reviewed_at'],
        reviewed_notes: prior['reviewed_notes'],
        version_id: lifecycle.latest_version_id
      }, status: :conflict
      return
    end

    prev_reviewed_version_id = lifecycle.latest_version_id if lifecycle.locked_for_review?
    prev_reviewer = lifecycle.latest_record&.dig('reviewed_by') if lifecycle.locked_for_review?

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

      # Auto-validate inline so scripts saved via API still acquire a
      # validated_at timestamp. Combines syntax + mnemonic check; both must
      # pass for the version to be marked validated.
      validation = inline_validate(name, params[:text])
      results['validation'] = validation
      if validation && validation[:passed]
        lifecycle.record_validation(version_id: write_result, username: username())
      end
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
        lifecycle.record_execution(version_id: lifecycle.latest_version_id, username: username(), disconnect: disconnect)
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
      # Record a validated_at on the latest version when the explicit syntax
      # check is invoked from the UI and passes. Scope is optional in this
      # endpoint (the route doesn't include it); skip recording when absent.
      if script['title'].to_s.include?('Successful') && params[:scope]
        lifecycle = OpenC3::ScriptLifecycleModel.get_or_build(name: name, scope: params[:scope])
        if lifecycle.latest_version_id
          lifecycle.record_validation(version_id: lifecycle.latest_version_id, username: username())
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

  private

  # Combined syntax + mnemonic check used to decide whether to mark a save as
  # validated. Mnemonic check is a hard fail when applicable (script-engine
  # languages); for ruby/python it's still browser-side, so this method only
  # exercises the syntax check for those.
  def inline_validate(name, text)
    return { passed: false, syntax: nil, mnemonics: nil } if text.nil?
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

    { passed: syntax_passed && mnemonics_passed, syntax: syntax, mnemonics: mnemonics }
  rescue => e
    { passed: false, error: e.message }
  end
end
