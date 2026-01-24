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
  attr_accessor :start_time, :end_time, :offset, :item_key, :topic, :stream_mode

  def initialize(target:, packet:, item:, value_type: :RAW, start_time: nil, end_time: nil)
    @target_name = target
    @packet_name = packet
    @item_name = item
    @value_type = value_type
    @start_time = start_time
    @end_time = end_time
    @stream_mode = :DECOM
    @offset = '0-0'
    # Build key like StreamingObject does
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
    # Reset the connection to ensure clean state
    thread.class.class_variable_set(:@@conn, nil) if thread.class.class_variable_defined?(:@@conn)
    thread
  end

  # Reset connection before each test
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

  describe '#stream_items' do
    it 'streams INT values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'INT_PKT',
        data_type: 'INT',
        bit_size: 32,
        values: [-100, 0, 100, 12345]
      )
      expect(test_params['success']).to be true

      # Create streaming object for this item
      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      # Mock TargetModel.packet
      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])

      # Mock LocalApi.get_tlm_available to return available items
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      # Build objects_by_topic for stream_items
      objects_by_topic = { obj.topic => [obj] }

      # Call stream_items
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      # Verify results
      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_values'].length)
      test_params['expected_values'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams FLOAT values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'FLOAT_PKT',
        data_type: 'FLOAT',
        bit_size: 64,
        values: [-1.5, 0.0, 1.5, 3.14159]
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

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_values'].length)
      test_params['expected_values'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to be_within(1e-10).of(expected)
      end
    end

    it 'streams STRING values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'STRING_PKT',
        data_type: 'STRING',
        values: ['hello', 'world', 'test123']
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

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_values'].length)
      test_params['expected_values'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams DERIVED values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'DERIVED_PKT',
        data_type: 'DERIVED',
        values: [42, 3.14, 'status_ok']
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

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_values'].length)
      test_params['expected_values'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams array values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'ARRAY_PKT',
        data_type: 'FLOAT',
        array_size: 5,
        values: [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
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

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_values'].length)
      test_params['expected_values'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams CONVERTED values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'CONV_PKT',
        data_type: 'INT',
        bit_size: 16,
        values: [100, 200, 300],
        converted_values: [10.0, 20.0, 30.0],
        read_conversion: { 'converted_type' => 'FLOAT', 'converted_bit_size' => 64 }
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :CONVERTED,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__CONVERTED"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_converted'].length)
      test_params['expected_converted'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams FORMATTED values correctly' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'FMT_PKT',
        data_type: 'INT',
        bit_size: 16,
        values: [100, 200, 300],
        formatted_values: ['100 V', '200 V', '300 V'],
        format_string: '%d',
        units: 'V'
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :FORMATTED,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__FORMATTED"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      expect(streaming_api.transmitted_results.length).to eq(test_params['expected_formatted'].length)
      test_params['expected_formatted'].each_with_index do |expected, i|
        result = streaming_api.transmitted_results[i]
        expect(result['__type']).to eq('items')
        expect(result[obj.item_key]).to eq(expected)
      end
    end

    it 'streams multiple items from the same packet' do
      # Write data with multiple items - we'll write two separate packets
      # and query both items together
      test_params1 = write_test_data(
        target: 'STREAM_TEST',
        packet: 'MULTI_PKT',
        data_type: 'INT',
        bit_size: 32,
        values: [1, 2, 3]
      )
      expect(test_params1['success']).to be true

      obj1 = MockStreamingObject.new(
        target: test_params1['target_name'],
        packet: test_params1['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params1['start_time']).to_i * 1_000_000_000,
        end_time: Time.parse(test_params1['end_time']).to_i * 1_000_000_000
      )

      thread = create_thread([obj1])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params1['packet_def'])
      available_items = ["#{obj1.target_name}__#{obj1.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj1.topic => [obj1] }
      thread.send(:stream_items, objects_by_topic, [obj1.topic], [obj1.offset])

      # Should have 3 results with timestamps
      expect(streaming_api.transmitted_results.length).to eq(3)
      streaming_api.transmitted_results.each do |result|
        expect(result['__type']).to eq('items')
        expect(result['__time']).to be_a(Integer)
        expect(result['__time']).to be > 0
      end
    end

    it 'includes timestamp in results' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'TIME_PKT',
        data_type: 'INT',
        bit_size: 32,
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
      # Timestamp should be in nanoseconds and within reasonable range
      expect(result['__time']).to be > Time.now.to_i * 1_000_000_000 - 60_000_000_000  # within last minute
    end

    it 'returns true when end_time is specified (indicating completion)' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'DONE_PKT',
        data_type: 'INT',
        bit_size: 32,
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

      # Should return true because end_time was specified
      expect(done).to be true
    end

    it 'returns false when end_time is nil (indicating more data may come)' do
      test_params = write_test_data(
        target: 'STREAM_TEST',
        packet: 'CONT_PKT',
        data_type: 'INT',
        bit_size: 32,
        values: [1, 2]
      )
      expect(test_params['success']).to be true

      obj = MockStreamingObject.new(
        target: test_params['target_name'],
        packet: test_params['packet_name'],
        item: 'VALUE',
        value_type: :RAW,
        start_time: Time.parse(test_params['start_time']).to_i * 1_000_000_000,
        end_time: nil  # No end time - streaming continues
      )

      thread = create_thread([obj])

      allow(OpenC3::TargetModel).to receive(:packet).and_return(test_params['packet_def'])
      available_items = ["#{obj.target_name}__#{obj.packet_name}__VALUE__RAW"]
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available).and_return(available_items)

      objects_by_topic = { obj.topic => [obj] }
      done = thread.send(:stream_items, objects_by_topic, [obj.topic], [obj.offset])

      # Should return false because no end_time was specified
      expect(done).to be false
    end
  end
end
