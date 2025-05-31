# encoding: ascii-8bit

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

module OpenC3
  class ScriptEngine
    attr_accessor :running_script

    def initialize(running_script)
      @running_script = running_script
    end

    # Override this method in the subclass to implement the script engine
    def run_line(line, lines, filename, line_no)
      puts line
      return line_no + 1
    end

    def run_text(text, filename: nil, line_no: 1, end_line_no: nil, bind_variables: false)
      lines = text.lines
      loop do
        line = lines[line_no - 1]
        return if line.nil?

        begin
          next_line_no = line_no + 1
          running_script.pre_line_instrumentation(filename, line_no)
          next_line_no = run_line(line, lines, filename, line_no)
          running_script.post_line_instrumentation(filename, line_no)
        rescue Exception => e
          retry if running_script.exception_instrumentation(e, filename, line_no)
        end

        line_no = next_line_no
        return if end_line_no and line_no > end_line_no
      end
    end
  end
end
