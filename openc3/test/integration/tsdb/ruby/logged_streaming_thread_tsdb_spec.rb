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

# End-to-end TSDB streaming tests for LoggedStreamingThread.
#
# These tests verify that the streaming API can correctly read data from QuestDB
# using the stream_items method. Data is inserted using Python's QuestDBClient
# (as the real system does) and read back using Ruby's LoggedStreamingThread.
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#     2. Run tests: bundle exec rspec ruby/logged_streaming_thread_tsdb_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'

# Add the cmd-tlm-api models path for streaming classes
# Path: openc3/test/integration/tsdb/ruby -> openc3-cosmos-cmd-tlm-api/app/models
CMD_TLM_API_MODELS = File.expand_path('../../../../../openc3-cosmos-cmd-tlm-api/app/models', __dir__)
$LOAD_PATH.unshift(CMD_TLM_API_MODELS) unless $LOAD_PATH.include?(CMD_TLM_API_MODELS)

require 'logged_streaming_thread'

# Mock StreamingObject for testing
class MockStreamingObject
  attr_accessor :key, :target_name, :packet_name, :item_name, :value_type
  attr_accessor :start_time, :end_time, :offset, :item_key, :topic, :stream_mode, :cmd_or_tlm

  def initialize(target:, packet:, item:, value_type: :RAW, start_time: nil, end_time: nil)
    @target_name = target
    @packet_name = packet
    @item_name = item
    @value_type = value_type
    @start_time = start_time
    @end_time = end_time
    @stream_mode = :DECOM
    @cmd_or_tlm = :TLM
    @offset = '0-0'
    @key = "DECOM__TLM__#{target}__#{packet}__#{item}__#{value_type}"
    @item_key = "#{target}__#{packet}__#{item}__#{value_type}"
    @topic = "DEFAULT__DECOM__{#{target}}__#{packet}"
  end
end

# Mock StreamingApi for capturing transmitted results
class MockStreamingApi
  attr_reader :transmitted_results

  def initialize
    @transmitted_results = []
  end

  def transmit_results(results)
    @transmitted_results.concat(results)
  end

  def clear
    @transmitted_results.clear
  end
end

# Mock Collection for stream_items
class MockCollection
  attr_reader :objects

  def initialize(objects)
    @objects = objects
  end

  def length
    @objects.length
  end

  def topics_offsets_and_objects
    topics = []
    offsets = []
    item_objects_by_topic = {}
    packet_objects_by_topic = {}

    @objects.each do |obj|
      topics << obj.topic unless topics.include?(obj.topic)
      offsets << obj.offset

      if obj.item_name
        item_objects_by_topic[obj.topic] ||= []
        item_objects_by_topic[obj.topic] << obj
      else
        packet_objects_by_topic[obj.topic] ||= []
        packet_objects_by_topic[obj.topic] << obj
      end
    end

    [topics, offsets, item_objects_by_topic, packet_objects_by_topic]
  end

  def includes_realtime
    false
  end
end

RSpec.describe LoggedStreamingThread, :questdb do
  let(:streaming_api) { MockStreamingApi.new }
  let(:scope) { 'DEFAULT' }
  let(:token) { nil }

  # Helper to create a LoggedStreamingThread with mocked dependencies
  def create_thread(objects)
    collection = MockCollection.new(objects)
    thread = LoggedStreamingThread.new(streaming_api, collection, 100, scope: scope, token: token)
    thread.class.class_variable_set(:@@conn, nil) if thread.class.class_variable_defined?(:@@conn)
    thread
  end

  # Helper method to run a streaming roundtrip test
  # @param write_options [Hash] Options passed to write_test_data
  # @param value_type [Symbol] :RAW, :CONVERTED, or :FORMATTED
  # @param expected_key [String] Key in test_params for expected values
  # @param comparator [Proc] Optional custom comparison block (receives expected, actual, index)
  def run_streaming_test(write_options, value_type: :RAW, expected_key: 'expected_values', &comparator)
    test_params = write_test_data(**write_options)
    expect(test_params['success']).to be true

    obj = MockStreamingObject.new(
      target: test_params['target_name'],
      packet: test_params['packet_name'],
      item: 'VALUE',
      value_type: value_type,
      start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
      end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
    )

    thread = create_thread([obj])

    allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
    available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__#{value_type}"]
    allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

    objects_by_topic = { obj.topic => [obj] }
    thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

    expected = if expected_key == 'expected_values'
      decode_expected_values(test_params[expected_key])
    else
      test_params[expected_key]
    end

    expect(streaming_api.transmitted_results.length).to eq(expected.length)
    expected.each_with_index do |exp_val, i|
      result = streaming_api.transmitted_results[i]
      expect(result['__type']).to eq('items')
      actual = result[obj.item_key]
      if comparator
        comparator.call(exp_val, actual, i)
      else
        expect(actual).to eq(exp_val), "Value mismatch at index #{i}: expected #{exp_val}, got #{actual}"
      end
    end
  end

  before(:each) do
    if LoggedStreamingThread.class_variable_defined?(:@@conn)
      conn = LoggedStreamingThread.class_variable_get(:@@conn)
      conn&.finish rescue nil
      LoggedStreamingThread.class_variable_set(:@@conn, nil)
    end
    streaming_api.clear
  end

  after(:each) do
    if LoggedStreamingThread.class_variable_defined?(:@@conn)
      conn = LoggedStreamingThread.class_variable_get(:@@conn)
      conn&.finish rescue nil
      LoggedStreamingThread.class_variable_set(:@@conn, nil)
    end
  end

  describe 'INT (signed integer) streaming' do
    it 'streams INT 8-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'INT8', data_type: 'INT', bit_size: 8,
        values: [-128, -64, -1, 0, 1, 64, 127]
      })
    end

    it 'streams INT 16-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'INT16', data_type: 'INT', bit_size: 16,
        values: [-32768, -16384, -1, 0, 1, 16384, 32767]
      })
    end

    it 'streams INT 32-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'INT32', data_type: 'INT', bit_size: 32,
        values: [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647]
      })
    end

    it 'streams INT 64-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'INT64', data_type: 'INT', bit_size: 64,
        values: [-9223372036854775807, -4611686018427387904, -1, 0, 1, 4611686018427387904, 9223372036854775807]
      })
    end
  end

  describe 'UINT (unsigned integer) streaming' do
    it 'streams UINT 8-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'UINT8', data_type: 'UINT', bit_size: 8,
        values: [0, 1, 64, 127, 128, 192, 255]
      })
    end

    it 'streams UINT 16-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'UINT16', data_type: 'UINT', bit_size: 16,
        values: [0, 1, 16384, 32767, 32768, 49152, 65535]
      })
    end

    it 'streams UINT 32-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'UINT32', data_type: 'UINT', bit_size: 32,
        values: [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295]
      })
    end

    it 'streams UINT 64-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'UINT64', data_type: 'UINT', bit_size: 64,
        values: [0, 1, 4611686018427387904, 9223372036854775807]
      })
    end
  end

  describe 'FLOAT streaming' do
    it 'streams FLOAT 32-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'FLOAT32', data_type: 'FLOAT', bit_size: 32,
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

    it 'streams FLOAT 64-bit values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'FLOAT64', data_type: 'FLOAT', bit_size: 64,
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

  describe 'STRING streaming' do
    it 'streams STRING values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'STRING', data_type: 'STRING',
        values: ['', 'hello', 'Hello World!', 'CONNECTED', '0x1234ABCD', "with\nnewline", 'unicode: éèêë']
      })
    end
  end

  describe 'BLOCK (binary) streaming' do
    it 'streams BLOCK binary data correctly' do
      test_binaries = [
        '',
        "\x00",
        "\x00\x01\x02\x03",
        "\xff\xfe\xfd",
        (0..255).to_a.pack('C*'),
        'ASCII text as bytes'
      ]
      base64_values = test_binaries.map { |b| Base64.strict_encode64(b) }

      run_streaming_test({
        target: 'STREAM', packet: 'BLOCK', data_type: 'BLOCK',
        values: base64_values
      }) do |exp_val, actual, i|
        actual = actual.force_encoding('ASCII-8BIT') if actual.is_a?(String)
        exp_val = exp_val.force_encoding('ASCII-8BIT') if exp_val.is_a?(String)
        expect(actual).to eq(exp_val), "Binary mismatch at index #{i}"
      end
    end
  end

  describe 'DERIVED streaming' do
    it 'streams DERIVED integer values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'DERIVED_INT', data_type: 'DERIVED',
        values: [42, -100, 0, 999999]
      })
    end

    it 'streams DERIVED float values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'DERIVED_FLOAT', data_type: 'DERIVED',
        values: [3.14159, -2.71828, 0.0, 1e10]
      })
    end

    it 'streams DERIVED string values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'DERIVED_STR', data_type: 'DERIVED',
        values: ['hello', 'world', 'CONNECTED']
      })
    end
  end

  describe 'Array streaming' do
    it 'streams numeric arrays correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'ARRAY_NUM', data_type: 'FLOAT', array_size: 10,
        values: [
          [1.0, 2.0, 3.0, 4.0, 5.0],
          [-1.5, 0.0, 1.5],
          [1e10, 1e-10, 0.0],
          [100, 200, 300]
        ]
      })
    end

    it 'streams string arrays correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'ARRAY_STR', data_type: 'STRING', array_size: 10,
        values: [
          ['a', 'b', 'c'],
          ['CONNECTED', 'DISCONNECTED', 'UNKNOWN'],
          ['hello', 'world']
        ]
      })
    end

    it 'streams mixed-type arrays correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'ARRAY_MIX', data_type: 'DERIVED', array_size: 10,
        values: [
          [1, 'two', 3.0, true],
          [nil, 'hello', 42],
          [true, false, 'yes', 'no']
        ]
      })
    end
  end

  describe 'Object streaming' do
    it 'streams simple OBJECT values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'OBJ_SIMPLE', data_type: 'DERIVED',
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

    it 'streams complex OBJECT values correctly' do
      run_streaming_test({
        target: 'STREAM', packet: 'OBJ_COMPLEX', data_type: 'DERIVED',
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

  describe 'Value types (CONVERTED, FORMATTED)' do
    it 'streams CONVERTED values correctly' do
      run_streaming_test(
        {
          target: 'STREAM', packet: 'CONVERTED', data_type: 'INT', bit_size: 16,
          values: [100, 200, 300],
          converted_values: [1.0, 2.0, 3.0],
          read_conversion: { 'converted_type' => 'FLOAT', 'converted_bit_size' => 64 }
        },
        value_type: :CONVERTED,
        expected_key: 'expected_converted'
      )
    end

    it 'streams FORMATTED values correctly' do
      run_streaming_test(
        {
          target: 'STREAM', packet: 'FORMATTED', data_type: 'INT', bit_size: 16,
          values: [100, 200, 300],
          formatted_values: ['100 units', '200 units', '300 units'],
          format_string: '%d',
          units: 'units'
        },
        value_type: :FORMATTED,
        expected_key: 'expected_formatted'
      )
    end
  end

  describe 'Calculated timestamp items' do
    # Helper to run timestamp streaming tests
    def run_timestamp_stream_test(item_name, format_type)
      test_params = write_test_data(
        target: 'STREAM', packet: "TS_#{item_name}", data_type: 'INT', bit_size: 32,
        values: [1, 2, 3]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: item_name,
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )
      # Update the item_key to match the timestamp item name
      obj.item_key = "#{obj.target_name}__#{obj.packet_name}__#{item_name}__RAW"

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__#{item_name}__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(streaming_api.transmitted_results.length).to eq(3)

      expected_start = Time.parse(test_params['start_time'])

      streaming_api.transmitted_results.each_with_index do |result, i|
        expect(result['__type']).to eq('items')
        actual = result[obj.item_key]
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
          parsed = Time.parse(actual)
          expect(parsed.to_f).to be_within(0.001).of(expected_time.to_f),
            "Timestamp formatted mismatch at index #{i}: expected #{expected_time}, got #{actual}"
        else
          raise "Unknown format_type: #{format_type}"
        end
      end
    end

    it 'streams PACKET_TIMESECONDS correctly' do
      run_timestamp_stream_test('PACKET_TIMESECONDS', :seconds)
    end

    it 'streams PACKET_TIMEFORMATTED correctly' do
      run_timestamp_stream_test('PACKET_TIMEFORMATTED', :formatted)
    end

    it 'streams RECEIVED_TIMESECONDS correctly' do
      run_timestamp_stream_test('RECEIVED_TIMESECONDS', :seconds)
    end

    it 'streams RECEIVED_TIMEFORMATTED correctly' do
      run_timestamp_stream_test('RECEIVED_TIMEFORMATTED', :formatted)
    end

    it 'streams timestamp items alongside regular items' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'TS_MIXED_STREAM', data_type: 'INT', bit_size: 32,
        values: [100, 200]
      )
      expect(test_params['success']).to be true

      # Create streaming objects for both regular and timestamp items
      obj_ts = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'PACKET_TIMESECONDS',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )
      obj_ts.item_key = "#{obj_ts.target_name}__#{obj_ts.packet_name}__PACKET_TIMESECONDS__RAW"

      obj_val = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj_ts, obj_val])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = [
        "#{obj_ts.target_name}__#{obj_ts.packet_name}__PACKET_TIMESECONDS__RAW",
        "#{obj_val.target_name}__#{obj_val.packet_name}__VALUE__RAW"
      ]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj_ts.topic => [obj_ts, obj_val] }
      thread.send(:stream_items, objects_by_topic, [obj_ts.topic], [obj_ts.offset])

      expect(streaming_api.transmitted_results.length).to eq(2)

      # First row
      result = streaming_api.transmitted_results[0]
      expect(result[obj_ts.item_key]).to be_a(Float)
      expect(result[obj_val.item_key]).to eq(100)

      # Second row
      result = streaming_api.transmitted_results[1]
      expect(result[obj_ts.item_key]).to be_a(Float)
      expect(result[obj_val.item_key]).to eq(200)
    end
  end

  describe 'Streaming behavior' do
    it 'includes timestamp in results' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'TIME_PKT', data_type: 'INT', bit_size: 32,
        values: [42]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(streaming_api.transmitted_results.length).to eq(1)
      result = streaming_api.transmitted_results[0]
      expect(result['__time']).to be_a(Integer)
      expect(result['__time']).to be > Time.now.to_i * 1_000_000_000 - 60_000_000_000
    end

    it 'returns true when end_time is specified (indicating completion)' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'DONE_PKT', data_type: 'INT', bit_size: 32,
        values: [1, 2]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      done = thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(done).to be true
    end

    it 'returns false when end_time is nil (indicating more data may come)' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'CONT_PKT', data_type: 'INT', bit_size: 32,
        values: [1, 2]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: nil
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      done = thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(done).to be false
    end
  end
end
