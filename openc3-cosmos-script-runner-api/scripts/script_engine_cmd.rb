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

require 'openc3'
require 'openc3/models/script_engine_model'

class RunningScriptProxy
  def pre_line_instrumentation(filename, line_number)
  end

  def post_line_instrumentation(filename, line_number)
  end

  def exception_instrumentation(error, filename, line_number)
  end
end

command = ARGV[0]
filename = ARGV[1]
extension = File.extname(filename).to_s.downcase

script_engine_filename = nil
script_engine_model = OpenC3::ScriptEngineModel.get_model(name: extension, scope: 'DEFAULT')
if script_engine_model
    script_engine_filename = script_engine_model.filename
else
    puts("Script Engine for #{filename} not found")
    exit(1)
end

klass = OpenC3.require_class(script_engine_filename)
running_script_proxy = RunningScriptProxy()
script_engine = klass.new(running_script_proxy)

# Retrieve file contents
text = File.read(filename)

exit_code = 0
case command
when "syntax_check"
  exit_code = script_engine.syntax_check(text, filename)
when "mnemonic_check"
  exit_code = script_engine.mnemonic_check(text, filename)
else
  puts("Unknown command: #{command}")
  exit_code = 1
end

exit(exit_code)