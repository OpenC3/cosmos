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

require 'spec_helper'
require 'openc3/models/reducer_model'

module OpenC3
  describe ReducerModel do
    before(:each) do
      mock_redis()
    end

    describe "add_file, rm_file, all_files" do
      it "adds a file, removes a file, lists all files" do
        inst_filename = "DEFAULT/decom_logs/tlm/INST/20211122/20211229191610578229500__20211229192610563836500__DEFAULT__INST__ALL__rt__decom.bin.gz"
        ReducerModel.add_file(inst_filename)
        # NOTE: Identical except INST2
        inst2_filename = "DEFAULT/decom_logs/tlm/INST2/20211122/20211229191610578229500__20211229192610563836500__DEFAULT__INST2__ALL__rt__decom.bin.gz"
        ReducerModel.add_file(inst2_filename)
        expect(ReducerModel.all_files(type: :DECOM, target: "INST", scope: "DEFAULT")).to eql [inst_filename]
        expect(ReducerModel.all_files(type: :DECOM, target: "INST2", scope: "DEFAULT")).to eql [inst2_filename]
        ReducerModel.rm_file(inst_filename)
        expect(ReducerModel.all_files(type: :DECOM, target: "INST", scope: "DEFAULT")).to eql []
        expect(ReducerModel.all_files(type: :DECOM, target: "INST2", scope: "DEFAULT")).to eql [inst2_filename]
        ReducerModel.rm_file(inst2_filename)
        expect(ReducerModel.all_files(type: :DECOM, target: "INST2", scope: "DEFAULT")).to eql []

        minute_filename = "DEFAULT/reduced_minute_logs/tlm/INST/20211122/20211229191610578229500__20211229192610563836500__DEFAULT__INST__ALL__rt__reduced_minute.bin.gz"
        ReducerModel.add_file(minute_filename)
        expect(ReducerModel.all_files(type: :MINUTE, target: "INST", scope: "DEFAULT")).to eql [minute_filename]
        expect(ReducerModel.all_files(type: :MINUTE, target: "BLAH", scope: "DEFAULT")).to eql []
        ReducerModel.rm_file(minute_filename)
        expect(ReducerModel.all_files(type: :MINUTE, target: "INST", scope: "DEFAULT")).to eql []
      end
    end
  end
end
