# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/io/stdout'

module OpenC3
  describe Stdout do
    describe "instance" do
      it "returns a single instance" do
        expect(Stdout.instance).to eq(Stdout.instance)
      end
    end

    describe "puts" do
      it "writes to STDOUT" do
        expect($stdout).to receive(:puts).with("TEST")
        Stdout.instance.puts("TEST")
      end
    end
  end
end
