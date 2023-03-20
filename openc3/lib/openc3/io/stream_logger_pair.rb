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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/logs/stream_log'

module OpenC3
  # Holds a read/write pair of stream logs
  class StreamLogPair
    # @return [StreamLog] The read log
    attr_accessor :read_log
    # @return [StreamLog] The write log
    attr_accessor :write_log

    # @param name [String] name to be added to log filenames
    # @param params [Array] stream log writer parameters or empty array
    def initialize(name, params = [])
      if params.empty?
        stream_log_class = StreamLog
      else
        stream_log_class = OpenC3.require_class(params[0])
      end
      if params[1]
        @read_log = stream_log_class.new(name, :READ, *params[1..-1])
        @write_log = stream_log_class.new(name, :WRITE, *params[1..-1])
      else
        @read_log = stream_log_class.new(name, :READ)
        @write_log = stream_log_class.new(name, :WRITE)
      end
    end

    # Change the stream log name
    # @param name [String] new name
    def name=(name)
      @read_log.name = name
      @write_log.name = name
    end

    # Start stream logs
    def start
      @read_log.start
      @write_log.start
    end

    # Close any open stream log files
    def stop
      @read_log.stop
      @write_log.stop
    end

    def shutdown
      @read_log.shutdown
      @write_log.shutdown
    end

    # Clone the stream log pair
    def clone
      stream_log_pair = super()
      stream_log_pair.read_log = @read_log.clone
      stream_log_pair.write_log = @write_log.clone
      stream_log_pair.read_log.start if @read_log.logging_enabled
      stream_log_pair.write_log.start if @write_log.logging_enabled
      stream_log_pair
    end
  end
end
