# Copyright 2026 OpenC3, Inc.
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

# End-to-end TSDB roundtrip tests for Ruby CvtModel.
#
# These tests verify that all COSMOS data types can be:
# 1. Written to QuestDB using Python's QuestDBClient (as the real system does)
# 2. Read back using Ruby's CvtModel.tsdb_lookup (as the real system does)
# 3. Round-trip with correct type conversion and value fidelity
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#     2. Run tests: bundle exec rspec ruby/cvt_model_tsdb_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'

RSpec.describe OpenC3::CvtModel, :questdb do
  # Reset connection before each test to ensure clean state
  before(:each) do
    OpenC3::CvtModel.class_variable_set(:@@conn, nil)
  end

  after(:each) do
    # Clean up connection
    conn = OpenC3::CvtModel.class_variable_get(:@@conn)
    if conn && !conn.finished?
      conn.finish rescue nil
    end
    OpenC3::CvtModel.class_variable_set(:@@conn, nil)
  end

  # Helper method to run a roundtrip test
  # @param write_options [Hash] Options passed to write_test_data
  # @param value_type [String] 'RAW', 'CONVERTED', or 'FORMATTED'
  # @param expected_key [String] Key in test_params for expected values
  # @param comparator [Proc] Optional custom comparison block (receives expected, actual, index)
  def run_roundtrip_test(write_options, value_type: 'RAW', expected_key: 'expected_values', &comparator)
    test_params = write_test_data(**write_options)
    expect(test_params['success']).to be true

    items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', value_type, false]]
    allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

    result = OpenC3::CvtModel.tsdb_lookup(
      items,
      start_time: test_params['start_time'],
      end_time: test_params['end_time']
    )

    expected = if expected_key == 'expected_values'
      decode_expected_values(test_params[expected_key])
    else
      test_params[expected_key]
    end

    expect(result.length).to eq(expected.length)
    expected.each_with_index do |exp_val, i|
      actual = result[i][0][0]
      if comparator
        comparator.call(exp_val, actual, i)
      else
        expect(actual).to eq(exp_val), "Value mismatch at index #{i}: expected #{exp_val}, got #{actual}"
      end
    end
  end

  describe 'INT (signed integer) round-trip' do
    it 'round-trips INT 8-bit values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'INT8', data_type: 'INT', bit_size: 8,
        values: [-128, -64, -1, 0, 1, 64, 127]
      })
    end

    it 'round-trips INT 16-bit values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'INT16', data_type: 'INT', bit_size: 16,
        values: [-32768, -16384, -1, 0, 1, 16384, 32767]
      })
    end

    it 'round-trips INT 32-bit values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'INT32', data_type: 'INT', bit_size: 32,
        # Avoid QuestDB NULL sentinel (Integer.MIN_VALUE)
        values: [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647]
      })
    end

    it 'round-trips INT 64-bit values correctly using DECIMAL column' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'INT64', data_type: 'INT', bit_size: 64,
        # Avoid QuestDB NULL sentinel (Long.MIN_VALUE)
        values: [-9223372036854775807, -4611686018427387904, -1, 0, 1, 4611686018427387904, 9223372036854775807]
      })
    end
  end

  describe 'UINT (unsigned integer) round-trip' do
    it 'round-trips UINT 8-bit values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'UINT8', data_type: 'UINT', bit_size: 8,
        values: [0, 1, 64, 127, 128, 192, 255]
      })
    end

    it 'round-trips UINT 16-bit values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'UINT16', data_type: 'UINT', bit_size: 16,
        values: [0, 1, 16384, 32767, 32768, 49152, 65535]
      })
    end

    it 'round-trips UINT 32-bit values correctly using long column' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'UINT32', data_type: 'UINT', bit_size: 32,
        values: [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295]
      })
    end

    it 'round-trips UINT 64-bit values that fit in signed long correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'UINT64', data_type: 'UINT', bit_size: 64,
        # Values that fit in signed long (0 to 2^63-1)
        values: [0, 1, 4611686018427387904, 9223372036854775807]
      })
    end
  end

  describe 'FLOAT round-trip' do
    it 'round-trips FLOAT 32-bit (single precision) values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'FLOAT32', data_type: 'FLOAT', bit_size: 32,
        values: [-3.4028235e38, -1.0, 0.0, 1.0, 3.4028235e38]
      }) do |exp_val, actual, i|
        if exp_val == 0.0
          expect(actual).to eq(0.0)
        else
          expect((exp_val - actual).abs).to be < (exp_val.abs * 1e-6),
            "Float mismatch at index #{i}: expected #{exp_val}, got #{actual}"
        end
      end
    end

    it 'round-trips FLOAT 64-bit (double precision) values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'FLOAT64', data_type: 'FLOAT', bit_size: 64,
        values: [-1.7976931348623157e308, -1.0, 0.0, 1.0, 1.7976931348623157e308]
      }) do |exp_val, actual, i|
        if exp_val == 0.0
          expect(actual).to eq(0.0)
        else
          expect((exp_val - actual).abs).to be < (exp_val.abs * 1e-14),
            "Float mismatch at index #{i}: expected #{exp_val}, got #{actual}"
        end
      end
    end
  end

  describe 'STRING round-trip' do
    it 'round-trips STRING values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'STRING', data_type: 'STRING',
        values: ['', 'hello', 'Hello World!', 'CONNECTED', '0x1234ABCD', "with\nnewline", 'unicode: éèêë']
      })
    end
  end

  describe 'BLOCK (binary) round-trip' do
    it 'round-trips BLOCK binary data stored as base64 correctly' do
      # Binary data must be base64-encoded for JSON transport to Python
      test_binaries = [
        '',                           # empty
        "\x00",                       # single null byte
        "\x00\x01\x02\x03",           # small sequence
        "\xff\xfe\xfd",               # high bytes
        (0..255).to_a.pack('C*'),     # all byte values
        'ASCII text as bytes'         # text as bytes
      ]
      base64_values = test_binaries.map { |b| Base64.strict_encode64(b) }

      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'BLOCK', data_type: 'BLOCK',
        values: base64_values
      }) do |exp_val, actual, i|
        actual = actual.force_encoding('ASCII-8BIT') if actual.is_a?(String)
        exp_val = exp_val.force_encoding('ASCII-8BIT') if exp_val.is_a?(String)
        expect(actual).to eq(exp_val), "Binary mismatch at index #{i}"
      end
    end
  end

  describe 'DERIVED round-trip' do
    it 'round-trips DERIVED integer values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'DERIVED_INT', data_type: 'DERIVED',
        values: [42, -100, 0, 999999]
      })
    end

    it 'round-trips DERIVED float values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'DERIVED_FLOAT', data_type: 'DERIVED',
        values: [3.14159, -2.71828, 0.0, 1e10]
      })
    end

    it 'round-trips DERIVED string values correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'DERIVED_STR', data_type: 'DERIVED',
        values: ['hello', 'world', 'CONNECTED']
      })
    end
  end

  describe 'Array round-trip' do
    it 'round-trips numeric arrays (JSON-encoded) correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'ARRAY_NUM', data_type: 'FLOAT', array_size: 10,
        values: [
          [1.0, 2.0, 3.0, 4.0, 5.0],
          [-1.5, 0.0, 1.5],
          [1e10, 1e-10, 0.0],
          [100, 200, 300]
        ]
      })
    end

    it 'round-trips string arrays (JSON-encoded) correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'ARRAY_STR', data_type: 'STRING', array_size: 10,
        values: [
          ['a', 'b', 'c'],
          ['CONNECTED', 'DISCONNECTED', 'UNKNOWN'],
          ['hello', 'world']
        ]
      })
    end

    it 'round-trips mixed-type arrays (JSON-encoded) correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'ARRAY_MIX', data_type: 'DERIVED', array_size: 10,
        values: [
          [1, 'two', 3.0, true],
          [nil, 'hello', 42],
          [true, false, 'yes', 'no']
        ]
      })
    end
  end

  describe 'Object round-trip' do
    it 'round-trips simple OBJECT values (JSON-encoded) correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'OBJ_SIMPLE', data_type: 'DERIVED',
        values: [
          {},
          { 'key' => 'value' },
          { 'name' => 'test', 'count' => 42 },
          { 'nested' => { 'inner' => 'value' } }
        ]
      }) do |exp_val, actual, i|
        actual = JSON.parse(actual) if actual.is_a?(String)
        expect(actual).to eq(exp_val), "Object mismatch at index #{i}"
      end
    end

    it 'round-trips complex OBJECT values with mixed types correctly' do
      run_roundtrip_test({
        target: 'RUBY_RT', packet: 'OBJ_COMPLEX', data_type: 'DERIVED',
        values: [
          { 'int' => 42, 'float' => 3.14, 'string' => 'hello', 'bool' => true, 'null' => nil },
          { 'array' => [1, 2, 3], 'nested' => { 'a' => 1, 'b' => 2 } },
          { 'mixed_array' => [1, 'two', 3.0, true] }
        ]
      }) do |exp_val, actual, i|
        actual = JSON.parse(actual) if actual.is_a?(String)
        expect(actual).to eq(exp_val), "Object mismatch at index #{i}"
      end
    end
  end

  describe 'Value types (RAW, CONVERTED, FORMATTED)' do
    it 'reads CONVERTED values correctly' do
      run_roundtrip_test(
        {
          target: 'RUBY_RT', packet: 'CONVERTED', data_type: 'INT', bit_size: 16,
          values: [100, 200, 300],
          converted_values: [1.0, 2.0, 3.0],
          read_conversion: { 'converted_type' => 'FLOAT', 'converted_bit_size' => 64 }
        },
        value_type: 'CONVERTED',
        expected_key: 'expected_converted'
      )
    end

    it 'reads FORMATTED values correctly' do
      run_roundtrip_test(
        {
          target: 'RUBY_RT', packet: 'FORMATTED', data_type: 'INT', bit_size: 16,
          values: [100, 200, 300],
          formatted_values: ['100 units', '200 units', '300 units'],
          format_string: '%d',
          units: 'units'
        },
        value_type: 'FORMATTED',
        expected_key: 'expected_formatted'
      )
    end
  end

  describe 'Calculated timestamp items' do
    # Helper to run timestamp item tests
    def run_timestamp_test(item_name, format_type)
      # Write some test data to create a table with timestamps
      test_params = write_test_data(
        target: 'RUBY_RT', packet: "TS_#{item_name}", data_type: 'INT', bit_size: 32,
        values: [1, 2, 3]
      )
      expect(test_params['success']).to be true

      # Request the calculated timestamp item
      items = [[test_params['target_name'], test_params['packet_name'], item_name, 'RAW', false]]
      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expect(result.length).to eq(3), "Expected 3 results, got #{result.length}"

      # Parse the expected start time
      expected_start = Time.parse(test_params['start_time'])

      result.each_with_index do |row, i|
        actual = row[0][0]
        # Each row is 1 second apart (based on how write_test_data works)
        expected_time = expected_start + i

        case format_type
        when :seconds
          expect(actual).to be_a(Float), "Expected Float at index #{i}, got #{actual.class}"
          expect(actual).to be_within(0.001).of(expected_time.to_f),
            "Timestamp seconds mismatch at index #{i}: expected #{expected_time.to_f}, got #{actual}"
        when :formatted
          expect(actual).to be_a(String), "Expected String at index #{i}, got #{actual.class}"
          # Verify it's ISO 8601 format with Z timezone suffix
          expect(actual).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/),
            "Expected ISO 8601 format at index #{i}, got #{actual}"
          # Verify the formatted string can be parsed back to approximately the same time
          parsed = Time.parse(actual)
          expect(parsed.to_f).to be_within(0.001).of(expected_time.to_f),
            "Timestamp formatted mismatch at index #{i}: expected #{expected_time}, got #{actual}"
        else
          raise "Unknown format_type: #{format_type}"
        end
      end
    end

    it 'calculates PACKET_TIMESECONDS correctly' do
      run_timestamp_test('PACKET_TIMESECONDS', :seconds)
    end

    it 'calculates PACKET_TIMEFORMATTED correctly' do
      run_timestamp_test('PACKET_TIMEFORMATTED', :formatted)
    end

    it 'calculates RECEIVED_TIMESECONDS correctly' do
      run_timestamp_test('RECEIVED_TIMESECONDS', :seconds)
    end

    it 'calculates RECEIVED_TIMEFORMATTED correctly' do
      run_timestamp_test('RECEIVED_TIMEFORMATTED', :formatted)
    end

    it 'returns timestamp items alongside regular items' do
      # Write test data
      test_params = write_test_data(
        target: 'RUBY_RT', packet: 'TS_MIXED', data_type: 'INT', bit_size: 32,
        values: [100, 200]
      )
      expect(test_params['success']).to be true

      # Request both regular item and timestamp items
      items = [
        [test_params['target_name'], test_params['packet_name'], 'PACKET_TIMESECONDS', 'RAW', false],
        [test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false],
        [test_params['target_name'], test_params['packet_name'], 'PACKET_TIMEFORMATTED', 'RAW', false]
      ]
      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expect(result.length).to eq(2)

      # First row
      expect(result[0][0][0]).to be_a(Float)  # PACKET_TIMESECONDS
      expect(result[0][1][0]).to eq(100)       # VALUE
      expect(result[0][2][0]).to be_a(String)  # PACKET_TIMEFORMATTED

      # Second row
      expect(result[1][0][0]).to be_a(Float)  # PACKET_TIMESECONDS
      expect(result[1][1][0]).to eq(200)       # VALUE
      expect(result[1][2][0]).to be_a(String)  # PACKET_TIMEFORMATTED
    end
  end
end
