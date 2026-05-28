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

    # --- Shared examples ---------------------------------------------------

    # Common boilerplate exercised by nearly every generator. Pass the
    # generator name; help-exit-status defaults to 0 (the user explicitly
    # asked for --help) but is 1 for target-derived generators which exit 1
    # whenever required args are missing.
    shared_examples 'standard help/arg behavior' do |generator, help_status: 0|
      it "shows help with --help flag" do
        expect { run_gen([generator, '--help']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(help_status) }
      end

      it "requires a #{generator} name" do
        expect { run_gen([generator]) }
          .to raise_error(SystemExit)
      end
    end

    # Generators that accept (but ignore + warn about) --ruby/--python.
    # `flag` is the flag to pass; `args` is the full arg array.
    shared_examples 'ignores language flag with warning' do |args, regex|
      it "ignores a language flag and warns when one is supplied" do
        expect { run_gen(args) }.to output(regex).to_stdout
      end
    end

    # --- Tests --------------------------------------------------------------

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

      it "aborts when language flag appears before the name" do
        # `cli generate plugin --python` — no NAME positional arg
        expect { run_gen(['plugin', '--python']) }
          .to raise_error(SystemExit)
      end

      it "aborts when both --ruby and --python are supplied" do
        expect { run_gen(['plugin', 'test-plugin', '--ruby', '--python']) }
          .to raise_error(SystemExit)
      end

      include_examples 'standard help/arg behavior', 'plugin'
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

      it "aborts when language flag appears before the name" do
        expect { run_gen(['target', '--ruby']) }
          .to raise_error(SystemExit)
      end

      include_examples 'standard help/arg behavior', 'target'
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

      include_examples 'standard help/arg behavior', 'microservice'
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

      include_examples 'ignores language flag with warning',
                       ['widget', 'TestWidget', '--python'],
                       %r{--ruby/--python is ignored for the widget generator}

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

      include_examples 'standard help/arg behavior', 'widget'
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

      include_examples 'ignores language flag with warning',
                       ['tool_vue', 'Test Tool', '--ruby'],
                       %r{--ruby/--python is ignored for the tool_vue generator}

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

      include_examples 'standard help/arg behavior', 'tool_vue'
    end

    # --- Target-derived generators (conversion / processor / limits_response /
    # command_validator) all share the same ruby/python/help/required-args shape.
    # Per-generator extras are captured in :ruby_class and :ruby_class_methods
    # below; we only run those assertions when the test row provides them.
    [
      {
        generator:          'conversion',
        suffix:             'CONVERSION',
        file_basename:      'test_conversion',
        ruby_class:         'TestConversion',
        ruby_class_methods: ['def call'],
      },
      {
        generator:          'processor',
        suffix:             'PROCESSOR',
        file_basename:      'test_processor',
      },
      {
        generator:          'limits_response',
        suffix:             'LIMITS_RESPONSE',
        file_basename:      'test_limits_response',
        ruby_class:         'TestLimitsResponse',
        ruby_class_methods: ['def call'],
      },
      {
        generator:          'command_validator',
        suffix:             'COMMAND_VALIDATOR',
        file_basename:      'test_command_validator',
        ruby_class:         'TestCommandValidator',
        ruby_class_methods: ['def pre_check(command)', 'def post_check(command)'],
      },
    ].each do |row|
      describe "generate #{row[:generator]}" do
        let(:gen) { row[:generator] }
        let(:suffix) { row[:suffix] }
        let(:base) { row[:file_basename] }

        before(:each) do
          run_gen(['plugin', "#{gen.tr('_', '-')}-test", '--ruby'])
          run_gen(['target', 'EXAMPLE', '--ruby'])
        end

        it "generates a Ruby #{row[:generator].tr('_', ' ')} (language read from target.txt)" do
          result = run_gen([gen, 'EXAMPLE', 'test'])
          expect(result).to eql("TEST_#{suffix}")
          rb_path = "targets/EXAMPLE/lib/#{base}.rb"
          expect(File.exist?(rb_path)).to be true

          if row[:ruby_class]
            content = File.read(rb_path)
            expect(content).to include("class #{row[:ruby_class]}")
            row[:ruby_class_methods].each { |m| expect(content).to include(m) }
          end
        end

        it "generates a Python #{row[:generator].tr('_', ' ')} when target is Python" do
          run_gen(['target', 'PYTARGET', '--python'])
          result = run_gen([gen, 'PYTARGET', 'test'])
          expect(result).to eql("TEST_#{suffix}")
          expect(File.exist?("targets/PYTARGET/lib/#{base}.py")).to be true
        end

        include_examples 'standard help/arg behavior', row[:generator], help_status: 1
      end
    end

    # Extra conversion-specific tests that don't apply to all target-derived
    # generators (target.txt corruption, missing target, language flag warning).
    describe "generate conversion edge cases" do
      before(:each) do
        run_gen(['plugin', 'conversion-test', '--ruby'])
        run_gen(['target', 'EXAMPLE', '--ruby'])
      end

      include_examples 'ignores language flag with warning',
                       ['conversion', 'EXAMPLE', 'test', '--python'],
                       %r{--ruby/--python is ignored for the conversion generator}

      it "ignored flag does not affect output language (still Ruby from target.txt)" do
        expect { run_gen(['conversion', 'EXAMPLE', 'test', '--python']) }.to output.to_stdout
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.rb')).to be true
        expect(File.exist?('targets/EXAMPLE/lib/test_conversion.py')).to be false
      end

      it "produces only the .py file when target is Python" do
        run_gen(['target', 'PYTARGET', '--python'])
        run_gen(['conversion', 'PYTARGET', 'test'])
        expect(File.exist?('targets/PYTARGET/lib/test_conversion.py')).to be true
        expect(File.exist?('targets/PYTARGET/lib/test_conversion.rb')).to be false
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
