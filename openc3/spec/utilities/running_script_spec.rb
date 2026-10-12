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
require 'tempfile'
require 'openc3/utilities/running_script'

module OpenC3
  describe Script do
    describe "open_bucket_dialog in a running script" do
      include OpenC3::Script

      before(:each) do
        @instance = double("RunningScript", scope: 'DEFAULT', scriptrunner_puts: nil, perform_wait: nil)
        allow(@instance).to receive(:user_input).and_return({
          'bucket' => 'OPENC3_CONFIG_BUCKET',
          'path' => 'DEFAULT/targets/INST/procedures/test.rb',
          'filename' => 'test.rb',
        })
        allow(RunningScript).to receive(:instance).and_return(@instance)
      end

      it "returns the file with its bucket and bucket path" do
        file = Tempfile.new('bucket_dialog')
        expect(self).to receive(:_get_storage_file).with('targets/INST/procedures/test.rb', bucket: 'OPENC3_CONFIG_BUCKET', scope: 'DEFAULT').and_return(file)
        result = open_bucket_dialog("Title")
        expect(result).to be(file)
        expect(result.filename).to eql 'test.rb'
        expect(result.bucket).to eql 'OPENC3_CONFIG_BUCKET'
        expect(result.bucket_path).to eql 'DEFAULT/targets/INST/procedures/test.rb'
        file.close!
      end
    end
  end
end
