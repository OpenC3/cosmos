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
require 'openc3/models/tool_config_model'
require 'openc3/utilities/local_mode'
require 'fileutils'
require 'tmpdir'

module OpenC3
  describe ToolConfigModel, type: :model do
    before(:each) do
      mock_redis()
      setup_system()
      # LocalMode reads OPENC3_LOCAL_MODE_PATH into a constant at load time, so
      # point it at a temp dir the same way local_mode_spec does rather than
      # depending on /plugins existing
      # nil is meaningful: it records that the variable was unset, so the
      # assignment in after(:each) deletes the key again rather than setting it
      @saved_local_mode = ENV.fetch('OPENC3_LOCAL_MODE', nil)
      @saved_local_mode_path = LocalMode::OPENC3_LOCAL_MODE_PATH
      ENV['OPENC3_LOCAL_MODE'] = '1'
      @local_mode_dir = Dir.mktmpdir
      saved_verbose = $VERBOSE; $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @local_mode_dir)
      $VERBOSE = saved_verbose
    end

    after(:each) do
      ENV['OPENC3_LOCAL_MODE'] = @saved_local_mode
      saved_verbose = $VERBOSE; $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @saved_local_mode_path)
      $VERBOSE = saved_verbose
      FileUtils.rm_rf(@local_mode_dir) if @local_mode_dir
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
        # delete_config only touches a file when local mode is on and the local
        # mode path exists, so set both up here. Without this the test only
        # passed in the container, where OPENC3_LOCAL_MODE is set and /plugins
        # exists; anywhere else delete_tool_config returned nil early.
        config_path = "#{@local_mode_dir}/DEFAULT/tool_config/toolie/namely.json"
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, '{}')

        names = ToolConfigModel.delete_config('toolie', 'namely', local_mode: true, scope: 'DEFAULT')
        expect(names[0]).to match(/.*\/DEFAULT\/tool_config\/toolie\/namely.json.*/)
        expect(File.exist?(config_path)).to be false
      end

      it "deletes without local mode" do
        ENV.delete('OPENC3_LOCAL_MODE')
        expect(ToolConfigModel.delete_config('toolie', 'namely', local_mode: true, scope: 'DEFAULT')).to be_nil
      end

      it "allows valid tool and config names" do
        ToolConfigModel.save_config('my-tool', 'My Config 1.0', '{}', local_mode: false, scope: 'DEFAULT')
        config = ToolConfigModel.load_config('my-tool', 'My Config 1.0', scope: 'DEFAULT')
        expect(config).to eq('{}')
      end

      it "rejects invalid characters in tool name" do
        expect { ToolConfigModel.save_config('../evil', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.save_config('evil/sub', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.save_config('evil\\sub', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.save_config('', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.save_config('evil@name', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.save_config('evil#name', 'name', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.delete_config('../evil', 'name', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.load_config('../evil', 'name', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
        expect { ToolConfigModel.list_configs('../evil', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid tool name/)
      end

      it "rejects invalid characters in config name" do
        expect { ToolConfigModel.save_config('tool', '../../etc/passwd', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.save_config('tool', 'sub/dir', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.save_config('tool', 'sub\\dir', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.save_config('tool', '', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.save_config('tool', 'name@evil', '{}', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.delete_config('tool', '../evil', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
        expect { ToolConfigModel.load_config('tool', '../evil', scope: 'DEFAULT') }.to raise_error(ToolConfigModel::InvalidNameError, /Invalid config name/)
      end
    end
  end
end
