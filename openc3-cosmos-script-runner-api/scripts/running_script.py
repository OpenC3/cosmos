# Copyright 2024 OpenC3, Inc.
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

from openc3.script.suite_runner import SuiteRunner
from openc3.utilities.string import build_timestamped_filename
from openc3.utilities.bucket_utilities import BucketUtilities
from openc3.script.storage import _get_storage_file
import re
import linecache


# sleep in a script - returns true if canceled mid sleep
def _openc3_script_sleep(sleep_time=None):
    if RunningScript.disconnect:
        return True

    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps(
            {
                "type": "line",
                "filename": RunningScript.instance.current_filename,
                "line_no": RunningScript.instance.current_line_number,
                "state": "waiting",
            }
        ),
    )

    if not sleep_time:  # Handle infinite wait
        sleep_time = 30000000
    if sleep_time > 0.0:
        end_time = time.time() + sleep_time
        count = 0
        while time.time() < end_time:
            time.sleep(0.01)
            count += 1
            if (count % 100) == 0:  # Approximately Every Second
                Store.publish(
                    f"script-api:running-script-channel:{RunningScript.instance.id}",
                    json.dumps(
                        {
                            "type": "line",
                            "filename": RunningScript.instance.current_filename,
                            "line_no": RunningScript.instance.current_line_number,
                            "state": "waiting",
                        }
                    ),
                )

            if RunningScript.instance.pause:
                RunningScript.instance.perform_pause()
                return True

            if RunningScript.instance.check_and_clear_go():
                return True

            if RunningScript.instance.stop:
                raise StopScript
    return False


import openc3.script.api_shared

setattr(openc3.script.api_shared, "openc3_script_sleep", _openc3_script_sleep)

import os
from io import StringIO
import ast
import json
import uuid
import re
import time
import socket
import sys
import traceback
import threading
from datetime import datetime, timezone
from threading import Lock
from openc3.environment import *
from openc3.utilities.store import Store
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.message_log import MessageLog
from openc3.utilities.logger import Logger
from openc3.utilities.target_file import TargetFile
from openc3.io.stdout import Stdout
from openc3.io.stderr import Stderr
from openc3.top_level import kill_thread
from openc3.script.exceptions import StopScript, SkipScript
from openc3.script.suite import Group
from script_instrumentor import ScriptInstrumentor
import openc3.utilities.target_file_importer

# Define all the user input methods used in scripting which we need to broadcast to the frontend
# Note: This list matches the list in run_script.rb:151
# These are implemented as command line versions in openc3/script/__init__.py
SCRIPT_METHODS = [
    "ask",
    "ask_string",
    "message_box",
    "vertical_message_box",
    "combo_box",
    "prompt",
    "prompt_for_hazardous",
    "metadata_input",
    "open_file_dialog",
    "open_files_dialog",
]


def running_script_method(method, *args, **kwargs):
    while True:
        if RunningScript.instance:
            RunningScript.instance.scriptrunner_puts(f"{method}({', '.join(args)})")
            prompt_id = str(uuid.uuid1())
            RunningScript.instance.perform_wait(
                {"method": method, "id": prompt_id, "args": args, "kwargs": kwargs}
            )
            input = RunningScript.instance.user_input
            # All ask and prompt dialogs should include a 'Cancel' button
            # If they cancel we wait so they can potentially stop
            if input == "Cancel":
                RunningScript.instance.perform_pause()
            else:
                if "open_file" in method:
                    files = []
                    for theFilename in input:
                        file = _get_storage_file(
                            f"tmp/{theFilename}", scope=RunningScript.instance.scope
                        )

                        def filename(self):
                            return theFilename

                        type(file).filename = filename
                        files.append(file)
                        pass
                    if method == "open_file_dialog":  # Simply return the only file
                        files = files[0]
                    return files
                else:
                    return input
        else:
            raise RuntimeError("Script input method called outside of running script")


for method in SCRIPT_METHODS:
    code = f"def {method}(*args, **kwargs):\n    return running_script_method('{method}', *args, **kwargs)"
    function = compile(code, "<string>", "exec")
    exec(function, globals())
    setattr(openc3.script, method, globals()[method])

from openc3.script import *

RAILS_ROOT = os.path.abspath(os.path.join(__file__, "../.."))


class RunningScript:
    # Matches the following test cases:
    # class MySuite(TestSuite)
    # class MySuite(Suite)
    PYTHON_SUITE_REGEX = re.compile("\s*class\s+\w+\s*\(\s*(Suite|TestSuite)\s*\)")

    # Can't use isoformat because it appends "+00:00" instead of "Z"
    STRFTIME_FORMAT = "%Y-%m-%dT%H:%M:%S.%fZ"

    instance = None
    id = None
    my_message_log = None
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
        if cls.my_message_log:
            return cls.my_message_log

        if cls.instance:
            scope = cls.instance.scope
            basename = os.path.splitext(os.path.basename(cls.instance.filename))[0]
            regex = re.compile("(\s|\W)")
            tags = [re.sub(regex, "_", basename)]
        else:
            scope = OPENC3_SCOPE
            tags = []
        cls.my_message_log = MessageLog(
            "sr", os.path.join(RAILS_ROOT, "log"), tags=tags, scope=scope
        )
        return cls.my_message_log

    # Parameters are passed to RunningScript.new as strings because
    # RunningScript.spawn must pass strings to ChildProcess.build
    def __init__(self, id, scope, name, disconnect):
        RunningScript.instance = self
        RunningScript.id = id
        self.scope = scope
        self.name = name
        self.filename = name
        self.user_input = ""
        self.prompt_id = None
        self.line_offset = 0
        self.output_io = StringIO("")
        self.output_io_mutex = Lock()
        self.allow_start = True
        self.continue_after_error = True
        self.debug_text = None
        self.debug_history = []
        self.debug_code_completion = None
        self.top_level_instrumented_cache = None
        self.output_time = datetime.now(timezone.utc).strftime(
            RunningScript.STRFTIME_FORMAT
        )
        self.state = "init"
        self.script_globals = globals()
        RunningScript.disconnect = disconnect

        self.initialize_variables()
        self.redirect_io()  # Redirect stdout and stderr
        self.mark_breakpoints(self.filename)
        if disconnect:
            openc3.script.disconnect_script()

        # Get details from redis
        details = Store.get(f"running-script:{RunningScript.id}")
        if details:
            self.details = json.loads(details)
        else:
            # Create as much details as we know
            self.details = {
                "id": RunningScript.id,
                "name": self.filename,
                "scope": self.scope,
                "start_time": self.output_time,
                "update_time": self.output_time,
            }

        # Update details in redis
        self.details["hostname"] = socket.gethostname()
        self.details["state"] = self.state
        self.details["line_no"] = 1
        self.details["update_time"] = self.output_time
        Store.set(f"running-script:{RunningScript.id}", json.dumps(self.details))

        # Retrieve file
        self.body = TargetFile.body(self.scope, self.name)
        if not self.body:
            raise RuntimeError(f"Unable to retrieve: {self.name} in scope {self.scope}")
        else:
            self.body = self.body.decode()
        breakpoints = []
        if self.filename in RunningScript.breakpoints:
            my_breakpoints = RunningScript.breakpoints[self.filename]
            for key in my_breakpoints:
                breakpoints.append(key - 1)  # -1 because frontend lines are 0-indexed
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "file",
                    "filename": self.filename,
                    "scope": self.scope,
                    "text": self.body,
                    "breakpoints": breakpoints,
                }
            ),
        )
        if self.PYTHON_SUITE_REGEX.findall(self.body):
            # Call load_utility to parse the suite and allow for individual methods to be executed
            load_utility(name)

            # Process the suite file in this context so we can load it
            SuiteRunner.build_suites(from_globals=globals())

    def parse_options(self, options):
        settings = {}
        if "manual" in options:
            settings["Manual"] = True
            RunningScript.manual = True
        else:
            settings["Manual"] = False
            RunningScript.manual = False

        if "pauseOnError" in options:
            settings["Pause on Error"] = True
            RunningScript.pause_on_error = True
        else:
            settings["Pause on Error"] = False
            RunningScript.pause_on_error = False

        if "continueAfterError" in options:
            settings["Continue After Error"] = True
            self.continue_after_error = True
        else:
            settings["Continue After Error"] = False
            self.continue_after_error = False

        if "abortAfterError" in options:
            settings["Abort After Error"] = True
            Group.abort_on_exception = True
        else:
            settings["Abort After Error"] = False
            Group.abort_on_exception = False

        if "loop" in options:
            settings["Loop"] = True
        else:
            settings["Loop"] = False

        if "breakLoopOnError" in options:
            settings["Break Loop On Error"] = True
        else:
            settings["Break Loop On Error"] = False

        SuiteRunner.settings = settings

    # Let the script continue pausing if in step mode (continue cannot be method name)
    def do_continue(self):
        self.go = True
        if self.step:
            self.pause = True

    # Sets step mode and lets the script continue but with pause set
    def do_step(self):
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "step",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )
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
        if RunningScript.run_thread:
            self.stop = True
            kill_thread(self, RunningScript.run_thread)
            RunningScript.run_thread = None

    def clear_prompt(self):
        # Allow things to continue once the prompt is cleared
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps({"type": "script", "prompt_complete": self.prompt_id}),
        )
        self.prompt_id = None

    def as_json(self):
        return {
            "id": RunningScript.id,
            "state": self.state,
            "filename": self.current_filename,
            "line_no": self.current_line_no,
        }

    # Private methods

    def graceful_kill(self):
        self.stop = True

    def initialize_variables(self):
        RunningScript.error = None
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
        if self.filename and not self.filename == "":
            return self.filename
        else:
            return "Untitled" + str(RunningScript.id)

    def stop_message_log(self):
        metadata = {"user": self.details["user"], "scriptname": self.unique_filename()}
        if RunningScript.my_message_log:
            RunningScript.my_message_log.stop(True, metadata=metadata)
        RunningScript.my_message_log = None

    # TODO: This doesn't appear to be called
    def set_filename(self, filename):
        # Stop the message log so a new one will be created with the new filename
        self.stop_message_log()
        self.filename = filename

        # Deal with breakpoints created under the previous filename.
        bkpt_filename = self.unique_filename()
        if not bkpt_filename in RunningScript.breakpoints:
            RunningScript.breakpoints[bkpt_filename] = RunningScript.breakpoints[
                self.filename
            ]
        if bkpt_filename != self.filename:
            del RunningScript.breakpoints[self.filename]
            self.filename = bkpt_filename
        self.scopemark_breakpoints(self.filename)

    def text(self):
        return self.body

    def set_text(self, text, filename=""):
        if not self.running():
            self.filename = filename
            self.mark_breakpoints(self.filename)
            self.body = text

    def running(self):
        if RunningScript.run_thread:
            return True
        else:
            return False

    def do_retry_needed(self):
        self.retry_needed = True

    def run(self):
        if not self.running():
            self.run_text(self.body)

    def run_and_close_on_complete(self, text_binding=None):
        self.run_text(self.body, 0, text_binding, True)

    @classmethod
    def instrument_script(cls, text, filename):
        if filename and not filename == "":
            cls.file_cache[filename] = text

        parsed = ast.parse(text)
        tree = ScriptInstrumentor(filename).visit(parsed)
        result = compile(tree, filename=filename, mode="exec")
        return result

    def pre_line_instrumentation(
        self, filename, line_number, global_variables, local_variables
    ):
        self.script_binding = [global_variables, local_variables]
        self.current_filename = filename
        self.current_line_number = line_number
        if self.use_instrumentation:
            # Clear go
            self.go = False

            # Handle stopping mid-script if necessary
            if self.stop:
                raise StopScript

            self.handle_potential_tab_change(filename)

            line_number = line_number + self.line_offset
            detail_string = None
            if filename:
                detail_string = os.path.basename(filename) + ":" + str(line_number)
                Logger.detail_string = detail_string

            Store.publish(
                f"script-api:running-script-channel:{RunningScript.id}",
                json.dumps(
                    {
                        "type": "line",
                        "filename": self.current_filename,
                        "line_no": self.current_line_number,
                        "state": "running",
                    }
                ),
            )
            self.handle_pause(filename, line_number)
            self.handle_line_delay()

    def post_line_instrumentation(self, filename, line_number):
        if self.use_instrumentation:
            line_number = line_number + self.line_offset
            self.handle_output_io(filename, line_number)

    def exception_instrumentation(self, filename, line_number):
        _, error, _ = sys.exc_info()
        if (
            issubclass(error.__class__, StopScript)
            or issubclass(error.__class__, SkipScript)
            or not self.use_instrumentation
        ):
            raise error
        elif not error == RunningScript.error:
            line_number = line_number + self.line_offset
            return self.handle_exception(error, False, filename, line_number)

    def perform_wait(self, prompt):
        self.mark_waiting()
        self.wait_for_go_or_stop(prompt=prompt)

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
                if debug_text in self.script_binding[1]:  # In local variables
                    debug_text = (
                        f"print({debug_text})"  # Automatically add print to print it
                    )
                exec(
                    debug_text,
                    self.script_binding[0],
                    self.script_binding[1],
                )
            else:
                exec(debug_text, self.script_globals)

            self.handle_output_io()
        except Exception as error:
            Logger.error(error.__class__.__name__ + " : " + str(error))
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
    def clear_breakpoints(cls, filename=None):
        if filename == None or filename == "":
            cls.breakpoints = {}
        else:
            if filename in cls.breakpoints:
                del cls.breakpoints[filename]

    def current_backtrace(self):
        trace = []
        if RunningScript.run_thread:
            for filename, lineno, name, line in traceback.extract_stack(
                sys._current_frames()[RunningScript.run_thread.ident]
            ):
                # next if line.include?(OpenC3::PATH)    # Ignore OpenC3 internals
                # next if line.include?('lib/ruby/gems') # Ignore system gems
                # next if line.include?('app/models/running_script') # Ignore this file
                trace.append(f"{filename}:{lineno}:{name}:{line}")
        return trace

    def scriptrunner_puts(self, string, color="BLACK"):
        line_to_write = (
            datetime.now(timezone.utc).strftime(RunningScript.STRFTIME_FORMAT)
            + " (SCRIPTRUNNER): "
            + string
        )
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps({"type": "output", "line": line_to_write, "color": color}),
        )

    @classmethod
    def script_get_breakpoints(cls, scope, name):
        breakpoints = Store.hget(
            f"{scope}__script-breakpoints", name.split("*")[0]
        )  # Split '*' that indicates modified
        if breakpoints:
            return json.loads(breakpoints)
        return []

    def handle_output_io(self, filename=None, line_number=None):
        if not filename:
            filename = self.current_filename
        if not line_number:
            line_number = self.current_line_number
        self.output_time = datetime.now(timezone.utc).strftime(
            RunningScript.STRFTIME_FORMAT
        )
        string = self.output_io.getvalue()
        self.output_io.truncate(0)
        self.output_io.seek(0)
        if len(string) > 0 and string[-1] == "\n":
            time_formatted = self.output_time
            color = "BLACK"
            lines_to_write = ""
            out_line_number = str(line_number)
            if filename:
                out_filename = os.path.basename(filename)

            # Build each line to write
            line_count = 0
            for out_line in string.splitlines():
                out_line = out_line.rstrip()
                try:
                    json_hash = json.loads(out_line)
                    if "@timestamp" in json_hash:
                        time_formatted = json_hash["@timestamp"]
                    if "log" in json_hash:
                        out_line = json_hash["log"]
                except:
                    # Regular output
                    pass

                if (
                    len(out_line) >= 25
                    and out_line[0:2] == "20"
                    and out_line[10] == " "
                    and out_line[26:28] == " ("
                ):
                    line_to_write = out_line
                else:
                    if filename:
                        line_to_write = (
                            time_formatted
                            + f" ({out_filename}:{out_line_number}): "
                            + out_line
                        )
                    else:
                        line_to_write = time_formatted + " (SCRIPTRUNNER): " + out_line
                        color = "BLUE"
                lines_to_write = lines_to_write + line_to_write + "\n"
                line_count += 1

            if len(lines_to_write) > RunningScript.max_output_characters:
                # We want the full @@max_output_characters so don't subtract the additional "ERROR: ..." text
                published_lines = lines_to_write[
                    0 : RunningScript.max_output_characters
                ]
                published_lines = (
                    published_lines
                    + f"\nERROR: Too much to publish. Truncating {len(lines_to_write)} characters of output to {RunningScript.max_output_characters} characters.\n"
                )
            else:
                published_lines = lines_to_write

            Store.publish(
                f"script-api:running-script-channel:{RunningScript.id}",
                json.dumps({"type": "output", "line": published_lines, "color": color}),
            )
            # Add to the message log
            self.message_log().write(lines_to_write)

    def graceful_kill(self):
        # Just to avoid warning
        pass

    def wait_for_go_or_stop(self, error=None, prompt=None):
        count = -1
        self.go = False
        if prompt:
            self.prompt_id = prompt["id"]
        while not self.go and not self.stop:
            time.sleep(0.01)
            count += 1
            if count % 100 == 0:  # Approximately Every Second
                Store.publish(
                    f"script-api:running-script-channel:{RunningScript.id}",
                    json.dumps(
                        {
                            "type": "line",
                            "filename": self.current_filename,
                            "line_no": self.current_line_number,
                            "state": self.state,
                        }
                    ),
                )
                if prompt:
                    Store.publish(
                        f"script-api:running-script-channel:{RunningScript.id}",
                        json.dumps(
                            {
                                "type": "script",
                                "method": prompt["method"],
                                "prompt_id": prompt["id"],
                                "args": prompt["args"],
                                "kwargs": prompt["kwargs"],
                            }
                        ),
                    )
        if prompt:
            self.clear_prompt()
        RunningScript.instance.prompt_id = None
        self.go = False
        self.mark_running()
        if self.stop:
            raise StopScript
        if error and not self.continue_after_error:
            raise error

    def wait_for_go_or_stop_or_retry(self, error=None):
        count = 0
        self.go = False
        while not self.go and not self.stop and not self.retry_needed:
            time.sleep(0.01)
            count += 1
            if (count % 100) == 0:  # Approximately Every Second
                Store.publish(
                    f"script-api:running-script-channel:{RunningScript.id}",
                    json.dumps(
                        {
                            "type": "line",
                            "filename": self.current_filename,
                            "line_no": self.current_line_number,
                            "state": self.state,
                        }
                    ),
                )
        self.go = False
        self.mark_running()
        if self.stop:
            raise StopScript
        if error and not self.continue_after_error:
            raise error

    def mark_running(self):
        self.state = "running"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def mark_paused(self):
        self.state = "paused"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def mark_waiting(self):
        self.state = "waiting"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def mark_error(self):
        self.state = "error"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def mark_fatal(self):
        self.state = "fatal"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def mark_stopped(self):
        self.state = "stopped"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )
        if SuiteRunner.suite_results:
            SuiteRunner.suite_results.complete()
            # context looks like the following:
            # MySuite:ExampleGroup:script_2
            # MySuite:ExampleGroup Manual Setup
            # MySuite Manual Teardown
            init_split = SuiteRunner.suite_results.context.split()
            parts = init_split[0].split(":")
            if len(parts) == 3:
                # Remove test_ or script_ because it doesn't add any info
                parts[2] = re.sub(r"^test_", "", parts[2])
                parts[2] = re.sub(r"^script_", "", parts[2])
            parts = [
                part[0:10] for part in parts
            ]  # Only take the first 10 characters to prevent huge filenames
            # If the initial split on whitespace has more than 1 item it means
            # a Manual Setup or Teardown was performed. Add this to the filename.
            # NOTE: We're doing this here with a single underscore to preserve
            # double underscores as Suite, Group, Script delimiters
            if len(parts) == 2 and len(init_split) > 1:
                parts[1] += f"_{init_split[-1]}"
            elif len(parts) == 1 and len(init_split) > 1:
                parts[0] += f"_{init_split[-1]}"
            Store.publish(
                f"script-api:running-script-channel:{self.id}",
                json.dumps(
                    {"type": "report", "report": SuiteRunner.suite_results.report()}
                ),
            )
            # Write out the report to a local file
            log_dir = os.path.join(RAILS_ROOT, "log")
            filename = os.path.join(
                log_dir, build_timestamped_filename(["sr", "__".join(parts)])
            )
            with open(filename, "wb") as file:
                file.write(SuiteRunner.suite_results.report().encode())
            # Generate the bucket key by removing the date underscores in the filename to create the bucket file structure
            bucket_key = os.path.join(
                f"{self.scope}/tool_logs/sr/",
                re.sub("_", "", os.path.basename(filename)[0:10]),
                os.path.basename(filename),
            )
            metadata = {
                # Note: The chars '(' and ')' are used by RunningScripts.vue to differentiate between script logs
                "user": self.details["user"],
                "scriptname": f"{self.current_filename} ({SuiteRunner.suite_results.context.strip()})",
            }
            thread = BucketUtilities.move_log_file_to_bucket(
                filename, bucket_key, metadata=metadata
            )
            # Wait for the file to get moved to S3 because after this the process will likely die
            thread.join()

        Store.publish(
            f"script-api:cmd-running-script-channel:{RunningScript.id}",
            json.dumps("shutdown"),
        )

    def mark_breakpoint(self):
        self.state = "breakpoint"
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "line",
                    "filename": self.current_filename,
                    "line_no": self.current_line_number,
                    "state": self.state,
                }
            ),
        )

    def run_thread_body(
        self,
        text,
        line_offset,
        text_binding,
        close_on_complete,
        saved_instance,
        saved_run_thread,
        initial_filename=None,
    ):
        try:
            # Capture STDOUT and STDERR
            sys.stdout.add_stream(self.output_io)
            sys.stderr.add_stream(self.output_io)

            if not close_on_complete:
                output = f"Starting script: {os.path.basename(self.filename)}"
                if RunningScript.disconnect:
                    output += " in DISCONNECT mode"
                self.scriptrunner_puts(output)
            self.handle_output_io()

            # Start Output Thread
            if not RunningScript.output_thread:
                RunningScript.output_thread = threading.Thread(
                    target=RunningScript.output_thread, daemon=True
                )
                RunningScript.output_thread.start()

            if initial_filename:
                linecache.cache[initial_filename] = (
                    len(text),
                    None,
                    text.splitlines(keepends=True),
                    initial_filename,
                )
                instrumented_script = self.instrument_script(text, initial_filename)
            else:
                linecache.cache[self.filename] = (
                    len(text),
                    None,
                    text.splitlines(keepends=True),
                    self.filename,
                )
                instrumented_script = self.instrument_script(text, self.filename)

            # Execute the script
            self.pre_line_time = time.time()
            if text_binding:
                exec(instrumented_script, text_binding[0], text_binding[1])
            else:
                exec(instrumented_script, self.script_globals)

            self.handle_output_io()
            if not close_on_complete:
                self.scriptrunner_puts(
                    f"Script completed: {os.path.basename(self.filename)}"
                )

        except Exception as error:
            if issubclass(error.__class__, StopScript) or issubclass(
                error.__class__, SkipScript
            ):
                self.handle_output_io()
                self.scriptrunner_puts(
                    f"Script stopped: {os.path.basename(self.filename)}"
                )
            else:
                uncaught_exception = True
                exc_type, exc_value, exc_traceback = sys.exc_info()
                filename = exc_traceback.tb_frame.f_code.co_filename
                line_number = exc_traceback.tb_lineno
                self.handle_exception(error, True, filename, line_number)
                self.handle_output_io()
                self.scriptrunner_puts(
                    f"Exception in Control Statement - Script stopped: {os.path.basename(self.filename)}"
                )
                self.mark_fatal()
        finally:
            # Stop Capturing STDOUT and STDERR
            # Check for remove_stream because if the tool is quitting the
            # OpenC3::restore_io may have been called which sets stdout and
            # stderr to the IO constant
            if hasattr(sys.stdout, "remove_stream"):
                sys.stdout.remove_stream(self.output_io)
            if hasattr(sys.stderr, "remove_stream"):
                sys.stderr.remove_stream(self.output_io)

            # Clear run thread and instance to indicate we are no longer running
            RunningScript.instance = saved_instance
            RunningScript.run_thread = saved_run_thread
            self.script_binding = None
            # Set the current_filename to the original file and the current_line_number to 0
            # so the mark_stopped method will signal the frontend to reset to the original
            self.current_filename = self.filename
            self.current_line_number = 0
            if RunningScript.output_thread and not RunningScript.instance:
                RunningScript.cancel_output = True
                RunningScript.output_sleeper.cancel()
                kill_thread(self, RunningScript.output_thread)
                RunningScript.output_thread = None
            self.mark_stopped()
            self.current_filename = None

    def run_text(
        self,
        text,
        line_offset=0,
        text_binding=None,
        close_on_complete=False,
        initial_filename=None,
    ):
        self.initialize_variables()
        self.line_offset = line_offset
        saved_instance = RunningScript.instance
        saved_run_thread = RunningScript.run_thread
        RunningScript.instance = self
        if initial_filename:
            Store.publish(
                f"script-api:running-script-channel:{RunningScript.id}",
                json.dumps(
                    {
                        "type": "file",
                        "filename": initial_filename,
                        "scope": self.scope,
                        "text": text,
                        "breakpoints": [],
                    }
                ),
            )
        RunningScript.run_thread = threading.Thread(
            target=self.run_thread_body,
            args=[
                text,
                line_offset,
                text_binding,
                close_on_complete,
                saved_instance,
                saved_run_thread,
                initial_filename,
            ],
            daemon=True,
        )
        RunningScript.run_thread.start()

    def handle_potential_tab_change(self, filename):
        # Make sure the correct file is shown in script runner
        if self.current_file != filename:
            if not filename in self.call_stack:
                self.call_stack.append(filename)
                self.load_file_into_script(filename)
            self.current_file = filename

    def handle_pause(self, filename, line_number):
        breakpoint = False
        if (
            filename in RunningScript.breakpoints
            and line_number in RunningScript.breakpoints[filename]
        ):
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
        if RunningScript.line_delay > 0.0:
            sleep_time = RunningScript.line_delay - (time.time() - self.pre_line_time)
            if sleep_time > 0.0:
                time.sleep(sleep_time)
        self.pre_line_time = time.time()

    def handle_exception(self, error, fatal, filename=None, line_number=0):
        self.exceptions = self.exceptions or []
        self.exceptions.append(error)
        RunningScript.error = error

        if error.__class__.__name__ == "DRbConnError":
            Logger.error("Error Connecting to Command and Telemetry Server")
        else:
            # Logger.error(repr(error))
            exc_type, exc_value, exc_tb = sys.exc_info()
            Logger.error(
                "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
            )
        self.handle_output_io(filename, line_number)

        if (
            not RunningScript.pause_on_error
            and not self.continue_after_error
            and not fatal
        ):
            raise error

        if not fatal and RunningScript.pause_on_error:
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
        if filename in RunningScript.breakpoints:
            my_breakpoints = RunningScript.breakpoints[filename]
            for key in my_breakpoints:
                breakpoints.append(key - 1)  # -1 because frontend lines are 0-indexed
        cached = None
        if filename in RunningScript.file_cache:
            cached = RunningScript.file_cache[filename]
        if cached:
            self.body = cached
        else:
            text = TargetFile.body(self.scope, filename)
            if not text:
                raise RuntimeError(
                    f"Unable to retrieve: {filename} in scope {self.scope}"
                )
            else:
                text = text.decode()
            RunningScript.file_cache[filename] = text
            self.body = text
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.id}",
            json.dumps(
                {
                    "type": "file",
                    "filename": filename,
                    "text": self.body,
                    "breakpoints": breakpoints,
                }
            ),
        )

    def mark_breakpoints(self, filename):
        breakpoints = []
        if filename in RunningScript.breakpoints:
            breakpoints = RunningScript.breakpoints[filename]
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
        RunningScript.cancel_output = False
        RunningScript.output_sleeper = Sleeper()
        while True:
            if RunningScript.cancel_output:
                break
            if (time.time() - self.output_time) > 5.0:
                self.handle_output_io()
            if RunningScript.cancel_output:
                break
            if RunningScript.output_sleeper.sleep(1.0):
                break


openc3.script.RUNNING_SCRIPT = RunningScript

###########################################################################
# START PUBLIC API
###########################################################################


def step_mode():
    RunningScript.instance.step()


setattr(openc3.script, "step_mode", step_mode)


def run_mode():
    RunningScript.instance.go()


setattr(openc3.script, "run_mode", run_mode)


def start(procedure_name):
    path = procedure_name

    # Check RAM based instrumented cache
    breakpoints = []
    if path in RunningScript.breakpoints:
        my_breakpoints = RunningScript.breakpoints[path]
        for key in my_breakpoints:
            breakpoints.append(key - 1)  # -1 because frontend lines are 0-indexed

    instrumented_script = None
    instrumented_cache = None
    text = None
    if path in RunningScript.instrumented_cache:
        instrumented_cache, text = RunningScript.instrumented_cache[path]

    if instrumented_cache:
        # Use cached instrumentation
        instrumented_script = instrumented_cache
        cached = True
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.instance.id}",
            json.dumps(
                {
                    "type": "file",
                    "filename": procedure_name,
                    "text": text,
                    "breakpoints": breakpoints,
                }
            ),
        )
    else:
        # Retrieve file
        text = TargetFile.body(RunningScript.instance.scope, procedure_name)
        if not text:
            raise RuntimeError(
                f"Unable to retrieve: {procedure_name} in scope {RunningScript.instance.scope}"
            )
        else:
            text = text.decode()
        Store.publish(
            f"script-api:running-script-channel:{RunningScript.instance.id}",
            json.dumps(
                {
                    "type": "file",
                    "filename": procedure_name,
                    "text": text,
                    "breakpoints": breakpoints,
                }
            ),
        )

        # Cache instrumentation into RAM
        instrumented_script = RunningScript.instrument_script(text, path)
        RunningScript.instrumented_cache[path] = [instrumented_script, text]
        cached = False

    running = Store.smembers("running-scripts")
    if running is None:
        running = []
    Store.publish(
        "script-api:all-scripts-channel",
        json.dumps(
            {
                "type": "start",
                "filename": procedure_name,
                "active_scripts": len(running),
            }
        ),
    )
    linecache.cache[path] = (
        len(text),
        None,
        text.splitlines(keepends=True),
        path,
    )
    exec(instrumented_script, RunningScript.instance.script_globals)

    # Return whether we had to load and instrument this file, i.e. it was not cached
    return not cached


setattr(openc3.script, "start", start)


# Load an additional python file
def load_utility(procedure_name):
    extension = os.path.splitext(procedure_name)[1]
    if extension != ".py":
        procedure_name += ".py"
    not_cached = False
    if RunningScript.instance:
        saved = RunningScript.instance.use_instrumentation
        try:
            RunningScript.instance.use_instrumentation = False
            not_cached = start(procedure_name)
        finally:
            RunningScript.instance.use_instrumentation = saved
    else:
        raise RuntimeError("load_utility not supported outside of Script Runner")
    # Return whether we had to load and instrument this file, i.e. it was not cached
    # This is designed to match the behavior of Ruby's require and load keywords
    return not_cached


###########################################################################
# END PUBLIC API
###########################################################################


setattr(openc3.script, "load_utility", load_utility)
setattr(openc3.script, "require_utility", load_utility)


def display_screen(target_name, screen_name, x=None, y=None, scope=OPENC3_SCOPE):
    definition = openc3.script.get_screen_definition(
        target_name, screen_name, scope=scope
    )
    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps(
            {
                "type": "screen",
                "target_name": target_name,
                "screen_name": screen_name,
                "definition": definition,
                "x": x,
                "y": y,
            }
        ),
    )


setattr(openc3.script, "display_screen", display_screen)


def clear_screen(target_name, screen_name):
    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps(
            {
                "type": "clearscreen",
                "target_name": target_name,
                "screen_name": screen_name,
            }
        ),
    )


setattr(openc3.script, "clear_screen", clear_screen)


def clear_all_screens():
    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps({"type": "clearallscreens"}),
    )


setattr(openc3.script, "clear_all_screens", clear_all_screens)


def local_screen(screen_name, definition, x=None, y=None):
    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps(
            {
                "type": "screen",
                "target_name": "LOCAL",
                "screen_name": screen_name,
                "definition": definition,
                "x": x,
                "y": y,
            }
        ),
    )


setattr(openc3.script, "local_screen", local_screen)


def download_file(path, scope=OPENC3_SCOPE):
    url = openc3.script.get_download_url(path, scope=scope)
    Store.publish(
        f"script-api:running-script-channel:{RunningScript.instance.id}",
        json.dumps(
            {"type": "downloadfile", "filename": os.path.basename(path), "url": url}
        ),
    )


setattr(openc3.script, "download_file", download_file)
