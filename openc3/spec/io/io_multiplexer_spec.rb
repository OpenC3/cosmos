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

require 'spec_helper'
require 'openc3/io/io_multiplexer'

module OpenC3
  describe IoMultiplexer do
    before(:each) do
      @io = IoMultiplexer.new
    end

    describe "stream_operator" do
      it "supports the << operator" do
        @io.add_stream(STDOUT)
        expect($stdout).to receive(:<<).with("TEST").and_return($stdout)
        result = (@io << "TEST")
        expect(result).to eql(@io)
      end
    end

    describe "add_stream" do
      it "adds a single stream" do
        @io.add_stream(STDOUT)
        expect($stdout).to receive(:puts).with("TEST")
        @io.puts "TEST"
      end

      it "adds multiple streams" do
        @io.add_stream(STDOUT)
        @io.add_stream(STDERR)
        expect($stdout).to receive(:puts).with("TEST")
        expect($stderr).to receive(:puts).with("TEST")
        @io.puts "TEST"
      end
    end

    describe "remove_stream" do
      it "removes the stream from output" do
        @io.add_stream(STDOUT)
        @io.add_stream(STDERR)
        @io.remove_stream(STDOUT)
        expect($stdout).not_to receive(:puts).with("TEST")
        expect($stderr).to receive(:puts).with("TEST")
        @io.puts "TEST"
      end
    end

    describe "print, printf, putc, puts, flush" do
      it "defers to the stream" do
        @io.add_stream(STDOUT)
        expect($stdout).to receive(:print).with("TEST")
        @io.print "TEST"
        expect($stdout).to receive(:printf).with("TEST")
        @io.printf "TEST"
        expect($stdout).to receive(:putc).with("TEST")
        @io.putc "TEST"
        expect($stdout).to receive(:puts).with("TEST")
        @io.puts "TEST"
        expect($stdout).to receive(:flush)
        @io.flush
      end
    end

    describe "write write_nonblock" do
      it "defers to the stream" do
        @io.add_stream(STDOUT)
        expect($stdout).to receive(:write).with("TEST").and_return(4)
        len = @io.write "TEST"
        expect(len).to eql 4
        expect($stdout).to receive(:write_nonblock).with("TEST").and_return(4)
        len = @io.write_nonblock "TEST"
        expect(len).to eql 4
      end
    end

    describe "remove_default_io" do
      it "removes STDOUT and STDERR from the streams" do
        f = File.open("unittest.txt", 'w')
        @io.add_stream(STDOUT)
        @io.add_stream(STDERR)
        @io.add_stream(f)
        @io.remove_default_io
        @io.puts "TEST"
        f.close
        expect($stdout).not_to receive(:puts).with("TEST")
        expect($stderr).not_to receive(:puts).with("TEST")
        expect(File.read("unittest.txt")).to eql "TEST\n"
        File.delete("unittest.txt")
      end
    end

    describe "it answers respond_to? correctly" do
      # NOTE: Ruby Logger uses log.respond_to?(:write) and log.respond_to?(:close)
      # to determine if it's a valid IO system, otherwise it assumes you're passing
      # a string which is a filename to open
      # https://github.com/ruby/logger/blob/master/lib/logger/log_device.rb#L80

      it "respond_to? :write" do
        expect(@io.respond_to?(:write)).to be true
      end

      it "respond_to? :close" do
        expect(@io.respond_to?(:close)).to be true
      end

      it "does not respond_to? :no_such_method" do
        expect(@io.respond_to?(:no_such_method)).to be false
      end
    end
  end
end
