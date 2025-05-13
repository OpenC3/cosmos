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
    msg['json_data'] = JSON.generate(packet_data)
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
      { 'description' => 'packets in decom mode', 'data' => { 'packets' => ['DECOM__TLM__INST__PARAMS__CONVERTED'] } },
      { 'description' => 'packets in raw mode', 'data' => { 'packets' => ['RAW__TLM__INST__PARAMS'] } },
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
          it 'has start time and end time within the file time range' do
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
            msg1 = { 'time' => @start_time.to_i * 1_000_000_000 } # newest is now
            allow(OpenC3::EphemeralStore.instance).to receive(:get_newest_message).and_return([nil, msg1])
            msg2 = { 'time' => (@start_time.to_i - 100) * 1_000_000_000 } # oldest is 100s ago
            allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return(["#{@start_time.to_i - 100}000-0", msg2])

            @time = Time.at(@start_time.to_i - 1.5)
            data['start_time'] = @file_start_time # make it hit the files
            data['end_time'] = @start_time.to_i * 1_000_000_000 # now
            @api.add(data)
            sleep 2.65 # Allow the threads to run (files need a long time)
            # We expect at least 9 messages: 7 from the fixture file, at least one from redis, and the empty one at the end
            expect(@messages.length).to be >= 9
            expect(@messages[-1]).to eq([]) # empty message to say we're done
          end
        end
      end
    end
  end
end
