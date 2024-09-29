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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require_relative '../models/script'

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
    render :json => Script.all(scope)
  end

  def delete_temp
    return unless authorization('script_edit')
    scope = sanitize_params([:scope])
    return unless scope
    scope = scope[0]
    render :json => Script.delete_temp(scope)
  end

  def body
    return unless authorization('script_view')
    scope, name = sanitize_params([:scope, :name])
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
      # Using 'render :json => results' results in a raw json string like:
      # {"contents":"{\"json_class\":\"String\",\"raw\":[35,226,128...]}","breakpoints":[],"locked":false}
      render plain: JSON.generate(results)
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
    Script.create(args)
    results = {}
    if ((File.extname(name) == '.py') and (params[:text] =~ PYTHON_SUITE_REGEX)) or ((File.extname(name) != '.py') and (params[:text] =~ SUITE_REGEX))
      results_suites, results_error, success = Script.process_suite(name, params[:text], username: username(), scope: scope)
      results['suites'] = results_suites
      results['error'] = results_error
      results['success'] = success
    end
    OpenC3::Logger.info("Script created: #{name}", scope: scope, user: username()) if success
    render :json => results
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end

  def run
    scope, name = sanitize_params([:scope, :name], :allow_forward_slash => true)
    return unless scope
    # Extract the target that this script lives under
    target_name = name.split('/')[0]
    return unless authorization('script_run', target_name: target_name)
    suite_runner = params[:suiteRunner] ? params[:suiteRunner].as_json(:allow_nan => true) : nil
    disconnect = params[:disconnect] == 'disconnect'
    environment = params[:environment]
    running_script_id = Script.run(scope, name, suite_runner, disconnect, environment, user_full_name(), username())
    if running_script_id
      OpenC3::Logger.info("Script started: #{name}", scope: scope, user: username())
      render :plain => running_script_id.to_s
    else
      head :not_found
    end
  end

  def lock
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name])
    return unless scope
    Script.lock(scope, name, username())
    render status: 200
  end

  def unlock
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name])
    return unless scope
    locked_by = Script.locked?(scope, name)
    Script.unlock(scope, name) if username() == locked_by
    render status: 200
  end

  def destroy
    return unless authorization('script_edit')
    scope, name = sanitize_params([:scope, :name])
    return unless scope
    Script.destroy(scope, name)
    OpenC3::Logger.info("Script destroyed: #{name}", scope: scope, user: username())
    head :ok
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end

  def syntax
    # Extract the target that this script lives under
    name = sanitize_params([:name], :allow_forward_slash => true)
    return unless name
    name = name[0]
    target_name = name.split('/')[0]
    return unless authorization('script_run', target_name: target_name)
    script = Script.syntax(name, request.body.read)
    if script
      render :json => script
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
      render :json => script
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
end
