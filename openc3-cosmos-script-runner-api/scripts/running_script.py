# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
from io import StringIO
from inspect import getsourcefile
import json
import uuid
import re
import time
import socket
import sys
import traceback
from datetime import datetime
from threading import Lock
import openc3.script
from openc3.environment import *
from openc3.utilities.store import Store

RAILS_ROOT = os.path.abspath(os.path.join(getsourcefile(lambda:0), '..'))

class RunningScript:
    # Matches the following test cases:
    # class MySuite(TestSuite)
    # class MySuite(Suite)
    SUITE_REGEX = re.compile("^(\s*)?class\s+\w+\((Suite|TestSuite)\)")

    instance = None
    id = None
    message_log = None
    run_thread = None
    breakpoints = {}
    line_delay = 0.1
    max_output_characters = 50000
    instrumented_cache = {}
    file_cache = {}
    output_thread = None
    pause_on_error = True
    error = None
    output_sleeper = Sleeper()
    cancel_output = False
    manual = True

    @classmethod
    def message_log(cls):
        if cls.message_log:
            return cls.message_log

        if cls.instance:
            scope = cls.instance.scope
            basename = os.path.splitext(os.path.basename(cls.instance.filename))[0]
            regex = re.compile("(\s|\W)")
            tags = [regex.sub(regex, '_', basename)]
        else:
            scope = OPENC3_SCOPE
            tags = []
        cls.message_log = MessageLog.new("sr", os.path.join(RAILS_ROOT, 'log'), tags = tags, scope = scope)

    def message_log(self):
        self.__class__.message_log()

    def script_body(self, scope, name):
        pass # TODO

    # Parameters are passed to RunningScript.new as strings because
    # RunningScript.spawn must pass strings to ChildProcess.build
    def __init__(self, id, scope, name, disconnect):
        self.instance = self
        self.id = id
        self.scope = scope
        self.name = name
        self.filename = name
        self.user_input = ''
        self.prompt_id = None
        self.line_offset = 0
        self.output_io = StringIO('')
        self.output_io_mutex = Lock()
        self.allow_start = True
        self.continue_after_error = True
        self.debug_text = None
        self.debug_history = []
        self.debug_code_completion = None
        self.top_level_instrumented_cache = None
        self.output_time = datetime.now().isoformat()
        self.state = "init"

        self.initialize_variables()
        self.redirect_io() # Redirect $stdout and $stderr
        self.mark_breakpoints(self.filename)
        if disconnect:
            self.disconnect_script()

        # Get details from redis

        details = Store.get(f"running-script:{self.id}")
        if details:
            self.details = json.loads(details)
        else:
            # Create as much details as we know
            self.details = { 'id': self.id, 'name': self.filename, 'scope': self.scope, 'start_time': self.output_time, 'update_time': self.output_time }

        # Update details in redis
        self.details['hostname'] = socket.gethostname()
        self.details['state'] = self.state
        self.details['line_no'] = 1
        self.details['update_time'] = self.output_time
        Store.set(f"running-script:{self.id}", json.dumps(self.details))

        # Retrieve file
        self.body = self.script_body(self.scope, self.name)
        breakpoints = []
        if self.filename in self.breakpoints:
            my_breakpoints = self.breakpoints[self.filename]
            for key in my_breakpoints:
                breakpoints.append(key - 1) # -1 because frontend lines are 0-indexed
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'file', 'filename': self.filename, 'scope': self.scope, 'text': self.body, 'breakpoints': breakpoints }))
        if self.SUITE_REGEX.match(self.body):
            # Process the suite file in this context so we can load it
            # TODO: Do we need to worry about success or failure of the suite processing?
            # ::Script.process_suite(name, @body, new_process: false, scope: @scope)
            # Call load_utility to parse the suite and allow for individual methods to be executed
            # load_utility(name)
            pass # TODO

    def parse_options(self, options):
        settings = {}
        if 'manual' in options:
            settings['Manual'] = True
            self.manual = True
        else:
            settings['Manual'] = False
            self.manual = False

        if 'pauseOnError' in options:
            settings['Pause on Error'] = True
            self.pause_on_error = True
        else:
            settings['Pause on Error'] = False
            self.pause_on_error = False

        if 'continueAfterError' in options:
            settings['Continue After Error'] = True
            self.continue_after_error = True
        else:
            settings['Continue After Error'] = False
            self.continue_after_error = False

        if 'abortAfterError' in options:
          settings['Abort After Error'] = True
          # TODO: Test.abort_on_exception = True
        else:
          settings['Abort After Error'] = False
          # TODO: Test.abort_on_exception = False

        if 'loop' in options:
            settings['Loop'] = True
        else:
            settings['Loop'] = False

        if 'breakLoopOnError' in options:
            settings['Break Loop On Error'] = True
        else:
            settings['Break Loop On Error'] = False

        # TODO: SuiteRunner.settings = settings

    # Let the script continue pausing if in step mode (continue cannot be method name)
    def do_continue(self):
        self.go = True
        if self.step:
            self.pause = True

    # Sets step mode and lets the script continue but with pause set
    def do_step(self):
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'step', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))
        self.step = True
        self.go = True
        self.pause = True

    # Clears step mode and lets the script continue
    def do_go(self):
        self.step = False
        self.go = True
        self.pause = False

    def check_and_clear_go(self):
        temp = self.go
        self.go = False
        return temp

    def do_pause(self):
        self.pause = True
        self.go = False

    def do_stop(self):
        if self.run_thread:
            self.stop = True
            # TODO: OpenC3.kill_thread(self, @@run_thread)
            self.run_thread = None

    def clear_prompt(self):
        # Allow things to continue once the prompt is cleared
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'script', 'prompt_complete': self.prompt_id }))
        self.prompt_id = None

    def as_json(self):
        return { 'id': self.id, 'state': self.state, 'filename': self.current_filename, 'line_no': self.current_line_no }

    # Private methods

    def graceful_kill(self):
        self.stop = True

    def initialize_variables(self):
        self.error = None
        self.go = False
        self.pause = False
        self.step = False
        self.stop = False
        self.retry_needed = False
        self.use_instrumentation = True
        self.call_stack = []
        self.pre_line_time = time.time()
        self.current_file = self.filename
        self.exceptions = None
        self.script_binding = [{}, {}]
        self.inline_eval = None
        self.current_filename = None
        self.current_line_number = 0
        self.call_stack.append(self.current_file)

    def unique_filename(self):
        if self.filename and not self.filename == '':
            return self.filename
        else:
            return "Untitled" + str(self.id)

    def stop_message_log(self):
        metadata = {
          "scriptname": self.unique_filename()
        }
        if self.message_log:
            self.message_log.stop(True, metadata = metadata)
        self.message_log = None

    def set_filename(self, filename):
        # Stop the message log so a new one will be created with the new filename
        self.stop_message_log()
        self.filename = filename

        # Deal with breakpoints created under the previous filename.
        bkpt_filename = self.unique_filename()
        if not bkpt_filename in self.breakpoints:
            self.breakpoints[bkpt_filename] = self.breakpoints[self.filename]
        if bkpt_filename != self.filename:
            del self.breakpoints[self.filename]
            self.filename = bkpt_filename
        self.scopemark_breakpoints(self.filename)

    def text(self):
        return self.body

    def set_text(self, text, filename = ''):
        if not self.running():
            self.filename = filename
            self.mark_breakpoints(self.filename)
            self.body = text

    def running(self):
        if self.run_thread:
            return True
        else:
            return False

    def set_retry_needed(self):
        self.retry_needed = True

    def run(self):
        if not self.running():
            self.run_text(self.body)

    def run_and_close_on_complete(self, text_binding = None):
        self.run_text(self.body, 0, text_binding, True)

    @classmethod
    def instrument_script(cls, text, filename):
        # TODO
        # if filename and not filename == '':
        #     self.file_cache[filename] = text

        # ruby_lex_utils = RubyLexUtils.new
        # instrumented_text = ''

        # @cancel_instrumentation = false
        # comments_removed_text = ruby_lex_utils.remove_comments(text)
        # num_lines = comments_removed_text.num_lines.to_f
        # num_lines = 1 if num_lines < 1
        # instrumented_text =
        #   instrument_script_implementation(ruby_lex_utils,
        #                                     comments_removed_text,
        #                                     num_lines,
        #                                     filename,
        #                                     mark_private)

        # raise OpenC3::StopScript if @cancel_instrumentation
        # instrumented_text
        pass

    # def self.instrument_script_implementation(ruby_lex_utils,
    #                                           comments_removed_text,
    #                                           num_lines,
    #                                           filename,
    #                                           mark_private = false)
    #   if mark_private
    #     instrumented_text = 'private; '
    #   else
    #     instrumented_text = ''
    #   end

    #   ruby_lex_utils.each_lexed_segment(comments_removed_text) do |segment, instrumentable, inside_begin, line_no|
    #     return nil if @cancel_instrumentation
    #     instrumented_line = ''
    #     if instrumentable
    #       # Add a newline if it's empty to ensure the instrumented code has
    #       # the same number of lines as the original script. Note that the
    #       # segment could have originally had comments but they were stripped in
    #       # ruby_lex_utils.remove_comments
    #       if segment.strip.empty?
    #         instrumented_text << "\n"
    #         next
    #       end

    #       # Create a variable to hold the segment's return value
    #       instrumented_line << "__return_val = nil; "

    #       # If not inside a begin block then create one to catch exceptions
    #       unless inside_begin
    #         instrumented_line << 'begin; '
    #       end

    #       # Add preline instrumentation
    #       instrumented_line << "RunningScript.instance.script_binding = binding(); "\
    #         "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); "

    #       # Add the actual line
    #       instrumented_line << "__return_val = begin; "
    #       instrumented_line << segment
    #       instrumented_line.chomp!

    #       # Add postline instrumentation
    #       instrumented_line << " end; RunningScript.instance.post_line_instrumentation('#{filename}', #{line_no}); "

    #       # Complete begin block to catch exceptions
    #       unless inside_begin
    #         instrumented_line << "rescue Exception => eval_error; "\
    #         "retry if RunningScript.instance.exception_instrumentation(eval_error, '#{filename}', #{line_no}); end; "
    #       end

    #       instrumented_line << " __return_val\n"
    #     else
    #       unless segment =~ /^\s*end\s*$/ or segment =~ /^\s*when .*$/
    #         num_left_brackets = segment.count('{')
    #         num_right_brackets = segment.count('}')
    #         num_left_square_brackets = segment.count('[')
    #         num_right_square_brackets = segment.count(']')

    #         if (num_right_brackets > num_left_brackets) ||
    #           (num_right_square_brackets > num_left_square_brackets)
    #           instrumented_line = segment
    #         else
    #           instrumented_line = "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); " + segment
    #         end
    #       else
    #         instrumented_line = segment
    #       end
    #     end

    #     instrumented_text << instrumented_line
    #   end
    #   instrumented_text
    # end

    def pre_line_instrumentation(self, filename, line_number):
        self.current_filename = filename
        self.current_line_number = line_number
        if self.use_instrumentation:
            # Clear go
            self.go = False

            # Handle stopping mid-script if necessary
            if self.stop:
                raise StopScript

            self.handle_potential_tab_change(filename)

            # Adjust line number for offset in main script
            line_number = line_number + self.line_offset
            detail_string = None
            if filename:
                detail_string = os.path.basename(filename) + ':' + str(line_number)
                Logger.detail_string = detail_string

            Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': 'running' }))
            self.handle_pause(filename, line_number)
            self.handle_line_delay()

    def post_line_instrumentation(self, filename, line_number):
        if self.use_instrumentation:
            line_number = line_number + self.line_offset
            self.handle_output_io(filename, line_number)

    def exception_instrumentation(self, error, filename, line_number):
        if error.__class__ == StopScript or error.__class__ == SkipScript or not self.use_instrumentation:
            raise error
        elif not error == self.error:
            line_number = line_number + self.line_offset
            self.handle_exception(error, False, filename, line_number)

    def perform_wait(self, prompt):
        self.mark_waiting()
        self.wait_for_go_or_stop(prompt = prompt)

    def perform_pause(self):
        self.mark_paused()
        self.wait_for_go_or_stop()

    def perform_breakpoint(self, filename, line_number):
        self.mark_breakpoint()
        self.scriptrunner_puts(f"Hit Breakpoint at {filename}:{line_number}")
        self.handle_output_io(filename, line_number)
        self.wait_for_go_or_stop()

    def debug(self, debug_text):
        try:
            self.handle_output_io()
            if not self.running():
                # Capture STDOUT and STDERR
                $stdout.add_stream(@output_io)
                $stderr.add_stream(@output_io)

            if self.script_binding:
                # Check for accessing an instance variable or local
                if debug_text in self.script_binding[1]: # In local variables
                    debug_text = f"print({debug_text})" # Automatically add print to print it
                eval(debug_text, globals = self.script_binding[0], locals = self.script_binding[1])
            else:
                eval(debug_text)

            self.handle_output_io()
        except Exception as error:
            if error.__class__ == DRbConnError:
                Logger.error("Error Connecting to Command and Telemetry Server")
            else:
                Logger.error(error.class.to_s.split('::')[-1] + ' : ' + error.message)
            self.handle_output_io()
        finally:
            if not running()
                # Capture STDOUT and STDERR
                $stdout.remove_stream(@output_io)
                $stderr.remove_stream(@output_io)

    @classmethod
    def set_breakpoint(cls, filename, line_number):
        if not filename in cls.breakpoints:
            cls.breakpoints[filename] = {}
        cls.breakpoints[filename][line_number] = True

    @classmethod
    def clear_breakpoint(cls, filename, line_number):
        if not filename in cls.breakpoints:
            cls.breakpoints[filename] = {}
        if line_number in cls.breakpoints[filename]:
            del cls.breakpoints[filename][line_number]

    @classmethod
    def clear_breakpoints(cls, filename = None):
        if filename == None or filename == '':
            cls.breakpoints = {}
        else:
            if filename in cls.breakpoints:
                del cls.breakpoints[filename]

    def current_backtrace(self):
        trace = []
        if self.run_thread:
            for filename, lineno, name, line in traceback.extract_stack(sys._current_frames()[self.run_thread.ident]):
                #next if line.include?(OpenC3::PATH)    # Ignore OpenC3 internals
                #next if line.include?('lib/ruby/gems') # Ignore system gems
                #next if line.include?('app/models/running_script') # Ignore this file
                trace.append(f"{filename}:{lineno}:{name}:{line}")
        return trace

    def scriptrunner_puts(self, string, color = 'BLACK'):
        line_to_write = datetime.now.isoformat() + " (SCRIPTRUNNER): " + string
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'output', 'line': line_to_write, 'color': color }))

    def handle_output_io(self, filename = None, line_number = None):
        if not filename:
            filename = self.current_filename
        if not line_number:
            line_number = self.current_line_number
        self.output_time = datetime.now.isoformat()
        if self.output_io.getvalue()[-1] == "\n":
            time_formatted = self.output_time
            color = 'BLACK'
            lines_to_write = ''
            out_line_number = str(line_number)
            if filename:
                out_filename = os.path.basename(filename)

            # Build each line to write
            string = self.output_io.getvalue()
            self.output_io = StringIO('')
            line_count = 0
            for line in string.splitlines():
                line = line.rstrip()
                try:
                    json_hash = json.loads(out_line)
                    if json["@timestamp"]:
                        time_formatted = json["@timestamp"]
                    if "log" in json_hash:
                        out_line = json_hash["log"]
                except:
                    # Regular output
                    pass

                if len(out_line) >= 25 and out_line[0:2] == '20' and out_line[10] == ' ' and out_line[23:25] == ' (':
                    line_to_write = out_line
                else:
                    if filename:
                        line_to_write = time_formatted + f" ({out_filename}:{out_line_number}): " + out_line
                    else:
                        line_to_write = time_formatted + " (SCRIPTRUNNER): " + out_line
                        color = 'BLUE'
                lines_to_write.append(line_to_write + "\n")
                line_count += 1

            if len(lines_to_write) > self.max_output_characters:
                # We want the full @@max_output_characters so don't subtract the additional "ERROR: ..." text
                published_lines = lines_to_write[0:self.max_output_characters]
                published_lines = published_lines + f"\nERROR: Too much to publish. Truncating {len(lines_to_write)} characters of output to {self.max_output_characters} characters.\n"
            else:
                published_lines = lines_to_write

            Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'output', 'line': published_lines, 'color': color }))
            # Add to the message log
            self.message_log().write(lines_to_write)

    def graceful_kill(self):
        # Just to avoid warning
        pass

    def wait_for_go_or_stop(self, error = None, prompt = None):
        count = -1
        self.go = False
        if prompt:
            self.prompt_id = prompt['id']
        while not self.go and not self.stop:
            time.sleep(0.01)
            count += 1
            if count % 100 == 0: # Approximately Every Second
                Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))
                if prompt:
                    Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'script', 'method': prompt['method'], 'prompt_id': prompt['id'], 'args': prompt['args'], 'kwargs': prompt['kwargs'] }))
        if prompt:
            self.clear_prompt()
        RunningScript.instance.prompt_id = None
        self.go = False
        self.mark_running()
        if self.stop:
            raise StopScript
        if error and not self.continue_after_error:
            raise error

    def wait_for_go_or_stop_or_retry(error = nil)
        count = 0
        @go = false
        until (@go or @stop or @retry_needed)
          sleep(0.01)
          count += 1
          if (count % 100) == 0 # Approximately Every Second
            OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :line, filename: @current_filename, line_no: @current_line_number, state: @state }))
        @go = false
        mark_running()
        raise OpenC3::StopScript if @stop
        raise error if error and !@continue_after_error

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
        OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :report, report: OpenC3::SuiteRunner.suite_results.report }))
        # Write out the report to a local file
        log_dir = File.join(RAILS_ROOT, 'log')
        filename = File.join(log_dir, File.build_timestamped_filename(['sr', 'report']))
        File.open(filename, 'wb') do |file|
          file.write(OpenC3::SuiteRunner.suite_results.report)
        end
        # Generate the bucket key by removing the date underscores in the filename to create the bucket file structure
        bucket_key = File.join("#{@scope}/tool_logs/sr/", File.basename(filename)[0..9].gsub("_", ""), File.basename(filename))
        metadata = {
          # Note: The text 'Script Report' is used by RunningScripts.vue to differentiate between script logs
          "scriptname" => "#{@current_filename} (Script Report)"
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
                  close_on_complete = false)
      initialize_variables()
      @line_offset = line_offset
      saved_instance = @@instance
      saved_run_thread = @@run_thread
      @@instance   = self
      @@run_thread = Thread.new do
        uncaught_exception = false
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
            # Instrument the script
            if text_binding
              instrumented_script = self.class.instrument_script(text, @filename, false)
            else
              instrumented_script = self.class.instrument_script(text, @filename, true)
            end
            @top_level_instrumented_cache = [text, line_offset, @filename, instrumented_script]
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

        rescue Exception => error
          if error.class <= OpenC3::StopScript or error.class <= OpenC3::SkipScript
            handle_output_io()
            scriptrunner_puts "Script stopped: #{File.basename(@filename)}"
          else
            uncaught_exception = true
            filename, line_number = error.source
            handle_exception(error, true, filename, line_number)
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
      rescue => error
        # Qt.execute_in_main_thread(true) do
        #  ExceptionDialog.new(self, error, "Output Thread")
        # end

  ##################################################################
  # Override openc3.script functions when running in ScriptRunner
  ##################################################################

  # Define all the user input methods used in scripting which we need to broadcast to the frontend
  # Note: This list matches the list in run_script.rb:116
  SCRIPT_METHODS = ['ask', 'ask_string', 'message_box', 'vertical_message_box', 'combo_box', 'prompt', 'prompt_for_hazardous', 'metadata_input', 'open_file_dialog', 'open_files_dialog']

  for method in SCRIPT_METHODS:
      def my_method(*args, *kwargs):
          while True:
              if RunningScript.instance:
                  RunningScript.instance.scriptrunner_puts(f"{method}({', '.join(args)})")
                  prompt_id = str(uuid.uuid1())
                  RunningScript.instance.perform_wait({ 'method': method, 'id': prompt_id, 'args': args, 'kwargs': kwargs })
                  input = RunningScript.instance.user_input()
                  # All ask and prompt dialogs should include a 'Cancel' button
                  # If they cancel we wait so they can potentially stop
                  if input == 'Cancel':
                      RunningScript.instance.perform_pause()
                  else:
                      if 'open_file' in method:
                          files = []
                          for filename in input:
                              file = _get_storage_file(f"tmp/{filename}", scope = RunningScript.instance.scope)
                              # Set filename method we added to Tempfile in the core_ext
                              file.filename = filename
                              files.append(file)
                          files = files[0] if method == 'open_file_dialog' # Simply return the only file
                          return files
                      else:
                          return input
              else:
                  raise RuntimeError("Script input method called outside of running script")
    setattr(openc3.script, method, my_method)

  def step_mode
      RunningScript.instance.step()
  setattr(openc3.script, 'step_mode', step_mode)

  def run_mode
      RunningScript.instance.go()
  setattr(openc3.script, 'run_mode', run_mode)

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
          if RunningScript.instance.pause:
            RunningScript.instance.perform_pause
            return true
          end
          if RunningScript.instance.check_and_clear_go():
              return True
          if RunningScript.instance.stop:
              raise StopScript

      return False

    def display_screen(target_name, screen_name, x = nil, y = nil, scope: $openc3_scope)
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

    def download_file(file_or_path)
      if file_or_path.respond_to? :read
        data = file_or_path.read
        filename = File.basename(file_or_path.filename)
      else # path
        data = ::Script.body(RunningScript.instance.scope, file_or_path)
        filename = File.basename(file_or_path)
      end
      OpenC3::Store.publish(["script-api", "running-script-channel:#{RunningScript.instance.id}"].compact.join(":"), JSON.generate({ type: :downloadfile, filename: filename, text: data.to_utf8 }))
