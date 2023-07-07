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
import threading
from datetime import datetime
from threading import Lock
import openc3.script
from openc3.environment import *
from openc3.utilities.store import Store
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.message_log import MessageLog
from openc3.utilities.logger import Logger
from openc3.utilities.target_file import TargetFile
from openc3.io.stdout import Stdout
from openc3.io.stderr import Stderr
from openc3.top_level import kill_thread

RAILS_ROOT = os.path.abspath(os.path.join(getsourcefile(lambda:0), '..'))

class StopScript(Exception):
   pass
class SkipScript(Exception):
   pass

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
    disconnect = False

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
        self.disconnect = disconnect

        self.initialize_variables()
        self.redirect_io() # Redirect stdout and stderr
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
        self.body = TargetFile.body(self.scope, self.name)
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
            kill_thread(self, self.run_thread)
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
                sys.stdout.add_stream(self.output_io)
                sys.stderr.add_stream(self.output_io)

            if self.script_binding:
                # Check for accessing an instance variable or local
                if debug_text in self.script_binding[1]: # In local variables
                    debug_text = f"print({debug_text})" # Automatically add print to print it
                eval(debug_text, globals = self.script_binding[0], locals = self.script_binding[1])
            else:
                eval(debug_text)

            self.handle_output_io()
        except Exception as error:
            Logger.error(error.__class__.__name__ + ' : ' + error.message)
            self.handle_output_io()
        finally:
            if not self.running():
                # Capture STDOUT and STDERR
                sys.stdout.remove_stream(self.output_io)
                sys.stderr.remove_stream(self.output_io)

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
        line_to_write = datetime.now().isoformat() + " (SCRIPTRUNNER): " + string
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'output', 'line': line_to_write, 'color': color }))

    def handle_output_io(self, filename = None, line_number = None):
        if not filename:
            filename = self.current_filename
        if not line_number:
            line_number = self.current_line_number
        self.output_time = datetime.now().isoformat()
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

    def wait_for_go_or_stop_or_retry(self, error = None):
        count = 0
        self.go = False
        while not self.go and not self.stop and not self.retry_needed:
            time.sleep(0.01)
            count += 1
            if (count % 100) == 0: # Approximately Every Second
                Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))
        self.go = False
        self.mark_running()
        if self.stop:
            raise StopScript
        if error and not self.continue_after_error:
            raise error

    def mark_running(self):
        self.state = 'running'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def mark_paused(self):
        self.state = 'paused'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def mark_waiting(self):
        self.state = 'waiting'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def mark_error(self):
        self.state = 'error'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def mark_fatal(self):
        self.state = 'fatal'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def mark_stopped(self):
        self.state = 'stopped'
        Store.publish(f"script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))
        # TODO
        # if OpenC3::SuiteRunner.suite_results
        #     OpenC3::SuiteRunner.suite_results.complete
        #     OpenC3::Store.publish(["script-api", "running-script-channel:#{@id}"].compact.join(":"), JSON.generate({ type: :report, report: OpenC3::SuiteRunner.suite_results.report }))
        #     # Write out the report to a local file
        #     log_dir = File.join(RAILS_ROOT, 'log')
        #     filename = File.join(log_dir, File.build_timestamped_filename(['sr', 'report']))
        #     File.open(filename, 'wb') do |file|
        #       file.write(OpenC3::SuiteRunner.suite_results.report)
        #     # Generate the bucket key by removing the date underscores in the filename to create the bucket file structure
        #     bucket_key = File.join("#{@scope}/tool_logs/sr/", File.basename(filename)[0..9].gsub("_", ""), File.basename(filename))
        #     metadata = {
        #       # Note: The text 'Script Report' is used by RunningScripts.vue to differentiate between script logs
        #       "scriptname" => "#{@current_filename} (Script Report)"
        #     }
        #     thread = OpenC3::BucketUtilities.move_log_file_to_bucket(filename, bucket_key, metadata: metadata)
        #     # Wait for the file to get moved to S3 because after this the process will likely die
        #     thread.join
        Store.publish("script-api:cmd-running-script-channel:{self.id}", json.dumps("shutdown"))

    def mark_breakpoint(self):
        self.state = 'breakpoint'
        Store.publish("script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'line', 'filename': self.current_filename, 'line_no': self.current_line_number, 'state': self.state }))

    def run_thread(self, text, line_offset, text_binding, close_on_complete, saved_instance, saved_run_thread):
        uncaught_exception = False
        try:
            # Capture STDOUT and STDERR
            sys.stdout.add_stream(self.output_io)
            sys.stderr.add_stream(self.output_io)

            if not close_on_complete:
                output = f"Starting script: {os.path.basename(self.filename)}"
                if self.disconnect:
                    output += " in DISCONNECT mode"
                self.scriptrunner_puts(output)
            self.handle_output_io()

            # Start Output Thread
            if not self.output_thread:
                self.output_thread = threading.Thread(target = self.output_thread, daemon = True)

            # # Check top level cache
            # if @top_level_instrumented_cache &&
            #   (@top_level_instrumented_cache[1] == line_offset) &&
            #   (@top_level_instrumented_cache[2] == @filename) &&
            #   (@top_level_instrumented_cache[0] == text)
            #   # Use the instrumented cache
            #   instrumented_script = @top_level_instrumented_cache[3]
            # else
            #   # Instrument the script
            #   if text_binding
            #     instrumented_script = self.class.instrument_script(text, @filename, false)
            #   else
            #     instrumented_script = self.class.instrument_script(text, @filename, true)
            #   end
            #   @top_level_instrumented_cache = [text, line_offset, @filename, instrumented_script]
            # end

            # Execute the script
            self.pre_line_time = time.time()
            if text_binding:
                eval(instrumented_script, globals=text_binding[0], locals=text_binding[1])
            else:
                eval(instrumented_script)

            self.handle_output_io()
            if not close_on_complete:
                self.scriptrunner_puts(f"Script completed: {os.path.basename(self.filename)}")

        except Exception as error:
            if error.__class__ == StopScript or error.__class__ == SkipScript:
                self.handle_output_io()
                self.scriptrunner_puts(f"Script stopped: {os.path.basename(self.filename)}")
            else:
                uncaught_exception = True
                exc_type, exc_value, exc_traceback = sys.exc_info()
                filename = exc_traceback.tb_frame.f_code.co_filename
                line_number = exc_traceback.tb_lineno
                self.handle_exception(error, True, filename, line_number)
                self.handle_output_io()
                self.scriptrunner_puts(f"Exception in Control Statement - Script stopped: {os.path.basename(self.filename)}")
                self.mark_fatal()
        finally:
            # Stop Capturing STDOUT and STDERR
            # Check for remove_stream because if the tool is quitting the
            # OpenC3::restore_io may have been called which sets stdout and
            # stderr to the IO constant
            if hasattr(sys.stdout, 'remove_stream'):
                sys.stdout.remove_stream(self.output_io)
            if hasattr(sys.stderr, 'remove_stream'):
                sys.stderr.remove_stream(self.output_io)

            # Clear run thread and instance to indicate we are no longer running
            self.instance = saved_instance
            self.run_thread = saved_run_thread
            self.active_script = self.script
            self.script_binding = None
            # Set the current_filename to the original file and the current_line_number to 0
            # so the mark_stopped method will signal the frontend to reset to the original
            self.current_filename = self.filename
            self.current_line_number = 0
            if self.output_thread and not self.instance:
                self.cancel_output = True
                self.output_sleeper.cancel()
                kill_thread(self, self.output_thread)
                self.output_thread = None
            self.mark_stopped()
            self.current_filename = None

    def run_text(self, text, line_offset = 0, text_binding = None, close_on_complete = False):
        self.initialize_variables()
        self.line_offset = line_offset
        saved_instance = self.instance
        saved_run_thread = self.run_thread
        self.instance = self
        self.run_thread = threading.Thread(target = self.run_thread, args=[text, line_offset, text_binding, close_on_complete, saved_instance, saved_run_thread], daemon = True)

    def handle_potential_tab_change(self, filename):
        # Make sure the correct file is shown in script runner
        if self.current_file != filename:
            if not filename in self.call_stack:
                self.call_stack.append(filename)
                self.load_file_into_script(filename)
            self.current_file = filename

    def handle_pause(self, filename, line_number):
        breakpoint = False
        if filename in self.breakpoints and line_number in self.breakpoints[filename]:
            breakpoint = True

        filename = os.path.basename(filename)
        if self.pause:
            if not self.step:
                self.pause = False
            if breakpoint:
                self.perform_breakpoint(filename, line_number)
            else:
                self.perform_pause()
        elif breakpoint:
            self.perform_breakpoint(filename, line_number)

    def handle_line_delay(self):
      if self.line_delay > 0.0:
          sleep_time = self.line_delay - (time.time() - self.pre_line_time)
          if sleep_time > 0.0:
              time.sleep(sleep_time)
      self.pre_line_time = time.time()

    def handle_exception(self, error, fatal, filename = None, line_number = 0):
        self.exceptions = self.exceptions or []
        self.exceptions.append(error)
        self.error = error

        # if error.__class__ == DRbConnError:
        #     Logger.error("Error Connecting to Command and Telemetry Server")
        # elif error.__class__ == CheckError:
        #     Logger.error(error.message)
        # else:
        # Logger.error(error.__class__.__name__ + ' : ' + error.message)
        exc_type, exc_value, exc_tb = sys.exc_info()
        Logger.error(traceback.format_exception(exc_type, exc_value, exc_tb))
        self.handle_output_io(filename, line_number)

        if not self.pause_on_error and not self.continue_after_error and not fatal:
            raise error

        if not fatal and self.pause_on_error:
            self.mark_error()
            self.wait_for_go_or_stop_or_retry(error)

        if self.retry_needed:
            self.retry_needed = False
            return True
        else:
            return False

    def load_file_into_script(self, filename):
        self.mark_breakpoints(filename)
        breakpoints = []
        if filename in self.breakpoints:
            my_breakpoints = self.breakpoints[filename]
            for key in my_breakpoints:
                breakpoints.append(key - 1) # -1 because frontend lines are 0-indexed
        cached = None
        if filename in self.file_cache:
          cached = self.file_cache[filename]
        if cached:
            self.body = cached
        else:
            text = TargetFile.body(self.scope, filename)
            self.file_cache[filename] = text
            self.body = text
        Store.publish("script-api:running-script-channel:{self.id}", json.dumps({ 'type': 'file', 'filename': filename, 'text': self.body, 'breakpoints': breakpoints }))

    def mark_breakpoints(self, filename):
        breakpoints = []
        if filename in self.breakpoints:
            breakpoints = self.breakpoints[filename]
        if breakpoints:
            for line_number, present in breakpoints.items():
                if present:
                    RunningScript.set_breakpoint(filename, line_number)
        else:
            for line_number in self.script_get_breakpoints(self.scope, filename):
                RunningScript.set_breakpoint(filename, line_number + 1)

    def redirect_io(self):
        # Redirect Standard Output and Standard Error
        sys.stdout = Stdout.instance()
        sys.stderr = Stderr.instance()
        Logger.stdout = True
        Logger.level = Logger.INFO

    def output_thread(self):
        self.cancel_output = False
        self.output_sleeper = Sleeper()
        while True:
            if self.cancel_output:
                break
            if (time.time() - self.output_time) > 5.0:
                self.handle_output_io()
            if self.cancel_output:
                break
            if self.output_sleeper.sleep(1.0):
                break

##################################################################
# Override openc3.script functions when running in ScriptRunner
##################################################################

# Define all the user input methods used in scripting which we need to broadcast to the frontend
# Note: This list matches the list in run_script.rb:116
SCRIPT_METHODS = ['ask', 'ask_string', 'message_box', 'vertical_message_box', 'combo_box', 'prompt', 'prompt_for_hazardous', 'metadata_input', 'open_file_dialog', 'open_files_dialog']

for method in SCRIPT_METHODS:
    def my_method(*args, **kwargs):
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
                            # TODO file = _get_storage_file(f"tmp/{filename}", scope = RunningScript.instance.scope)
                            # Set filename method we added to Tempfile in the core_ext
                            # file.filename = filename
                            # files.append(file)
                            pass
                        if method == 'open_file_dialog': # Simply return the only file
                            files = files[0]
                        return files
                    else:
                        return input
            else:
                raise RuntimeError("Script input method called outside of running script")
    setattr(openc3.script, method, my_method)

def step_mode():
    RunningScript.instance.step()
setattr(openc3.script, 'step_mode', step_mode)

def run_mode():
    RunningScript.instance.go()
setattr(openc3.script, 'run_mode', run_mode)

def start(procedure_name):
    path = procedure_name

    # Check RAM based instrumented cache
    breakpoints = []
    if path in RunningScript.breakpoints:
        my_breakpoints = RunningScript.breakpoints[path]
        for key in my_breakpoints:
            breakpoints.append(key - 1) # -1 because frontend lines are 0-indexed

    instrumented_script = None
    instrument_cache = None
    text = None
    if path in RunningScript.instrumented_cache:
        instrumented_cache, text = RunningScript.instrumented_cache[path]

    if instrumented_cache:
        # Use cached instrumentation
        instrumented_script = instrumented_cache
        cached = True
        Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'file', 'filename': procedure_name, 'text': text, 'breakpoints': breakpoints }))
    else:
        # Retrieve file
        text = TargetFile.body(RunningScript.instance.scope, procedure_name)
        if not text:
            raise RuntimeError(f"Unable to retrieve: {procedure_name}")
        Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'file', 'filename': procedure_name, 'text': text, 'breakpoints': breakpoints }))

        # Cache instrumentation into RAM
        instrumented_script = RunningScript.instrument_script(text, path, True)
        RunningScript.instrumented_cache[path] = [instrumented_script, text]
        cached = False

    eval(instrumented_script)

    # Return whether we had to load and instrument this file, i.e. it was not cached
    return not cached
setattr(openc3.script, 'start', start)

# Require an additional ruby file
def load_utility(procedure_name):
    # Ensure require_utility works like require where you don't need the .rb extension
    extension = os.path.splitext(procedure_name)[1]
    if extension != '.py':
        procedure_name += '.py'
    not_cached = False
    if RunningScript.instance:
        saved = RunningScript.instance.use_instrumentation
        try:
            RunningScript.instance.use_instrumentation = False
            not_cached = start(procedure_name)
        finally:
            RunningScript.instance.use_instrumentation = saved
    else: # Just call require
        # TODO
        # importlib.import_module(module)
        # importlib.reload(module)
        # not_cached = require(procedure_name)
        pass
    # Return whether we had to load and instrument this file, i.e. it was not cached
    # This is designed to match the behavior of Ruby's require and load keywords
    return not_cached
setattr(openc3.script, 'load_utility', load_utility)
setattr(openc3.script, 'require_utility', load_utility)

# sleep in a script - returns true if canceled mid sleep
def openc3_script_sleep(sleep_time = None):
    if RunningScript.disconnect:
        return True

    Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'line', 'filename': RunningScript.instance.current_filename, 'line_no': RunningScript.instance.current_line_number, 'state': 'waiting' }))

    if not sleep_time: # Handle infinite wait
        sleep_time = 30000000
    if sleep_time > 0.0:
        end_time = time.time() + sleep_time
        count = 0
        while time.time() < end_time:
          time.sleep(0.01)
          count += 1
          if (count % 100) == 0: # Approximately Every Second
              Store.publish("script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'line', 'filename': RunningScript.instance.current_filename, 'line_no': RunningScript.instance.current_line_number, 'state': 'waiting' }))

          if RunningScript.instance.pause:
              RunningScript.instance.perform_pause()
              return True

          if RunningScript.instance.check_and_clear_go():
              return True

          if RunningScript.instance.stop:
              raise StopScript
    return False

# def display_screen(target_name, screen_name, x = None, y = None, scope = OPENC3_SCOPE):
#     definition = get_screen_definition(target_name, screen_name, scope = scope)
#     Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'screen', 'target_name': target_name, 'screen_name': screen_name, 'definition': definition, 'x': x, 'y': y }))

def clear_screen(target_name, screen_name):
    Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'clearscreen', 'target_name': target_name, 'screen_name': screen_name }))

def clear_all_screens():
    Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'clearallscreens' }))

def local_screen(screen_name, definition, x = None, y = None):
    Store.publish(f"script-api:running-script-channel:{RunningScript.instance.id}", json.dumps({ 'type': 'screen', 'target_name': "LOCAL", 'screen_name': screen_name, 'definition': definition, 'x': x, 'y': y }))

def download_file(file_or_path):
    if hasattr(file_or_path, 'read') and callable(file_or_path.read):
        data = file_or_path.read()
        if hasattr(file_or_path, 'name') and callable(file_or_path.name):
            filename = os.path.basename(file_or_path.name)
        else:
            filename = 'unnamed_file.bin'
    else: # path
        data = TargetFile.body(RunningScript.instance.scope, file_or_path)
        filename = os.path.basename(file_or_path)
    Store.publish(f"script-api:running-script-channel:#{RunningScript.instance.id}", json.dumps({ 'type': 'downloadfile', 'filename': filename, 'text': data }))
