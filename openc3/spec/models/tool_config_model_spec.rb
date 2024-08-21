# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/tool_config_model'

module OpenC3
  describe ToolConfigModel, type: :model do
    before(:each) do
      mock_redis()
      setup_system()
    end

    describe "self.tool_config" do

      it "self.load_config" do
        config = ToolConfigModel.load_config('toolie', 'namely', scope: 'DEFAULT')
        expect(config).to be_nil
      end

      it "self.list_configs" do
        all = ToolConfigModel.list_configs('toolie', scope: 'DEFAULT')
        expect(all[0]).to be_nil # eq('ps')
      end

      it "self.config_tool_names" do
        names = ToolConfigModel.config_tool_names(scope: 'DEFAULT')
        expect(names[0]).to be_nil # eq('ps')
      end

      it "deletes" do
        names = ToolConfigModel.delete_config('toolie', 'namely', local_mode: true, scope: 'DEFAULT')
        expect(names[0]).to match(/.*\/DEFAULT\/tool_config\/toolie\/namely.json.*/)
      end
    end
  end
end
