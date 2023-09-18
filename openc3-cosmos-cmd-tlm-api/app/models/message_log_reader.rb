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

class MessageLogReader
  attr_reader :bucket_file

  def initialize(bucket_file)
    @bucket_file = bucket_file
    reset()
  end

  def reset
    @lines = nil
    @next_line = nil
    @index = 0
  end

  def open(path)
    reset()
    @lines = File.read(path).to_s.lines
    process_line()
  end

  def close
    # Nothing to do
  end

  def read
    return_line = @next_line
    process_line()
    return return_line
  end

  def next_entry_time
    if @next_line
      return @next_line['time'].to_i
    end
    return nil
  end

  # private

  def process_line
    line = @lines[@index]
    if line and line[0] == '{'
      @index += 1
      @next_line = JSON.parse(line.chomp, allow_nan: true, create_additions: true)
    else
      @next_line = nil
    end
  end
end
