# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
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
    @file&.close
    @file = nil
    @next_line = nil
  end

  # Lines are read one at a time as they are consumed rather than loading the
  # whole (decompressed) file up front, so memory use stays constant no matter
  # how large a message log grows.
  def open(path)
    reset()
    @file = File.open(path, 'r')
    process_line()
  end

  def close
    reset()
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
    line = @file&.gets
    if line and line[0] == '{'
      @next_line = JSON.parse(line.chomp, allow_nan: true, create_additions: true)
    else
      # End of file (or a non-JSON line) - nothing more to read so release the
      # file handle now instead of waiting on the caller to close
      @next_line = nil
      @file&.close
      @file = nil
    end
  end
end
