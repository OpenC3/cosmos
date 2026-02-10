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
require 'openc3/core_ext/objectspace'

describe ObjectSpace do
  if RUBY_ENGINE == 'ruby'
    describe "find" do
      it "finds a class in the Ruby object space" do
        expect(ObjectSpace.find(Class)).not_to be_nil
        expect(ObjectSpace.find(OpenC3)).to be_nil
      end
    end

    describe "find_all" do
      it "finds classes in the Ruby object space" do
        expect(ObjectSpace.find_all(Class)).to be_a(Array)
        expect(ObjectSpace.find_all(OpenC3)).to eql([])
      end
    end
  end
end
