# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'open3'
require 'base64'

# Set environment variables for QuestDB connection (test defaults)
ENV['OPENC3_TSDB_HOSTNAME'] ||= '127.0.0.1'
ENV['OPENC3_TSDB_INGEST_PORT'] ||= '9000'
ENV['OPENC3_TSDB_QUERY_PORT'] ||= '8812'
ENV['OPENC3_TSDB_USERNAME'] ||= 'admin'
ENV['OPENC3_TSDB_PASSWORD'] ||= 'admin'
ENV['OPENC3_SCOPE'] ||= 'DEFAULT'

# Set global scope variable used by OpenC3 models
$openc3_scope = ENV['OPENC3_SCOPE']

# Add openc3 lib path
# Path: openc3/test/integration/tsdb/ruby -> openc3/lib
$LOAD_PATH.unshift(File.expand_path('../../../../lib', __dir__))

require 'openc3'
require 'openc3/models/cvt_model'
require 'openc3/utilities/questdb_client'

# Path to the Python helper script and openc3/python for poetry
QUESTDB_WRITER_PATH = File.expand_path('../helpers/questdb_writer.py', __dir__)
OPENC3_PYTHON_ROOT = File.expand_path('../../../../python', __dir__)

# Helper module for QuestDB cross-language tests
module QuestDBTestHelpers
  # Check if QuestDB is available
  def questdb_available?
    result = run_python_helper('check')
    result['available'] == true
  rescue StandardError
    false
  end

  # Run the Python helper script with given arguments
  # Uses 'poetry run' to ensure the correct Python environment with dependencies
  def run_python_helper(command, **options)
    args = [command]
    options.each do |key, value|
      next if value.nil?
      args << "--#{key}"
      args << (value.is_a?(String) ? value : JSON.generate(value))
    end

    cmd = ['poetry', 'run', 'python', QUESTDB_WRITER_PATH] + args
    stdout, stderr, status = Open3.capture3(*cmd, chdir: OPENC3_PYTHON_ROOT)

    unless status.success?
      raise "Python helper failed: #{stderr}\nCommand: #{cmd.join(' ')}"
    end

    JSON.parse(stdout)
  end

  # Write test data using Python and return the test parameters
  def write_test_data(target:, packet:, data_type:, values:, **options)
    run_python_helper(
      'write',
      target: target,
      packet: packet,
      data_type: data_type,
      values: values,
      **options
    )
  end

  # Clean up a test table
  def cleanup_table(table_name)
    run_python_helper('cleanup', table: table_name)
  rescue StandardError
    # Ignore cleanup errors
  end

  # Decode expected values from the Python helper output
  # Handles base64-encoded binary data
  def decode_expected_values(values)
    values.map do |v|
      if v.is_a?(Hash) && v['__base64__']
        Base64.strict_decode64(v['__base64__'])
      else
        v
      end
    end
  end
end

RSpec.configure do |config|
  config.include QuestDBTestHelpers

  # Skip all tests if QuestDB is not available
  config.before(:suite) do
    unless QuestDBTestHelpers.instance_method(:questdb_available?).bind(Object.new).call
      puts "\n\nSkipping QuestDB tests - QuestDB not available."
      puts "Start QuestDB with: docker compose -f docker-compose.test.yml up -d\n\n"
    end
  end

  config.around(:each, :questdb) do |example|
    if questdb_available?
      example.run
    else
      skip "QuestDB not available"
    end
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed
end
