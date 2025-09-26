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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'tempfile'
require 'openc3/utilities/target_file'
require 'openc3/utilities/running_script'
require 'openc3/script/suite'
require 'openc3/script/suite_runner'
require 'openc3/tools/test_runner/test'

OpenC3.require_file 'openc3/utilities/store'

class Script < OpenC3::TargetFile
  def self.all(scope, target = nil)
    super(scope, nil, target: target) # No path matchers
  end

  def self.lock(scope, name, username)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hset("#{scope}__script-locks", name, username)
  end

  def self.unlock(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hdel("#{scope}__script-locks", name)
  end

  def self.locked?(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    locked_by = OpenC3::Store.hget("#{scope}__script-locks", name)
    locked_by ||= false
    locked_by
  end

  def self.get_breakpoints(scope, name)
    breakpoints = OpenC3::Store.hget("#{scope}__script-breakpoints", name.split('*')[0]) # Split '*' that indicates modified
    return JSON.parse(breakpoints, allow_nan: true, create_additions: true) if breakpoints
    []
  end

  def self.process_suite(name, contents, new_process: true, username: nil, scope:)
    python = false
    python = true if File.extname(name) == '.py'

    start = Time.now

    if python
      temp = Tempfile.new(%w[suite .py])
    else
      temp = Tempfile.new(%w[suite .rb])
    end

    # Remove any carriage returns which ruby doesn't like
    temp.write(contents.gsub(/\r/, ' '))
    temp.close

    # We open a new process so as to not pollute the API with require
    results = nil
    success = true
    if new_process or python
      if python
        runner_path = File.join(RAILS_ROOT, 'scripts', 'run_suite_analysis.py')
        process = ChildProcess.build('python', runner_path.to_s, scope, temp.path)
      else
        runner_path = File.join(RAILS_ROOT, 'scripts', 'run_suite_analysis.rb')
        process = ChildProcess.build('ruby', runner_path.to_s, scope, temp.path)
      end
      process.cwd = File.join(RAILS_ROOT, 'scripts')

      # Check for offline access token
      model = nil
      model = OpenC3::OfflineAccessModel.get_model(name: username, scope: scope) if username and username != ''

      # Set proper secrets for running script
      process.environment['SECRET_KEY_BASE'] = nil
      process.environment['OPENC3_REDIS_USERNAME'] = ENV['OPENC3_SR_REDIS_USERNAME']
      process.environment['OPENC3_REDIS_PASSWORD'] = ENV['OPENC3_SR_REDIS_PASSWORD']
      process.environment['OPENC3_BUCKET_USERNAME'] = ENV['OPENC3_SR_BUCKET_USERNAME']
      process.environment['OPENC3_BUCKET_PASSWORD'] = ENV['OPENC3_SR_BUCKET_PASSWORD']
      process.environment['OPENC3_SR_REDIS_USERNAME'] = nil
      process.environment['OPENC3_SR_REDIS_PASSWORD'] = nil
      process.environment['OPENC3_SR_BUCKET_USERNAME'] = nil
      process.environment['OPENC3_SR_BUCKET_PASSWORD'] = nil
      process.environment['OPENC3_API_CLIENT'] = ENV['OPENC3_API_CLIENT']
      if model and model.offline_access_token
        auth = OpenC3::OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
        valid_token = auth.get_token_from_refresh_token(model.offline_access_token)
        if valid_token
          process.environment['OPENC3_API_TOKEN'] = model.offline_access_token
        else
          model.offline_access_token = nil
          model.update
          raise "offline_access token invalid for script"
        end
      else
        process.environment['OPENC3_API_USER'] = ENV['OPENC3_API_USER']
        if ENV['OPENC3_SERVICE_PASSWORD']
          process.environment['OPENC3_API_PASSWORD'] = ENV['OPENC3_SERVICE_PASSWORD']
        else
          # The viewer user doesn't have an offline access token (because they can't run scripts)
          # but they still want to be able to view suite files
          # Since processing a suite file requires running it they won't get the Suite chrome
          # so return nothing here and allow Script Runner to simply view the suite file
          return '', '', false
        end
      end
      process.environment['GEM_HOME'] = ENV['GEM_HOME']
      process.environment['PYTHONUSERBASE'] = ENV['PYTHONUSERBASE']

      # Spawned process should not be controlled by same Bundler constraints as spawning process
      ENV.each do |key, _value|
        if key =~ /^BUNDLE/
          process.environment[key] = nil
        end
      end
      process.environment['RUBYOPT'] = nil # Removes loading bundler setup
      process.environment['OPENC3_SCOPE'] = scope

      stdout = Tempfile.new("child-stdout")
      stdout.sync = true
      stderr = Tempfile.new("child-stderr")
      stderr.sync = true
      process.io.stdout = stdout
      process.io.stderr = stderr
      process.start
      process.wait
      stdout.rewind
      stdout_results = stdout.read
      stdout.close
      stdout.unlink
      stderr.rewind
      stderr_results = stderr.read
      stderr.close
      stderr.unlink
      success = process.exit_code == 0
    else
      require temp.path
      stdout_results = OpenC3::SuiteRunner.build_suites.as_json().to_json(allow_nan: true)
    end
    temp.delete
    puts "Processed #{name} in #{Time.now - start} seconds"
    # Make sure we're getting the last line which should be the suite
    puts "Stdout Results:#{stdout_results}:"
    puts "Stderr Results:#{stderr_results}:"
    stdout_results = stdout_results.split("\n")[-1] if stdout_results
    return stdout_results, stderr_results, success
  end

  def self.create(params)
    existing = body(params[:scope], params[:name])
    # Commit if there is no existing or something has changed
    if existing.nil? or existing != params[:text]
      super(params[:scope], params[:name], params[:text])
    end
    breakpoints = params[:breakpoints]
    if breakpoints
      if breakpoints.empty?
        OpenC3::Store.hdel("#{params[:scope]}__script-breakpoints", params[:name])
      else
        OpenC3::Store.hset("#{params[:scope]}__script-breakpoints", params[:name],
          breakpoints.as_json().to_json(allow_nan: true))
      end
    end
  end

  def self.delete_temp(scope)
    files = super(scope)
    files.each do |name|
      # Remove any breakpoints associated with the temp files
      OpenC3::Store.hdel("#{scope}__script-breakpoints", "#{TEMP_FOLDER}/#{File.basename(name)}")
    end
  end

  def self.destroy(scope, name)
    super(scope, name)
    OpenC3::Store.hdel("#{scope}__script-breakpoints", name)
  end

  def self.run(
    scope,
    name,
    suite_runner = nil,
    disconnect = false,
    environment = nil,
    user_full_name = nil,
    username = nil,
    line_no = nil,
    end_line_no = nil
  )
    RunningScript.spawn(scope, name, suite_runner, disconnect, environment, user_full_name, username, line_no, end_line_no)
  end

  def self.instrumented(filename, text)
    language = detect_language(text, filename)
    if language == 'ruby'
      return {
        'title' => 'Instrumented Script',
        'description' =>
          RunningScript.instrument_script(
            text,
            filename,
            true,
          ).split("\n").as_json().to_json(allow_nan: true),
      }
    elsif language == 'python'
      start = Time.now
      temp = Tempfile.new(%w[instrument .py])
      temp.write(text)
      temp.close

      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_instrument.py')
      process = ChildProcess.build('python', runner_path.to_s, temp.path)
      process.cwd = File.join(RAILS_ROOT, 'scripts')

      stdout = Tempfile.new("child-stdout")
      stdout.sync = true
      stderr = Tempfile.new("child-stderr")
      stderr.sync = true
      process.io.stdout = stdout
      process.io.stderr = stderr
      process.start
      process.wait
      stdout.rewind
      stdout_results = stdout.read
      stdout.close
      stdout.unlink
      stderr.rewind
      stderr_results = stderr.read
      stderr.close
      stderr.unlink
      success = process.exit_code == 0
      puts "Processed Instrumenting #{filename} in #{Time.now - start} seconds"
      # Make sure we're getting the last line which should be the suite
      puts "Stdout Results:#{stdout_results}:"
      puts "Stderr Results:#{stderr_results}:"
      # stdout_results = stdout_results.split("\n")[-1] if stdout_results

      if success
        return {
          'title' => 'Instrumented Script',
          'description' =>
            stdout_results.to_s.split("\n").as_json().to_json(allow_nan: true),
        }
      else
        return {
          'title' => 'Error Instrumenting Script',
          'description' =>
            (stdout_results.to_s + stderr_results.to_s).split("\n").as_json().to_json(allow_nan: true),
        }
      end
    else
      return {
        'title' => 'Instrumenting Not Supported',
        'description' => ['Only Ruby and Python Support Viewing Instrumentation'].as_json.to_json,
      }
    end
  end

  def self.detect_language(text, filename = nil)
    if filename
      extension = File.extname(filename)
      if extension == '.rb'
        return 'ruby'
      elsif extension == '.py'
        return 'python'
      elsif extension.length > 0
        return 'other'
      end
    end

    return 'ruby' if text =~ /^\s*(require|load|puts) /
    return 'python' if text =~ /^\s*(import|from) /
    return 'ruby' if text =~ /^\s*end\s*$/
    return 'python' if text =~ /^\s*(if|def|while|else|elif|class).*:\s*$/
    return 'ruby' # otherwise guess Ruby
  end

  def self.mnemonics(filename, text)
    # Ruby and Python are currently handled in-browser
    # Script Engine Possibly
    extension = File.extname(filename).to_s.downcase
    script_engine_model = OpenC3::ScriptEngineModel.get_model(name: extension, scope: 'DEFAULT')
    if script_engine_model
      script_engine = script_engine_model.filename
      if File.extname(script_engine).to_s.downcase == '.py'
        process_name = 'python'
        runner_path = File.join(RAILS_ROOT, 'scripts', 'script_engine_cmd.py')
      else
        process_name = 'ruby'
        runner_path = File.join(RAILS_ROOT, 'scripts', 'script_engine_cmd.rb')
      end

      tf = nil
      begin
        tf = Tempfile.new((['mnemonics', extension]))
        tf.write(text)
        tf.close()
        results, status = Open3.capture2e("#{process_name} \"#{runner_path}\" mnemonic_check \"#{tf.path}\"")
        lines = []
        if results and results.length > 0
          results.each_line do |line|
            lines << line
          end
          return(
            { 'title' => 'Mnemonics Check Failed', 'description' => lines.as_json().to_json(allow_nan: true) }
          )
        else
          return(
            {
              'title' => 'Mnemonics Check Successful',
              'description' => ["Mnemonics OK"].as_json().to_json(allow_nan: true),
            }
          )
        end
      ensure
        tf.unlink if tf
      end
    else
      raise "Unsupported script file type: #{extension}"
    end
  end

  def self.syntax(filename, text)
    if text.nil?
      return(
        { 'title' => 'Syntax Check Failed', 'description' => 'no text passed' }
      )
    end
    language = detect_language(text, filename)
    if language == 'ruby'
      check_process = IO.popen('ruby -c -rubygems 2>&1', 'r+')
      check_process.write("require 'openc3'; require 'openc3/script'; " + text)
      check_process.close_write
      results = check_process.readlines
      check_process.close
      if results
        if results.any?(/Syntax OK/)
          return(
            {
              'title' => 'Syntax Check Successful',
              'description' => results.as_json().to_json(allow_nan: true),
            }
          )
        else
          # Results is an array of strings like this: ":2: syntax error ..."
          # Normally the procedure comes before the first colon but since we
          # are writing to the process this is blank so we throw it away
          results.map! { |result| result.split(':')[1..-1].join(':') }
          return(
            { 'title' => 'Syntax Check Failed', 'description' => results.as_json().to_json(allow_nan: true) }
          )
        end
      else
        return(
          {
            'title' => 'Syntax Check Exception',
            'description' => 'Ruby syntax check unexpectedly returned nil',
          }
        )
      end
    elsif language == 'python'
      # Python
      tf = nil
      begin
        tf = Tempfile.new((['syntax', '.py']))
        tf.write(text)
        tf.close()
        results, status = Open3.capture2e("python -m py_compile #{tf.path}")
        lines = []
        if results and results.length > 0
          results.each_line do |line|
            lines << line
          end
          return(
            { 'title' => 'Syntax Check Failed', 'description' => lines.as_json().to_json(allow_nan: true) }
          )
        else
          return(
            {
              'title' => 'Syntax Check Successful',
              'description' => ["Syntax OK"].as_json().to_json(allow_nan: true),
            }
          )
        end
      ensure
        tf.unlink if tf
      end
    else
      # Script Engine Possibly
      extension = File.extname(filename).to_s.downcase
      script_engine_model = OpenC3::ScriptEngineModel.get_model(name: extension, scope: 'DEFAULT')
      if script_engine_model
        script_engine = script_engine_model.filename
        if File.extname(script_engine).to_s.downcase == '.py'
          process_name = 'python'
          runner_path = File.join(RAILS_ROOT, 'scripts', 'script_engine_cmd.py')
        else
          process_name = 'ruby'
          runner_path = File.join(RAILS_ROOT, 'scripts', 'script_engine_cmd.rb')
        end

        tf = nil
        begin
          tf = Tempfile.new((['syntax', extension]))
          tf.write(text)
          tf.close()
          results, status = Open3.capture2e("#{process_name} \"#{runner_path}\" syntax_check \"#{tf.path}\"")
          lines = []
          if results and results.length > 0
            results.each_line do |line|
              lines << line
            end
            return(
              { 'title' => 'Syntax Check Failed', 'description' => lines.as_json().to_json(allow_nan: true) }
            )
          else
            return(
              {
                'title' => 'Syntax Check Successful',
                'description' => ["Syntax OK"].as_json().to_json(allow_nan: true),
              }
            )
          end
        ensure
          tf.unlink if tf
        end
      else
        raise "Unsupported script file type: #{extension}"
      end
    end
  end
end
