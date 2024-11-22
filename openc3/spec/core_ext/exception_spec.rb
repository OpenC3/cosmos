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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/core_ext/exception'

describe Exception do
  describe "filtered" do
    it "filters an Exception" do
      raise "My message"
    rescue => e
      e.backtrace << "/lib/ruby/gems/2.7.0/gems/rspec-core-3.10.1/lib/rspec/core/example_group.rb:1"
      expect(e.filtered).to match(/My message/)
      expect(e.filtered).not_to match(/lib\/ruby\/gems/)
    end
  end

  describe "formatted" do
    it "formats an Exception" do
      raise "My message"
    rescue => e
      expect(e.formatted).to match(/RuntimeError : My message/)
      expect(e.formatted).to match(/#{File.expand_path(__FILE__)}/)
    end

    it "formats an Exception without RuntimeError class" do
      begin
        raise "My message"
      rescue => e
        expect(e.formatted(true)).not_to match(/RuntimeError/)
        expect(e.formatted(true)).to match(/My message/)
        expect(e.formatted(true)).to match(/#{File.expand_path(__FILE__)}/)
      end

      # If it's not a RuntimeError then we should still see the class
      begin
        raise ArgumentError.new("My message")
      rescue => e
        expect(e.formatted(true)).to match(/ArgumentError/)
        expect(e.formatted(true)).to match(/My message/)
        expect(e.formatted(true)).to match(/#{File.expand_path(__FILE__)}/)
      end
    end

    it "formats an Exception without stack trace" do
      begin
        raise "My message"
      rescue => e
        expect(e.formatted(false, false)).to match(/RuntimeError : My message/)
        expect(e.formatted(false, false)).not_to match(/#{File.expand_path(__FILE__)}/)
      end

      begin
        raise "My message"
      rescue => e
        expect(e.formatted(true, false)).to match(/My message/)
        expect(e.formatted(true, false)).not_to match(/#{File.expand_path(__FILE__)}/)
      end
    end
  end

  describe "source" do
    it "returns the file and line number of the exception" do
      line = __LINE__; raise "My message"
    rescue => e
      file, line = e.source
      expect(file).to eql __FILE__
      expect(line).to eql line
    end

    it "returns the file and line number of the exception" do
      line = __LINE__; raise "My message"
    rescue => e
      # Check to simulate being on UNIX or Windows
      if e.backtrace[0].include?(':') # windows
        e.backtrace[0].gsub!(/[A-Z]:/, '')
        file_name = __FILE__.gsub(/[A-Z]:/, '')
      else
        e.backtrace[0] = "C:" + e.backtrace[0]
        file_name = "C:#{__FILE__}"
      end
      file, line = e.source
      expect(file).to eql file_name
      expect(line).to eql line
    end
  end
end
