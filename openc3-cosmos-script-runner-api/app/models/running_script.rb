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
require 'openc3/models/offline_access_model'
require 'openc3/models/environment_model'
require 'openc3/utilities/bucket_require'

RAILS_ROOT = File.expand_path(File.join(__dir__, '..', '..'))

module OpenC3
  module Script
    private
    # Define all the user input methods used in scripting which we need to broadcast to the frontend
    # Note: This list matches the list in run_script.rb:116
    SCRIPT_METHODS = %i[ask ask_string message_box vertical_message_box combo_box prompt prompt_for_hazardous
      metadata_input open_file_dialog open_files_dialog]
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
      def start(procedure_name)
        path = procedure_name

        # Check RAM based instrumented cache
        breakpoints = RunningScript.breakpoints[path]&.filter { |_, present| present }&.map { |line_number, _| line_number - 1 } # -1 because frontend lines are 0-indexed
        breakpoints ||= []
        instrumented_cache, text = RunningScript.instrumented_cache[path]
        instrumented_script = nil
        if instrumented_cache
          # Use cached instrumentation
          instrumented_script = instrumented_cache
          cached = true
          OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :file, filename: procedure_name, text: text.to_utf8, breakpoints: breakpoints }))
        else
          # Retrieve file
          text = ::Script.body(RunningScript.instance.scope, procedure_name)
          raise "Unable to retrieve: #{procedure_name}" unless text
          OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :file, filename: procedure_name, text: text.to_utf8, breakpoints: breakpoints }))

          # Cache instrumentation into RAM
          instrumented_script = RunningScript.instrument_script(text, path, true)
          RunningScript.instrumented_cache[path] = [instrumented_script, text]
          cached = false
        end
        running = OpenC3::Store.smembers("running-scripts")
        running ||= []
        OpenC3::Store.publish(["script-api", "all-scripts-channel"].compact.join(":"), JSON.generate({ type: :start, filename: procedure_name, active_scripts: running.length }))
        Object.class_eval(instrumented_script, path, 1)

        # Return whether we had to load and instrument this file, i.e. it was not cached
        !cached
      end

      # Require an additional ruby file
      def load_utility(procedure_name)
        # Ensure require_utility works like require where you don't need the .rb extension
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
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :line, filename: RunningScript.instance.current_filename, line_no: RunningScript.instance.current_line_number, state: :waiting }))

        sleep_time = 30000000 unless sleep_time # Handle infinite wait
        if sleep_time > 0.0
          end_time = Time.now.sys + sleep_time
          count = 0
          until Time.now.sys >= end_time
            sleep(0.01)
            count += 1
            if (count % 100) == 0 # Approximately Every Second
              OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :line, filename: RunningScript.instance.current_filename, line_no: RunningScript.instance.current_line_number, state: :waiting }))
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
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :screen, target_name: target_name, screen_name: screen_name, definition: definition, x: x, y: y }))
      end

      def clear_screen(target_name, screen_name)
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :clearscreen, target_name: target_name, screen_name: screen_name }))
      end

      def clear_all_screens
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :clearallscreens }))
      end

      def local_screen(screen_name, definition, x = nil, y = nil)
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :screen, target_name: "LOCAL", screen_name: screen_name, definition: definition, x: x, y: y }))
      end

      def download_file(path, scope: RunningScript.instance.scope)
        url = get_download_url(path, scope: scope)
        OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :downloadfile, filename: File.basename(path), url: url }))
      end
    end
  end
end

class RunningScript
  attr_accessor :id
  attr_accessor :state
  attr_accessor :scope
  attr_accessor :name

  attr_accessor :use_instrumentation
  attr_reader :filename
  attr_reader :current_filename
  attr_reader :current_line_number
  attr_accessor :continue_after_error
  attr_accessor :exceptions
  attr_accessor :script_binding
  attr_reader :script_class
  attr_reader :top_level_instrumented_cache
  attr_reader :script
  attr_accessor :user_input
  attr_accessor :prompt_id

  # This REGEX is also found in scripts_controller.rb
  # Matches the following test cases:
  # class  MySuite  <  TestSuite
  #   class MySuite < OpenC3::Suite
  # class MySuite < Cosmos::TestSuite
  # class MySuite < Suite # comment
  # # class MySuite < Suite # <-- doesn't match commented out
  SUITE_REGEX = /^(\s*)?class\s+\w+\s+<\s+(Cosmos::|OpenC3::)?(Suite|TestSuite)/

  @@instance = nil
  @@id = nil
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

  def self.message_log(_id = @@id)
    return @@message_log if @@message_log

    if @@instance
      scope =  @@instance.scope
      tags = [File.basename(@@instance.filename, '.rb').gsub(/(\s|\W)/, '_')]
    else
      scope = $openc3_scope
      tags = []
    end
    @@message_log = OpenC3::MessageLog.new("sr", File.join(RAILS_ROOT, 'log'), tags: tags, scope: scope)
  end

  def message_log
    self.class.message_log(@id)
  end

  def self.all
    array = OpenC3::Store.smembers('running-scripts')
    items = []
    array.each do |member|
      items << JSON.parse(member, :allow_nan => true, :create_additions => true)
    end
    items.sort { |a, b| b['id'] <=> a['id'] }
  end

  def self.find(id)
    result = OpenC3::Store.get("running-script:#{id}").to_s
    if result.length > 0
      JSON.parse(result, :allow_nan => true, :create_additions => true)
    else
      return nil
    end
  end

  def self.delete(id)
    OpenC3::Store.del("running-script:#{id}")
    running = OpenC3::Store.smembers("running-scripts")
    running.each do |item|
      parsed = JSON.parse(item, :allow_nan => true, :create_additions => true)
      if parsed["id"].to_s == id.to_s
        OpenC3::Store.srem("running-scripts", item)
        break
      end
    end
  end

  def self.spawn(scope, name, suite_runner = nil, disconnect = false, environment = nil, user_full_name = nil, username = nil)
    if File.extname(name) == '.py'
      process_name = 'python'
      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_script.py')
    else
      process_name = 'ruby'
      runner_path = File.join(RAILS_ROOT, 'scripts', 'run_script.rb')
    end
    running_script_id = OpenC3::Store.incr('running-script-id')

    # Open Source full name (EE has the actual name)
    user_full_name ||= 'Anonymous'
    start_time = Time.now
    details = {
      id: running_script_id,
      scope: scope,
      name: name,
      user: user_full_name,
      start_time: start_time.to_s,
      disconnect: disconnect,
      environment: environment
    }
    OpenC3::Store.sadd('running-scripts', details.as_json(:allow_nan => true).to_json(:allow_nan => true))
    details[:hostname] = Socket.gethostname
    # details[:pid] = process.pid
    details[:state] = :spawning
    details[:line_no] = 1
    details[:update_time] = start_time.to_s
    details[:suite_runner] = suite_runner.as_json(:allow_nan => true).to_json(:allow_nan => true) if suite_runner
    OpenC3::Store.set("running-script:#{running_script_id}", details.as_json(:allow_nan => true).to_json(:allow_nan => true))

    process = ChildProcess.build(process_name, runner_path.to_s, running_script_id.to_s)
    process.io.inherit! # Helps with debugging
    process.cwd = File.join(RAILS_ROOT, 'scripts')

    # Check for offline access token
    model = nil
    model = OpenC3::OfflineAccessModel.get_model(name: username, scope: scope) if username and username != ''

    # Load the global environment variables
    values = OpenC3::EnvironmentModel.all(scope: scope).values
    values.each do |env|
      process.environment[env['key']] = env['value']
    end
    # Load the script specific ENV vars set by the GUI
    # These can override the previously defined global env vars
    if environment
      environment.each do |env|
        process.environment[env['key']] = env['value']
      end
    end

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

    process.start
    running_script_id
  end

  # Parameters are passed to RunningScript.new as strings because
  # RunningScript.spawn must pass strings to ChildProcess.build
  def initialize(id, scope, name, disconnect)
    @@instance = self
    @id = id
    @@id = id
    @scope = scope
    @name = name
    @filename = name
    @user_input = ''
    @prompt_id = nil
    @line_offset = 0
    @output_io = StringIO.new('', 'r+')
    @output_io_mutex = Mutex.new
    @allow_start = true
    @continue_after_error = true
    @debug_text = nil
    @debug_history = []
    @debug_code_completion = nil
    @top_level_instrumented_cache = nil
    @output_time = Time.now.sys
    @state = :init

    initialize_variables()
    redirect_io() # Redirect $stdout and $stderr
    mark_breakpoints(@filename)
    disconnect_script() if disconnect

    # Get details from redis

    details = OpenC3::Store.get("running-script:#{id}")
    if details
      @details = JSON.parse(details, :allow_nan => true, :create_additions => true)
    else
      # Create as much details as we know
      @details = { id: @id, name: @filename, scope: @scope, start_time: Time.now.to_s, update_time: Time.now.to_s }
    end

    # Update details in redis
    @details[:hostname] = Socket.gethostname
    @details[:state] = @state
    @details[:line_no] = 1
    @details[:update_time] = Time.now.to_s
    OpenC3::Store.set("running-script:#{id}", @details.as_json(:allow_nan => true).to_json(:allow_nan => true))

    # Retrieve file
    @body = ::Script.body(@scope, name)
    breakpoints = @@breakpoints[filename]&.filter { |_, present| present }&.map { |line_number, _| line_number - 1 } # -1 because frontend lines are 0-indexed
    breakpoints ||= []
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"),
                          JSON.generate({ type: :file, filename: @filename, scope: @scope, text: @body.to_utf8, breakpoints: breakpoints }))
    if (@body =~ SUITE_REGEX)
      # Process the suite file in this context so we can load it
      # TODO: Do we need to worry about success or failure of the suite processing?
      ::Script.process_suite(name, @body, new_process: false, scope: @scope)
      # Call load_utility to parse the suite and allow for individual methods to be executed
      load_utility(name)
    end
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
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :step, filename: @current_filename, line_no: @current_line_number, state: @state }))
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
      OpenC3.kill_thread(self, @@run_thread)
      @@run_thread = nil
    end
  end

  def stop?
    @stop
  end

  def clear_prompt
    # Allow things to continue once the prompt is cleared
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :script, prompt_complete: @prompt_id }))
    @prompt_id = nil
  end

  def as_json(*_args)
    { id: @id, state: @state, filename: @current_filename, line_no: @current_line_no }
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
    @current_file = @filename
    @exceptions = nil
    @script_binding = nil
    @inline_eval = nil
    @current_filename = nil
    @current_line_number = 0

    @call_stack.push(@current_file.dup)
  end

  def unique_filename
    if @filename and !@filename.empty?
      return @filename
    else
      return "Untitled" + @id.to_s
    end
  end

  def stop_message_log
    metadata = {
      "user" => @details['user'],
      "scriptname" => unique_filename()
    }
    @@message_log.stop(true, metadata: metadata) if @@message_log
    @@message_log = nil
  end

  # TODO: Is this ever called?
  def filename=(filename)
    # Stop the message log so a new one will be created with the new filename
    stop_message_log()
    @filename = filename

    # Deal with breakpoints created under the previous filename.
    bkpt_filename = unique_filename()
    if @@breakpoints[bkpt_filename].nil?
      @@breakpoints[bkpt_filename] = @@breakpoints[@filename]
    end
    if bkpt_filename != @filename
      @@breakpoints.delete(@filename)
      @filename = bkpt_filename
    end
    mark_breakpoints(@filename)
  end

  attr_writer :allow_start

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

  def set_text(text, filename = '')
    unless running?()
      @filename = filename
      mark_breakpoints(@filename)
      @body = text
    end
  end

  def self.running?
    if @@run_thread then true else false end
  end

  def running?
    if @@instance == self and RunningScript.running?() then true else false end
  end

  def retry_needed
    @retry_needed = true
  end

  def run
    unless self.class.running?()
      run_text(@body)
    end
  end

  def run_and_close_on_complete(text_binding = nil)
    run_text(@body, 0, text_binding, true)
  end

  def self.instrument_script(text, filename, mark_private = false)
    if filename and !filename.empty?
      @@file_cache[filename] = text.clone
    end

    ruby_lex_utils = RubyLexUtils.new
    instrumented_text = ''

    @cancel_instrumentation = false
    comments_removed_text = ruby_lex_utils.remove_comments(text)
    num_lines = comments_removed_text.num_lines.to_f
    num_lines = 1 if num_lines < 1
    instrumented_text =
      instrument_script_implementation(ruby_lex_utils,
                                        comments_removed_text,
                                        num_lines,
                                        filename,
                                        mark_private)

    raise OpenC3::StopScript if @cancel_instrumentation
    instrumented_text
  end

  def self.instrument_script_implementation(ruby_lex_utils,
                                            comments_removed_text,
                                            _num_lines,
                                            filename,
                                            mark_private = false)
    if mark_private
      instrumented_text = 'private; '
    else
      instrumented_text = ''
    end

    ruby_lex_utils.each_lexed_segment(comments_removed_text) do |segment, instrumentable, inside_begin, line_no|
      return nil if @cancel_instrumentation
      instrumented_line = ''
      if instrumentable
        # Add a newline if it's empty to ensure the instrumented code has
        # the same number of lines as the original script. Note that the
        # segment could have originally had comments but they were stripped in
        # ruby_lex_utils.remove_comments
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
          "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); "

        # Add the actual line
        instrumented_line << "__return_val = begin; "
        instrumented_line << segment
        instrumented_line.chomp!

        # Add postline instrumentation
        instrumented_line << " end; RunningScript.instance.post_line_instrumentation('#{filename}', #{line_no}); "

        # Complete begin block to catch exceptions
        unless inside_begin
          instrumented_line << "rescue Exception => eval_error; "\
          "retry if RunningScript.instance.exception_instrumentation(eval_error, '#{filename}', #{line_no}); end; "
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
            instrumented_line = "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); " + segment
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
    @current_filename = filename
    @current_line_number = line_number
    if @use_instrumentation
      # Clear go
      @go = false

      # Handle stopping mid-script if necessary
      raise OpenC3::StopScript if @stop

      handle_potential_tab_change(filename)

      # Adjust line number for offset in main script
      line_number = line_number + @line_offset # if @active_script.object_id == @script.object_id
      detail_string = nil
      if filename
        detail_string = File.basename(filename) << ':' << line_number.to_s
        OpenC3::Logger.detail_string = detail_string
      end

      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: :running }))
      handle_pause(filename, line_number)
      handle_line_delay()
    end
  end

  def post_line_instrumentation(filename, line_number)
    if @use_instrumentation
      line_number = line_number + @line_offset # if @active_script.object_id == @script.object_id
      handle_output_io(filename, line_number)
    end
  end

  def exception_instrumentation(error, filename, line_number)
    if error.class <= OpenC3::StopScript || error.class <= OpenC3::SkipScript || !@use_instrumentation
      raise error
    elsif !error.eql?(@@error)
      line_number = line_number + @line_offset # if @active_script.object_id == @script.object_id
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
    if not running?
      # Capture STDOUT and STDERR
      $stdout.add_stream(@output_io)
      $stderr.add_stream(@output_io)
    end

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
  ensure
    if not running?
      # Capture STDOUT and STDERR
      $stdout.remove_stream(@output_io)
      $stderr.remove_stream(@output_io)
    end
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

  def scriptrunner_puts(string, color = 'BLACK')
    line_to_write = Time.now.sys.formatted + " (SCRIPTRUNNER): " + string
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :output, line: line_to_write, color: color }))
  end

  def handle_output_io(filename = @current_filename, line_number = @current_line_number)
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
          out_line = json["log"] if json["log"]
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
      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :output, line: published_lines.as_json(:allow_nan => true), color: color }))
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
      sleep(0.01)
      count += 1
      if count % 100 == 0 # Approximately Every Second
        OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
        OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :script, method: prompt['method'], prompt_id: prompt['id'], args: prompt['args'], kwargs: prompt['kwargs'] })) if prompt
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
      sleep(0.01)
      count += 1
      if (count % 100) == 0 # Approximately Every Second
        OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
      end
    end
    @go = false
    mark_running()
    raise OpenC3::StopScript if @stop
    raise error if error and !@continue_after_error
  end

  def mark_running
    @state = :running
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def mark_paused
    @state = :paused
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def mark_waiting
    @state = :waiting
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def mark_error
    @state = :error
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def mark_fatal
    @state = :fatal
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def mark_stopped
    @state = :stopped
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
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
      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :report, report: OpenC3::SuiteRunner.suite_results.report }))
      # Write out the report to a local file
      log_dir = File.join(RAILS_ROOT, 'log')
      filename = File.join(log_dir, File.build_timestamped_filename(['sr', parts.join('__')]))
      File.open(filename, 'wb') do |file|
        file.write(OpenC3::SuiteRunner.suite_results.report)
      end
      # Generate the bucket key by removing the date underscores in the filename to create the bucket file structure
      bucket_key = File.join("#{@scope}/tool_logs/sr/", File.basename(filename)[0..9].gsub("_", ""), File.basename(filename))
      metadata = {
        # Note: The chars '(' and ')' are used by RunningScripts.vue to differentiate between script logs
        "user" => @details['user'],
        "scriptname" => "#{@current_filename} (#{OpenC3::SuiteRunner.suite_results.context.strip})"
      }
      thread = OpenC3::BucketUtilities.move_log_file_to_bucket(filename, bucket_key, metadata: metadata)
      # Wait for the file to get moved to S3 because after this the process will likely die
      thread.join
    end
    OpenC3::Store.publish(["script-api", "cmd-running-script-channel:#{@id}"].compact.join(":"), JSON.generate("shutdown"))
  end

  def mark_breakpoint
    @state = :breakpoint
    OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
  end

  def run_text(text,
               line_offset = 0,
               text_binding = nil,
               close_on_complete = false,
               initial_filename: nil)
    initialize_variables()
    @line_offset = line_offset
    saved_instance = @@instance
    saved_run_thread = @@run_thread
    @@instance = self
    if initial_filename
      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :file, filename: initial_filename, text: text.to_utf8, breakpoints: [] }))
    end
    @@run_thread = Thread.new do
      begin
        # Capture STDOUT and STDERR
        $stdout.add_stream(@output_io)
        $stderr.add_stream(@output_io)

        unless close_on_complete
          output = "Starting script: #{File.basename(@filename)}"
          output += " in DISCONNECT mode" if $disconnect
          scriptrunner_puts(output)
        end
        handle_output_io()

        # Start Output Thread
        @@output_thread = Thread.new { output_thread() } unless @@output_thread

        # Check top level cache
        if @top_level_instrumented_cache &&
          (@top_level_instrumented_cache[1] == line_offset) &&
          (@top_level_instrumented_cache[2] == @filename) &&
          (@top_level_instrumented_cache[0] == text)
          # Use the instrumented cache
          instrumented_script = @top_level_instrumented_cache[3]
        else
          instrument_filename = @filename
          instrument_filename = initial_filename if initial_filename
          # Instrument the script
          if text_binding
            instrumented_script = self.class.instrument_script(text, instrument_filename, false)
          else
            instrumented_script = self.class.instrument_script(text, instrument_filename, true)
          end
          @top_level_instrumented_cache = [text, line_offset, instrument_filename, instrumented_script]
        end

        # Execute the script with warnings disabled
        OpenC3.disable_warnings do
          @pre_line_time = Time.now.sys
          if text_binding
            eval(instrumented_script, text_binding, @filename, 1)
          else
            Object.class_eval(instrumented_script, @filename, 1)
          end
        end

        handle_output_io()
        scriptrunner_puts "Script completed: #{File.basename(@filename)}" unless close_on_complete

      rescue Exception => e # rubocop:disable Lint/RescueException
        if e.class <= OpenC3::StopScript or e.class <= OpenC3::SkipScript
          handle_output_io()
          scriptrunner_puts "Script stopped: #{File.basename(@filename)}"
        else
          filename, line_number = e.source
          handle_exception(e, true, filename, line_number)
          handle_output_io()
          scriptrunner_puts "Exception in Control Statement - Script stopped: #{File.basename(@filename)}"
          mark_fatal()
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
        # Set the current_filename to the original file and the current_line_number to 0
        # so the mark_stopped method will signal the frontend to reset to the original
        @current_filename = @filename
        @current_line_number = 0
        if @@output_thread and not @@instance
          @@cancel_output = true
          @@output_sleeper.cancel
          OpenC3.kill_thread(self, @@output_thread)
          @@output_thread = nil
        end
        mark_stopped()
        @current_filename = nil
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
    @@error = error

    if error.class == DRb::DRbConnError
      OpenC3::Logger.error("Error Connecting to Command and Telemetry Server")
    elsif error.class == OpenC3::CheckError
      OpenC3::Logger.error(error.message)
    else
      OpenC3::Logger.error(error.class.to_s.split('::')[-1] + ' : ' + error.message)
      if ENV['OPENC3_FULL_BACKTRACE']
        relevent_lines = error.backtrace
      else
        relevent_lines = error.backtrace.select { |line| !line.include?("/src/app") && !line.include?("/openc3/lib") && !line.include?("/usr/lib/ruby") }
      end
      OpenC3::Logger.error(relevent_lines.join("\n\n")) unless relevent_lines.empty?
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
      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :file, filename: filename, text: @body.to_utf8, breakpoints: breakpoints }))
    else
      text = ::Script.body(@scope, filename)
      @@file_cache[filename] = text
      @body = text
      OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :file, filename: filename, text: @body.to_utf8, breakpoints: breakpoints }))
    end
  end

  def mark_breakpoints(filename)
    breakpoints = @@breakpoints[filename]
    if breakpoints
      breakpoints.each do |line_number, present|
        RunningScript.set_breakpoint(filename, line_number) if present
      end
    else
      ::Script.get_breakpoints(@scope, filename).each do |line_number|
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
