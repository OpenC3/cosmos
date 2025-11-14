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
require "openc3/utilities/logger"

module OpenC3
  describe Logger do
    before(:each) do
      Logger.class_variable_set(:@@instance, nil)
    end

    describe "initialize" do
      it "initializes the level to INFO" do
        expect(Logger.new.level).to eql Logger::INFO
      end
    end

    describe "level" do
      it "gets and set the level" do
        Logger.level = Logger::DEBUG
        expect(Logger.level).to eql Logger::DEBUG
      end
    end

    def test_output(level, method, block = false)
      stdout = StringIO.new('', 'r+')
      $stdout = stdout
      Logger.level = level
      if block
        # Fortify doesn't like this due to Access Specifier Manipulation
        # but this is only test code
        Logger.send(method, "Message1") { "Block1" }
        json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
        expect(json['message']).not_to match("Message1")
        expect(json['level']).to match(method.upcase)
        expect(json['message']).to match("Block1")
      else
        # Fortify doesn't like this due to Access Specifier Manipulation
        # but this is only test code
        Logger.send(method, "Message1")
        json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
        expect(json['level']).to match(method.upcase)
        expect(json['message']).to match("Message1")
      end
      $stdout = STDOUT
    end

    def test_no_output(level, method, block = false)
      stdout = StringIO.new('', 'r+')
      $stdout = stdout
      Logger.level = level
      if block
        # Fortify doesn't like this due to Access Specifier Manipulation
        # but this is only test code
        Logger.send(method, "Message2") { "Block2" }
      else
        # Fortify doesn't like this due to Access Specifier Manipulation
        # but this is only test code
        Logger.send(method, "Message2")
      end
      expect(stdout.string).to be_empty
      $stdout = STDOUT
    end

    describe "debug" do
      it "prints if level is DEBUG or higher" do
        test_output(Logger::DEBUG, 'debug')
        test_output(Logger::DEBUG, 'info')
        test_output(Logger::DEBUG, 'warn')
        test_output(Logger::DEBUG, 'error')
        test_output(Logger::DEBUG, 'fatal')
        test_no_output(Logger::INFO, 'debug')
        test_no_output(Logger::WARN, 'debug')
        test_no_output(Logger::ERROR, 'debug')
        test_no_output(Logger::FATAL, 'debug')
      end
      it "takes a block" do
        test_output(Logger::DEBUG, 'debug', true)
        test_output(Logger::DEBUG, 'info', true)
        test_output(Logger::DEBUG, 'warn', true)
        test_output(Logger::DEBUG, 'error', true)
        test_output(Logger::DEBUG, 'fatal', true)
        test_no_output(Logger::INFO, 'debug', true)
        test_no_output(Logger::WARN, 'debug', true)
        test_no_output(Logger::ERROR, 'debug', true)
        test_no_output(Logger::FATAL, 'debug', true)
      end
    end

    describe "info" do
      it "prints if level is INFO or higher" do
        test_output(Logger::INFO, 'info')
        test_output(Logger::INFO, 'warn')
        test_output(Logger::INFO, 'error')
        test_output(Logger::INFO, 'fatal')
        test_no_output(Logger::WARN, 'info')
        test_no_output(Logger::ERROR, 'info')
        test_no_output(Logger::FATAL, 'info')
      end
      it "takes a block" do
        test_output(Logger::INFO, 'info', true)
        test_output(Logger::INFO, 'warn', true)
        test_output(Logger::INFO, 'error', true)
        test_output(Logger::INFO, 'fatal', true)
        test_no_output(Logger::WARN, 'info', true)
        test_no_output(Logger::ERROR, 'info', true)
        test_no_output(Logger::FATAL, 'info', true)
      end
    end

    describe "warn" do
      it "prints if level is WARN or higher" do
        test_output(Logger::WARN, 'warn')
        test_output(Logger::WARN, 'error')
        test_output(Logger::WARN, 'fatal')
        test_no_output(Logger::ERROR, 'warn')
        test_no_output(Logger::FATAL, 'warn')
      end
      it "takes a block" do
        test_output(Logger::WARN, 'warn', true)
        test_output(Logger::WARN, 'error', true)
        test_output(Logger::WARN, 'fatal', true)
        test_no_output(Logger::ERROR, 'warn', true)
        test_no_output(Logger::FATAL, 'warn', true)
      end
    end

    describe "error" do
      it "prints if level is ERROR or higher" do
        test_output(Logger::ERROR, 'error')
        test_output(Logger::ERROR, 'fatal')
        test_no_output(Logger::FATAL, 'info')
      end
      it "takes a block" do
        test_output(Logger::ERROR, 'error', true)
        test_output(Logger::ERROR, 'fatal', true)
        test_no_output(Logger::FATAL, 'info', true)
      end
    end

    describe "fatal" do
      it "only prints if level is FATAL" do
        test_output(Logger::FATAL, 'fatal')
      end
      it "takes a block" do
        test_output(Logger::FATAL, 'fatal', true)
      end
    end

    describe "log_message with OPENC3_LOG_STDERR" do
      before(:each) do
        Logger.level = Logger::DEBUG
        ENV.delete('OPENC3_LOG_STDERR')
      end

      after(:each) do
        ENV.delete('OPENC3_LOG_STDERR')
        $stdout = STDOUT
        $stderr = STDERR
      end

      # Helper method to setup StringIO streams
      def setup_streams
        stdout = StringIO.new('', 'r+')
        stderr = StringIO.new('', 'r+')
        $stdout = stdout
        $stderr = stderr
        [stdout, stderr]
      end

      context "when OPENC3_LOG_STDERR is not set" do
        it "logs all levels to stdout" do
          stdout, stderr = setup_streams

          Logger.debug("Debug message")
          Logger.info("Info message")
          Logger.warn("Warn message")
          Logger.error("Error message")
          Logger.fatal("Fatal message")

          # All messages should go to stdout
          output_lines = stdout.string.lines
          expect(output_lines.length).to eq(5)
          expect(output_lines[0]).to include('Debug message')
          expect(output_lines[1]).to include('Info message')
          expect(output_lines[2]).to include('Warn message')
          expect(output_lines[3]).to include('Error message')
          expect(output_lines[4]).to include('Fatal message')

          # Nothing should go to stderr
          expect(stderr.string).to be_empty
        end
      end

      # Test truthy values that enable stderr routing
      ['true', '1', 'yes', 'on', 'TRUE', 'YeS'].each do |truthy_value|
        context "when OPENC3_LOG_STDERR is set to '#{truthy_value}'" do
          it "logs warn, error, and fatal to stderr" do
            ENV['OPENC3_LOG_STDERR'] = truthy_value
            stdout, stderr = setup_streams

            Logger.debug("Debug message")
            Logger.info("Info message")
            Logger.warn("Warn message")
            Logger.error("Error message")
            Logger.fatal("Fatal message")

            # Debug and info should go to stdout
            stdout_lines = stdout.string.lines
            expect(stdout_lines.length).to eq(2)
            expect(stdout_lines[0]).to include('Debug message')
            expect(stdout_lines[1]).to include('Info message')

            # Warn, error, and fatal should go to stderr
            stderr_lines = stderr.string.lines
            expect(stderr_lines.length).to eq(3)
            expect(stderr_lines[0]).to include('Warn message')
            expect(stderr_lines[1]).to include('Error message')
            expect(stderr_lines[2]).to include('Fatal message')
          end
        end
      end

      # Test falsy values that keep all logs on stdout
      [['false', 'Warn message', :warn],
       ['0', 'Error message', :error],
       ['', 'Fatal message', :fatal],
       ['arbitrary', 'Warn message', :warn]].each do |env_value, message, level|
        context "when OPENC3_LOG_STDERR is set to '#{env_value}'" do
          it "logs all levels to stdout" do
            ENV['OPENC3_LOG_STDERR'] = env_value
            stdout, stderr = setup_streams

            Logger.send(level, message)

            # Message should go to stdout (not a recognized truthy value)
            expect(stdout.string).to include(message)
            expect(stderr.string).to be_empty
          end
        end
      end

      context "JSON format verification with stderr" do
        it "outputs valid JSON to stderr when enabled" do
          ENV['OPENC3_LOG_STDERR'] = 'true'
          stdout, stderr = setup_streams

          Logger.error("Test error message")

          # Verify JSON is valid and contains expected fields
          json = JSON.parse(stderr.string, allow_nan: true, create_additions: true)
          expect(json['level']).to eq('ERROR')
          expect(json['message']).to eq('Test error message')
          expect(json).to have_key('time')
          expect(json).to have_key('@timestamp')
          expect(json).to have_key('container_name')
        end
      end
    end

    describe "log_message with other parameter" do
      before(:each) do
        Logger.level = Logger::INFO
      end

      after(:each) do
        $stdout = STDOUT
      end

      def setup_stdout
        stdout = StringIO.new('', 'r+')
        $stdout = stdout
        stdout
      end

      context "with nested hash" do
        it "merges nested hash into log data" do
          stdout = setup_stdout
          
          other = {
            request_id: '12345',
            metadata: {
              source: 'test',
              version: '1.0'
            }
          }
          
          Logger.info("Test message", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['message']).to eq('Test message')
          expect(json['request_id']).to eq('12345')
          expect(json['metadata']).to be_a(Hash)
          expect(json['metadata']['source']).to eq('test')
          expect(json['metadata']['version']).to eq('1.0')
        end
      end

      context "with array values" do
        it "includes array values in log data" do
          stdout = setup_stdout
          
          other = {
            tags: ['error', 'critical', 'alert'],
            items: [1, 2, 3]
          }
          
          Logger.warn("Warning message", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['tags']).to eq(['error', 'critical', 'alert'])
          expect(json['items']).to eq([1, 2, 3])
        end
      end

      context "with Time objects" do
        it "converts Time objects to strings" do
          stdout = setup_stdout
          
          time = Time.parse("2025-01-15 12:30:45 UTC")
          other = {
            start_time: time,
            end_time: time + 3600
          }
          
          Logger.info("Time test", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['start_time']).to be_a(String)
          expect(json['end_time']).to be_a(String)
        end
      end

      context "with Symbol values" do
        it "converts symbols to strings" do
          stdout = setup_stdout
          
          other = {
            status: :success,
            operation: :read
          }
          
          Logger.info("Symbol test", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['status']).to eq('success')
          expect(json['operation']).to eq('read')
        end
      end

      context "with special float values" do
        it "handles Infinity, -Infinity, and NaN" do
          stdout = setup_stdout
          
          other = {
            pos_infinity: Float::INFINITY,
            neg_infinity: -Float::INFINITY,
            not_a_number: Float::NAN
          }
          
          Logger.info("Float test", other: other)
          
          # When create_additions: true, the special floats are reconstructed
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['pos_infinity']).to eq(Float::INFINITY)
          expect(json['neg_infinity']).to eq(-Float::INFINITY)
          expect(json['not_a_number'].nan?).to be true
          
          # Verify the raw JSON contains the special representation
          raw_output = stdout.string
          expect(raw_output).to include('"json_class":"Float"')
          expect(raw_output).to include('"raw":"Infinity"')
          expect(raw_output).to include('"raw":"-Infinity"')
          expect(raw_output).to include('"raw":"NaN"')
        end
      end

      context "with Exception object" do
        it "serializes exception details" do
          stdout = setup_stdout
          
          begin
            raise StandardError.new("Test error")
          rescue => e
            other = {
              exception: e
            }
            
            Logger.error("Exception occurred", other: other)
          end
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['exception']).to be_a(Hash)
          expect(json['exception']['class']).to eq('StandardError')
          expect(json['exception']['message']).to eq('Test error')
          expect(json['exception']['backtrace']).to be_a(Array)
        end
      end

      context "with Regexp values" do
        it "converts regexp to string" do
          stdout = setup_stdout
          
          other = {
            pattern: /test.*pattern/i
          }
          
          Logger.info("Regexp test", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['pattern']).to eq('(?i-mx:test.*pattern)')
        end
      end

      context "with mixed complex types" do
        it "handles deeply nested structures with various types" do
          stdout = setup_stdout
          
          other = {
            request: {
              id: 'req-123',
              timestamp: Time.now.utc,
              params: ['param1', 'param2'],
              flags: {
                debug: true,
                verbose: false,
                level: :high
              }
            },
            metrics: {
              duration: 123.45,
              count: 10
            }
          }
          
          Logger.info("Complex test", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['request']).to be_a(Hash)
          expect(json['request']['id']).to eq('req-123')
          expect(json['request']['params']).to eq(['param1', 'param2'])
          expect(json['request']['flags']['level']).to eq('high')
          expect(json['metrics']['duration']).to eq(123.45)
          expect(json['metrics']['count']).to eq(10)
        end
      end

      context "with nil and empty values" do
        it "handles nil values correctly" do
          stdout = setup_stdout
          
          other = {
            value1: nil,
            value2: '',
            value3: []
          }
          
          Logger.info("Nil test", other: other)
          
          json = JSON.parse(stdout.string, allow_nan: true, create_additions: true)
          expect(json['value1']).to be_nil
          expect(json['value2']).to eq('')
          expect(json['value3']).to eq([])
        end
      end
    end
  end
end
