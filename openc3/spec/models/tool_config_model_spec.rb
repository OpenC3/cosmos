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
    end

    # LocalMode captures its path in a constant at load time, so point it at a
    # temp dir without the redefinition warning
    def set_local_mode_path(path)
      saved_verbose = $VERBOSE
      $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, path)
      $VERBOSE = saved_verbose
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
        # delete_config only writes to the filesystem in local mode, so enable
        # it against a temp dir rather than depending on the container /plugins
        ENV['OPENC3_LOCAL_MODE'] = '1'
        tmp_dir = Dir.mktmpdir
        original_path = LocalMode::OPENC3_LOCAL_MODE_PATH
        set_local_mode_path(tmp_dir)
        begin
          ToolConfigModel.save_config('toolie', 'namely', '{}', local_mode: true, scope: 'DEFAULT')
          config_path = File.join(tmp_dir, 'DEFAULT', 'tool_config', 'toolie', 'namely.json')
          expect(File.exist?(config_path)).to be true
          names = ToolConfigModel.delete_config('toolie', 'namely', local_mode: true, scope: 'DEFAULT')
          expect(names[0]).to match(/.*\/DEFAULT\/tool_config\/toolie\/namely.json.*/)
          expect(File.exist?(config_path)).to be false
          expect(ToolConfigModel.load_config('toolie', 'namely', scope: 'DEFAULT')).to be_nil
        ensure
          set_local_mode_path(original_path)
          ENV.delete('OPENC3_LOCAL_MODE')
          FileUtils.rm_rf(tmp_dir)
        end
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
