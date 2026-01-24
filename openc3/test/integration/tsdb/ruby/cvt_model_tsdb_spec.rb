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

  describe 'INT (signed integer) round-trip' do
    it 'round-trips INT 8-bit values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'INT8',
        data_type: 'INT',
        bit_size: 8,
        values: [-128, -64, -1, 0, 1, 64, 127]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val), "Value mismatch at index #{i}: expected #{exp_val}, got #{result[i][0][0]}"
      end
    end

    it 'round-trips INT 16-bit values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'INT16',
        data_type: 'INT',
        bit_size: 16,
        values: [-32768, -16384, -1, 0, 1, 16384, 32767]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips INT 32-bit values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'INT32',
        data_type: 'INT',
        bit_size: 32,
        # Avoid QuestDB NULL sentinel (Integer.MIN_VALUE)
        values: [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips INT 64-bit values correctly using DECIMAL column' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'INT64',
        data_type: 'INT',
        bit_size: 64,
        # Avoid QuestDB NULL sentinel (Long.MIN_VALUE)
        values: [-9223372036854775807, -4611686018427387904, -1, 0, 1, 4611686018427387904, 9223372036854775807]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end
  end

  describe 'UINT (unsigned integer) round-trip' do
    it 'round-trips UINT 8-bit values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'UINT8',
        data_type: 'UINT',
        bit_size: 8,
        values: [0, 1, 64, 127, 128, 192, 255]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips UINT 16-bit values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'UINT16',
        data_type: 'UINT',
        bit_size: 16,
        values: [0, 1, 16384, 32767, 32768, 49152, 65535]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips UINT 32-bit values correctly using long column' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'UINT32',
        data_type: 'UINT',
        bit_size: 32,
        values: [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips UINT 64-bit values that fit in signed long correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'UINT64',
        data_type: 'UINT',
        bit_size: 64,
        # Values that fit in signed long (0 to 2^63-1)
        values: [0, 1, 4611686018427387904, 9223372036854775807]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end
  end

  describe 'FLOAT round-trip' do
    it 'round-trips FLOAT 32-bit (single precision) values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'FLOAT32',
        data_type: 'FLOAT',
        bit_size: 32,
        values: [-3.4028235e38, -1.0, 0.0, 1.0, 3.4028235e38]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        actual = result[i][0][0]
        if exp_val == 0.0
          expect(actual).to eq(0.0)
        else
          expect((exp_val - actual).abs).to be < (exp_val.abs * 1e-6)
        end
      end
    end

    it 'round-trips FLOAT 64-bit (double precision) values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'FLOAT64',
        data_type: 'FLOAT',
        bit_size: 64,
        values: [-1.7976931348623157e308, -1.0, 0.0, 1.0, 1.7976931348623157e308]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        actual = result[i][0][0]
        if exp_val == 0.0
          expect(actual).to eq(0.0)
        else
          expect((exp_val - actual).abs).to be < (exp_val.abs * 1e-14)
        end
      end
    end
  end

  describe 'STRING round-trip' do
    it 'round-trips STRING values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'STRING',
        data_type: 'STRING',
        values: ['', 'hello', 'Hello World!', 'CONNECTED', '0x1234ABCD', "with\nnewline", 'unicode: éèêë']
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
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

      # Base64 encode for transport to Python
      base64_values = test_binaries.map { |b| Base64.strict_encode64(b) }

      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'BLOCK',
        data_type: 'BLOCK',
        values: base64_values
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        # Force encoding comparison for binary data
        actual = result[i][0][0]
        actual = actual.force_encoding('ASCII-8BIT') if actual.is_a?(String)
        exp_val = exp_val.force_encoding('ASCII-8BIT') if exp_val.is_a?(String)
        expect(actual).to eq(exp_val), "Binary mismatch at index #{i}"
      end
    end
  end

  describe 'DERIVED round-trip' do
    it 'round-trips DERIVED integer values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'DERIVED_INT',
        data_type: 'DERIVED',
        values: [42, -100, 0, 999999]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips DERIVED float values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'DERIVED_FLOAT',
        data_type: 'DERIVED',
        values: [3.14159, -2.71828, 0.0, 1e10]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips DERIVED string values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'DERIVED_STR',
        data_type: 'DERIVED',
        values: ['hello', 'world', 'CONNECTED']
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end
  end

  describe 'Array round-trip' do
    it 'round-trips numeric arrays (JSON-encoded) correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'ARRAY_NUM',
        data_type: 'FLOAT',
        array_size: 10,
        values: [
          [1.0, 2.0, 3.0, 4.0, 5.0],
          [-1.5, 0.0, 1.5],
          [1e10, 1e-10, 0.0],
          [100, 200, 300]
        ]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips string arrays (JSON-encoded) correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'ARRAY_STR',
        data_type: 'STRING',
        array_size: 10,
        values: [
          ['a', 'b', 'c'],
          ['CONNECTED', 'DISCONNECTED', 'UNKNOWN'],
          ['hello', 'world']
        ]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'round-trips mixed-type arrays (JSON-encoded) correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'ARRAY_MIX',
        data_type: 'DERIVED',
        array_size: 10,
        values: [
          [1, 'two', 3.0, true],
          [nil, 'hello', 42],
          [true, false, 'yes', 'no']
        ]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end
  end

  describe 'Object round-trip' do
    it 'round-trips simple OBJECT values (JSON-encoded) correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'OBJ_SIMPLE',
        data_type: 'DERIVED',
        values: [
          {},
          { 'key' => 'value' },
          { 'name' => 'test', 'count' => 42 },
          { 'nested' => { 'inner' => 'value' } }
        ]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        actual = result[i][0][0]
        # Parse if string (JSON-encoded)
        actual = JSON.parse(actual) if actual.is_a?(String)
        expect(actual).to eq(exp_val)
      end
    end

    it 'round-trips complex OBJECT values with mixed types correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'OBJ_COMPLEX',
        data_type: 'DERIVED',
        values: [
          { 'int' => 42, 'float' => 3.14, 'string' => 'hello', 'bool' => true, 'null' => nil },
          { 'array' => [1, 2, 3], 'nested' => { 'a' => 1, 'b' => 2 } },
          { 'mixed_array' => [1, 'two', 3.0, true] }
        ]
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'RAW', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = decode_expected_values(test_params['expected_values'])
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        actual = result[i][0][0]
        # Parse if string (JSON-encoded)
        actual = JSON.parse(actual) if actual.is_a?(String)
        expect(actual).to eq(exp_val)
      end
    end
  end

  describe 'Value types (RAW, CONVERTED, FORMATTED)' do
    it 'reads CONVERTED values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'CONVERTED',
        data_type: 'INT',
        bit_size: 16,
        values: [100, 200, 300],
        converted_values: [1.0, 2.0, 3.0],
        read_conversion: { 'converted_type' => 'FLOAT', 'converted_bit_size' => 64 }
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'CONVERTED', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = test_params['expected_converted']
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end

    it 'reads FORMATTED values correctly' do
      test_params = write_test_data(
        target: 'RUBY_RT',
        packet: 'FORMATTED',
        data_type: 'INT',
        bit_size: 16,
        values: [100, 200, 300],
        formatted_values: ['100 units', '200 units', '300 units'],
        format_string: '%d',
        units: 'units'
      )

      expect(test_params['success']).to be true

      items = [[test_params['target_name'], test_params['packet_name'], 'VALUE', 'FORMATTED', false]]

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      result = OpenC3::CvtModel.tsdb_lookup(
        items,
        start_time: test_params['start_time'],
        end_time: test_params['end_time']
      )

      expected = test_params['expected_formatted']
      expect(result.length).to eq(expected.length)
      expected.each_with_index do |exp_val, i|
        expect(result[i][0][0]).to eq(exp_val)
      end
    end
  end
end
