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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'securerandom'
require 'openc3'
require 'openc3/utilities/bucket_utilities'
require 'openc3/script'
require 'openc3/io/stdout'
require 'openc3/io/stderr'
require 'childprocess'
require 'openc3/script/suite_runner'
require 'openc3/utilities/store'
require 'openc3/utilities/store_queued'
require 'openc3/utilities/bucket_require'
require 'openc3/models/offline_access_model'
require 'openc3/models/environment_model'
require 'openc3/models/script_status_model'

RAILS_ROOT = File.expand_path(File.join(__dir__, '..', '..'))
SCRIPT_API = 'script-api'

def running_script_publish(channel_name, data)
  stream_name = [SCRIPT_API, channel_name].compact.join(":")
  OpenC3::Store.publish(stream_name, JSON.generate(data))
end

def running_script_anycable_publish(channel_name, data)
  stream_name = [SCRIPT_API, channel_name].compact.join(":")
  stream_data = {"stream" => stream_name, "data" => JSON.generate(data)}
  OpenC3::Store.publish("__anycable__", JSON.generate(stream_data))
end

module OpenC3
  module Script
    private
    # Define all the user input methods used in scripting which we need to broadcast to the frontend
    # Note: This list matches the list in run_script.rb:116
    SCRIPT_METHODS = %i[ask ask_string message_box vertical_message_box combo_box prompt prompt_for_hazardous
      prompt_for_critical_cmd metadata_input open_file_dialog open_files_dialog]
    SCRIPT_METHODS.each do |method|
      define_method(method) do |*args, **kwargs|
        while true
          if RunningScript.instance
            RunningScript.instance.scriptrunner_puts("#{method}(#{args.join(', ')})")
            prompt_id = SecureRandom.uuid
            RunningScript.instance.perform_wait({ 'method' => method, 'id' => prompt_id, 'args' => args, 'kwargs' => kwargs })
            input = RunningScript.instance.user_input
            # All ask and prompt dialogs should include a 'Cancel' button
            # If they cancel we wait so they can potentially stop
            if input == 'Cancel'
              RunningScript.instance.perform_pause
            else
              if (method.to_s.include?('open_file'))
                files = input.map do |filename|
                  file = _get_storage_file("tmp/#{filename}", scope: RunningScript.instance.scope)
                  # Set filename method we added to Tempfile in the core_ext
                  file.filename = filename
                  file
                end
                files = files[0] if method.to_s == 'open_file_dialog' # Simply return the only file
                return files
              elsif method.to_s == 'prompt_for_critical_cmd'
                if input == 'REJECTED'
                  raise "Critical Cmd Rejected"
                end
                return input
              else
                return input
              end
            end
          else
            raise "Script input method called outside of running script"
          end
        end
      end
    end

    def step_mode
      RunningScript.instance.step
    end

    def run_mode
      RunningScript.instance.go
    end

    OpenC3.disable_warnings do
      def start(procedure_name, line_no: 1, end_line_no: nil, bind_variables: false, complete: false)
        RunningScript.instance.execute_while_paused_info = nil
        path = procedure_name

        # Check RAM based instrumented cache
        breakpoints = RunningScript.breakpoints[path]&.filter { |_, present| present }&.map { |line_number, _| line_number - 1 } # -1 because frontend lines are 0-indexed
        breakpoints ||= []

        instrumented_script = nil
        instrumented_cache = nil
        text = nil
        if line_no == 1 and end_line_no.nil?
          instrumented_cache, text = RunningScript.instrumented_cache[path]
        end

        if instrumented_cache
          # Use cached instrumentation
          instrumented_script = instrumented_cache
          cached = true
          running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :file, filename: procedure_name, text: text.to_utf8, breakpoints: breakpoints })
        else
          # Retrieve file
          text = ::Script.body(RunningScript.instance.scope, procedure_name)
          raise "Unable to retrieve: #{procedure_name}" unless text
          running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :file, filename: procedure_name, text: text.to_utf8, breakpoints: breakpoints })

          # Cache instrumentation into RAM
          if line_no == 1 and end_line_no.nil?
            instrumented_script = RunningScript.instrument_script(text, path, true)
            RunningScript.instrumented_cache[path] = [instrumented_script, text]
          else
            if line_no > 1 or not end_line_no.nil?
              text_lines = text.lines

              # Instrument only the specified lines
              if end_line_no.nil?
                end_line_no = text_lines.length
              end

              if line_no < 1 or line_no > text_lines.length
                raise "Invalid start line number: #{line_no} for #{procedure_name}"
              end

              if end_line_no < 1 or end_line_no > text_lines.length
                raise "Invalid end line number: #{end_line_no} for #{procedure_name}"
              end

              if line_no > end_line_no
                raise "Start line number #{line_no} is greater than end line number #{end_line_no} for #{procedure_name}"
              end

              text = text_lines[(line_no - 1)...end_line_no].join
            end

            if bind_variables
              instrumented_script = RunningScript.instrument_script(text, path, false, line_offset: line_no - 1, cache: false)
            else
              instrumented_script = RunningScript.instrument_script(text, path, true, line_offset: line_no - 1, cache: false)
            end
          end

          cached = false
        end
        running = ScriptStatusModel.all(scope: RunningScript.instance.scope, type: 'running')
        running_script_anycable_publish("all-scripts-channel", { type: :start, filename: procedure_name, active_scripts: running.length, scope: RunningScript.instance.scope })

        if bind_variables
          eval(instrumented_script, RunningScript.instance.script_binding, path, line_no)
        else
          Object.class_eval(instrumented_script, path, line_no)
        end

        if complete
          RunningScript.instance.script_status.state = 'completed'
          RunningScript.instance.script_status.end_time = Time.now.utc.iso8601
          RunningScript.instance.script_status.update(queued: true)
          raise OpenC3::StopScript
        end

        # Return whether we had to load and instrument this file, i.e. it was not cached
        !cached
      end

      def goto(line_no_or_procedure_name, line_no = nil)
        if line_no.nil?
          start(RunningScript.instance.current_filename, line_no: line_no_or_procedure_name, bind_variables: true, complete: true)
        else
          start(line_no_or_procedure_name, line_no: line_no, bind_variables: true, complete: true)
        end
      end

      # Require an additional ruby file
      def load_utility(procedure_name)
        # Ensure load_utility works like require where you don't need the .rb extension
        if File.extname(procedure_name) != '.rb'
          procedure_name += '.rb'
        end
        not_cached = false
        if defined? RunningScript and RunningScript.instance
          saved = RunningScript.instance.use_instrumentation
          begin
            RunningScript.instance.use_instrumentation = false
            not_cached = start(procedure_name)
          ensure
            RunningScript.instance.use_instrumentation = saved
          end
        else # Just call require
          not_cached = require(procedure_name)
        end
        # Return whether we had to load and instrument this file, i.e. it was not cached
        # This is designed to match the behavior of Ruby's require and load keywords
        not_cached
      end
      alias require_utility load_utility

      # sleep in a script - returns true if canceled mid sleep
      def openc3_script_sleep(sleep_time = nil)
        return true if $disconnect
        RunningScript.instance.update_running_script_store("waiting")
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :line, filename: RunningScript.instance.current_filename, line_no: RunningScript.instance.current_line_number, state: :waiting })

        sleep_time = 30000000 unless sleep_time # Handle infinite wait
        if sleep_time > 0.0
          end_time = Time.now.sys + sleep_time
          count = 0
          until Time.now.sys >= end_time
            sleep(0.01)
            count += 1
            if (count % 100) == 0 # Approximately Every Second
              running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :line, filename: RunningScript.instance.current_filename, line_no: RunningScript.instance.current_line_number, state: :waiting })
            end
            if RunningScript.instance.pause?
              RunningScript.instance.perform_pause
              return true
            end
            return true if RunningScript.instance.go?
            raise StopScript if RunningScript.instance.stop?
          end
        end
        return false
      end

      def display_screen(target_name, screen_name, x = nil, y = nil, scope: RunningScript.instance.scope)
        definition = get_screen_definition(target_name, screen_name, scope: scope)
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :screen, target_name: target_name, screen_name: screen_name, definition: definition, x: x, y: y })
      end

      def clear_screen(target_name, screen_name)
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :clearscreen, target_name: target_name, screen_name: screen_name })
      end

      def clear_all_screens
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :clearallscreens })
      end

      def local_screen(screen_name, definition, x = nil, y = nil)
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :screen, target_name: "LOCAL", screen_name: screen_name, definition: definition, x: x, y: y })
      end

      def download_file(path, scope: RunningScript.instance.scope)
        url = _get_download_url(path, scope: scope)
        running_script_anycable_publish("running-script-channel:#{RunningScript.instance.id}", { type: :downloadfile, filename: File.basename(path), url: url })
      end
    end
  end
end

class RunningScript
  def id
    return @script_status.id
  end
  def scope
    return @script_status.scope
  end
  def filename
    return @script_status.filename
  end
  def current_filename
    return @script_status.current_filename
  end
  def current_line_number
    return @script_status.line_no
  end

  attr_accessor :use_instrumentation
  attr_accessor :continue_after_error
  attr_accessor :exceptions
  attr_accessor :script_binding
  attr_accessor :user_input
  attr_accessor :prompt_id
  attr_reader :script_status
  attr_accessor :execute_while_paused_info

  # This REGEX is also found in scripts_controller.rb
  # Matches the following test cases:
  # class  MySuite  <  TestSuite
  #   class MySuite < OpenC3::Suite
  # class MySuite < Cosmos::TestSuite
  # class MySuite < Suite # comment
  # # class MySuite < Suite # <-- doesn't match commented out
  SUITE_REGEX = /^(\s*)?class\s+\w+\s+<\s+(Cosmos::|OpenC3::)?(Suite|TestSuite)/

  @@instance = nil
  @@message_log = nil
  @@run_thread = nil
  @@breakpoints = {}
  @@line_delay = 0.1
  @@max_output_characters = 50000
  @@instrumented_cache = {}
  @@file_cache = {}
  @@output_thread = nil
  @@pause_on_error = true
  @@error = nil
  @@output_sleeper = OpenC3::Sleeper.new
  @@cancel_output = false

  def self.message_log
    return @@message_log if @@message_log

    if @@instance
      scope = @@instance.scope
      tags = [File.basename(@@instance.filename, '.rb').gsub(/(\s|\W)/, '_')]
    else
      scope = $openc3_scope
      tags = []
    end
    @@message_log = OpenC3::MessageLog.new("sr", File.join(RAILS_ROOT, 'log'), tags: tags, scope: scope)
  end

  def message_log
    self.class.message_log
  end

  def self.spawn(scope, name, suite_runner = nil, disconnect = false, environment = nil, user_full_name = nil, username = nil, line_no = nil, end_line_no = nil)
    if File.extname(name) == '.py'
      process_name = 'python'
      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_script.py')
    else
      process_name = 'ruby'
      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_script.rb')
    end

    running_script_id = OpenC3::Store.incr('running-script-id')

    # COSMOS Core username (Enterprise has the actual name)
    username ||= 'Anonymous'
    # COSMOS Core full name (Enterprise has the actual name)
    user_full_name ||= 'Anonymous'
    start_time = Time.now.utc.iso8601

    process = ChildProcess.build(process_name, runner_path.to_s, running_script_id.to_s, scope)
    process.io.inherit! # Helps with debugging
    process.cwd = File.join(RAILS_ROOT, 'scripts')

    # Check for offline access token
    model = nil
    model = OpenC3::OfflineAccessModel.get_model(name: username, scope: scope) if username != 'Anonymous'

    # Load the global environment variables
    status_environment = {}
    values = OpenC3::EnvironmentModel.all(scope: scope).values
    values.each do |env|
      process.environment[env['key']] = env['value']
      status_environment[env['key']] = env['value']
    end
    # Load the script specific ENV vars set by the GUI
    # These can override the previously defined global env vars
    if environment
      environment.each do |env|
        process.environment[env['key']] = env['value']
        status_environment[env['key']] = env['value']
      end
    end

    script_status = OpenC3::ScriptStatusModel.new(
      name: running_script_id.to_s, # Unique id for this script
      state: 'spawning', # State will be spawning until the script is running
      shard: 0, # Future enhancement of script runner shards
      filename: name, # Initial filename never changes
      current_filename: name, # Current filename updates while we are running
      line_no: 0, # 0 means not running yet
      start_line_no: line_no || 1, # Line number to start running the script
      end_line_no: end_line_no || nil, # Line number to stop running the script
      username: username, # username of the person who started the script
      user_full_name: user_full_name, # full name of the person who started the script
      start_time: start_time, # Time the script started ISO format
      end_time: nil, # Time the script ended ISO format
      disconnect: disconnect, # Disconnect is set to true if the script is running in a disconnected mode
      environment: status_environment.as_json(:allow_nan => true).to_json(:allow_nan => true), # nil or Hash of key/value pairs for environment variables
      suite_runner: suite_runner ? suite_runner.as_json(:allow_nan => true).to_json(:allow_nan => true) : nil,
      errors: nil, # array of errors that occurred during the script run
      pid: nil, # pid of the script process - set by the script itself when it starts
      updated_at: nil, # Set by create/update - ISO format
      scope: scope # Scope of the script
    )
    script_status.create(isoformat: true)

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
        raise "No authentication available for script"
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

    process.detach = true
    process.start
    running_script_id
  end

  def initialize(script_status)
    @@instance = self
    @script_status = script_status
    @script_status.pid = Process.pid
    @user_input = ''
    @prompt_id = nil
    @line_offset = 0
    @output_io = StringIO.new('', 'r+')
    @output_io_mutex = Mutex.new
    @continue_after_error = true
    @debug_text = nil
    @debug_history = []
    @debug_code_completion = nil
    @output_time = Time.now.sys

    initialize_variables()
    update_running_script_store("init")
    redirect_io() # Redirect $stdout and $stderr
    mark_breakpoints(@script_status.filename)
    disconnect_script() if @script_status.disconnect

    # Retrieve file
    @body = ::Script.body(@script_status.scope, @script_status.filename)
    raise "Script not found: #{@script_status.filename}" if @body.nil?
    breakpoints = @@breakpoints[@script_status.filename]&.filter { |_, present| present }&.map { |line_number, _| line_number - 1 } # -1 because frontend lines are 0-indexed
    breakpoints ||= []
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :file, filename: @script_status.filename, scope: @script_status.scope, text: @body.to_utf8, breakpoints: breakpoints })
    if (@body =~ SUITE_REGEX)
      # Process the suite file in this context so we can load it
      # TODO: Do we need to worry about success or failure of the suite processing?
      ::Script.process_suite(@script_status.filename, @body, new_process: false, scope: @script_status.scope)
      # Call load_utility to parse the suite and allow for individual methods to be executed
      load_utility(@script_status.filename)
    end
  end

  # Called to update the running script state every time the state or line_no changes
  def update_running_script_store(state = nil)
    @script_status.state = state if state
    @script_status.update(queued: true)
  end

  def parse_options(options)
    settings = {}
    if options.include?('manual')
      settings['Manual'] = true
      $manual = true
    else
      settings['Manual'] = false
      $manual = false
    end
    if options.include?('pauseOnError')
      settings['Pause on Error'] = true
      @@pause_on_error = true
    else
      settings['Pause on Error'] = false
      @@pause_on_error = false
    end
    if options.include?('continueAfterError')
      settings['Continue After Error'] = true
      @continue_after_error = true
    else
      settings['Continue After Error'] = false
      @continue_after_error = false
    end
    if options.include?('abortAfterError')
      settings['Abort After Error'] = true
      OpenC3::Test.abort_on_exception = true
    else
      settings['Abort After Error'] = false
      OpenC3::Test.abort_on_exception = false
    end
    if options.include?('loop')
      settings['Loop'] = true
    else
      settings['Loop'] = false
    end
    if options.include?('breakLoopOnError')
      settings['Break Loop On Error'] = true
    else
      settings['Break Loop On Error'] = false
    end
    OpenC3::SuiteRunner.settings = settings
  end

  # Let the script continue pausing if in step mode
  def continue
    @go = true
    @pause = true if @step
  end

  # Sets step mode and lets the script continue but with pause set
  def step
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :step, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
    @step = true
    @go = true
    @pause = true
  end

  # Clears step mode and lets the script continue
  def go
    @step = false
    @go = true
    @pause = false
  end

  def go?
    temp = @go
    @go = false
    temp
  end

  def pause
    @pause = true
    @go    = false
  end

  def pause?
    @pause
  end

  def stop
    if @@run_thread
      @stop = true
      @script_status.end_time = Time.now.utc.iso8601
      update_running_script_store("stopped")
      OpenC3.kill_thread(self, @@run_thread)
      @@run_thread = nil
    end
  end

  def stop?
    @stop
  end

  def clear_prompt
    # Allow things to continue once the prompt is cleared
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :script, prompt_complete: @prompt_id })
    @prompt_id = nil
  end

  # Private methods

  def graceful_kill
    @stop = true
  end

  def initialize_variables
    @@error = nil
    @go = false
    @pause = false
    @step = false
    @stop = false
    @retry_needed = false
    @use_instrumentation = true
    @call_stack = []
    @pre_line_time = Time.now.sys
    @exceptions = nil
    @script_binding = nil
    @inline_eval = nil
    @script_status.current_filename = @script_status.filename
    @script_status.line_no = 0
    @current_file = nil
    @execute_while_paused_info = nil
  end

  def unique_filename
    if @script_status.filename and !@script_status.filename.empty?
      return @script_status.filename
    else
      return "Untitled" + @script_status.id.to_s
    end
  end

  def stop_message_log
    metadata = {
      "id" => @script_status.id,
      "user" => @script_status.username,
      "scriptname" => unique_filename()
    }
    if @@message_log
      @script_status.log = @@message_log.stop(true, metadata: metadata)
      @script_status.update
    end
    @@message_log = nil
  end

  def self.instance
    @@instance
  end

  def self.instance=(value)
    @@instance = value
  end

  def self.line_delay
    @@line_delay
  end

  def self.line_delay=(value)
    @@line_delay = value
  end

  def self.max_output_characters
    @@max_output_characters
  end

  def self.max_output_characters=(value)
    @@max_output_characters = value
  end

  def self.breakpoints
    @@breakpoints
  end

  def self.instrumented_cache
    @@instrumented_cache
  end

  def self.instrumented_cache=(value)
    @@instrumented_cache = value
  end

  def self.file_cache
    @@file_cache
  end

  def self.file_cache=(value)
    @@file_cache = value
  end

  def self.pause_on_error
    @@pause_on_error
  end

  def self.pause_on_error=(value)
    @@pause_on_error = value
  end

  def text
    @body
  end

  def retry_needed
    @retry_needed = true
  end

  def run
    run_text(@body)
  end

  def self.instrument_script(text, filename, mark_private = false, line_offset: 0, cache: true)
    if cache and filename and !filename.empty?
      @@file_cache[filename] = text.clone
    end

    ruby_lex_utils = RubyLexUtils.new
    instrumented_text = ''

    @cancel_instrumentation = false
    num_lines = text.num_lines.to_f
    num_lines = 1 if num_lines < 1
    instrumented_text =
      instrument_script_implementation(ruby_lex_utils,
                                       text,
                                       num_lines,
                                       filename,
                                       mark_private,
                                       line_offset)

    raise OpenC3::StopScript if @cancel_instrumentation
    instrumented_text
  end

  def self.instrument_script_implementation(ruby_lex_utils,
                                            text,
                                            _num_lines,
                                            filename,
                                            mark_private = false,
                                            line_offset = 0)
    if mark_private
      instrumented_text = 'private; '
    else
      instrumented_text = ''
    end

    ruby_lex_utils.each_lexed_segment(text) do |segment, instrumentable, inside_begin, line_no|
      return nil if @cancel_instrumentation
      instrumented_line = ''
      if instrumentable
        # Add a newline if it's empty to ensure the instrumented code has
        # the same number of lines as the original script
        if segment.strip.empty?
          instrumented_text << "\n"
          next
        end

        # Create a variable to hold the segment's return value
        instrumented_line << "__return_val = nil; "

        # If not inside a begin block then create one to catch exceptions
        unless inside_begin
          instrumented_line << 'begin; '
        end

        # Add preline instrumentation
        instrumented_line << "RunningScript.instance.script_binding = binding(); "\
          "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no + line_offset}); "

        # Add the actual line
        instrumented_line << "__return_val = begin; "
        instrumented_line << segment
        instrumented_line.chomp!

        # Add postline instrumentation
        instrumented_line << " end; RunningScript.instance.post_line_instrumentation('#{filename}', #{line_no + line_offset}); "

        # Complete begin block to catch exceptions
        unless inside_begin
          instrumented_line << "rescue Exception => eval_error; "\
          "retry if RunningScript.instance.exception_instrumentation(eval_error, '#{filename}', #{line_no + line_offset}); end; "
        end

        instrumented_line << " __return_val\n"
      else
        unless segment =~ /^\s*end\s*$/ or segment =~ /^\s*when .*$/
          num_left_brackets = segment.count('{')
          num_right_brackets = segment.count('}')
          num_left_square_brackets = segment.count('[')
          num_right_square_brackets = segment.count(']')

          if (num_right_brackets > num_left_brackets) ||
            (num_right_square_brackets > num_left_square_brackets)
            instrumented_line = segment
          else
            instrumented_line = "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no + line_offset}); " + segment
          end
        else
          instrumented_line = segment
        end
      end

      instrumented_text << instrumented_line
    end
    instrumented_text
  end

  def pre_line_instrumentation(filename, line_number)
    @script_status.current_filename = filename
    @script_status.line_no = line_number
    if @use_instrumentation
      # Clear go
      @go = false

      # Handle stopping mid-script if necessary
      raise OpenC3::StopScript if @stop

      handle_potential_tab_change(filename)

      # Adjust line number for offset in main script
      line_number = line_number + @line_offset
      detail_string = nil
      if filename
        detail_string = File.basename(filename) << ':' << line_number.to_s
        OpenC3::Logger.detail_string = detail_string
      end

      update_running_script_store("running")
      running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
      handle_pause(filename, line_number)
      handle_line_delay()
    end
  end

  def post_line_instrumentation(filename, line_number)
    if @use_instrumentation
      line_number = line_number + @line_offset
      handle_output_io(filename, line_number)
    end
  end

  def exception_instrumentation(error, filename, line_number)
    if error.class <= OpenC3::StopScript || error.class <= OpenC3::SkipScript || !@use_instrumentation
      raise error
    elsif !error.eql?(@@error)
      line_number = line_number + @line_offset
      handle_exception(error, false, filename, line_number)
    end
  end

  def perform_wait(prompt)
    mark_waiting()
    wait_for_go_or_stop(prompt: prompt)
  end

  def perform_pause
    mark_paused()
    wait_for_go_or_stop()
  end

  def perform_breakpoint(filename, line_number)
    mark_breakpoint()
    scriptrunner_puts "Hit Breakpoint at #{filename}:#{line_number}"
    handle_output_io(filename, line_number)
    wait_for_go_or_stop()
  end

  def debug(debug_text)
    handle_output_io()

    if @script_binding
      # Check for accessing an instance variable or local
      if debug_text =~ /^@\S+$/ || @script_binding.local_variables.include?(debug_text.to_sym)
        debug_text = "puts #{debug_text}" # Automatically add puts to print it
      end
      eval(debug_text, @script_binding, 'debug', 1)
    else
      Object.class_eval(debug_text, 'debug', 1)
    end
    handle_output_io()
  rescue Exception => e
    if e.class == DRb::DRbConnError
      OpenC3::Logger.error("Error Connecting to Command and Telemetry Server")
    else
      OpenC3::Logger.error(e.class.to_s.split('::')[-1] + ' : ' + e.message)
    end
    handle_output_io()
  end

  def self.set_breakpoint(filename, line_number)
    @@breakpoints[filename] ||= {}
    @@breakpoints[filename][line_number] = true
  end

  def self.clear_breakpoint(filename, line_number)
    @@breakpoints[filename] ||= {}
    @@breakpoints[filename].delete(line_number) if @@breakpoints[filename][line_number]
  end

  def self.clear_breakpoints(filename = nil)
    if filename == nil or filename.empty?
      @@breakpoints = {}
    else
      @@breakpoints.delete(filename)
    end
  end

  def clear_breakpoints
    ScriptRunnerFrame.clear_breakpoints(unique_filename())
  end

  def current_backtrace
    trace = []
    if @@run_thread
      temp_trace = @@run_thread.backtrace
      temp_trace.each do |line|
        next if line.include?(OpenC3::PATH)    # Ignore OpenC3 internals
        next if line.include?('lib/ruby/gems') # Ignore system gems
        next if line.include?('app/models/running_script') # Ignore this file
        trace << line
      end
    end
    trace
  end

  def execute_while_paused(filename, line_no = 1, end_line_no = nil)
    if @script_status.state == 'paused' or @script_status.state == 'error' or @script_status.state == 'breakpoint'
      @execute_while_paused_info = { filename: filename, line_no: line_no, end_line_no: end_line_no }
    else
      scriptrunner_puts("Cannot execute selection or goto unless script is paused, breakpoint, or in error state")
    end
  end

  def scriptrunner_puts(string, color = 'BLACK')
    line_to_write = Time.now.sys.formatted + " (SCRIPTRUNNER): " + string
    $stdout.puts line_to_write
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :output, line: line_to_write, color: color })
  end

  def handle_output_io(filename = nil, line_number = nil)
    filename = @script_status.current_filename if filename.nil?
    line_number = @script_status.line_no if line_number.nil?

    @output_time = Time.now.sys
    if @output_io.string[-1..-1] == "\n"
      time_formatted = Time.now.sys.formatted
      color = 'BLACK'
      lines_to_write = ''
      out_line_number = line_number.to_s
      out_filename = File.basename(filename) if filename

      # Build each line to write
      string = @output_io.string.clone
      @output_io.string = @output_io.string[string.length..-1]
      line_count = 0
      string.each_line(chomp: true) do |out_line|
        begin
          json = JSON.parse(out_line, :allow_nan => true, :create_additions => true)
          time_formatted = Time.parse(json["@timestamp"]).sys.formatted if json["@timestamp"]
          if json["log"]
            out_line = json["log"]
          elsif json["message"]
            out_line = json["message"]
          end
        rescue
          # Regular output
        end

        if out_line.length >= 25 and out_line[0..1] == '20' and out_line[10] == ' ' and out_line[23..24] == ' ('
          line_to_write = out_line
        else
          if filename
            line_to_write = time_formatted + " (#{out_filename}:#{out_line_number}): " + out_line
          else
            line_to_write = time_formatted + " (SCRIPTRUNNER): " + out_line
            color = 'BLUE'
          end
        end
        lines_to_write << (line_to_write + "\n")
        line_count += 1
      end # string.each_line

      if lines_to_write.length > @@max_output_characters
        # We want the full @@max_output_characters so don't subtract the additional "ERROR: ..." text
        published_lines = lines_to_write[0...@@max_output_characters]
        published_lines << "\nERROR: Too much to publish. Truncating #{lines_to_write.length} characters of output to #{@@max_output_characters} characters.\n"
      else
        published_lines = lines_to_write
      end
      running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :output, line: published_lines.as_json(:allow_nan => true), color: color })
      # Add to the message log
      message_log.write(lines_to_write)
    end
  end

  def graceful_kill
    # Just to avoid warning
  end

  def wait_for_go_or_stop(error = nil, prompt: nil)
    count = -1
    @go = false
    @prompt_id = prompt['id'] if prompt
    until (@go or @stop)
      check_execute_while_paused()
      sleep(0.01)
      count += 1
      if count % 100 == 0 # Approximately Every Second
        running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
        running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :script, method: prompt['method'], prompt_id: prompt['id'], args: prompt['args'], kwargs: prompt['kwargs'] }) if prompt
      end
    end
    clear_prompt() if prompt
    RunningScript.instance.prompt_id = nil
    @go = false
    mark_running()
    raise OpenC3::StopScript if @stop
    raise error if error and !@continue_after_error
  end

  def wait_for_go_or_stop_or_retry(error = nil)
    count = 0
    @go = false
    until (@go or @stop or @retry_needed)
      check_execute_while_paused()
      sleep(0.01)
      count += 1
      if (count % 100) == 0 # Approximately Every Second
        running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
      end
    end
    @go = false
    mark_running()
    raise OpenC3::StopScript if @stop
    raise error if error and !@continue_after_error
  end

  def check_execute_while_paused
    if @execute_while_paused_info
      if @script_status.current_filename == @execute_while_paused_info[:filename]
        bind_variables = true
      else
        bind_variables = false
      end
      if @execute_while_paused_info[:end_line_no]
        # Execute Selection While Paused
        state = @script_status.state
        current_filename = @script_status.current_filename
        line_no = @script_status.line_no
        start(@execute_while_paused_info[:filename], line_no: @execute_while_paused_info[:line_no], end_line_no: @execute_while_paused_info[:end_line_no], bind_variables: bind_variables)
        # Need to restore state after returning so that the correct line will be shown in ScriptRunner
        @script_status.state = state
        @script_status.current_filename = current_filename
        @script_status.line_no = line_no
        @script_status.update(queued: true)
        running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
      else
        # Goto While Paused
        start(@execute_while_paused_info[:filename], line_no: @execute_while_paused_info[:line_no], bind_variables: bind_variables, complete: true)
      end
    end
  ensure
    @execute_while_paused_info = nil
  end

  def mark_running
    update_running_script_store("running")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def mark_paused
    update_running_script_store("paused")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def mark_waiting
    update_running_script_store("waiting")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def mark_error
    update_running_script_store("error")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def mark_crashed
    @script_status.end_time = Time.now.utc.iso8601
    update_running_script_store("crashed")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def mark_completed
    @script_status.end_time = Time.now.utc.iso8601
    update_running_script_store("completed")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
    if OpenC3::SuiteRunner.suite_results
      OpenC3::SuiteRunner.suite_results.complete
      # context looks like the following:
      # MySuite:ExampleGroup:script_2
      # MySuite:ExampleGroup Manual Setup
      # MySuite Manual Teardown
      init_split = OpenC3::SuiteRunner.suite_results.context.split()
      parts = init_split[0].split(':')
      if parts[2]
        # Remove test_ or script_ because it doesn't add any info
        parts[2] = parts[2].sub(/^test_/, '').sub(/^script_/, '')
      end
      parts.map! { |part| part[0..9] } # Only take the first 10 characters to prevent huge filenames
      # If the initial split on whitespace has more than 1 item it means
      # a Manual Setup or Teardown was performed. Add this to the filename.
      # NOTE: We're doing this here with a single underscore to preserve
      # double underscores as Suite, Group, Script delimiters
      if parts[1] and init_split.length > 1
        parts[1] += "_#{init_split[-1]}"
      elsif parts[0] and init_split.length > 1
        parts[0] += "_#{init_split[-1]}"
      end
      running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :report, report: OpenC3::SuiteRunner.suite_results.report })
      # Write out the report to a local file
      log_dir = File.join(RAILS_ROOT, 'log')
      filename = File.join(log_dir, File.build_timestamped_filename(['sr', parts.join('__')]))
      File.open(filename, 'wb') do |file|
        file.write(OpenC3::SuiteRunner.suite_results.report)
      end
      # Generate the bucket key by removing the date underscores in the filename to create the bucket file structure
      bucket_key = File.join("#{@script_status.scope}/tool_logs/sr/", File.basename(filename)[0..9].gsub("_", ""), File.basename(filename))
      metadata = {
        # Note: The chars '(' and ')' are used by RunningScripts.vue to differentiate between script logs
        "id" => @script_status.id,
        "user" => @script_status.username,
        "scriptname" => "#{@script_status.current_filename} (#{OpenC3::SuiteRunner.suite_results.context.strip})"
      }
      thread = OpenC3::BucketUtilities.move_log_file_to_bucket(filename, bucket_key, metadata: metadata)
      # Wait for the file to get moved to S3 because after this the process will likely die
      @script_status.report = bucket_key
      @script_status.update(queued: true)
      thread.join
    end
    running_script_publish("cmd-running-script-channel:#{@script_status.id}", "shutdown")
  end

  def mark_breakpoint
    update_running_script_store("breakpoint")
    running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :line, filename: @script_status.current_filename, line_no: @script_status.line_no, state: @script_status.state })
  end

  def run_text(text,
               initial_filename: nil)
    initialize_variables()
    saved_instance = @@instance
    saved_run_thread = @@run_thread
    @@instance = self

    @@run_thread = Thread.new do
      begin
        # Capture STDOUT and STDERR
        $stdout.add_stream(@output_io)
        $stderr.add_stream(@output_io)

        output = "Starting script: #{File.basename(@script_status.filename)}"
        output += " in DISCONNECT mode" if $disconnect
        output += ", line_delay = #{@@line_delay}"
        scriptrunner_puts(output)
        handle_output_io()

        # Start Output Thread
        @@output_thread = Thread.new { output_thread() } unless @@output_thread

        if initial_filename == 'SCRIPTRUNNER'
          # Don't instrument pseudo scripts
          instrument_filename = initial_filename
          instrumented_script = text
        else
          # Instrument everything else
          instrument_filename = @script_status.filename
          instrument_filename = initial_filename if initial_filename
          instrumented_script = self.class.instrument_script(text, instrument_filename, true)
        end

        # Execute the script with warnings disabled
        OpenC3.disable_warnings do
          @pre_line_time = Time.now.sys
          Object.class_eval(instrumented_script, instrument_filename, 1)
        end

        handle_output_io()
        scriptrunner_puts "Script completed: #{@script_status.filename}"

      rescue Exception => e # rubocop:disable Lint/RescueException
        if e.class <= OpenC3::StopScript or e.class <= OpenC3::SkipScript
          handle_output_io()
          scriptrunner_puts "Script stopped: #{@script_status.filename}"
        else
          filename, line_number = e.source
          handle_exception(e, true, filename, line_number)
          handle_output_io()
          scriptrunner_puts "Exception in Control Statement - Script stopped: #{@script_status.filename}"
          mark_crashed()
        end
      ensure
        # Stop Capturing STDOUT and STDERR
        # Check for remove_stream because if the tool is quitting the
        # OpenC3::restore_io may have been called which sets $stdout and
        # $stderr to the IO constant
        $stdout.remove_stream(@output_io) if $stdout.respond_to? :remove_stream
        $stderr.remove_stream(@output_io) if $stderr.respond_to? :remove_stream

        # Clear run thread and instance to indicate we are no longer running
        @@instance = saved_instance
        @@run_thread = saved_run_thread
        @active_script = @script
        @script_binding = nil
        # Set the current_filename to the original file and the line_no to 0
        # so the mark_complete method will signal the frontend to reset to the original
        @script_status.current_filename = @script_status.filename
        @script_status.line_no = 0
        if @@output_thread and not @@instance
          @@cancel_output = true
          @@output_sleeper.cancel
          OpenC3.kill_thread(self, @@output_thread)
          @@output_thread = nil
        end
        mark_completed()
      end
    end
  end

  def handle_potential_tab_change(filename)
    # Make sure the correct file is shown in script runner
    if @current_file != filename
      if @call_stack.include?(filename)
        index = @call_stack.index(filename)
      else # new file
        @call_stack.push(filename.dup)
        load_file_into_script(filename)
      end

      @current_file = filename
    end
  end

  def handle_pause(filename, line_number)
    breakpoint = false
    breakpoint = true if @@breakpoints[filename] and @@breakpoints[filename][line_number]

    filename = File.basename(filename)
    if @pause
      @pause = false unless @step
      if breakpoint
        perform_breakpoint(filename, line_number)
      else
        perform_pause()
      end
    else
      perform_breakpoint(filename, line_number) if breakpoint
    end
  end

  def handle_line_delay
    if @@line_delay > 0.0
      sleep_time = @@line_delay - (Time.now.sys - @pre_line_time)
      sleep(sleep_time) if sleep_time > 0.0
    end
    @pre_line_time = Time.now.sys
  end

  def handle_exception(error, fatal, filename = nil, line_number = 0)
    @exceptions ||= []
    @exceptions << error
    @script_status.errors ||= []
    @script_status.errors << error.formatted
    @@error = error

    if error.class == DRb::DRbConnError
      OpenC3::Logger.error("Error Connecting to Command and Telemetry Server")
    elsif error.class == OpenC3::CheckError
      OpenC3::Logger.error(error.message)
    else
      OpenC3::Logger.error(error.class.to_s.split('::')[-1] + ' : ' + error.message)
      if ENV['OPENC3_FULL_BACKTRACE']
        OpenC3::Logger.error(error.backtrace.join("\n\n"))
      end
    end
    handle_output_io(filename, line_number)

    raise error if !@@pause_on_error and !@continue_after_error and !fatal

    if !fatal and @@pause_on_error
      mark_error()
      wait_for_go_or_stop_or_retry(error)
    end

    if @retry_needed
      @retry_needed = false
      true
    else
      false
    end
  end

  def load_file_into_script(filename)
    mark_breakpoints(filename)
    breakpoints = @@breakpoints[filename]&.filter { |_, present| present }&.map { |line_number, _| line_number - 1 } # -1 because frontend lines are 0-indexed
    breakpoints ||= []
    cached = @@file_cache[filename]
    if cached
      @body = cached
      running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :file, filename: filename, text: @body.to_utf8, breakpoints: breakpoints })
    else
      text = ::Script.body(@script_status.scope, filename)
      raise "Script not found: #{filename}" if text.nil?
      @@file_cache[filename] = text
      @body = text
      running_script_anycable_publish("running-script-channel:#{@script_status.id}", { type: :file, filename: filename, text: @body.to_utf8, breakpoints: breakpoints })
    end
  end

  def mark_breakpoints(filename)
    breakpoints = @@breakpoints[filename]
    if breakpoints
      breakpoints.each do |line_number, present|
        RunningScript.set_breakpoint(filename, line_number) if present
      end
    else
      ::Script.get_breakpoints(@script_status.scope, filename).each do |line_number|
        RunningScript.set_breakpoint(filename, line_number + 1)
      end
    end
  end

  def redirect_io
    # Redirect Standard Output and Standard Error
    $stdout = OpenC3::Stdout.instance
    $stderr = OpenC3::Stderr.instance
    OpenC3::Logger.stdout = true
    OpenC3::Logger.level = OpenC3::Logger::INFO
  end

  def output_thread
    @@cancel_output = false
    @@output_sleeper = OpenC3::Sleeper.new
    begin
      loop do
        break if @@cancel_output
        handle_output_io() if (Time.now.sys - @output_time) > 5.0
        break if @@cancel_output
        break if @@output_sleeper.sleep(1.0)
      end # loop
    rescue => e
      # Qt.execute_in_main_thread(true) do
      #  ExceptionDialog.new(self, error, "Output Thread")
      # end
    end
  end

end
