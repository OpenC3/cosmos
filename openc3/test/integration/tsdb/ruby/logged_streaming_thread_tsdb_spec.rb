# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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

  def initialize(target:, packet:, item: nil, value_type: :RAW, start_time: nil, end_time: nil, cmd_or_tlm: :TLM)
    @target_name = target
    @packet_name = packet
    @item_name = item
    @value_type = value_type
    @start_time = start_time
    @end_time = end_time
    @stream_mode = :DECOM
    @cmd_or_tlm = cmd_or_tlm
    @offset = '0-0'
    ct = cmd_or_tlm.to_s
    topic_type = (cmd_or_tlm == :CMD) ? 'DECOMCMD' : 'DECOM'
    if item
      @key = "DECOM__#{ct}__#{target}__#{packet}__#{item}__#{value_type}"
      @item_key = "#{target}__#{packet}__#{item}__#{value_type}"
    else
      @key = "DECOM__#{ct}__#{target}__#{packet}__#{value_type}"
      @item_key = nil
    end
    @topic = "DEFAULT__#{topic_type}__{#{target}}__#{packet}"
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
  def create_thread(objects, max_batch_size: 100)
    collection = MockCollection.new(objects)
    thread = LoggedStreamingThread.new(streaming_api, collection, max_batch_size, scope: scope, token: token)
    OpenC3::QuestDBClient.disconnect
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
      expect(result['__type']).to eq('ITEMS')
      actual = result[obj.item_key]
      if comparator
        comparator.call(exp_val, actual, i)
      else
        expect(actual).to eq(exp_val), "Value mismatch at index #{i}: expected #{exp_val}, got #{actual}"
      end
    end
  end

  before(:each) do
    OpenC3::QuestDBClient.disconnect
    streaming_api.clear
  end

  after(:each) do
    OpenC3::QuestDBClient.disconnect
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

    it 'resolves CMD items with units (no format_string) to FORMATTED' do
      spec = {
        'tables' => [
          {
            'target' => 'CMDUNITS', 'packet' => 'TEMP',
            'data_type' => 'INT', 'bit_size' => 16, 'cmd_or_tlm' => 'CMD',
            'units' => 'degC',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 100 }, 'formatted_values' => { 'VALUE' => '100 degC' } },
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 200 }, 'formatted_values' => { 'VALUE' => '200 degC' } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 300 }, 'formatted_values' => { 'VALUE' => '300 degC' } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      table_info = test_params['tables'][0]
      target = table_info['target_name']
      packet = table_info['packet_name']

      obj = MockStreamingObject.new(
        target: target,
        packet: packet,
        item: 'VALUE',
        value_type: :WITH_UNITS,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000,
        cmd_or_tlm: :CMD
      )

      thread = create_thread([obj])

      # Mock packet_item to return item_def with units but NO format_string.
      # Before the bug fix, this would resolve to RAW instead of FORMATTED
      # because only format_string was checked, not units.
      item_def = {
        'name' => 'VALUE',
        'data_type' => 'INT',
        'bit_size' => 16,
        'units' => 'degC'
      }
      allow(OpenC3::TargetModel).to receive(:packet_item)
        .with(target, packet, 'VALUE', hash_including(type: :CMD))
        .and_return(item_def)
      allow(OpenC3::TargetModel).to receive(:packet)
        .and_return(table_info['packet_def'])

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      results = streaming_api.transmitted_results
      expect(results.length).to eq(3)

      # With the fix, units causes resolution to FORMATTED so we read VALUE__F column
      expect(results[0][obj.item_key]).to eq('100 degC')
      expect(results[1][obj.item_key]).to eq('200 degC')
      expect(results[2][obj.item_key]).to eq('300 degC')
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
        expect(result['__type']).to eq('ITEMS')
        expect(result['__time']).to be_a(Integer), "Expected __time to be Integer, got #{result['__time'].class}"
        expect(result['__time']).to be > 1_000_000_000_000_000_000, "Expected nanosecond timestamp for __time, got #{result['__time']}"
        actual = result[obj.item_key]
        expected_time = expected_start + i

        case format_type
        when :seconds
          expect(actual).to be_a(Float), "Expected Float at index #{i}, got #{actual.class}"
          # Verify format like 1770924878.8600922 (Unix timestamp with fractional seconds)
          expect(actual.to_s).to match(/^\d{10}\.\d+$/),
            "Expected Unix timestamp with fractional seconds (e.g., 1770924878.8600922) at index #{i}, got #{actual}"
          expect(actual).to be_within(0.001).of(expected_time.to_f),
            "Timestamp seconds mismatch at index #{i}: expected #{expected_time.to_f}, got #{actual}"
        when :formatted
          expect(actual).to be_a(String), "Expected String at index #{i}, got #{actual.class}"
          # Verify it's ISO 8601 format: YYYY-MM-DDTHH:MM:SS.ffffffZ
          expect(actual).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/),
            "Expected ISO 8601 format (e.g., 2026-02-12T22:19:47.234298Z) at index #{i}, got #{actual}"
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

  describe 'Decom packet timestamp items' do
    it 'includes correctly formatted timestamp items in decom packet results' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'DECOM_TS', data_type: 'INT', bit_size: 32,
        values: [100, 200, 300]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        value_type: :CONVERTED,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_decom_packets_from_tsdb, objects_by_topic)

      expect(streaming_api.transmitted_results.length).to eq(3)

      expected_start = Time.parse(test_params['start_time'])

      streaming_api.transmitted_results.each_with_index do |result, i|
        expect(result['__type']).to eq('PACKET')
        expect(result['__packet']).to eq(obj.key)

        # __time should be nanoseconds integer
        expect(result['__time']).to be_a(Integer), "Expected __time to be Integer, got #{result['__time'].class}"
        expect(result['__time']).to be > 1_000_000_000_000_000_000, "Expected nanosecond timestamp for __time"

        expected_time = expected_start + i

        # PACKET_TIMESECONDS: float like 1770924878.8600922
        pkt_ts = result['PACKET_TIMESECONDS']
        expect(pkt_ts).to be_a(Float), "Expected PACKET_TIMESECONDS to be Float, got #{pkt_ts.class}"
        expect(pkt_ts.to_s).to match(/^\d{10}\.\d+$/),
          "Expected PACKET_TIMESECONDS like 1770924878.8600922, got #{pkt_ts}"
        expect(pkt_ts).to be_within(0.001).of(expected_time.to_f),
          "PACKET_TIMESECONDS mismatch at index #{i}: expected #{expected_time.to_f}, got #{pkt_ts}"

        # PACKET_TIMEFORMATTED: ISO 8601 like 2026-02-12T22:19:47.234298Z
        pkt_tf = result['PACKET_TIMEFORMATTED']
        expect(pkt_tf).to be_a(String), "Expected PACKET_TIMEFORMATTED to be String, got #{pkt_tf.class}"
        expect(pkt_tf).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/),
          "Expected PACKET_TIMEFORMATTED as ISO 8601 (e.g., 2026-02-12T22:19:47.234298Z), got #{pkt_tf}"
        expect(Time.parse(pkt_tf).to_f).to be_within(0.001).of(expected_time.to_f),
          "PACKET_TIMEFORMATTED value mismatch at index #{i}"

        # RECEIVED_TIMESECONDS: float like 1770924878.8600922
        rcv_ts = result['RECEIVED_TIMESECONDS']
        expect(rcv_ts).to be_a(Float), "Expected RECEIVED_TIMESECONDS to be Float, got #{rcv_ts.class}"
        expect(rcv_ts.to_s).to match(/^\d{10}\.\d+$/),
          "Expected RECEIVED_TIMESECONDS like 1770924878.8600922, got #{rcv_ts}"
        expect(rcv_ts).to be_within(0.001).of(expected_time.to_f),
          "RECEIVED_TIMESECONDS mismatch at index #{i}: expected #{expected_time.to_f}, got #{rcv_ts}"

        # RECEIVED_TIMEFORMATTED: ISO 8601 like 2026-02-12T22:19:47.234298Z
        rcv_tf = result['RECEIVED_TIMEFORMATTED']
        expect(rcv_tf).to be_a(String), "Expected RECEIVED_TIMEFORMATTED to be String, got #{rcv_tf.class}"
        expect(rcv_tf).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/),
          "Expected RECEIVED_TIMEFORMATTED as ISO 8601 (e.g., 2026-02-12T22:19:47.234298Z), got #{rcv_tf}"
        expect(Time.parse(rcv_tf).to_f).to be_within(0.001).of(expected_time.to_f),
          "RECEIVED_TIMEFORMATTED value mismatch at index #{i}"
      end
    end

    it 'has consistent timestamps between __time and PACKET_TIMESECONDS' do
      test_params = write_test_data(
        target: 'STREAM', packet: 'DECOM_TS_CONSISTENT', data_type: 'INT', bit_size: 32,
        values: [42]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_decom_packets_from_tsdb, objects_by_topic)

      expect(streaming_api.transmitted_results.length).to eq(1)
      result = streaming_api.transmitted_results[0]

      # __time (nanoseconds) and PACKET_TIMESECONDS (float seconds) should represent the same time
      time_from_ns = result['__time'] / 1_000_000_000.0
      expect(time_from_ns).to be_within(0.001).of(result['PACKET_TIMESECONDS']),
        "__time (#{result['__time']}) and PACKET_TIMESECONDS (#{result['PACKET_TIMESECONDS']}) are inconsistent"

      # PACKET_TIMEFORMATTED should parse to the same time as PACKET_TIMESECONDS
      formatted_time = Time.parse(result['PACKET_TIMEFORMATTED']).to_f
      expect(formatted_time).to be_within(0.001).of(result['PACKET_TIMESECONDS']),
        "PACKET_TIMEFORMATTED (#{result['PACKET_TIMEFORMATTED']}) and PACKET_TIMESECONDS (#{result['PACKET_TIMESECONDS']}) are inconsistent"
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

      # Use current time as end_time so it's already in the past by the time stream_items returns
      # The data was written with timestamps around "now", so this captures all rows
      # and ensures the end_time <= Time.now check returns true
      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.now.to_i * 1_000_000_000
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

  describe 'Multi-table k-way merge streaming' do
    # Helper to create streaming objects and mocks from write_multi_table_data result
    def setup_multi_table_stream(test_params, value_type: :RAW)
      objects = []
      available_items = []

      test_params['tables'].each do |table_info|
        target = table_info['target_name']
        packet = table_info['packet_name']
        ct = table_info['cmd_or_tlm'] == 'CMD' ? :CMD : :TLM

        obj = MockStreamingObject.new(
          target: target,
          packet: packet,
          item: 'VALUE',
          value_type: value_type,
          start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
          end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000,
          cmd_or_tlm: ct
        )
        objects << obj

        packet_def = table_info['packet_def']
        if ct == :CMD
          allow(OpenC3::TargetModel).to receive(:packet)
            .with(target, packet, hash_including(type: :CMD))
            .and_return(packet_def)
          allow(OpenC3::TargetModel).to receive(:packet_item)
            .with(target, packet, 'VALUE', hash_including(type: :CMD))
            .and_return(packet_def['items'].first)
        else
          allow(OpenC3::TargetModel).to receive(:packet)
            .with(target, packet, hash_including(type: :TLM))
            .and_return(packet_def)
          available_items << "#{target}__#{packet}__VALUE__#{value_type}"
        end
      end

      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects
    end

    def build_objects_by_topic(objects)
      objects_by_topic = {}
      objects.each do |obj|
        objects_by_topic[obj.topic] ||= []
        objects_by_topic[obj.topic] << obj
      end
      objects_by_topic
    end

    it 'merges two tables with interleaved timestamps in correct order' do
      spec = {
        'tables' => [
          {
            'target' => 'MERGE', 'packet' => 'TLM_A',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 100 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 200 } },
              { 'offset_ms' => 4000, 'values' => { 'VALUE' => 300 } }
            ]
          },
          {
            'target' => 'MERGE', 'packet' => 'TLM_B',
            'data_type' => 'FLOAT', 'bit_size' => 64, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 1.5 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 2.5 } },
              { 'offset_ms' => 5000, 'values' => { 'VALUE' => 3.5 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      objects = setup_multi_table_stream(test_params)
      thread = create_thread(objects)

      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(6)

      # Verify timestamp ordering: A(0), B(1000), A(2000), B(3000), A(4000), B(5000)
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort), "Results not in timestamp order: #{times}"

      # Verify interleaving: A, B, A, B, A, B
      item_key_a = objects[0].item_key
      item_key_b = objects[1].item_key
      expected_keys = [item_key_a, item_key_b, item_key_a, item_key_b, item_key_a, item_key_b]
      actual_keys = results.map { |r| r.key?(item_key_a) ? item_key_a : item_key_b }
      expect(actual_keys).to eq(expected_keys)

      # Verify values
      expect(results[0][item_key_a]).to eq(100)
      expect(results[1][item_key_b]).to eq(1.5)
      expect(results[2][item_key_a]).to eq(200)
      expect(results[3][item_key_b]).to eq(2.5)
      expect(results[4][item_key_a]).to eq(300)
      expect(results[5][item_key_b]).to eq(3.5)

      # Each result should only have its own item key, not the other table's
      results.each_with_index do |r, i|
        if actual_keys[i] == item_key_a
          expect(r).not_to have_key(item_key_b), "Result #{i} from table A should not have table B's key"
        else
          expect(r).not_to have_key(item_key_a), "Result #{i} from table B should not have table A's key"
        end
      end
    end

    it 'merges three tables in correct timestamp order' do
      spec = {
        'tables' => [
          {
            'target' => 'MERGE3', 'packet' => 'PKT_A',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 10 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 40 } },
              { 'offset_ms' => 6000, 'values' => { 'VALUE' => 70 } }
            ]
          },
          {
            'target' => 'MERGE3', 'packet' => 'PKT_B',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 20 } },
              { 'offset_ms' => 4000, 'values' => { 'VALUE' => 50 } },
              { 'offset_ms' => 7000, 'values' => { 'VALUE' => 80 } }
            ]
          },
          {
            'target' => 'MERGE3', 'packet' => 'PKT_C',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 30 } },
              { 'offset_ms' => 5000, 'values' => { 'VALUE' => 60 } },
              { 'offset_ms' => 8000, 'values' => { 'VALUE' => 90 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      objects = setup_multi_table_stream(test_params)
      thread = create_thread(objects)

      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(9)

      # Verify strict timestamp ordering
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort), "Results not in timestamp order"

      # Verify interleaving: A,B,C,A,B,C,A,B,C
      item_keys = objects.map(&:item_key)
      expected_pattern = item_keys * 3
      actual_pattern = results.map { |r| item_keys.find { |k| r.key?(k) } }
      expect(actual_pattern).to eq(expected_pattern)

      # Verify values in order
      expected_values = [10, 20, 30, 40, 50, 60, 70, 80, 90]
      actual_values = results.map { |r| item_keys.map { |k| r[k] }.compact.first }
      expect(actual_values).to eq(expected_values)
    end

    it 'merges sporadic CMD packets with dense TLM in correct order' do
      spec = {
        'tables' => [
          {
            'target' => 'CMDTLM', 'packet' => 'TELEM',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } },
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 2 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 3 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 4 } },
              { 'offset_ms' => 4000, 'values' => { 'VALUE' => 5 } }
            ]
          },
          {
            'target' => 'CMDTLM', 'packet' => 'CMD1',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'CMD',
            'rows' => [
              { 'offset_ms' => 1500, 'values' => { 'VALUE' => 99 }, 'cosmos_extra' => '{"username":"admin"}' },
              { 'offset_ms' => 3500, 'values' => { 'VALUE' => 98 }, 'cosmos_extra' => '{"username":"operator"}' }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      objects = setup_multi_table_stream(test_params)
      thread = create_thread(objects)

      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(7)

      # Verify timestamp ordering
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort), "Results not in timestamp order"

      # Verify interleaving: TLM(0), TLM(1000), CMD(1500), TLM(2000), TLM(3000), CMD(3500), TLM(4000)
      tlm_key = objects[0].item_key
      cmd_key = objects[1].item_key
      expected_keys = [tlm_key, tlm_key, cmd_key, tlm_key, tlm_key, cmd_key, tlm_key]
      actual_keys = results.map { |r| r.key?(tlm_key) ? tlm_key : cmd_key }
      expect(actual_keys).to eq(expected_keys)

      # CMD results should have COSMOS_EXTRA, TLM should not
      results.each_with_index do |r, i|
        if actual_keys[i] == cmd_key
          expect(r).to have_key('COSMOS_EXTRA'), "CMD result #{i} should have COSMOS_EXTRA"
        else
          expect(r).not_to have_key('COSMOS_EXTRA'), "TLM result #{i} should not have COSMOS_EXTRA"
        end
      end
    end

    it 'filters tables with no data in the queried range' do
      spec = {
        'tables' => [
          {
            'target' => 'FILTER', 'packet' => 'EARLY',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } },
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 2 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 3 } }
            ]
          },
          {
            'target' => 'FILTER', 'packet' => 'LATE',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 10000, 'values' => { 'VALUE' => 100 } },
              { 'offset_ms' => 11000, 'values' => { 'VALUE' => 200 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      # Create objects but narrow the time range to only cover EARLY table
      early_table = test_params['tables'][0]
      early_start = early_table['timestamps_ns'].min
      early_end = early_table['timestamps_ns'].max + 1_000_000_000

      objects = []
      test_params['tables'].each do |table_info|
        target = table_info['target_name']
        packet = table_info['packet_name']

        obj = MockStreamingObject.new(
          target: target,
          packet: packet,
          item: 'VALUE',
          value_type: :RAW,
          start_time: early_start,
          end_time: early_end
        )
        objects << obj

        allow(OpenC3::TargetModel).to receive(:packet)
          .with(target, packet, hash_including(type: :TLM))
          .and_return(table_info['packet_def'])
      end

      available_items = objects.map { |o| "#{o.target_name}__#{o.packet_name}__VALUE__RAW" }
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      thread = create_thread(objects)
      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(3)

      # All results should be from EARLY table only
      early_key = objects[0].item_key
      results.each do |r|
        expect(r).to have_key(early_key), "Expected only EARLY table results"
      end
      expect(results.map { |r| r[early_key] }).to eq([1, 2, 3])
    end

    it 'computes calculated timestamps correctly across tables' do
      spec = {
        'tables' => [
          {
            'target' => 'MTIME', 'packet' => 'TBL_A',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 2 } }
            ]
          },
          {
            'target' => 'MTIME', 'packet' => 'TBL_B',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 10 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 20 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      # Create objects requesting PACKET_TIMEFORMATTED from each table
      objects = []
      test_params['tables'].each do |table_info|
        target = table_info['target_name']
        packet = table_info['packet_name']

        obj = MockStreamingObject.new(
          target: target,
          packet: packet,
          item: 'PACKET_TIMEFORMATTED',
          value_type: :RAW,
          start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
          end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
        )
        obj.item_key = "#{target}__#{packet}__PACKET_TIMEFORMATTED__RAW"
        objects << obj

        allow(OpenC3::TargetModel).to receive(:packet)
          .with(target, packet, hash_including(type: :TLM))
          .and_return(table_info['packet_def'])
      end

      available_items = objects.map { |o| "#{o.target_name}__#{o.packet_name}__PACKET_TIMEFORMATTED__RAW" }
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      thread = create_thread(objects)
      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(4)

      # Verify timestamp ordering
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort)

      # Each result's formatted time should match its own __time
      results.each_with_index do |r, i|
        item_key = objects.map(&:item_key).find { |k| r.key?(k) }
        expect(item_key).not_to be_nil, "Result #{i} should have a PACKET_TIMEFORMATTED key"

        formatted = r[item_key]
        expect(formatted).to be_a(String), "Expected String at index #{i}"
        expect(formatted).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/),
          "Expected ISO 8601 format at index #{i}, got #{formatted}"

        # Verify the formatted time matches __time
        parsed_time = Time.parse(formatted)
        time_from_ns = r['__time'] / 1_000_000_000.0
        expect(parsed_time.to_f).to be_within(0.001).of(time_from_ns),
          "Formatted time mismatch at index #{i}: #{formatted} vs __time #{r['__time']}"
      end
    end

    it 'handles batch boundaries correctly with small max_batch_size' do
      spec = {
        'tables' => [
          {
            'target' => 'BATCH', 'packet' => 'TBL_A',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 3 } },
              { 'offset_ms' => 4000, 'values' => { 'VALUE' => 5 } },
              { 'offset_ms' => 6000, 'values' => { 'VALUE' => 7 } }
            ]
          },
          {
            'target' => 'BATCH', 'packet' => 'TBL_B',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 2 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 4 } },
              { 'offset_ms' => 5000, 'values' => { 'VALUE' => 6 } },
              { 'offset_ms' => 7000, 'values' => { 'VALUE' => 8 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      objects = setup_multi_table_stream(test_params)
      thread = create_thread(objects, max_batch_size: 3)

      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(8)

      # All 8 results should be in strict timestamp order regardless of batching
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort), "Results not in timestamp order across batch boundaries"

      # Verify values in order: 1,2,3,4,5,6,7,8
      item_keys = objects.map(&:item_key)
      actual_values = results.map { |r| item_keys.map { |k| r[k] }.compact.first }
      expect(actual_values).to eq([1, 2, 3, 4, 5, 6, 7, 8])
    end

    it 'returns no results when all tables have data outside the queried range' do
      spec = {
        'tables' => [
          {
            'target' => 'EMPTY', 'packet' => 'TBL_A',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } },
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 2 } }
            ]
          },
          {
            'target' => 'EMPTY', 'packet' => 'TBL_B',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 10 } },
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 20 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      # Query 1 hour before the data
      base_ns = test_params['base_time_ns']
      early_start = base_ns - 7_200_000_000_000  # 2 hours before
      early_end = base_ns - 3_600_000_000_000     # 1 hour before

      objects = []
      test_params['tables'].each do |table_info|
        target = table_info['target_name']
        packet = table_info['packet_name']

        obj = MockStreamingObject.new(
          target: target,
          packet: packet,
          item: 'VALUE',
          value_type: :RAW,
          start_time: early_start,
          end_time: early_end
        )
        objects << obj

        allow(OpenC3::TargetModel).to receive(:packet)
          .with(target, packet, hash_including(type: :TLM))
          .and_return(table_info['packet_def'])
      end

      available_items = objects.map { |o| "#{o.target_name}__#{o.packet_name}__VALUE__RAW" }
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      thread = create_thread(objects)
      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      expect(streaming_api.transmitted_results).to be_empty
    end

    it 'streams multiple items from same packet alongside another table' do
      spec = {
        'tables' => [
          {
            'target' => 'MULTI', 'packet' => 'VALS',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 0, 'values' => { 'VALUE' => 100 } },
              { 'offset_ms' => 2000, 'values' => { 'VALUE' => 200 } }
            ]
          },
          {
            'target' => 'MULTI', 'packet' => 'OTHER',
            'data_type' => 'INT', 'bit_size' => 32, 'cmd_or_tlm' => 'TLM',
            'rows' => [
              { 'offset_ms' => 1000, 'values' => { 'VALUE' => 50 } },
              { 'offset_ms' => 3000, 'values' => { 'VALUE' => 75 } }
            ]
          }
        ]
      }

      test_params = write_multi_table_data(spec)
      expect(test_params['success']).to be true

      start_ns = Time.parse(test_params['start_time']).to_i * 1_000_000_000
      end_ns = Time.parse(test_params['end_time']).to_i * 1_000_000_000

      vals_info = test_params['tables'][0]
      other_info = test_params['tables'][1]

      # Table A: VALUE (RAW) + PACKET_TIMESECONDS - same packet, two items
      obj_raw = MockStreamingObject.new(
        target: vals_info['target_name'],
        packet: vals_info['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: start_ns,
        end_time: end_ns
      )
      obj_ts = MockStreamingObject.new(
        target: vals_info['target_name'],
        packet: vals_info['packet_name'],
        item: 'PACKET_TIMESECONDS',
        value_type: :RAW,
        start_time: start_ns,
        end_time: end_ns
      )
      obj_ts.item_key = "#{vals_info['target_name']}__#{vals_info['packet_name']}__PACKET_TIMESECONDS__RAW"

      # Table B: VALUE (RAW) only
      obj_other = MockStreamingObject.new(
        target: other_info['target_name'],
        packet: other_info['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: start_ns,
        end_time: end_ns
      )

      objects = [obj_raw, obj_ts, obj_other]

      allow(OpenC3::TargetModel).to receive(:packet)
        .with(vals_info['target_name'], vals_info['packet_name'], hash_including(type: :TLM))
        .and_return(vals_info['packet_def'])
      allow(OpenC3::TargetModel).to receive(:packet)
        .with(other_info['target_name'], other_info['packet_name'], hash_including(type: :TLM))
        .and_return(other_info['packet_def'])

      available_items = [
        "#{obj_raw.target_name}__#{obj_raw.packet_name}__VALUE__RAW",
        "#{obj_ts.target_name}__#{obj_ts.packet_name}__PACKET_TIMESECONDS__RAW",
        "#{obj_other.target_name}__#{obj_other.packet_name}__VALUE__RAW"
      ]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      thread = create_thread(objects)
      objects_by_topic = build_objects_by_topic(objects)
      topics = objects_by_topic.keys
      offsets = objects.map(&:offset)
      thread.send(:stream_items, objects_by_topic, topics, offsets)

      results = streaming_api.transmitted_results
      expect(results.length).to eq(4)

      # Verify timestamp ordering
      times = results.map { |r| r['__time'] }
      expect(times).to eq(times.sort)

      raw_key = obj_raw.item_key
      ts_key = obj_ts.item_key
      other_key = obj_other.item_key

      # Table A rows (indices 0, 2) should have both VALUE and PACKET_TIMESECONDS keys
      [0, 2].each do |i|
        expect(results[i]).to have_key(raw_key), "Table A result at #{i} should have VALUE RAW key"
        expect(results[i]).to have_key(ts_key), "Table A result at #{i} should have PACKET_TIMESECONDS key"
        expect(results[i][ts_key]).to be_a(Float), "PACKET_TIMESECONDS should be Float"
        expect(results[i]).not_to have_key(other_key), "Table A result at #{i} should not have Table B's key"
      end

      # Table B rows (indices 1, 3) should have only VALUE RAW key
      [1, 3].each do |i|
        expect(results[i]).to have_key(other_key), "Table B result at #{i} should have RAW key"
        expect(results[i]).not_to have_key(raw_key), "Table B result at #{i} should not have Table A's RAW key"
        expect(results[i]).not_to have_key(ts_key), "Table B result at #{i} should not have Table A's TIMESECONDS key"
      end
    end
  end
end
