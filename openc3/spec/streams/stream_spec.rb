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
require 'openc3/streams/stream'

module OpenC3
  describe Stream do
    describe "read, write, connected?, disconnect" do
      it "raises an error" do
        expect { Stream.new.read       }.to raise_error(/not defined/)
        expect { Stream.new.write(nil) }.to raise_error(/not defined/)
        expect { Stream.new.connect }.to raise_error(/not defined/)
        expect { Stream.new.connected? }.to raise_error(/not defined/)
        expect { Stream.new.disconnect }.to raise_error(/not defined/)
      end
    end
  end
end
