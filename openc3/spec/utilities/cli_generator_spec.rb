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
      ENV.delete('OPENC3_LANGUAGE')
    end

    after(:each) do
      Dir.chdir(@original_dir)
      FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      ENV.delete('OPENC3_LANGUAGE')
    end

    # Tests exercise the full entry point so extract_language!/check_args run.
    # generate() returns the value of the underlying generate_* method.
    def run_gen(args)
      CliGenerator.generate(args)
    end

    describe "generate plugin" do
      it "generates a Ruby plugin with --ruby flag" do
        result = run_gen(['plugin', 'test-plugin', '--ruby'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        expect(File.exist?('plugin.txt')).to be true
        expect(File.exist?('openc3-cosmos-test-plugin.gemspec')).to be true
        expect(File.exist?('Rakefile')).to be true
        expect(File.exist?('README.md')).to be true
      end

      it "writes a '# LANGUAGE ruby' comment to plugin.txt when --ruby is given" do
        run_gen(['plugin', 'test-plugin', '--ruby'])
        expect(File.read('plugin.txt')).to start_with("# LANGUAGE ruby\n")
      end

      it "writes a '# LANGUAGE python' comment to plugin.txt when --python is given" do
        run_gen(['plugin', 'test-plugin', '--python'])
        expect(File.read('plugin.txt')).to start_with("# LANGUAGE python\n")
      end

      it "generates a plugin without a language flag" do
        result = run_gen(['plugin', 'test-plugin'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        expect(File.exist?('plugin.txt')).to be true
      end

      it "does NOT write a # LANGUAGE comment when no language is specified" do
        run_gen(['plugin', 'test-plugin'])
        expect(File.read('plugin.txt')).not_to match(/^\s*#\s*LANGUAGE\b/)
      end

      it "uses OPENC3_LANGUAGE environment variable" do
        ENV['OPENC3_LANGUAGE'] = 'python'
        result = run_gen(['plugin', 'test-plugin'])
        expect(result).to eql('openc3-cosmos-test-plugin')
        # Env var resolves @@language, which causes the # LANGUAGE comment to be written.
        expect(File.read('plugin.txt')).to start_with("# LANGUAGE python\n")
      end

      it "prevents duplicate plugin generation" do
        run_gen(['plugin', 'test-plugin', '--ruby'])
        Dir.chdir(@temp_dir)
        expect { run_gen(['plugin', 'test-plugin', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { run_gen(['plugin', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a plugin name" do
        expect { run_gen(['plugin']) }
          .to raise_error(SystemExit)
      end

      it "aborts when language flag appears before the name" do
        # `cli generate plugin --python` — no NAME positional arg
        expect { run_gen(['plugin', '--python']) }
          .to raise_error(SystemExit)
      end

      it "aborts when both --ruby and --python are supplied" do
        expect { run_gen(['plugin', 'test-plugin', '--ruby', '--python']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate target" do
      before(:each) do
        run_gen(['plugin', 'test-plugin', '--ruby'])
      end

      it "generates a target with --ruby flag" do
        result = run_gen(['target', 'EXAMPLE', '--ruby'])
        expect(result).to eql('EXAMPLE')
        expect(File.exist?('targets/EXAMPLE')).to be true
        expect(File.exist?('targets/EXAMPLE/cmd_tlm/cmd.txt')).to be true
        expect(File.exist?('targets/EXAMPLE/cmd_tlm/tlm.txt')).to be true
        expect(File.exist?('targets/EXAMPLE/lib/example.rb')).to be true
      end

      it "inherits language from plugin.txt when no flag is given" do
        # Plugin was generated with --ruby, so plugin.txt has '# LANGUAGE ruby'
        result = run_gen(['target', 'EXAMPLE'])
        expect(result).to eql('EXAMPLE')
        expect(File.exist?('targets/EXAMPLE/lib/example.rb')).to be true
      end

      it "uses OPENC3_LANGUAGE env var when no flag is given and no plugin.txt comment" do
        Dir.chdir(@temp_dir)
        FileUtils.rm_rf('openc3-cosmos-test-plugin')
        run_gen(['plugin', 'test-plugin']) # no flag, no env var → no LANGUAGE comment
        ENV['OPENC3_LANGUAGE'] = 'python'
        result = run_gen(['target', 'EXAMPLE'])
        expect(result).to eql('EXAMPLE')
        expect(File.exist?('targets/EXAMPLE/lib/example.py')).to be true
      end

      it "aborts when language can't be resolved from any source" do
        Dir.chdir(@temp_dir)
        FileUtils.rm_rf('openc3-cosmos-test-plugin')
        run_gen(['plugin', 'test-plugin'])
        expect { run_gen(['target', 'EXAMPLE']) }
          .to raise_error(SystemExit)
      end

      it "explicit --python overrides plugin.txt ruby default" do
        result = run_gen(['target', 'EXAMPLE', '--python'])
        expect(result).to eql('EXAMPLE')
        expect(File.exist?('targets/EXAMPLE/lib/example.py')).to be true
      end

      it "writes LANGUAGE python to target.txt when --python is used" do
        run_gen(['target', 'EXAMPLE', '--python'])
        expect(File.read('targets/EXAMPLE/target.txt')).to include('LANGUAGE python')
      end

      it "prevents duplicate target generation" do
        run_gen(['target', 'EXAMPLE', '--ruby'])
        expect { run_gen(['target', 'EXAMPLE', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { run_gen(['target', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a target name" do
        expect { run_gen(['target']) }
          .to raise_error(SystemExit)
      end

      it "aborts when language flag appears before the name" do
        expect { run_gen(['target', '--ruby']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate microservice" do
      before(:each) do
        run_gen(['plugin', 'test-plugin', '--ruby'])
      end

      it "generates a Ruby microservice with explicit --ruby" do
        result = run_gen(['microservice', 'BACKGROUND', '--ruby'])
        expect(result).to eql('BACKGROUND')
        expect(File.exist?('microservices/BACKGROUND/background.rb')).to be true

        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('MICROSERVICE BACKGROUND background-microservice')
        expect(plugin_txt).to include('CMD ruby background.rb')
      end

      it "inherits language from plugin.txt when no flag is given" do
        result = run_gen(['microservice', 'BACKGROUND'])
        expect(result).to eql('BACKGROUND')
        expect(File.exist?('microservices/BACKGROUND/background.rb')).to be true
      end

      it "generates a Python microservice with plugin lib path setup" do
        Dir.chdir(@temp_dir)
        FileUtils.rm_rf('openc3-cosmos-test-plugin')
        run_gen(['plugin', 'test-plugin', '--python'])
        result = run_gen(['microservice', 'BACKGROUND', '--python'])
        expect(result).to eql('BACKGROUND')
        microservice_path = 'microservices/BACKGROUND/background.py'
        expect(File.exist?(microservice_path)).to be true

        # Verifies the fix for issue #3322: generated Python microservices must
        # prepend plugin `lib/` directories to sys.path before any user imports.
        contents = File.read(microservice_path)
        expect(contents).to include('from openc3.top_level import add_to_search_path')
        expect(contents).to include('glob.glob("/gems/gems/**/lib")')
        expect(contents).to include('add_to_search_path(path, True)')
        path_setup_index = contents.index('add_to_search_path(path, True)')
        microservice_import_index = contents.index('from openc3.microservices.microservice import Microservice')
        expect(path_setup_index).to be < microservice_import_index

        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('CMD python background.py')
      end

      it "aborts when language can't be resolved from any source" do
        Dir.chdir(@temp_dir)
        FileUtils.rm_rf('openc3-cosmos-test-plugin')
        run_gen(['plugin', 'test-plugin'])
        expect { run_gen(['microservice', 'BACKGROUND']) }
          .to raise_error(SystemExit)
      end

      it "prevents duplicate microservice generation" do
        run_gen(['microservice', 'BACKGROUND', '--ruby'])
        expect { run_gen(['microservice', 'BACKGROUND', '--ruby']) }
          .to raise_error(SystemExit)
      end

      it "rejects regeneration when plugin.txt already lists the microservice" do
        # Simulate user deleting microservices/NAME but leaving the plugin.txt
        # entry behind. Without this guard the generator would append a second
        # MICROSERVICE entry, which causes plugin install to fail with
        # "openc3_microservices:...already exists at create".
        run_gen(['microservice', 'BACKGROUND', '--ruby'])
        FileUtils.rm_rf('microservices/BACKGROUND')
        expect { run_gen(['microservice', 'BACKGROUND', '--ruby']) }
          .to raise_error(SystemExit)
        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt.scan(/^MICROSERVICE\s+BACKGROUND\b/).size).to eq(1)
      end

      it "shows help with --help flag" do
        expect { run_gen(['microservice', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a microservice name" do
        expect { run_gen(['microservice']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate widget" do
      before(:each) do
        run_gen(['plugin', 'widget-test', '--ruby'])
      end

      it "generates a widget without a language flag" do
        result = run_gen(['widget', 'TestWidget'])
        expect(result).to eql('TestWidget')
        expect(File.exist?('src/TestWidget.vue')).to be true
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('vite.config.js')).to be true

        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('WIDGET Test')
      end

      it "ignores a language flag and warns when one is supplied" do
        expect { run_gen(['widget', 'TestWidget', '--python']) }
          .to output(/--ruby\/--python is ignored for the widget generator/).to_stdout
        expect(File.exist?('src/TestWidget.vue')).to be true
      end

      it "rejects widget names without Widget suffix" do
        expect { run_gen(['widget', 'BadName']) }
          .to raise_error(SystemExit)
      end

      it "rejects widget names that don't start with uppercase" do
        expect { run_gen(['widget', 'badWidget']) }
          .to raise_error(SystemExit)
      end

      it "prevents duplicate widget generation" do
        run_gen(['widget', 'TestWidget'])
        expect { run_gen(['widget', 'TestWidget']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { run_gen(['widget', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a widget name" do
        expect { run_gen(['widget']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate tool" do
      before(:each) do
        run_gen(['plugin', 'tool-test', '--ruby'])
      end

      it "generates a Vue.js tool without a language flag" do
        result = run_gen(['tool_vue', 'Test Tool'])
        expect(result).to eql('testtool')
        expect(File.exist?('package.json')).to be true
        expect(File.exist?('vite.config.js')).to be true
        expect(File.exist?('src/App.vue')).to be true
        expect(File.exist?('src/tools/testtool/testtool.vue')).to be true

        plugin_txt = File.read('plugin.txt')
        expect(plugin_txt).to include('TOOL testtool "Test Tool"')
        expect(plugin_txt).to include('INLINE_URL main.js')
      end

      it "ignores a language flag and warns when one is supplied" do
        expect { run_gen(['tool_vue', 'Test Tool', '--ruby']) }
          .to output(/--ruby\/--python is ignored for the tool_vue generator/).to_stdout
        expect(File.exist?('src/tools/testtool/testtool.vue')).to be true
      end

      it "handles tool names with spaces and special characters" do
        result = run_gen(['tool_vue', 'My-Cool Tool'])
        expect(result).to eql('mycooltool')
        expect(File.exist?('src/tools/mycooltool/mycooltool.vue')).to be true
      end

      it "defaults to Vue.js when no type specified" do
        result = run_gen(['tool', 'Generic Tool'])
        expect(result).to eql('generictool')
        expect(File.exist?('vite.config.js')).to be true
        expect(File.exist?('src/App.vue')).to be true
      end

      it "generates an Angular tool" do
        result = run_gen(['tool_angular', 'Test Tool'])
        expect(result).to eql('testtool')
        expect(File.exist?('angular.json')).to be true
        expect(File.exist?('src/main.single-spa.ts')).to be true
      end

      it "generates a React tool" do
        result = run_gen(['tool_react', 'Test Tool'])
        expect(result).to eql('testtool')
        expect(File.exist?('webpack.config.js')).to be true
        expect(File.exist?('src/root.component.js')).to be true
      end

      it "generates a Svelte tool" do
        result = run_gen(['tool_svelte', 'Test Tool'])
        expect(result).to eql('testtool')
        expect(File.exist?('rollup.config.js')).to be true
        expect(File.exist?('src/App.svelte')).to be true
      end

      it "shows help with --help flag" do
        expect { run_gen(['tool_vue', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it "requires a tool name" do
        expect { run_gen(['tool_vue']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate command_validator" do
      before(:each) do
        run_gen(['plugin', 'validator-test', '--ruby'])
        run_gen(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a Ruby command validator (language read from target.txt)" do
        result = run_gen(['command_validator', 'EXAMPLE', 'test'])
        expect(result).to eql('TEST_COMMAND_VALIDATOR')
        expect(File.exist?('targets/EXAMPLE/lib/test_command_validator.rb')).to be true

        validator_content = File.read('targets/EXAMPLE/lib/test_command_validator.rb')
        expect(validator_content).to include('class TestCommandValidator')
        expect(validator_content).to include('def pre_check(command)')
        expect(validator_content).to include('def post_check(command)')
      end

      it "generates a Python command validator when target is Python" do
        run_gen(['target', 'PYTARGET', '--python'])
        result = run_gen(['command_validator', 'PYTARGET', 'test'])
        expect(result).to eql('TEST_COMMAND_VALIDATOR')
        expect(File.exist?('targets/PYTARGET/lib/test_command_validator.py')).to be true
      end

      it "shows help with --help flag" do
        expect { run_gen(['command_validator', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it "requires target and validator names" do
        expect { run_gen(['command_validator']) }
          .to raise_error(SystemExit)
      end
    end

    describe "generate conversion" do
      before(:each) do
        run_gen(['plugin', 'conversion-test', '--ruby'])
        run_gen(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a Ruby conversion (language read from target.txt)" do
        result = run_gen(['conversion', 'EXAMPLE', 'test'])
        expect(result).to eql('TEST_CONVERSION')
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.rb')).to be true

        conversion_content = File.read('targets/EXAMPLE/lib/test_conversion.rb')
        expect(conversion_content).to include('class TestConversion')
        expect(conversion_content).to include('def call')
      end

      it "generates a Python conversion when target is Python" do
        run_gen(['target', 'PYTARGET', '--python'])
        result = run_gen(['conversion', 'PYTARGET', 'test'])
        expect(result).to eql('TEST_CONVERSION')
        expect(File.exist?('targets/PYTARGET/lib/test_conversion.py')).to be true
        expect(File.exist?('targets/PYTARGET/lib/test_conversion.rb')).to be false
      end

      it "ignores a language flag and warns when one is supplied" do
        expect { run_gen(['conversion', 'EXAMPLE', 'test', '--python']) }
          .to output(/--ruby\/--python is ignored for the conversion generator/).to_stdout
        # The actual language must come from target.txt (Ruby in this case)
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.rb')).to be true
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.py')).to be false
      end

      it "aborts when target.txt has no LANGUAGE keyword" do
        File.write('targets/EXAMPLE/target.txt', "# no language here\n")
        expect { run_gen(['conversion', 'EXAMPLE', 'test']) }
          .to raise_error(SystemExit)
      end

      it "aborts when target does not exist" do
        expect { run_gen(['conversion', 'NOPE', 'test']) }
          .to raise_error(SystemExit)
      end

      it "shows help with --help flag" do
        expect { run_gen(['conversion', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    describe "generate processor" do
      before(:each) do
        run_gen(['plugin', 'processor-test', '--ruby'])
        run_gen(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a Ruby processor (language read from target.txt)" do
        result = run_gen(['processor', 'EXAMPLE', 'test'])
        expect(result).to eql('TEST_PROCESSOR')
        expect(File.exist?('targets/EXAMPLE/lib/test_processor.rb')).to be true
      end

      it "generates a Python processor when target is Python" do
        run_gen(['target', 'PYTARGET', '--python'])
        result = run_gen(['processor', 'PYTARGET', 'test'])
        expect(result).to eql('TEST_PROCESSOR')
        expect(File.exist?('targets/PYTARGET/lib/test_processor.py')).to be true
      end
    end

    describe "generate limits_response" do
      before(:each) do
        run_gen(['plugin', 'limits-test', '--ruby'])
        run_gen(['target', 'EXAMPLE', '--ruby'])
      end

      it "generates a Ruby limits response (language read from target.txt)" do
        result = run_gen(['limits_response', 'EXAMPLE', 'test'])
        expect(result).to eql('TEST_LIMITS_RESPONSE')
        expect(File.exist?('targets/EXAMPLE/lib/test_limits_response.rb')).to be true

        limits_content = File.read('targets/EXAMPLE/lib/test_limits_response.rb')
        expect(limits_content).to include('class TestLimitsResponse')
        expect(limits_content).to include('def call')
      end

      it "generates a Python limits response when target is Python" do
        run_gen(['target', 'PYTARGET', '--python'])
        result = run_gen(['limits_response', 'PYTARGET', 'test'])
        expect(result).to eql('TEST_LIMITS_RESPONSE')
        expect(File.exist?('targets/PYTARGET/lib/test_limits_response.py')).to be true
      end

      it "shows help with --help flag" do
        expect { run_gen(['limits_response', '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    describe "argument parsing edge cases" do
      it "handles empty arguments" do
        expect { run_gen([]) }
          .to raise_error(SystemExit)
      end

      it "rejects invalid command types" do
        expect { run_gen(['invalid_command']) }
          .to raise_error(SystemExit)
      end

      it "aborts on extra positional args after the name" do
        expect { run_gen(['plugin', 'test-plugin', 'extra']) }
          .to raise_error(SystemExit)
      end
    end
  end
end
