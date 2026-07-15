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
require 'openc3/models/setting_model'
require 'openc3/models/target_model'

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
  MAX_LIFECYCLE_COMMENT_LENGTH = 1000

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
      # Enterprise-only: seed Version History with the deployed body so
      # plugin-installed scripts have a baseline commit before any user edit.
      # Constant only loaded by the openc3-enterprise gem. Skip __TEMP__
      # scratch scripts — they are throwaway and need no history.
      if defined?(::VersionStore) && !name.start_with?("#{OpenC3::TargetFile::TEMP_FOLDER}/")
        plugin = OpenC3::TargetModel.plugin_version_label(name.split('/')[0], scope: scope)
        ::VersionStore.seed_initial_if_empty(scope: scope, name: name, body: file, plugin: plugin)
      end
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
      # Viewers without script_run still get the file contents, just no suite chrome.
      if suite_with_run_permission?(name, file)
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

  def lifecycle
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    unless lifecycle_enabled?()
      render json: { status: 'error', message: 'Script lifecycle is not enabled' }, status: :bad_request
      return
    end
    render json: Script.lifecycle(scope, name)
  end

  def set_lifecycle
    # All transitions require at least script_edit; transitions involving
    # 'approved' additionally require the script_approver permission (checked
    # below once the current state is known).
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    unless lifecycle_enabled?()
      render json: { status: 'error', message: 'Script lifecycle is not enabled' }, status: :bad_request
      return
    end
    if Script.temp_file?(name)
      render json: { status: 'error', message: 'Cannot set lifecycle on temporary files' }, status: :bad_request
      return
    end
    state = params[:state]
    comment = params[:comment].to_s.strip
    unless Script::LIFECYCLE_STATES.include?(state)
      render json: { status: 'error', message: "Invalid lifecycle state: #{state}" }, status: :bad_request
      return
    end
    if comment.length > MAX_LIFECYCLE_COMMENT_LENGTH
      render json: { status: 'error', message: "Comment must be #{MAX_LIFECYCLE_COMMENT_LENGTH} characters or less" }, status: :bad_request
      return
    end
    current = Script.lifecycle(scope, name)['state']
    unless Script::LIFECYCLE_TRANSITIONS[current].include?(state)
      render json: { status: 'error', message: "Cannot move script from #{current} to #{state}" }, status: :bad_request
      return
    end
    if (state == 'approved' or current == 'approved') and !authorization('script_approver')
      return
    end
    result = Script.set_lifecycle(scope, name, state, username(), comment, current: current)
    # The Enterprise store logs-and-swallows backend failures, returning nil.
    # Render an error instead of `json: nil`, which the ScriptLifecycleDialog
    # would try to read as `response.data.state` and crash on.
    if result.nil?
      render json: { status: 'error', message: 'Failed to change lifecycle' }, status: :internal_server_error
      return
    end
    OpenC3::Logger.info("Script lifecycle changed from #{current} to #{state}: #{name} (#{comment})", scope: scope, user: username())
    render json: result
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def create
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    if lifecycle_enabled?() and lifecycle_state(scope, name) == 'approved'
      render json: { status: 'error', message: 'Script is approved and cannot be modified. Move it back to review to edit.' }, status: :forbidden
      return
    end
    args = params.permit(:text, breakpoints: [])
    args[:scope] = scope
    args[:name] = name
    Script.create(args)
    results = {}
    # Enterprise-only: capture a git commit alongside the bucket write so
    # the new version_id can travel back to the editor. Skip __TEMP__ scratch
    # scripts — they are throwaway and would only add history noise.
    if defined?(::VersionStore) && !name.start_with?("#{OpenC3::TargetFile::TEMP_FOLDER}/")
      sha = ::VersionStore.commit(scope: scope, name: name, text: params[:text], username: username())
      results['version_id'] = sha if sha
    end
    # The file is still saved above; only the suite chrome is omitted when the editor lacks script_run.
    if suite_with_run_permission?(name, params[:text])
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
    # Users with only the script_run (runner) permission may only run
    # approved scripts. Users who can edit may run any lifecycle state.
    if lifecycle_enabled?() and (state = lifecycle_state(scope, name)) and state != 'approved' and !authorization('script_edit')
      return
    end
    # TODO 7.0: Should suiteRunner be snake case?
    suite_runner = params[:suiteRunner] ? params[:suiteRunner].as_json() : nil
    disconnect = params[:disconnect] == 'disconnect'
    environment = params[:environment]
    running_script_id = Script.run(scope, name, suite_runner, disconnect, environment, user_full_name(), username(), line_no, end_line_no)
    if running_script_id
      OpenC3::Logger.info("Script started: #{name}", scope: scope, user: username())
      render plain: running_script_id.to_s
    else
      render plain: "Script not found: #{name}", status: :not_found
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
    if lifecycle_enabled?() and lifecycle_state(scope, name) == 'approved'
      render json: { status: 'error', message: 'Script is approved and cannot be deleted. Move it back to review to delete.' }, status: :forbidden
      return
    end
    Script.destroy(scope, name)
    # Enterprise-only: record the deletion in git history.
    if defined?(::VersionStore)
      ::VersionStore.delete(scope: scope, name: name, username: username())
    end
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

  private

  # Suite analysis executes the file, so it is gated at the script_run tier rather
  # than the read-only script_view / script_edit endpoints that call this. Returns
  # true only when the text defines a suite AND the user has script_run permission.
  def suite_with_run_permission?(name, text)
    is_suite = if File.extname(name) == '.py'
      text =~ PYTHON_SUITE_REGEX
    else
      text =~ SUITE_REGEX
    end
    is_suite && authorized?('script_run', target_name: name.split('/')[0])
  end
  
  # Whether the Script Lifecycle feature is active: the Admin/Settings flag is
  # on AND the git-backed version store is available (Enterprise). Both are
  # required since the lifecycle is tracked as git commits/tags.
  def lifecycle_enabled?
    return false unless Script.lifecycle_enabled?
    setting = OpenC3::SettingModel.get(name: 'script_runner_lifecycle')
    return false unless setting
    setting['data'] == true or setting['data'] == 'true'
  end

  # Current lifecycle state for the create/run/destroy gates. The lookup hits
  # git (VersionStore); a transient backend error must not 500 the hottest
  # paths (especially run), so we log and fail OPEN by returning nil. Every
  # gate treats nil as "no restriction" (nil != 'approved', nil is falsey), so
  # an outage never blocks work — approval enforcement resumes once git heals.
  def lifecycle_state(scope, name)
    Script.lifecycle(scope, name)['state']
  rescue => e
    log_error(e)
    nil
  end

end
