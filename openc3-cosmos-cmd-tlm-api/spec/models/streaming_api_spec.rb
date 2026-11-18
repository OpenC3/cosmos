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

require 'rails_helper'
require 'openc3/utilities/aws_bucket'
require 'openc3/utilities/bucket_file_cache'

RSpec.describe StreamingApi, type: :model do
  before(:each) do
    # OpenC3::Logger.level = Logger::DEBUG

    mock_redis()
    setup_system()

    @start_time = Time.now
    @time = @start_time
    msg = {}
    msg['target_name'] = 'INST'
    msg['packet_name'] = 'PARAMS'
    msg['time'] = @time.to_i * 1_000_000_000
    packet_data = {}
    packet_data['PACKET_TIMESECONDS'] = @time.to_f
    packet_data['PACKET_TIMEFORMATTED'] = @time.formatted
    packet_data['VALUE1__R'] = 1
    msg['json_data'] = JSON.generate(packet_data, allow_nan: true)
    msg['buffer'] = '\x01\x02\x03\x04'
    # Send count is how many times we return a message from read_topics
    # We can limit this to simulate no packets being available from read_topics
    @send_count = 100

    allow(OpenC3::EphemeralStore.instance).to receive(:read_topics) do |params, &block|
      sleep 0.1 # Simulate a little blocking time, all test cases use 0.1 as a multiple
      @time += 1
      msg['time'] = @time.to_i * 1_000_000_000 # Convert to nsec
      if @send_count > 0
        @send_count -= 1
        block.call(params[0], "#{@time.to_i * 1000}-0", msg, nil)
        msg
      else
        {} # Return {} like the real store code
      end
    end

    # Treat every TSDB table as existing unless a test says otherwise. Returning nil
    # also keeps the table listing from consuming the mocked PG exec results.
    allow(OpenC3::QuestDBClient).to receive(:table_names).and_return(nil)

    # Ensure the BucketFileCache is clear so we don't leak the s3 mock
    BucketFileCache.class_variable_set(:@@instance, nil)

    @file_start_time = 1614890937274290500 # these are the unix epoch values for the timestamps in the file names in spec/fixtures/files
    @file_end_time = 1614891537276524900

    s3 = double("AwsS3Client").as_null_object
    allow(Aws::S3::Client).to receive(:new).and_return(s3)
    allow(s3).to receive(:head_bucket).and_return(true)
    allow(s3).to receive(:list_objects_v2) do |args|
      response = Object.new
      if args[:delimiter]
        def response.common_prefixes
          item = Object.new
          def item.prefix
            "20210304"
          end
          [item]
        end
      elsif args[:prefix].split('/')[1].include? 'decom'
        def response.contents
          file_1 = Object.new
          def file_1.key
            "DEFAULT/decom_logs/tlm/INST/20210304/20210304204857274290500__20210304205858274347600__DEFAULT__INST__PARAMS__rt__decom.bin.gz"
          end
          def file_1.size
            4221512
          end
          file_2 = Object.new
          def file_2.key
            "DEFAULT/decom_logs/tlm/INST/20210304/20210304204857274290500__20210304205858274347600__DEFAULT__INST__PARAMS__rt__decom.idx.gz"
          end
          def file_2.size
            86522
          end
          [ file_1, file_2 ]
        end
      else
        def response.contents
          file_1 = Object.new
          def file_1.key
            "DEFAULT/raw_logs/tlm/INST/20210304/20210304204857274290500__20210304205857276524900__DEFAULT__INST__PARAMS__rt__raw.bin.gz"
          end
          def file_1.size
            1000002
          end
          file_2 = Object.new
          def file_2.key
            "DEFAULT/raw_logs/tlm/INST/20210304/20210304204857274290500__20210304205857276524900__DEFAULT__INST__PARAMS__rt__raw.idx.gz"
          end
          def file_2.size
            571466
          end
          [ file_1, file_2 ]
        end
      end
      def response.is_truncated
        false
      end
      response
    end
    allow(s3).to receive(:get_object) do |args|
      FileUtils.cp(file_fixture(File.basename(args[:key])).realpath, args[:response_target])
    end

    @messages = []
    @subscription_key = "streaming_abc123"

    allow(ActionCable.server).to receive(:broadcast) do |uuid, message|
      @messages << message
    end

    @api = StreamingApi.new(@subscription_key, scope: 'DEFAULT')
  end

  after(:each) do
    @api.kill
  end

  it 'stores the channel and threads' do
    expect(@api.instance_variable_get('@realtime_thread')).to be_nil
    expect(@api.instance_variable_get('@logged_threads')).to be_empty
  end

  describe '#transmit_notice' do
    it 'only sends notices to clients that opted in' do
      @api.transmit_notice('SKIPPED', 'skipped', skipped_seconds: 1.5)
      expect(@messages).to be_empty

      @api.instance_variable_set('@notices', true)
      @api.transmit_notice('SKIPPED', 'skipped', skipped_seconds: 1.5)
      expect(@messages).to eq([{ "__type" => "NOTICE", "notice" => "SKIPPED", "message" => "skipped", "skipped_seconds" => 1.5 }])
    end

    it 'opts in via the add request' do
      allow(StreamingObject).to receive(:new).and_raise(OpenC3::ForbiddenError)
      @api.add({ 'scope' => 'DEFAULT', 'notices' => true, 'end_time' => 0, 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'] })
      expect(@api.instance_variable_get('@notices')).to be true
      end
    end

  describe '#kill' do
    class FakeStreamingThread < StreamingThread
      def initialize(streaming_api, stop_delay)
        super(streaming_api, nil)
        @stop_delay = stop_delay
      end

      def thread_body
        sleep 0.01
        sleep @stop_delay if @cancel_thread
      end
    end

    def start_fake_thread(stop_delay)
      thread = FakeStreamingThread.new(@api, stop_delay)
      thread.start
      thread
    end

    it 'returns as soon as the threads have exited' do
      threads = [start_fake_thread(0), start_fake_thread(0)]
      @api.instance_variable_set('@realtime_thread', threads[0])
      @api.instance_variable_set('@logged_threads', [threads[1]])
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @api.kill
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.5
      threads.each { |thread| expect(thread.instance_variable_get('@thread').alive?).to be false }
      expect(@api.instance_variable_get('@realtime_thread')).to be_nil
      expect(@api.instance_variable_get('@logged_threads')).to be_empty
    end

    it 'waits on the actual threads, not just the stop request' do
      thread = start_fake_thread(0.3)
      sleep 0.05 # Let the thread enter thread_body
      @api.instance_variable_set('@logged_threads', [thread])
      @api.kill
      expect(thread.instance_variable_get('@thread').alive?).to be false
    end

    it 'shares a single deadline across all threads' do
      threads = [start_fake_thread(5), start_fake_thread(5)]
      sleep 0.05 # Let the threads enter thread_body
      @api.instance_variable_set('@logged_threads', threads)
      expect(OpenC3::Logger).to receive(:warn).twice
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @api.kill
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be_within(0.3).of(StreamingApi::KILL_TIMEOUT_SECONDS)
      threads.each { |thread| thread.instance_variable_get('@thread').kill }
    end
  end

  describe '#expand_all_packets' do
    before(:each) do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST', 'SYSTEM', 'EMPTY', 'UNKNOWN'])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('INST', type: :CMD, scope: 'DEFAULT').and_return([
        'COLLECT',
        'ABORT',
        'CLEAR',
      ])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('INST', type: :TLM, scope: 'DEFAULT').and_return([
        'HEALTH_STATUS',
        'PARAMS',
      ])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('SYSTEM', type: :CMD, scope: 'DEFAULT').and_return([
        'META',
      ])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('SYSTEM', type: :TLM, scope: 'DEFAULT').and_return([
        'META',
      ])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('EMPTY', type: :CMD, scope: 'DEFAULT').and_raise(RuntimeError, "no packets")
      allow(OpenC3::TargetModel).to receive(:packet_names).with('EMPTY', type: :TLM, scope: 'DEFAULT').and_raise(RuntimeError, "no packets")
    end

    it 'expands COSMOS_ALL for a specific target in DECOM mode' do
      data = { 'packets' => ['DECOM__CMD__INST__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq([
        'DECOM__CMD__INST__COLLECT__CONVERTED',
        'DECOM__CMD__INST__ABORT__CONVERTED',
        'DECOM__CMD__INST__CLEAR__CONVERTED',
      ])
    end

    it 'expands COSMOS_ALL for a specific target in RAW mode (no value type)' do
      data = { 'packets' => ['RAW__CMD__INST__COSMOS_ALL'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq([
        'RAW__CMD__INST__COLLECT',
        'RAW__CMD__INST__ABORT',
        'RAW__CMD__INST__CLEAR',
      ])
    end

    it 'expands COSMOS_ALL for all targets' do
      data = { 'packets' => ['DECOM__TLM__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq([
        'DECOM__TLM__INST__HEALTH_STATUS__CONVERTED',
        'DECOM__TLM__INST__PARAMS__CONVERTED',
        'DECOM__TLM__SYSTEM__META__CONVERTED',
      ])
    end

    it 'passes through non-COSMOS_ALL keys unchanged' do
      data = { 'packets' => ['DECOM__CMD__INST__COLLECT__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq(['DECOM__CMD__INST__COLLECT__CONVERTED'])
    end

    it 'handles mixed COSMOS_ALL and concrete keys' do
      data = { 'packets' => ['DECOM__CMD__INST__COLLECT__CONVERTED', 'RAW__CMD__INST__COSMOS_ALL'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq([
        'DECOM__CMD__INST__COLLECT__CONVERTED',
        'RAW__CMD__INST__COLLECT',
        'RAW__CMD__INST__ABORT',
        'RAW__CMD__INST__CLEAR',
      ])
    end

    it 'handles COSMOS_ALL with nonexistent target gracefully' do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('BOGUS', type: :CMD, scope: 'DEFAULT').and_raise(RuntimeError, "Target 'BOGUS' does not exist")
      data = { 'packets' => ['DECOM__CMD__BOGUS__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to eq([])
    end

    it 'does nothing when packets key is absent' do
      data = { 'items' => ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      expect(data['packets']).to be_nil
    end

    it 'skips targets without the requested packet type for COSMOS_ALL targets' do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('UNKNOWN', type: :CMD, scope: 'DEFAULT').and_return([
        'UNKNOWN',
      ])
      data = { 'packets' => ['RAW__CMD__COSMOS_ALL'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      # EMPTY target raises RuntimeError, so it should be skipped
      empty_packets = data['packets'].select { |p| p.include?('EMPTY') }
      expect(empty_packets).to be_empty
      expect(data['packets']).to include('RAW__CMD__INST__COLLECT')
      expect(data['packets']).to include('RAW__CMD__SYSTEM__META')
    end

    it 'skips UNKNOWN target for DECOM' do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('UNKNOWN', type: :CMD, scope: 'DEFAULT').and_return([
        'UNKNOWN',
      ])
      # COSMOS_ALL targets: UNKNOWN target should be excluded entirely
      data = { 'packets' => ['DECOM__CMD__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      unknown_packets = data['packets'].select { |p| p.include?('UNKNOWN') }
      expect(unknown_packets).to be_empty
    end

    it 'keeps UNKNOWN target for RAW' do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('UNKNOWN', type: :CMD, scope: 'DEFAULT').and_return([
        'UNKNOWN',
      ])
      # COSMOS_ALL targets: UNKNOWN target should be included for RAW
      data = { 'packets' => ['RAW__CMD__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_all_packets, data, scope: 'DEFAULT')
      unknown_packets = data['packets'].select { |p| p.include?('UNKNOWN') }
      expect(unknown_packets).not_to be_empty
    end
  end

  describe '#expand_item_globs' do
    before(:each) do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('INST', type: :TLM, scope: 'DEFAULT').and_return([
        'HEALTH_STATUS',
        'PARAMS',
        'IMAGE',
      ])
      allow(OpenC3::TargetModel).to receive(:packet).with('INST', 'HEALTH_STATUS', type: :TLM, scope: 'DEFAULT').and_return({
        'items' => [
          { 'name' => 'TEMP1' },
          { 'name' => 'TEMP2' },
          { 'name' => 'TEMP3' },
          { 'name' => 'DURATION' },
          { 'name' => 'BRACKET[0]' },
          { 'name' => 'ARY[0]' },
          { 'name' => 'ARY[1]' },
        ]
      })
      allow(OpenC3::TargetModel).to receive(:packet).with('INST', 'PARAMS', type: :TLM, scope: 'DEFAULT').and_return({
        'items' => [
          { 'name' => 'VALUE1' },
          { 'name' => 'VALUE2' },
          { 'name' => 'TEMP1' },
        ]
      })
      allow(OpenC3::TargetModel).to receive(:packet).with('INST', 'IMAGE', type: :TLM, scope: 'DEFAULT').and_return({
        'items' => [
          { 'name' => 'DATA' },
        ]
      })
      allow(OpenC3::TargetModel).to receive(:get_item_to_packet_map).with('INST', scope: 'DEFAULT').and_return({
        'TEMP1' => ['HEALTH_STATUS', 'PARAMS'],
        'TEMP2' => ['HEALTH_STATUS'],
        'TEMP3' => ['HEALTH_STATUS'],
        'DURATION' => ['HEALTH_STATUS'],
        'VALUE1' => ['PARAMS'],
        'VALUE2' => ['PARAMS'],
        'DATA' => ['IMAGE'],
        'BRACKET[0]' => ['HEALTH_STATUS'],
        'ARY[0]' => ['HEALTH_STATUS'],
        'ARY[1]' => ['HEALTH_STATUS'],
      })
    end

    it 'passes through non-glob entries unchanged' do
      data = { 'items' => [['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', '0']])
    end

    it 'expands item glob for a specific packet' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__TEMP*__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED'],
      ])
    end

    it 'expands packet glob with concrete item name' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH*__TEMP1__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
      ])
    end

    it 'expands both packet and item globs' do
      data = { 'items' => [['DECOM__TLM__INST__*__TEMP1__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__PARAMS__TEMP1__CONVERTED', 'DECOM__TLM__INST__PARAMS__TEMP1__CONVERTED'],
      ])
    end

    it 'expands LATEST + item glob using item_to_packet_map' do
      data = { 'items' => [['DECOM__TLM__INST__LATEST__TEMP*__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__LATEST__TEMP1__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__LATEST__TEMP2__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__LATEST__TEMP3__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP3__CONVERTED'],
      ])
    end

    it 'returns empty for no matches' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__ZZZZZ*__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([])
    end

    it 'handles mixed glob and concrete entries' do
      data = { 'items' => [
        ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', '0'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP*__CONVERTED', '1'],
      ], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', '0'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED'],
      ])
    end

    it 'handles ? wildcard in item name' do
      data = { 'items' => [['DECOM__TLM__INST__PARAMS__VALUE?__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', 'DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED'],
        ['DECOM__TLM__INST__PARAMS__VALUE2__CONVERTED', 'DECOM__TLM__INST__PARAMS__VALUE2__CONVERTED'],
      ])
    end

    it 'preserves reduced type in expanded keys' do
      data = { 'items' => [['REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP*__CONVERTED__AVG', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED__AVG', 'REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED__AVG'],
        ['REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED__AVG', 'REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED__AVG'],
        ['REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED__AVG', 'REDUCED_MINUTE__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED__AVG'],
      ])
    end

    it 'does nothing when items key is absent' do
      data = { 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to be_nil
    end

    it 'handles nonexistent target gracefully for packet glob' do
      allow(OpenC3::TargetModel).to receive(:packet_names).with('BOGUS', type: :TLM, scope: 'DEFAULT').and_raise(RuntimeError, "Target 'BOGUS' does not exist")
      data = { 'items' => [['DECOM__TLM__BOGUS__*__TEMP1__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([])
    end

    it 'skips packets whose definition cannot be fetched' do
      allow(OpenC3::TargetModel).to receive(:packet).with('INST', 'IMAGE', type: :TLM, scope: 'DEFAULT').and_raise(RuntimeError, "Packet not found")
      data = { 'items' => [['DECOM__TLM__INST__*__DATA__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      # IMAGE packet raises, so only HEALTH_STATUS and PARAMS are checked — neither has DATA
      expect(data['items']).to eq([])
    end

    it 'handles flat string entries (non-array items)' do
      data = { 'items' => ['DECOM__TLM__INST__HEALTH_STATUS__TEMP*__CONVERTED'], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED'],
      ])
    end

    # --- Array-index bracket tests ---

    it 'passes through ARY[0] unchanged (array index is not a glob)' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([['DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', '0']])
    end

    it 'passes through BRACKET[0] unchanged (array index is not a glob)' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__BRACKET[0]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([['DECOM__TLM__INST__HEALTH_STATUS__BRACKET[0]__CONVERTED', '0']])
    end

    it 'passes through ARY[1] unchanged (array index is not a glob)' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__ARY[1]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([['DECOM__TLM__INST__HEALTH_STATUS__ARY[1]__CONVERTED', '0']])
    end

    it 'expands bracket range glob TEMP[1-3] to TEMP1, TEMP2, TEMP3' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__TEMP[1-3]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED'],
      ])
    end

    it 'star glob matches items with brackets in their names' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH_STATUS__*__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      item_names = data['items'].map { |pair| StreamingKey.parse(pair[0], item_key: true).item_name }
      expect(item_names).to include('BRACKET[0]', 'ARY[0]', 'ARY[1]')
    end

    it 'handles mixed concrete ARY[0] and glob TEMP* correctly' do
      data = { 'items' => [
        ['DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', '0'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP*__CONVERTED', '1'],
      ], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', '0'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP3__CONVERTED'],
      ])
    end

    it 'LATEST + BRACKET[0] passes through unchanged' do
      data = { 'items' => [['DECOM__TLM__INST__LATEST__BRACKET[0]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([['DECOM__TLM__INST__LATEST__BRACKET[0]__CONVERTED', '0']])
    end

    it 'LATEST + bracket range glob TEMP[1-3] expands correctly' do
      data = { 'items' => [['DECOM__TLM__INST__LATEST__TEMP[1-3]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__LATEST__TEMP1__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP1__CONVERTED'],
        ['DECOM__TLM__INST__LATEST__TEMP2__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP2__CONVERTED'],
        ['DECOM__TLM__INST__LATEST__TEMP3__CONVERTED', 'DECOM__TLM__INST__LATEST__TEMP3__CONVERTED'],
      ])
    end

    it 'packet glob HEALTH* + bracket item BRACKET[0] expands correctly' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH*__BRACKET[0]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__BRACKET[0]__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__BRACKET[0]__CONVERTED'],
      ])
    end

    it 'packet glob HEALTH* + bracket item ARY[0] expands correctly' do
      data = { 'items' => [['DECOM__TLM__INST__HEALTH*__ARY[0]__CONVERTED', '0']], 'scope' => 'DEFAULT' }
      @api.send(:expand_item_globs, data, scope: 'DEFAULT')
      expect(data['items']).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED'],
      ])
    end
  end

  describe '#build_item_collection' do
    before(:each) do
      allow(OpenC3::TargetModel).to receive(:get_item_to_packet_map).with('INST', scope: 'DEFAULT').and_return({
        'TEMP1' => ['HEALTH_STATUS', 'PARAMS'],
      })
    end

    let(:latest_key) { 'DECOM__TLM__INST__LATEST__TEMP1__CONVERTED' }
    let(:explicit_key) { 'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED' }

    def build(items)
      collection = StreamingObjectCollection.new
      @api.build_item_collection(collection, { 'items' => items }, scope: 'DEFAULT')
      collection
    end

    it 'expands LATEST into one object per packet keyed by the LATEST key' do
      collection = build([latest_key])
      expect(collection.objects.map { |o| [o.key, o.item_key] }).to eq([
        ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', latest_key],
        ['DECOM__TLM__INST__PARAMS__TEMP1__CONVERTED', latest_key],
      ])
    end

    it 'keeps a LATEST item and an explicit item for the same packet' do
      collection = build([latest_key, explicit_key])
      expect(collection.length).to eq(3)
      expect(collection.objects.select { |o| o.key == explicit_key }.map(&:item_key)).to contain_exactly(latest_key, explicit_key)
    end

    it 'removing the LATEST item leaves the explicit item' do
      collection = build([latest_key, explicit_key])
      build([latest_key]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map { |o| [o.key, o.item_key] }).to eq([[explicit_key, explicit_key]])
    end

    it 'removing the explicit item leaves the LATEST item' do
      collection = build([latest_key, explicit_key])
      build([explicit_key]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map(&:item_key).uniq).to eq([latest_key])
      expect(collection.length).to eq(2)
    end

    it 'rejects LATEST for commands' do
      expect { build(['DECOM__CMD__INST__LATEST__TEMP1__CONVERTED']) }.to raise_error(/LATEST is only supported for telemetry/)
    end

    it 'skips LATEST packets the user cannot access' do
      allow_any_instance_of(StreamingObject).to receive(:authorize) do |_object, packet_name:, **|
        raise OpenC3::ForbiddenError, 'forbidden' if packet_name == 'PARAMS'
      end
      expect(build([latest_key]).objects.map(&:packet_name)).to eq(['HEALTH_STATUS'])
    end

    it 'raises when the user cannot access any LATEST packet' do
      allow_any_instance_of(StreamingObject).to receive(:authorize).and_raise(OpenC3::ForbiddenError, 'forbidden')
      expect { build([latest_key]) }.to raise_error(OpenC3::ForbiddenError)
    end

    it 'removes an item added with an item_key when removed by key alone' do
      collection = build([[explicit_key, '0']])
      build([explicit_key]).objects.each { |o| collection.remove(o) }
      expect(collection).to be_empty
    end

    it 'removing an explicit item by key alone leaves the LATEST item' do
      collection = build([latest_key, [explicit_key, '0']])
      build([explicit_key]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map(&:item_key).uniq).to eq([latest_key])
      expect(collection.length).to eq(2)
    end

    it 'removing a LATEST item by key alone leaves the explicit item' do
      collection = build([[latest_key, '0'], explicit_key])
      build([latest_key]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map { |o| [o.key, o.item_key] }).to eq([[explicit_key, explicit_key]])
    end

    it 'removes every item_key for a key when removed by key alone' do
      collection = build([explicit_key, [explicit_key, '0']])
      expect(collection.length).to eq(2)
      build([explicit_key]).objects.each { |o| collection.remove(o) }
      expect(collection).to be_empty
    end

    it 'removing a key with an item_key only removes that item_key' do
      collection = build([explicit_key, [explicit_key, '0']])
      build([[explicit_key, '0']]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map(&:item_key)).to eq([explicit_key])
    end

    it 'removing an unknown item_key does not remove other item_keys' do
      collection = build([explicit_key, [explicit_key, '0']])
      build([[explicit_key, '1']]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map(&:item_key)).to contain_exactly(explicit_key, '0')
    end

    it 'falls back to matching source_key and item_key when the exact object is not found' do
      allow(OpenC3::TargetModel).to receive(:get_item_to_packet_map).with('INST', scope: 'DEFAULT').and_return({
        'TEMP1' => ['PARAMS'],
      })
      collection = build([[latest_key, '0'], [latest_key, '1']])
      allow(OpenC3::TargetModel).to receive(:get_item_to_packet_map).with('INST', scope: 'DEFAULT').and_return({
        'TEMP1' => ['HEALTH_STATUS'],
      })
      # The HEALTH_STATUS object was never added so the removal falls back to the sweep
      build([[latest_key, '0']]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map(&:item_key)).to eq(['1'])
    end

    it 'keeps a LATEST item and an explicit item with the same item_key' do
      collection = build([[latest_key, '0'], [explicit_key, '0']])
      expect(collection.length).to eq(3)
      build([[latest_key, '0']]).objects.each { |o| collection.remove(o) }
      expect(collection.objects.map { |o| [o.key, o.source_key] }).to eq([[explicit_key, explicit_key]])
    end

    it 'exact removal of a key-only item leaves other item_keys for the key' do
      collection = build([explicit_key, [explicit_key, '0']])
      key_only = collection.objects.find { |o| o.item_key == explicit_key }
      collection.remove(key_only, exact: true)
      expect(collection.objects.map(&:item_key)).to eq(['0'])
    end

    it 'exact removal of one LATEST packet leaves the others' do
      collection = build([latest_key])
      collection.remove(collection.objects[0], exact: true)
      expect(collection.objects.map(&:key)).to eq(['DECOM__TLM__INST__PARAMS__TEMP1__CONVERTED'])
    end

    it 'finishing a key-only item leaves an alias with a later end time' do
      collection = build([explicit_key, [explicit_key, '0']])
      thread = StreamingThread.new(@api, collection, scope: 'DEFAULT')
      thread.finish([collection.objects.find { |o| o.item_key == explicit_key }])
      expect(collection.objects.map(&:item_key)).to eq(['0'])
      expect(thread.instance_variable_get(:@cancel_thread)).to be_falsey
    end

    it 'hands off every alias on a caught-up topic and leaves topics that have not caught up' do
      collection = build([[explicit_key, '0'], [explicit_key, '1'], [latest_key, '2']])
      realtime = StreamingThread.new(@api, StreamingObjectCollection.new, scope: 'DEFAULT')
      health_status_topic = collection.objects[0].topic
      _topics, _offsets, item_objects_by_topic, packet_objects_by_topic = collection.topics_offsets_and_objects
      realtime.handoff_objects(collection, health_status_topic, item_objects_by_topic, packet_objects_by_topic)
      expect(realtime.instance_variable_get(:@collection).objects.map(&:item_key)).to contain_exactly('0', '1', '2')
      expect(collection.objects.map { |o| [o.packet_name, o.item_key] }).to eq([['PARAMS', '2']])
    end

    it 'handing off a LATEST packet leaves the packets that have not caught up' do
      collection = build([latest_key])
      health_status = collection.objects[0]
      health_status.offset = '100-0'
      realtime = StreamingThread.new(@api, StreamingObjectCollection.new, scope: 'DEFAULT')
      realtime.handoff_objects(collection, health_status.topic, { health_status.topic => [health_status] }, {})
      expect(collection.objects.map(&:packet_name)).to eq(['PARAMS'])
    end
  end

  describe 'add with COSMOS_ALL packets and authorization' do
    it 'skips unauthorized packets when using COSMOS_ALL' do
      $openc3_authorize = true
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetModel).to receive(:packet_names).with('INST', type: :CMD, scope: 'DEFAULT').and_return([
        'COLLECT',
        'ABORT',
      ])
      @send_count = 0
      data = { 'packets' => ['DECOM__CMD__INST__COSMOS_ALL__CONVERTED'], 'scope' => 'DEFAULT', 'token' => 'invalid' }
      # This should not raise - unauthorized packets are silently skipped
      expect { @api.add(data) }.not_to raise_error
      $openc3_authorize = false
    end
  end

  context 'streaming with Redis' do
    base_data = { 'scope' => 'DEFAULT' }
    modes = [
      { 'description' => 'items in decom mode', 'data' => { 'items' => ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED'] } },
      # { 'description' => 'packets in decom mode', 'data' => { 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'] } },
      # { 'description' => 'packets in raw mode', 'data' => { 'packets' => ['RAW__TLM__INST__PARAMS'] } },
    ]

    describe 'bad modes' do
      let(:data) { modes[0]['data'].dup.merge(base_data) }

      it 'should not allow start time more than 1min in the future' do
        data['start_time'] =(@start_time.to_i + 65) * 1_000_000_000 # 65s in future
        data['end_time'] = (@start_time.to_i + 120) * 1_000_000_000

        logger_messages = []
        allow(OpenC3::Logger).to receive(:debug) do |msg|
          logger_messages << msg
        end
        @api.add(data)
        sleep 0.25 # Allow the threads to run
        expect(logger_messages).to include("Finishing stream start_time too far in future")
      end
    end

    modes.each do |mode|
      context "for #{mode['description']}" do
        let(:data) { mode['data'].dup.merge(base_data) }

        it 'has no data in time range' do
          msg2 = { 'time' => ((@start_time.to_i - 100) * 1_000_000_000) - LoggedStreamingThread::ALLOWABLE_START_TIME_OFFSET_NSEC } # oldest is 100s before the allowable offset
          allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

          data['start_time'] =(@start_time.to_i - 5.5) * 1_000_000_000 # now
          data['end_time'] = (@start_time.to_i - 1.5) * 1_000_000_000 # 1.5 in the future
          @api.add(data)
          sleep 0.25 # Allow the threads to run
          # We should get the empty message to say we're done
          expect(@messages.length).to eq(1)
          expect(@messages[-1]).to eq([]) # empty message to say we're done
        end

        context 'realtime only' do
          # NOTE: We're not testing start time > Time.now as this is disallowed by the StreamingChannel

          it 'has no start and no end time' do
            @send_count = 3
            @api.add(data)
            sleep 0.35 # Allow the thread to run
            expect(@messages.length).to eq(3)
            # Remove the items and we should end
            @api.remove(data)
            sleep 2
            expect(@messages.length).to eq(4) # 3 plus the empty one
            expect(@messages[-1]).to eq([]) # Last message after removing the subscription should be empty
            sleep 0.15
            expect(@messages.length).to eq(4) # No more
            expect(@messages[-1]).to eq([]) # Last message should still be empty

            # Ensure we can add items again and resume processing
            @send_count = 100
            @api.add(data)
            while true
              sleep 0.05
              break if @messages.length > 4
            end
            @api.kill
            expect(@api.instance_variable_get('@realtime_thread')).to be_nil
          end

          it 'has no start time and future end time' do
            data['end_time'] = (@start_time.to_i + 1.5) * 1_000_000_000 # 1.5s in the future we stop
            @api.add(data)
            sleep 0.35 # Allow the thread to run
            # We should have 2 messages: one at 1s and then the time will disqualify them
            # so the final message is the empty set to say we're done
            expect(@messages.length).to eq(2)
            expect(@messages[-1]).to eq([]) # empty message to say we're done

            @api.kill
            expect(@api.instance_variable_get('@realtime_thread')).to be_nil
          end

          it 'skips ahead and notifies when far behind realtime' do
            # Messages read are 2 minutes older than the stream head so we're well past the max lag
            @time = @start_time - 120
            head = "#{Time.now.to_i * 1000}-0"
            allow_any_instance_of(RealtimeStreamingThread).to receive(:stream_heads) do |_thread, topics|
              topics.to_h { |topic| [topic, head] }
            end
            @send_count = 1
            data['notices'] = true
            @api.add(data)
            sleep 0.35 # Allow the thread to run
            notice = @messages.find { |message| message.is_a?(Hash) }
            expect(notice['notice']).to eq('SKIPPED')
            expect(notice['skipped_seconds']).to be > 60
            @api.kill
          end
        end

        context 'logging plus realtime' do
          it 'has past start time and no end time' do
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 1.5)
            data['start_time'] = @time.to_i * 1_000_000_000 # 1.5s in the past
            @api.add(data)
            sleep 0.55 # Allow the threads to run
            expect(@messages.length).to eq(5)
            expect(@api.instance_variable_get('@logged_threads').length).to eq(0)
            expect(@api.instance_variable_get('@realtime_thread')).to_not be_nil
            @api.kill
            expect(@api.instance_variable_get('@logged_threads')).to be_empty
          end

          it 'has past start time and future end time' do
            msg1 = { 'time' => @start_time.to_i * 1_000_000_000 } # newest is now
            allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 1.5)
            data['start_time'] = @time.to_i * 1_000_000_000 # 1.5s in the past
            data['end_time'] = (@start_time.to_i + 0.75) * 1_000_000_000 # 0.75s in the future
            @api.add(data)
            sleep 0.65 # Allow the threads to run
            # We expect 5 messages because total time is 2.25s and we get a packet at 1, 2, then one more plus empty
            expect(@messages.length).to eq(3)
            expect(@messages[-1]).to eq([]) # empty message to say we're done
            logged = @api.instance_variable_get('@logged_threads')
            expect(@api.instance_variable_get('@logged_threads').length).to eq(0)
          end
        end

        context 'logging only' do
          it 'has past start time and past end time' do
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 2.5)
            data['start_time'] = @time.to_i * 1_000_000_000 # 2.5s in the past
            data['end_time'] = (@start_time.to_i - 0.25) * 1_000_000_000 # 0.25s in the past
            @api.add(data)
            sleep 0.65 # Allow the threads to run
            # We expect 3 messages because total time is 2.25s and we get a packet at 1, 2, then one more plus empty
            expect(@messages.length).to eq(3)
            expect(@messages[-1]).to eq([]) # empty message to say we're done
          end

          it 'has past start time and past end time with limit' do
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            # Construct a valid redis message ID which is used to calculate the offset
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            # Reduce send_count to 1 so we only get 1 packet
            # This simulates a command log which isn't going to constantly spit out packets to force the final processing
            # The streaming api logic must determine we've waited long enough and stop the stream
            @send_count = 1
            @time = Time.at(@start_time.to_i - 2.5)
            data['start_time'] = @time.to_i * 1_000_000_000 # 2.5s in the past
            data['end_time'] = (@start_time.to_i - 0.25) * 1_000_000_000 # 0.25s in the past
            @api.add(data)
            sleep 0.65 # Allow the threads to run
            # We expect 2 messages because we get a packet at 1 plus empty
            expect(@messages.length).to eq(2)
            expect(@messages[-1]).to eq([]) # empty message to say we're done
          end
        end

        context 'from files' do
          before(:each) do
            # Reset the class variable to prevent leaking between tests
            OpenC3::QuestDBClient.disconnect
            # Mock get_tlm_available since the TargetModel isn't populated in mock redis
            allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) do |_instance, items, **_kwargs|
              items.map { |item| item.gsub('CONVERTED', 'RAW') }
            end
          end

          after(:each) do
            # Clean up the class variable after each test
            OpenC3::QuestDBClient.disconnect
          end

          it 'has start time and end time within the file time range' do
            mock_conn = instance_double(PG::Connection)
            allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
            # Data format: each row is array of [column_name, value] pairs
            # Query selects item columns plus timestamp as last column
            pg_data = [ [["PACKET_TIMESECONDS", @file_start_time], ["VALUE1", 10]] ]
            pg_data.define_singleton_method(:ntuples) do
              return 1
            end
            $exec_cnt = 0
            allow(mock_conn).to receive(:exec) do
              $exec_cnt += 1
              result = nil
              if $exec_cnt == 1
                result = pg_data
              end
              result
            end
            # Return non-TypeMapAllStrings so it doesn't try to set the type map
            allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

            msg1 = { 'time' => @start_time.to_i * 1_000_000_000 } # newest is now
            allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 1.5)
            data['start_time'] = @file_start_time # make it hit the files
            data['end_time'] = @file_start_time + 1000 # 1 ms after the beginning of the file so it only has one message to read
            @api.add(data)
            sleep 1.65 # Allow the threads to run (files need a long time)
            # We expect 2 messages, the one from the file and the empty one
            expect(@messages.length).to eq(2)
            expect(@messages[-1]).to eq([]) # empty message to say we're done
          end

          it 'has start time within the file time range and end time after the file' do
            mock_conn = instance_double(PG::Connection)
            allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
            # Data format: each row is array of [column_name, value] pairs
            # Multiple rows with timestamp values spread across file time range
            base_time = @file_start_time / 1_000_000_000
            pg_data = [
              [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1", 10]],
              [["PACKET_TIMESECONDS", (base_time + 100) * 1_000_000_000], ["VALUE1", 20]],
              [["PACKET_TIMESECONDS", (base_time + 200) * 1_000_000_000], ["VALUE1", 30]],
              [["PACKET_TIMESECONDS", (base_time + 300) * 1_000_000_000], ["VALUE1", 40]],
              [["PACKET_TIMESECONDS", (base_time + 400) * 1_000_000_000], ["VALUE1", 50]],
              [["PACKET_TIMESECONDS", (base_time + 500) * 1_000_000_000], ["VALUE1", 60]],
              [["PACKET_TIMESECONDS", (base_time + 600) * 1_000_000_000], ["VALUE1", 70]]
            ]
            pg_data.define_singleton_method(:ntuples) do
              return 7
            end
            $exec_cnt = 0
            allow(mock_conn).to receive(:exec) do
              $exec_cnt += 1
              result = nil
              if $exec_cnt == 1
                result = pg_data
              end
              result
            end
            # Return non-TypeMapAllStrings so it doesn't try to set the type map
            allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

            msg1 = { 'time' => @start_time.to_i * 1_000_000_000 } # newest is now
            allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 1.5)
            data['start_time'] = @file_start_time # make it hit the files
            data['end_time'] = @start_time.to_i * 1_000_000_000 # now
            @api.add(data)
            sleep 2.65 # Allow the threads to run (files need a long time)
            # We expect 2 messages: 1 batch with all 7 DB rows, and the empty completion message
            # (DB rows are batched into a single message, not sent individually)
            expect(@messages.length).to eq(2)
            expect(@messages[0].length).to eq(7) # First message should have 7 items from DB
            expect(@messages[-1]).to eq([]) # empty message to say we're done
          end
        end
      end
    end
  end

  context 'streaming array-indexed items from TSDB' do
    before(:each) do
      OpenC3::QuestDBClient.disconnect
      # Mock get_tlm_available to resolve CONVERTED -> RAW (as real API does for arrays)
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) do |_instance, items, **_kwargs|
        items.map { |item| item.gsub('CONVERTED', 'RAW') }
      end
      # Mock packet definition with array item
      allow(OpenC3::TargetModel).to receive(:packet).with('INST', 'PARAMS', type: :TLM, scope: 'DEFAULT').and_return({
        'items' => [
          { 'name' => 'VALUE1', 'data_type' => 'FLOAT', 'array_size' => nil },
          { 'name' => 'ARY', 'data_type' => 'FLOAT', 'array_size' => 64, 'read_conversion' => nil, 'states' => nil },
        ]
      })
    end

    after(:each) do
      OpenC3::QuestDBClient.disconnect
    end

    it 'extracts single array element ARY[0] from TSDB' do
      mock_conn = instance_double(PG::Connection)
      allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
      allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

      # DB returns the ARY column as a JSON array string (how QuestDB stores arrays)
      pg_data = [
        [["ARY", "[1.0, 2.0, 3.0]"], ["PACKET_TIMESECONDS", @file_start_time]]
      ]
      pg_data.define_singleton_method(:ntuples) { 1 }

      $exec_cnt = 0
      allow(mock_conn).to receive(:exec) do
        $exec_cnt += 1
        $exec_cnt == 1 ? pg_data : nil
      end

      msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
      allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

      data = { 'items' => ['DECOM__TLM__INST__PARAMS__ARY[0]__CONVERTED'], 'scope' => 'DEFAULT' }
      data['start_time'] = @file_start_time
      data['end_time'] = @file_start_time + 1000
      @api.add(data)
      sleep 1.65

      expect(@messages.length).to eq(2)
      expect(@messages[-1]).to eq([])

      first_entry = @messages[0][0]
      expect(first_entry['__type']).to eq('ITEMS')
      # The value should be the extracted element, not the full array
      item_key = 'DECOM__TLM__INST__PARAMS__ARY[0]__CONVERTED'
      expect(first_entry[item_key]).to eq(1.0)
    end

    it 'extracts different array indices from same array item' do
      mock_conn = instance_double(PG::Connection)
      allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
      allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

      # DB returns two ARY columns (one per requested index) both with same JSON array
      pg_data = [
        [["ARY", "[10.0, 20.0, 30.0]"], ["ARY", "[10.0, 20.0, 30.0]"], ["PACKET_TIMESECONDS", @file_start_time]]
      ]
      pg_data.define_singleton_method(:ntuples) { 1 }

      $exec_cnt = 0
      allow(mock_conn).to receive(:exec) do
        $exec_cnt += 1
        $exec_cnt == 1 ? pg_data : nil
      end

      msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
      allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

      data = { 'items' => [
        'DECOM__TLM__INST__PARAMS__ARY[0]__CONVERTED',
        'DECOM__TLM__INST__PARAMS__ARY[2]__CONVERTED',
      ], 'scope' => 'DEFAULT' }
      data['start_time'] = @file_start_time
      data['end_time'] = @file_start_time + 1000
      @api.add(data)
      sleep 1.65

      expect(@messages.length).to eq(2)
      expect(@messages[-1]).to eq([])

      first_entry = @messages[0][0]
      expect(first_entry['DECOM__TLM__INST__PARAMS__ARY[0]__CONVERTED']).to eq(10.0)
      expect(first_entry['DECOM__TLM__INST__PARAMS__ARY[2]__CONVERTED']).to eq(30.0)
    end

    it 'handles mixed array-indexed and scalar items' do
      mock_conn = instance_double(PG::Connection)
      allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
      allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

      pg_data = [
        [["VALUE1", 42.0], ["ARY", "[5.0, 6.0, 7.0]"], ["PACKET_TIMESECONDS", @file_start_time]]
      ]
      pg_data.define_singleton_method(:ntuples) { 1 }

      $exec_cnt = 0
      allow(mock_conn).to receive(:exec) do
        $exec_cnt += 1
        $exec_cnt == 1 ? pg_data : nil
      end

      msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
      allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

      data = { 'items' => [
        'DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED',
        'DECOM__TLM__INST__PARAMS__ARY[1]__CONVERTED',
      ], 'scope' => 'DEFAULT' }
      data['start_time'] = @file_start_time
      data['end_time'] = @file_start_time + 1000
      @api.add(data)
      sleep 1.65

      expect(@messages.length).to eq(2)
      expect(@messages[-1]).to eq([])

      first_entry = @messages[0][0]
      expect(first_entry['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED']).to eq(42.0)
      expect(first_entry['DECOM__TLM__INST__PARAMS__ARY[1]__CONVERTED']).to eq(6.0)
    end
  end

  context 'streaming packets' do
    before(:each) do
      # Reset the class variable to prevent leaking between tests
      OpenC3::QuestDBClient.disconnect
    end

    after(:each) do
      # Clean up the class variable after each test
      OpenC3::QuestDBClient.disconnect
    end

    context 'for packets in raw mode (from files)' do
      let(:data) { { 'packets' => ['RAW__TLM__INST__PARAMS'], 'scope' => 'DEFAULT' } }

      it 'streams raw packets from log files' do
        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 } # newest is now
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        data['start_time'] = @file_start_time
        data['end_time'] = @file_start_time + 1_000_000_000 # 1 second of data
        @api.add(data)
        sleep 2.5 # Allow the threads to run (files need a long time)

        # Should have received packet messages plus the empty completion message
        expect(@messages.length).to be >= 2
        expect(@messages[-1]).to eq([]) # empty message to say we're done

        # Verify packet format - raw packets have buffer field
        first_packet = @messages[0][0]
        expect(first_packet['__type']).to eq('PACKET')
        expect(first_packet['__packet']).to eq('RAW__TLM__INST__PARAMS')
        expect(first_packet['buffer']).to_not be_nil
        expect(first_packet['__time']).to_not be_nil
      end

      it 'streams all raw packets within time range' do
        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        data['start_time'] = @file_start_time
        data['end_time'] = @file_end_time
        @api.add(data)
        sleep 3.5 # Allow time for full file read

        expect(@messages.length).to be >= 2
        expect(@messages[-1]).to eq([])

        # Count total packets received (excluding empty completion message)
        total_packets = @messages[0..-2].sum { |batch| batch.length }
        expect(total_packets).to be > 0
      end
    end

    context 'for packets in decom mode (from TSDB)' do
      let(:data) { { 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'], 'scope' => 'DEFAULT' } }

      it 'streams decom packets from TSDB' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        # Return non-TypeMapAllStrings so it doesn't try to set the type map
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Mock data with all packet columns - including __C suffix for CONVERTED values
        # Include __pkt_time_ns and __rx_time_ns columns from CAST(timestamp_ns AS LONG) in query
        pg_data = [
          [["PACKET_TIMESECONDS", Time.at(base_time)], ["tag", "test"], ["VALUE1", 100], ["VALUE1__C", 10.5], ["VALUE2", 200], ["VALUE2__C", 20.5], ["__pkt_time_ns", @file_start_time], ["__rx_time_ns", @file_start_time]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do
          $exec_cnt += 1
          $exec_cnt == 1 ? pg_data : nil
        end

        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        data['start_time'] = @file_start_time
        data['end_time'] = @file_start_time + 1_000_000_000 # 1 second of data
        @api.add(data)
        sleep 1.5 # Allow the threads to run

        expect(@messages.length).to eq(2)
        expect(@messages[-1]).to eq([])

        # Verify packet format - decom packets have item values
        first_packet = @messages[0][0]
        expect(first_packet['__type']).to eq('PACKET')
        expect(first_packet['__packet']).to eq('DECOM__TLM__INST__PARAMS__CONVERTED')
        expect(first_packet['__time']).to_not be_nil
        # Decom packets should have converted values (from __C columns)
        expect(first_packet['VALUE1']).to eq(10.5)
        expect(first_packet['VALUE2']).to eq(20.5)
        # Should NOT have buffer field
        expect(first_packet['buffer']).to be_nil
      end

      it 'streams all decom packets within time range' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Multiple packets with different timestamps
        # Include __pkt_time_ns and __rx_time_ns columns from CAST(timestamp_ns AS LONG) in query
        pg_data = [
          [["PACKET_TIMESECONDS", Time.at(base_time)], ["tag", "test"], ["VALUE1", 100], ["VALUE1__C", 10.0], ["__pkt_time_ns", @file_start_time], ["__rx_time_ns", @file_start_time]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 100)], ["tag", "test"], ["VALUE1", 200], ["VALUE1__C", 20.0], ["__pkt_time_ns", @file_start_time + 100_000_000_000], ["__rx_time_ns", @file_start_time + 100_000_000_000]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 200)], ["tag", "test"], ["VALUE1", 300], ["VALUE1__C", 30.0], ["__pkt_time_ns", @file_start_time + 200_000_000_000], ["__rx_time_ns", @file_start_time + 200_000_000_000]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 300)], ["tag", "test"], ["VALUE1", 400], ["VALUE1__C", 40.0], ["__pkt_time_ns", @file_start_time + 300_000_000_000], ["__rx_time_ns", @file_start_time + 300_000_000_000]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 400)], ["tag", "test"], ["VALUE1", 500], ["VALUE1__C", 50.0], ["__pkt_time_ns", @file_start_time + 400_000_000_000], ["__rx_time_ns", @file_start_time + 400_000_000_000]]
        ]
        pg_data.define_singleton_method(:ntuples) { 5 }

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do
          $exec_cnt += 1
          $exec_cnt == 1 ? pg_data : nil
        end

        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        data['start_time'] = @file_start_time
        data['end_time'] = @file_end_time
        @api.add(data)
        sleep 1.5 # Allow time for DB query

        expect(@messages.length).to eq(2) # One batch + empty completion
        expect(@messages[-1]).to eq([])

        # Count total packets received (excluding empty completion message)
        total_packets = @messages[0..-2].sum { |batch| batch.length }
        expect(total_packets).to eq(5)
      end
    end

    context 'for packets in decom mode with missing TSDB tables' do
      let(:data) { { 'packets' => ['DECOM__TLM__INST__HEALTH_STATUS__CONVERTED', 'DECOM__TLM__INST__PARAMS__CONVERTED'], 'scope' => 'DEFAULT' } }

      before(:each) do
        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])
      end

      it 'only queries tables that exist' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)
        # Only PARAMS has ever been received so HEALTH_STATUS has no table
        allow(OpenC3::QuestDBClient).to receive(:table_names).and_return(Set['DEFAULT__TLM__INST__PARAMS'])

        base_time = @file_start_time / 1_000_000_000
        pg_data = [
          [["PACKET_TIMESECONDS", Time.at(base_time)], ["VALUE1", 100], ["VALUE1__C", 10.5], ["__pkt_time_ns", @file_start_time], ["__rx_time_ns", @file_start_time]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        queries = []
        allow(mock_conn).to receive(:exec) do |query|
          queries << query
          queries.length == 1 ? pg_data : nil
        end

        data['start_time'] = @file_start_time
        data['end_time'] = @file_start_time + 1_000_000_000
        @api.add(data)
        sleep 1.5 # Allow the threads to run

        expect(queries).to_not be_empty
        expect(queries.none? { |query| query.include?('HEALTH_STATUS') }).to be true
        expect(@messages.length).to eq(2)
        expect(@messages[0][0]['__packet']).to eq('DECOM__TLM__INST__PARAMS__CONVERTED')
        expect(@messages[-1]).to eq([])
      end

      it 'completes without querying when no tables exist' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(OpenC3::QuestDBClient).to receive(:table_names).and_return(Set.new)
        expect(mock_conn).to_not receive(:exec)

        data['start_time'] = @file_start_time
        data['end_time'] = @file_start_time + 1_000_000_000
        @api.add(data)
        sleep 1.5 # Allow the threads to run

        expect(@messages).to eq([[]])
      end
    end

    context 'for reduced items (aggregated from TSDB)' do
      let(:data) { { 'items' => ['REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG'], 'scope' => 'DEFAULT' } }

      # Mock result for the SHOW COLUMNS query that CONVERTED reduced queries issue to
      # determine which columns exist. Responds to #values like a PG::Result, returning
      # rows of [column_name, type, ...]. VALUE1__C is numeric so aggregation uses it.
      def reduced_columns_result
        rows = [
          ["PACKET_TIMESECONDS", "TIMESTAMP"],
          ["VALUE1", "INT"],
          ["VALUE1__C", "DOUBLE"],
        ]
        rows.define_singleton_method(:values) { self }
        rows
      end

      before(:each) do
        # Mock get_tlm_available since the TargetModel isn't populated in mock redis
        allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) do |_instance, items, **_kwargs|
          items.map { |item| item.gsub('CONVERTED', 'RAW') }
        end
      end

      it 'streams reduced minute data using SAMPLE BY' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Mock aggregated data with min, max, avg, stddev columns
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 5.0], ["VALUE1__CX", 15.0], ["VALUE1__CA", 10.0], ["VALUE1__CS", 2.5]],
          [["PACKET_TIMESECONDS", (base_time + 60) * 1_000_000_000], ["VALUE1__CN", 8.0], ["VALUE1__CX", 22.0], ["VALUE1__CA", 15.0], ["VALUE1__CS", 3.5]]
        ]
        pg_data.define_singleton_method(:ntuples) { 2 }

        # CONVERTED reduced queries first issue a SHOW COLUMNS query to determine which
        # columns exist. Return a numeric VALUE1__C so the aggregation uses the __C column.
        columns_data = reduced_columns_result

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
          next columns_data if query.include?('SHOW COLUMNS')

          $exec_cnt += 1
          # Verify the query uses SAMPLE BY
          expect(query).to include('SAMPLE BY 1m') if $exec_cnt == 1
          expect(query).to include('ALIGN TO CALENDAR') if $exec_cnt == 1
          $exec_cnt == 1 ? pg_data : nil
        end

        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        data['start_time'] = @file_start_time
        data['end_time'] = @file_start_time + 120_000_000_000 # 2 minutes of data
        @api.add(data)
        sleep 1.5 # Allow the threads to run

        expect(@messages.length).to eq(2) # One batch + empty completion
        expect(@messages[-1]).to eq([])

        # Verify first message contains aggregated data
        first_entry = @messages[0][0]
        expect(first_entry['__type']).to eq('ITEMS')
        expect(first_entry['__time']).to_not be_nil
      end

      it 'streams reduced hour data using SAMPLE BY 1h' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 1.0], ["VALUE1__CX", 100.0], ["VALUE1__CA", 50.0], ["VALUE1__CS", 25.0]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        columns_data = reduced_columns_result

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
          next columns_data if query.include?('SHOW COLUMNS')

          $exec_cnt += 1
          expect(query).to include('SAMPLE BY 1h') if $exec_cnt == 1
          $exec_cnt == 1 ? pg_data : nil
        end

        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        hour_data = { 'items' => ['REDUCED_HOUR__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG'], 'scope' => 'DEFAULT' }
        hour_data['start_time'] = @file_start_time
        hour_data['end_time'] = @file_start_time + 3600_000_000_000 # 1 hour of data
        @api.add(hour_data)
        sleep 1.5

        expect(@messages.length).to eq(2)
        expect(@messages[-1]).to eq([])
      end

      it 'streams reduced day data using SAMPLE BY 1d' do
        mock_conn = instance_double(PG::Connection)
        allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 0.0], ["VALUE1__CX", 1000.0], ["VALUE1__CA", 500.0], ["VALUE1__CS", 250.0]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        columns_data = reduced_columns_result

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
          next columns_data if query.include?('SHOW COLUMNS')

          $exec_cnt += 1
          expect(query).to include('SAMPLE BY 1d') if $exec_cnt == 1
          $exec_cnt == 1 ? pg_data : nil
        end

        msg1 = { 'time' => @start_time.to_i * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
        msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

        day_data = { 'items' => ['REDUCED_DAY__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG'], 'scope' => 'DEFAULT' }
        day_data['start_time'] = @file_start_time
        day_data['end_time'] = @file_start_time + 86400_000_000_000 # 1 day of data
        @api.add(day_data)
        sleep 1.5

        expect(@messages.length).to eq(2)
        expect(@messages[-1]).to eq([])
      end
    end
  end

  context 'multiple db_shards' do
    # INST lives on db_shard 1. The db_shard 0 EphemeralStore stubbed above
    # returns no messages so anything streamed must come from db_shard 1.
    before(:each) do
      @send_count = 0
      OpenC3::TargetModel.new(name: 'INST', scope: 'DEFAULT', db_shard: 1).create
    end

    it 'streams realtime items from the target db_shard' do
      @api.add({ 'items' => ['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED'], 'scope' => 'DEFAULT' })
      sleep 0.2 # Allow the thread to start
      time = Time.now.to_nsec_from_epoch
      OpenC3::EphemeralStore.instance(db_shard: 1).write_topic('DEFAULT__DECOM__{INST}__PARAMS',
        { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => time, 'json_data' => JSON.generate({ 'VALUE1' => 5 }) })
      start = Time.now
      sleep 0.05 while @messages.empty? and (Time.now - start) < 3
      expect(@messages[0][0]['DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED']).to eq(5)
    end

    it 'streams decom packets from the target db_shard TSDB' do
      # Only the db_shard 1 connection has data
      db_shard0_conn = instance_double(PG::Connection)
      allow(db_shard0_conn).to receive(:type_map_for_results).and_return(Object.new)
      allow(db_shard0_conn).to receive(:exec).and_return(nil)
      db_shard1_conn = instance_double(PG::Connection)
      allow(db_shard1_conn).to receive(:type_map_for_results).and_return(Object.new)
      pg_data = [
        [["PACKET_TIMESECONDS", Time.at(@file_start_time / 1_000_000_000)], ["VALUE1", 100], ["VALUE1__C", 10.5], ["__pkt_time_ns", @file_start_time], ["__rx_time_ns", @file_start_time]]
      ]
      pg_data.define_singleton_method(:ntuples) { 1 }
      exec_cnt = 0
      allow(db_shard1_conn).to receive(:exec) do
        exec_cnt += 1
        exec_cnt == 1 ? pg_data : nil
      end
      allow(OpenC3::QuestDBClient).to receive(:connection) { |db_shard: 0| db_shard == 1 ? db_shard1_conn : db_shard0_conn }

      @api.add({ 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'], 'scope' => 'DEFAULT',
        'start_time' => @file_start_time, 'end_time' => @file_start_time + 1_000_000_000 })
      sleep 1.5 # Allow the threads to run

      expect(@messages.length).to eq(2)
      expect(@messages[0][0]['__packet']).to eq('DECOM__TLM__INST__PARAMS__CONVERTED')
      expect(@messages[0][0]['VALUE1']).to eq(10.5)
      expect(@messages[-1]).to eq([])
    end
  end

  context 'time_type' do
    let(:item_key) { 'DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED' }

    it 'rejects an unknown time_type' do
      expect { @api.add({ 'items' => [item_key], 'scope' => 'DEFAULT', 'time_type' => 'BOGUS' }) }.to raise_error(ArgumentError, /Unknown time_type: BOGUS/)
    end

    it 'defaults to PACKET and accepts RECEIVED in any case' do
      expect(StreamingObject.parse_time_type(nil)).to eq(:PACKET)
      expect(StreamingObject.parse_time_type('')).to eq(:PACKET)
      expect(StreamingObject.parse_time_type('received')).to eq(:RECEIVED)
    end

    it 'rejects RECEIVED for historical RAW packets which come from packet time ordered files' do
      data = { 'packets' => ['RAW__TLM__INST__PARAMS'], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED',
        'start_time' => @file_start_time, 'end_time' => @file_start_time + 1_000_000_000 }
      expect { @api.add(data) }.to raise_error(ArgumentError, /not supported for historical RAW/)
    end

    it 'returns the received time as __time when streaming realtime' do
      packet_time = (@start_time.to_i - 86_400) * 1_000_000_000 # Simulator a day behind
      received_time = @start_time.to_i * 1_000_000_000
      msg = { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => packet_time, 'received_time' => received_time,
        'json_data' => JSON.generate({ 'VALUE1' => 5 }) }
      sent = false
      allow(OpenC3::EphemeralStore.instance).to receive(:read_topics) do |topics, &block|
        sleep 0.1
        unless sent
          sent = true
          block.call(topics[0], "#{@start_time.to_i * 1000}-0", msg, nil)
        end
        {}
      end

      @api.add({ 'items' => [item_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
      start = Time.now
      sleep 0.05 while @messages.empty? and (Time.now - start) < 3
      expect(@messages[0][0]['__time']).to eq(received_time)
      expect(@messages[0][0][item_key]).to eq(5)
    end

    it 'groups realtime items with different time types into separate entries' do
      msg = { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => 100, 'received_time' => 200,
        'json_data' => JSON.generate({ 'VALUE1' => 5 }) }
      # Deliver once, after both subscriptions exist, so the first read can't
      # publish only the PACKET entry and block the RECEIVED one
      ready = false
      sent = false
      allow(OpenC3::EphemeralStore.instance).to receive(:read_topics) do |topics, &block|
        sleep 0.1
        if ready and not sent
          sent = true
          block.call(topics[0], "1-0", msg, nil)
        end
        {}
      end
      @api.add({ 'items' => [[item_key, 'PKT']], 'scope' => 'DEFAULT' })
      @api.add({ 'items' => [[item_key, 'RX']], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
      ready = true
      start = Time.now
      sleep 0.05 while @messages.empty? and (Time.now - start) < 3
      entries = @messages.flatten
      expect(entries).to include(a_hash_including('__time' => 100, 'PKT' => 5))
      expect(entries).to include(a_hash_including('__time' => 200, 'RX' => 5))
    end

    it 'keeps PACKET ids unchanged and prefixes other time types' do
      packet = StreamingObject.new(item_key, nil, nil, item_key: item_key, scope: 'DEFAULT')
      received = StreamingObject.new(item_key, nil, nil, item_key: item_key, scope: 'DEFAULT', time_type: :RECEIVED)
      expect(packet.id).to eq("ITEM__#{item_key}__#{item_key}__#{item_key}")
      expect(received.id).to eq("RECEIVED__#{packet.id}")
    end

    context 'subscribing to the same item with both time types' do
      def realtime_ids
        @api.instance_variable_get(:@realtime_thread).instance_variable_get(:@collection).objects.map(&:id).sort
      end

      before(:each) do
        msg = { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => 100, 'received_time' => 200,
          'json_data' => JSON.generate({ 'VALUE1' => 5 }) }
        # Deliver once, after both subscriptions exist
        ready = false
        sent = false
        allow(OpenC3::EphemeralStore.instance).to receive(:read_topics) do |topics, &block|
          sleep 0.1
          if ready and not sent
            sent = true
            block.call(topics[0], "1-0", msg, nil)
          end
          {}
        end
        @api.add({ 'items' => [item_key], 'scope' => 'DEFAULT' })
        @api.add({ 'items' => [item_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
        ready = true
      end

      it 'streams both instead of dropping the second' do
        start = Time.now
        sleep 0.05 while @messages.empty? and (Time.now - start) < 3
        entries = @messages.flatten
        expect(entries).to include(a_hash_including('__time' => 100, item_key => 5))
        expect(entries).to include(a_hash_including('__time' => 200, item_key => 5))
      end

      it 'removes only the given time_type' do
        @api.remove({ 'items' => [item_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
        expect(realtime_ids).to eq(["ITEM__#{item_key}__#{item_key}__#{item_key}"])
      end

      it 'removes every time_type when none is given' do
        # Capture the collection first: the emptied thread completes and clears @realtime_thread
        collection = @api.instance_variable_get(:@realtime_thread).instance_variable_get(:@collection)
        @api.remove({ 'items' => [item_key], 'scope' => 'DEFAULT' })
        expect(collection.objects).to be_empty
      end

      it 'removes a packet subscription by time_type' do
        packet_key = 'DECOM__TLM__INST__PARAMS__CONVERTED'
        @api.add({ 'packets' => [packet_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
        @api.add({ 'packets' => [packet_key], 'scope' => 'DEFAULT' })
        @api.remove({ 'packets' => [packet_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED' })
        expect(realtime_ids).to include("PACKET__#{packet_key}")
        expect(realtime_ids).to_not include("RECEIVED__PACKET__#{packet_key}")
      end
    end

    describe 'LoggedStreamingThread setup' do
      # Packet times a day in the future, as from a simulator, received over the last 100s
      let(:oldest_msg) { { 'time' => (@start_time.to_i + 86_400) * 1_000_000_000, 'received_time' => (@start_time.to_i - 100) * 1_000_000_000 } }

      def setup_thread(time_type)
        allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", oldest_msg])
        collection = StreamingObjectCollection.new
        collection.add(StreamingObject.new(item_key, (@start_time.to_i - 50) * 1_000_000_000, nil, item_key: item_key, scope: 'DEFAULT', time_type: time_type))
        thread = LoggedStreamingThread.new(@api, collection, scope: 'DEFAULT', token: nil)
        thread.setup_thread_body(collection.objects)
        [thread, collection]
      end

      def setup_mode(time_type)
        thread, collection = setup_thread(time_type)
        [thread.instance_variable_get(:@thread_mode), collection.objects[0].offset]
      end

      it 'compares the start time against the oldest packet time for PACKET' do
        mode, _offset = setup_mode(:PACKET)
        expect(mode).to eq(:TSDB) # Start is before the oldest (future) packet time
      end

      it 'compares the start time against the oldest received time for RECEIVED' do
        mode, offset = setup_mode(:RECEIVED)
        expect(mode).to eq(:STREAM) # The received times in Redis cover the start
        # Backed off by the overlap buffer so variable write delay can't skip messages
        overlap_ms = LoggedStreamingThread::TSDB_STREAM_OVERLAP_NSEC / 1_000_000
        expect(offset).to eq("#{(@start_time.to_i - 50) * 1000 - overlap_ms}-0")
      end

      it 'skips the overlap messages before the start time' do
        thread, collection = setup_thread(:RECEIVED)
        start_nsec = (@start_time.to_i - 50) * 1_000_000_000
        msg = { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => 0, 'json_data' => JSON.generate({ 'VALUE1' => 5 }) }
        # Received just before the start but written to the stream after the estimated offset
        expect(thread.handle_message(msg.merge('received_time' => start_nsec - 1), collection.objects)).to be_nil
        expect(thread.handle_message(msg.merge('received_time' => start_nsec), collection.objects)).to include('__time' => start_nsec)
      end

      it 'still skips messages before the start time after handoff to realtime' do
        _thread, collection = setup_thread(:RECEIVED)
        start_nsec = (@start_time.to_i - 50) * 1_000_000_000
        realtime = RealtimeStreamingThread.new(@api, collection, scope: 'DEFAULT')
        msg = { 'target_name' => 'INST', 'packet_name' => 'PARAMS', 'time' => 0, 'json_data' => JSON.generate({ 'VALUE1' => 5 }) }
        expect(realtime.handle_message(msg.merge('received_time' => start_nsec - 1), collection.objects)).to be_nil
        expect(realtime.handle_message(msg.merge('received_time' => start_nsec), collection.objects)).to include('__time' => start_nsec)
      end
    end

    it 'queries TSDB items by received time and returns it as __time' do
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) { |_instance, items, **_kwargs| items }
      allow(OpenC3::TargetModel).to receive(:packet).and_return({ 'items' => [{ 'name' => 'VALUE1', 'data_type' => 'FLOAT', 'array_size' => nil }] })
      mock_conn = instance_double(PG::Connection)
      allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
      allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)
      received_time = @file_start_time + 500
      pg_data = [[["VALUE1__C", 1.5], ["PACKET_TIMESECONDS", @file_start_time - 86_400_000_000_000], ["__rx_time_ns", received_time], ["COSMOS_EXTRA", nil]]]
      pg_data.define_singleton_method(:ntuples) { 1 }
      queries = []
      allow(mock_conn).to receive(:exec) do |query|
        queries << query
        queries.length == 1 ? pg_data : nil
      end
      allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }])

      @api.add({ 'items' => [item_key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED',
        'start_time' => @file_start_time, 'end_time' => @file_start_time + 1000 })
      sleep 1.65

      expect(queries[0]).to include("WHERE RECEIVED_TIMESECONDS >= #{@file_start_time} AND RECEIVED_TIMESECONDS < #{@file_start_time + 1000}")
      expect(queries[0]).to include('ORDER BY RECEIVED_TIMESECONDS')
      expect(@messages[0][0]['__time']).to eq(received_time)
      expect(@messages[0][0][item_key]).to eq(1.5)
      expect(@messages[-1]).to eq([])
    end

    it 'samples reduced items by received time' do
      allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) { |_instance, items, **_kwargs| items }
      mock_conn = instance_double(PG::Connection)
      allow(OpenC3::QuestDBClient).to receive(:connection).and_return(mock_conn)
      allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)
      pg_data = [[["RECEIVED_TIMESECONDS", @file_start_time], ["VALUE1__A", 2.5]]]
      pg_data.define_singleton_method(:ntuples) { 1 }
      queries = []
      allow(mock_conn).to receive(:exec) do |query|
        queries << query
        queries.length == 1 ? pg_data : nil
      end
      allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", { 'time' => (@start_time.to_i - 100) * 1_000_000_000 }])

      key = 'REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__RAW__AVG'
      @api.add({ 'items' => [key], 'scope' => 'DEFAULT', 'time_type' => 'RECEIVED',
        'start_time' => @file_start_time, 'end_time' => @file_start_time + 120_000_000_000 })
      sleep 1.5

      expect(queries[0]).to start_with('SELECT CAST(RECEIVED_TIMESECONDS AS LONG) as RECEIVED_TIMESECONDS')
      expect(queries[0]).to include('timestamp(RECEIVED_TIMESECONDS) SAMPLE BY 1m')
      expect(@messages[0][0]['__time']).to eq(@file_start_time)
      expect(@messages[0][0][key]).to eq(2.5)
    end
  end
end
