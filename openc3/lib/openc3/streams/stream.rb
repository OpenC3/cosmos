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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  # Class that implements the following methods: read, write(data),
  # connect, connected? and disconnect. Streams are simply data sources which
  # {Protocol} classes read and write to. This separation of concerns
  # allows Streams to simply focus on getting and sending raw data while the
  # higher level processing occurs in {Protocol}.
  class Stream
    # Expected to return any amount of data on success, or a blank string on
    # closed/EOF, and may raise Timeout::Error, or other errors
    def read
      raise "read not defined by Stream"
    end

    # Expected to always return immediately with data if available or an empty string.
    # Should not raise errors
    def read_nonblock
      raise "read_nonblock not defined by Stream"
    end

    # Expected to write complete set of data.  May raise Timeout::Error
    # or other errors.
    #
    # @param data [String] Binary data to write to the stream
    def write(data)
      raise "write not defined by Stream"
    end

    # Connects the stream
    def connect
      raise "connect not defined by Stream"
    end

    # @return [Boolean] true if connected or false otherwise
    def connected?
      raise "connected? not defined by Stream"
    end

    # Disconnects the stream
    # Note that streams are not designed to be reconnected and must be recreated
    def disconnect
      raise "disconnect not defined by Stream"
    end
  end # class Stream
end
