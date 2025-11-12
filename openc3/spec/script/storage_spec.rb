# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/script'
require 'openc3/script/storage'
require 'openc3/api/api'
require 'tempfile'

module OpenC3
  describe Script do
    class StorageSpecApi
      include Api

      def initialize
        @storage_file_responses = {}
      end

      def shutdown
        # Stubbed method
      end

      def disconnect
        # Stubbed method
      end

      def generate_url
        return "http://localhost:2900"
      end

      def method_missing(name, *params, **kw_params)
        self.send(name, *params, **kw_params)
      end

      def set_storage_file_response(path, scope, file_or_error)
        key = "#{scope}/#{path}"
        @storage_file_responses[key] = file_or_error
      end

      # Mock the _get_storage_file method behavior
      def get_storage_file_mock(path, scope)
        key = "#{scope}/#{path}"
        response = @storage_file_responses[key]
        if response.is_a?(Exception)
          raise response
        elsif response
          return response
        else
          raise StandardError.new("File not found: #{path}")
        end
      end
    end

    let(:test_scope) { 'DEFAULT' }
    let(:test_path) { 'INST/procedures/test.rb' }
    let(:file_content) { "# Test file content\nputs 'Hello World'\n" }

    before(:each) do
      mock_redis()
      setup_system()

      # Setup global variables
      $openc3_scope = test_scope
      $openc3_in_cluster = true

      # Setup environment
      ENV['OPENC3_CLOUD'] = 'local'
      ENV['OPENC3_LOCAL_MODE'] = nil

      @api = StorageSpecApi.new
      # Mock the server proxy to directly call the api
      allow(ServerProxy).to receive(:new).and_return(@api)

      initialize_script()
    end

    after(:each) do
      # Cleanup
      ENV['OPENC3_LOCAL_MODE'] = nil
      shutdown_script()
    end

    describe "#get_target_file" do
      context "when getting a modified file (default behavior)" do
        it "returns a file from targets_modified" do
          # Mock _get_storage_file to return a file
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind
          path_for_filename = test_path
          mock_file.define_singleton_method(:filename) { "targets_modified/#{path_for_filename}" }

          # Mock the internal method call
          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, scope: test_scope)

          expect(result).to be_a(Tempfile)
          expect(result.read).to eq(file_content)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "falls back to targets if targets_modified fails" do
          # First call to targets_modified fails
          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_raise(StandardError.new("File not found"))

          # Second call to targets succeeds
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind
          path_for_filename = test_path
          mock_file.define_singleton_method(:filename) { "targets/#{path_for_filename}" }

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, scope: test_scope)

          expect(result).to be_a(Tempfile)
          expect(result.read).to eq(file_content)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end
      end

      context "when getting an original file" do
        it "returns a file from targets when original: true" do
          # Mock _get_storage_file to return a file from targets
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind
          path_for_filename = test_path
          mock_file.define_singleton_method(:filename) { "targets/#{path_for_filename}" }

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, original: true, scope: test_scope)

          expect(result).to be_a(Tempfile)
          expect(result.read).to eq(file_content)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "returns nil when original: true and file not found" do
          # Mock _get_storage_file to fail for targets
          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_raise(StandardError.new("File not found"))

          # Should not attempt to call targets_modified
          expect(self).not_to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            any_args
          )

          result = get_target_file(test_path, original: true, scope: test_scope)
          expect(result).to be_nil
        end
      end

      context "when in local mode" do
        before(:each) do
          ENV['OPENC3_LOCAL_MODE'] = 'true'
        end

        it "reads from local file system first when accessing targets_modified" do
          local_content = "# Local modified content\n"
          local_file = StringIO.new(local_content)

          # Mock LocalMode.open_local_file to return a local file
          expect(OpenC3::LocalMode).to receive(:open_local_file).with(
            test_path,
            scope: test_scope
          ).and_return(local_file)

          # Should not call _get_storage_file since local file was found
          expect(self).not_to receive(:_get_storage_file)

          # Capture and check stdout
          capture_io do |stdout|
            result = get_target_file(test_path, scope: test_scope)

            expect(result).to be_a(Tempfile)
            expect(result.read).to eq(local_content)
            expect(result.filename).to eq(test_path)
            result.close
            result.unlink

            expect(stdout.string).to include("Reading local #{test_scope}/targets_modified/#{test_path}")
          end
        end

        it "falls back to remote storage when local file not found" do
          # Mock LocalMode.open_local_file to return nil (file not found locally)
          expect(OpenC3::LocalMode).to receive(:open_local_file).with(
            test_path,
            scope: test_scope
          ).and_return(nil)

          # Mock remote storage retrieval
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind
          path_for_filename = test_path
          mock_file.define_singleton_method(:filename) { "targets_modified/#{path_for_filename}" }

          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, scope: test_scope)

          expect(result).to be_a(Tempfile)
          expect(result.read).to eq(file_content)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "does not check local mode when original: true" do
          # When original: true, should not check local mode
          expect(OpenC3::LocalMode).not_to receive(:open_local_file)

          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, original: true, scope: test_scope)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "falls back from local to remote to original targets on error" do
          # Local file not found
          expect(OpenC3::LocalMode).to receive(:open_local_file).and_return(nil)

          # Remote targets_modified fails
          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_raise(StandardError.new("Remote modified not found"))

          # Falls back to targets (original)
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, scope: test_scope)

          expect(result).to be_a(Tempfile)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end
      end

      context "with custom scope" do
        let(:custom_scope) { 'CUSTOM_SCOPE' }

        it "uses the provided scope parameter" do
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind

          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: custom_scope
          ).and_return(mock_file)

          result = get_target_file(test_path, scope: custom_scope)

          expect(result).to be_a(Tempfile)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "uses custom scope with local mode" do
          ENV['OPENC3_LOCAL_MODE'] = 'true'
          local_file = StringIO.new("local content")

          expect(OpenC3::LocalMode).to receive(:open_local_file).with(
            test_path,
            scope: custom_scope
          ).and_return(local_file)

          capture_io do |stdout|
            result = get_target_file(test_path, scope: custom_scope)
            result.close
            result.unlink

            expect(stdout.string).to include("Reading local #{custom_scope}/targets_modified/#{test_path}")
          end
        end
      end

      context "file properties" do
        it "returns a Tempfile with the correct filename set for modified files" do
          path_for_filename = test_path
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind
          mock_file.define_singleton_method(:filename) { "targets_modified/#{path_for_filename}" }

          allow(self).to receive(:_get_storage_file).and_return(mock_file)

          result = get_target_file(test_path, scope: test_scope)

          expect(result.filename).to eq("targets_modified/#{test_path}")
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "returns a Tempfile with the correct filename for local files" do
          ENV['OPENC3_LOCAL_MODE'] = 'true'
          local_file = StringIO.new("local content")

          allow(OpenC3::LocalMode).to receive(:open_local_file).and_return(local_file)

          capture_io do |stdout|
            result = get_target_file(test_path, scope: test_scope)

            expect(result.filename).to eq(test_path)
            result.close
            result.unlink
          end
        end

        it "returns a rewound Tempfile for local files" do
          ENV['OPENC3_LOCAL_MODE'] = 'true'
          local_file = StringIO.new("local content")

          allow(OpenC3::LocalMode).to receive(:open_local_file).and_return(local_file)

          capture_io do |stdout|
            result = get_target_file(test_path, scope: test_scope)

            # The file should be at position 0 (rewound)
            expect(result.pos).to eq(0)
            # Should be able to read the full content
            expect(result.read).to eq("local content")
            result.close
            result.unlink
          end
        end
      end

      context "with different path formats" do
        it "handles paths with subdirectories" do
          nested_path = "INST/procedures/subfolder/nested/test.rb"
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(file_content)
          mock_file.rewind

          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{nested_path}",
            scope: test_scope
          ).and_return(mock_file)

          result = get_target_file(nested_path, scope: test_scope)

          expect(result).to be_a(Tempfile)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end

        it "handles paths with different file extensions" do
          json_path = "INST/data/config.json"
          json_content = '{"key": "value"}'
          mock_file = Tempfile.new('test', binmode: true)
          mock_file.write(json_content)
          mock_file.rewind

          allow(self).to receive(:_get_storage_file).and_return(mock_file)

          result = get_target_file(json_path, scope: test_scope)

          expect(result.read).to eq(json_content)
          result.close
          result.unlink
          mock_file.close
          mock_file.unlink
        end
      end

      context "error handling" do
        it "returns nil when both targets_modified and targets fail" do
          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_raise(StandardError.new("Modified not found"))

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_raise(StandardError.new("Original not found"))

          result = get_target_file(test_path, scope: test_scope)
          expect(result).to be_nil
        end

        it "returns nil when file not found with custom error types" do
          expect(self).to receive(:_get_storage_file).with(
            "targets_modified/#{test_path}",
            scope: test_scope
          ).and_raise(RuntimeError.new("Custom error"))

          expect(self).to receive(:_get_storage_file).with(
            "targets/#{test_path}",
            scope: test_scope
          ).and_raise(RuntimeError.new("Custom error 2"))

          result = get_target_file(test_path, scope: test_scope)
          expect(result).to be_nil
        end
      end
    end
  end
end
