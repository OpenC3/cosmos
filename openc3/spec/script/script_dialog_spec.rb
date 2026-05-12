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

require 'spec_helper'
require 'openc3/script'

module OpenC3
  describe Script do
    describe "open_bucket_dialog stub" do
      include OpenC3::Script

      it "accepts no kwargs and returns user input" do
        allow(self).to receive(:print)
        allow(self).to receive(:gets).and_return("config/foo.txt\n")
        expect(open_bucket_dialog("Title")).to eql "config/foo.txt"
      end

      it "accepts default_path and filter kwargs" do
        captured = nil
        allow(self).to receive(:print) { |arg| captured = arg }
        allow(self).to receive(:gets).and_return("config/foo.txt\n")
        result = open_bucket_dialog(
          "Title", "Msg",
          default_path: "config/DEFAULT/targets/INST/procedures/",
          filter: ".rb",
        )
        expect(result).to eql "config/foo.txt"
        # Hint text should surface both kwargs to the user.
        expect(captured).to include "config/DEFAULT/targets/INST/procedures/"
        expect(captured).to include ".rb"
      end
    end
  end
end
