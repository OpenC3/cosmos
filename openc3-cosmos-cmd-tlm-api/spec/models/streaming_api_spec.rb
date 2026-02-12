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
        allow(OpenC3::Logger).to receive(:info) do |msg|
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
            LoggedStreamingThread.class_variable_set(:@@conn, nil) if LoggedStreamingThread.class_variable_defined?(:@@conn)
            # Mock get_tlm_available since the TargetModel isn't populated in mock redis
            allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) do |_instance, items, **_kwargs|
              items.map { |item| item.gsub('CONVERTED', 'RAW') }
            end
          end

          after(:each) do
            # Clean up the class variable after each test
            LoggedStreamingThread.class_variable_set(:@@conn, nil) if LoggedStreamingThread.class_variable_defined?(:@@conn)
          end

          it 'has start time and end time within the file time range' do
            mock_conn = instance_double(PG::Connection)
            allow(PG::Connection).to receive(:new).and_return(mock_conn)
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
            allow(PG::Connection).to receive(:new).and_return(mock_conn)
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

  context 'streaming packets' do
    before(:each) do
      # Reset the class variable to prevent leaking between tests
      LoggedStreamingThread.class_variable_set(:@@conn, nil) if LoggedStreamingThread.class_variable_defined?(:@@conn)
    end

    after(:each) do
      # Clean up the class variable after each test
      LoggedStreamingThread.class_variable_set(:@@conn, nil) if LoggedStreamingThread.class_variable_defined?(:@@conn)
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
        allow(PG::Connection).to receive(:new).and_return(mock_conn)
        # Return non-TypeMapAllStrings so it doesn't try to set the type map
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Mock data with all packet columns - including __C suffix for CONVERTED values
        pg_data = [
          [["PACKET_TIMESECONDS", Time.at(base_time)], ["tag", "test"], ["VALUE1", 100], ["VALUE1__C", 10.5], ["VALUE2", 200], ["VALUE2__C", 20.5]]
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
        allow(PG::Connection).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Multiple packets with different timestamps
        pg_data = [
          [["PACKET_TIMESECONDS", Time.at(base_time)], ["tag", "test"], ["VALUE1", 100], ["VALUE1__C", 10.0]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 100)], ["tag", "test"], ["VALUE1", 200], ["VALUE1__C", 20.0]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 200)], ["tag", "test"], ["VALUE1", 300], ["VALUE1__C", 30.0]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 300)], ["tag", "test"], ["VALUE1", 400], ["VALUE1__C", 40.0]],
          [["PACKET_TIMESECONDS", Time.at(base_time + 400)], ["tag", "test"], ["VALUE1", 500], ["VALUE1__C", 50.0]]
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

    context 'for reduced items (aggregated from TSDB)' do
      let(:data) { { 'items' => ['REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG'], 'scope' => 'DEFAULT' } }

      before(:each) do
        # Mock get_tlm_available since the TargetModel isn't populated in mock redis
        allow_any_instance_of(OpenC3::LocalApi).to receive(:get_tlm_available) do |_instance, items, **_kwargs|
          items.map { |item| item.gsub('CONVERTED', 'RAW') }
        end
      end

      it 'streams reduced minute data using SAMPLE BY' do
        mock_conn = instance_double(PG::Connection)
        allow(PG::Connection).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        # Mock aggregated data with min, max, avg, stddev columns
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 5.0], ["VALUE1__CX", 15.0], ["VALUE1__CA", 10.0], ["VALUE1__CS", 2.5]],
          [["PACKET_TIMESECONDS", (base_time + 60) * 1_000_000_000], ["VALUE1__CN", 8.0], ["VALUE1__CX", 22.0], ["VALUE1__CA", 15.0], ["VALUE1__CS", 3.5]]
        ]
        pg_data.define_singleton_method(:ntuples) { 2 }

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
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
        expect(first_entry['__type']).to eq('items')
        expect(first_entry['__time']).to_not be_nil
      end

      it 'streams reduced hour data using SAMPLE BY 1h' do
        mock_conn = instance_double(PG::Connection)
        allow(PG::Connection).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 1.0], ["VALUE1__CX", 100.0], ["VALUE1__CA", 50.0], ["VALUE1__CS", 25.0]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
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
        allow(PG::Connection).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:type_map_for_results).and_return(Object.new)

        base_time = @file_start_time / 1_000_000_000
        pg_data = [
          [["PACKET_TIMESECONDS", base_time * 1_000_000_000], ["VALUE1__CN", 0.0], ["VALUE1__CX", 1000.0], ["VALUE1__CA", 500.0], ["VALUE1__CS", 250.0]]
        ]
        pg_data.define_singleton_method(:ntuples) { 1 }

        $exec_cnt = 0
        allow(mock_conn).to receive(:exec) do |query|
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
end
