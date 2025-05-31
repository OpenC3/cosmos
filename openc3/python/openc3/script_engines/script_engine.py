# Copyright 2025 OpenC3, Inc.
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

class ScriptEngine:
    def __init__(self, running_script):
        self.running_script = running_script

    # Override this method in the subclass to implement the script engine
    def run_line(self, line, lines, filename, line_no):
        print(line)
        return line_no + 1

    def run_text(self, text, filename = None, line_no = 1, end_line_no = None, bind_variables = False):
        lines = text.splitlines()

        while True:
            if line_no > len(lines):
                return
            line = lines[line_no - 1]
            next_line_no = line_no + 1

            while True:
                try:
                    self.running_script.pre_line_instrumentation(filename, line_no, globals(), locals())
                    next_line_no = self.run_line(line, lines, filename, line_no)
                    break
                except Exception as e:
                    retry_needed = self.running_script.exception_instrumentation(filename, line_no)
                    if retry_needed:
                        continue
                    else:
                        break
                finally:
                    self.running_script.post_line_instrumentation(filename, line_no)

            line_no = next_line_no
            if end_line_no and line_no > end_line_no:
                return
