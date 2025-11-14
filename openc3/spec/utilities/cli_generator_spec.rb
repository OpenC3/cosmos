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

require "spec_helper"
require "openc3/utilities/cli_generator"
require "fileutils"
require "tmpdir"

module OpenC3
  describe CliGenerator do
    before(:each) do
      @temp_dir = Dir.mktmpdir
      @original_dir = Dir.pwd
      Dir.chdir(@temp_dir)
      ENV['OPENC3_LANGUAGE'] = 'ruby'
      # Initialize the class variable that check_args normally sets
      CliGenerator.class_variable_set(:@@language, 'rb')
    end

    after(:each) do
      Dir.chdir(@original_dir)
      FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      ENV.delete('OPENC3_LANGUAGE')
    end

    describe "generate_plugin" do
      it "generates a basic Ruby plugin" do
        result = CliGenerator.generate_plugin(['plugin', 'test-plugin', '--ruby'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        # generate_plugin changes into the plugin directory, so files are relative
        expect(File.exist?('plugin.txt')).to be true
        expect(File.exist?('openc3-cosmos-test-plugin.gemspec')).to be true
        expect(File.exist?('Rakefile')).to be true
        expect(File.exist?('README.md')).to be true
      end

      it "generates a Python plugin" do
        CliGenerator.class_variable_set(:@@language, 'py')
        result = CliGenerator.generate_plugin(['plugin', 'test-plugin', '--python'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        expect(File.exist?('plugin.txt')).to be true
      end

      it "uses OPENC3_LANGUAGE environment variable" do
        ENV['OPENC3_LANGUAGE'] = 'python'
        CliGenerator.class_variable_set(:@@language, 'py')
        result = CliGenerator.generate_plugin(['plugin', 'test-plugin'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        expect(File.exist?('plugin.txt')).to be true
      end

      it "prevents duplicate plugin generation" do
        result = CliGenerator.generate_plugin(['plugin', 'test-plugin', '--ruby'])
        Dir.chdir(@temp_dir)  # Go back to temp dir since generate_plugin cd's into plugin dir
        expect { CliGenerator.generate_plugin(['plugin', 'test-plugin', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_plugin(['plugin', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a plugin name" do
        expect { CliGenerator.generate_plugin(['plugin']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate_target" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'test-plugin', '--ruby'])
      end

      it "generates a target" do
        result = CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby'])
        expect(result).to eql('EXAMPLE')
        expect(File.exist?('targets/EXAMPLE')).to be true
        expect(File.exist?('targets/EXAMPLE/cmd_tlm/cmd.txt')).to be true
        expect(File.exist?('targets/EXAMPLE/cmd_tlm/tlm.txt')).to be true
      end

      it "prevents duplicate target generation" do
        CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby'])
        expect { CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_target(['target', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a target name" do
        expect { CliGenerator.generate_target(['target']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate_widget" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'widget-test', '--ruby'])
      end

      it "generates a widget with proper naming" do
        result = CliGenerator.generate_widget(['widget', 'TestWidget', '--ruby'])
        expect(result).to eql('TestWidget')
        expect(File.exist?('src/TestWidget.vue')).to be true
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('vite.config.js')).to be true

        # Verify widget was added to plugin.txt with Widget suffix removed
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('WIDGET Test')
      end

      it "rejects widget names without Widget suffix" do
        expect { CliGenerator.generate_widget(['widget', 'BadName', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "rejects widget names that don't start with uppercase" do
        expect { CliGenerator.generate_widget(['widget', 'badWidget', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "prevents duplicate widget generation" do
        CliGenerator.generate_widget(['widget', 'TestWidget', '--ruby'])
        expect { CliGenerator.generate_widget(['widget', 'TestWidget', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_widget(['widget', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a widget name" do
        expect { CliGenerator.generate_widget(['widget']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate_tool_vue" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'tool-test', '--ruby'])
      end

      it "generates a Vue.js tool" do
        result = CliGenerator.generate_tool(['tool_vue', 'Test Tool', '--ruby'])
        expect(result).to eql('testtool')
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('vite.config.js')).to be true
        expect(File.exist?('src/App.vue')).to be true
        expect(File.exist?('src/tools/testtool/testtool.vue')).to be true

        # Verify tool was added to plugin.txt
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('TOOL testtool "Test Tool"')
        expect(plugin_txt).to include('INLINE_URL main.js')
      end

      it "handles tool names with spaces and special characters" do
        result = CliGenerator.generate_tool(['tool_vue', 'My-Cool Tool', '--ruby'])
        expect(result).to eql('mycooltool')
        expect(File.exist?('src/tools/mycooltool/mycooltool.vue')).to be true
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_tool(['tool_vue', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a tool name" do
        expect { CliGenerator.generate_tool(['tool_vue']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate_tool (generic defaults to Vue)" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'tool-test', '--ruby'])
      end

      it "defaults to Vue.js when no type specified" do
        result = CliGenerator.generate_tool(['tool', 'Generic Tool', '--ruby'])
        expect(result).to eql('generictool')
        expect(File.exist?('vite.config.js')).to be true
        expect(File.exist?('src/App.vue')).to be true
      end
    end

    describe "generate_tool_angular" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'tool-test', '--ruby'])
      end

      it "generates an Angular tool" do
        result = CliGenerator.generate_tool(['tool_angular', 'Test Tool', '--ruby'])
        expect(result).to eql('testtool')
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('angular.json')).to be true
        expect(File.exist?('src/main.single-spa.ts')).to be true

        # Verify tool was added to plugin.txt
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('TOOL testtool "Test Tool"')
      end
    end

    describe "generate_tool_react" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'tool-test', '--ruby'])
      end

      it "generates a React tool" do
        result = CliGenerator.generate_tool(['tool_react', 'Test Tool', '--ruby'])
        expect(result).to eql('testtool')
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('webpack.config.js')).to be true
        expect(File.exist?('src/root.component.js')).to be true

        # Verify tool was added to plugin.txt
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('TOOL testtool "Test Tool"')
      end
    end

    describe "generate_tool_svelte" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'tool-test', '--ruby'])
      end

      it "generates a Svelte tool" do
        result = CliGenerator.generate_tool(['tool_svelte', 'Test Tool', '--ruby'])
        expect(result).to eql('testtool')
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('rollup.config.js')).to be true
        expect(File.exist?('src/App.svelte')).to be true

        # Verify tool was added to plugin.txt
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('TOOL testtool "Test Tool"')
      end
    end

    describe "generate_command_validator" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'validator-test', '--ruby'])
        CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a command validator" do
        result = CliGenerator.generate_command_validator(['command_validator', 'EXAMPLE', 'test', '--ruby'])
        expect(result).to eql('TEST_COMMAND_VALIDATOR')
        expect(File.exist?('targets/EXAMPLE/lib/test_command_validator.rb')).to be true

        # Verify validator file contains proper class structure
        validator_content = File.read('targets/EXAMPLE/lib/test_command_validator.rb')
        expect(validator_content).to include('class TestCommandValidator')
        expect(validator_content).to include('def pre_check(command)')
        expect(validator_content).to include('def post_check(command)')
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_command_validator(['command_validator', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it "requires target and validator names" do
        expect { CliGenerator.generate_command_validator(['command_validator']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate_conversion" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'conversion-test', '--ruby'])
        CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a conversion" do
        result = CliGenerator.generate_conversion(['conversion', 'EXAMPLE', 'test', '--ruby'])
        expect(result).to eql('TEST_CONVERSION')
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.rb')).to be true

        # Verify conversion file contains proper class structure
        conversion_content = File.read('targets/EXAMPLE/lib/test_conversion.rb')
        expect(conversion_content).to include('class TestConversion')
        expect(conversion_content).to include('def call')
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_conversion(['conversion', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    describe "generate_limits_response" do
      before(:each) do
        # generate_plugin already changes into the plugin directory
        CliGenerator.generate_plugin(['plugin', 'limits-test', '--ruby'])
        CliGenerator.generate_target(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a limits response" do
        result = CliGenerator.generate_limits_response(['limits_response', 'EXAMPLE', 'test', '--ruby'])
        expect(result).to eql('TEST_LIMITS_RESPONSE')
        expect(File.exist?('targets/EXAMPLE/lib/test_limits_response.rb')).to be true

        # Verify limits response file contains proper class structure
        limits_content = File.read('targets/EXAMPLE/lib/test_limits_response.rb')
        expect(limits_content).to include('class TestLimitsResponse')
        expect(limits_content).to include('def call')
      end

      it "shows help with --help flag" do
        expect { CliGenerator.generate_limits_response(['limits_response', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    describe "edge cases" do
      it "handles nil arguments gracefully" do
        expect { CliGenerator.generate_plugin(nil) }
          .to raise_error(NoMethodError)
      end

      it "handles empty arguments" do
        expect { CliGenerator.generate_plugin([]) }
          .to raise_error(SystemExit)
      end

      it "handles invalid command types" do
        expect { CliGenerator.generate(['invalid_command']) }
          .to raise_error(SystemExit)
      end
    end
  end
end
