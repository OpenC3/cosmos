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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

require 'spec_helper'
require 'fileutils'
require 'openc3/models/target_model'
require 'openc3/models/microservice_model'
require 'openc3/utilities/aws_bucket'
require 'openc3/utilities/s3_autoload'

module OpenC3
  AwsS3Client = 'Aws::S3::Client'

  describe TargetModel, type: :model do
    @fsys_s3 = false
    before(:all) do |example|
      # These tests work if there's a local S3 or a S3 (versitygw) service available. To enable
      # access to S3 (versitygw) for testing, change the compose.yaml services stanza to:
      #
      # services:
      #   openc3-buckets:
      #     ports:
      #       - "127.0.0.1:9000:9000"
      begin
        sock = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
        sock.bind(Socket.pack_sockaddr_in(9000, '127.0.0.1')) #raise if listening
        sock.close
        @fsys_s3 = true
        Logger.info("No S3 listener - using local_s3 client")
      rescue Errno::EADDRINUSE;
        Logger.info("Found listener on port 9000; presumably versitygw")
      end

    rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
      # We'll just skip them all if we get a networking error.
      example.skip e.message
    end

    before(:each) do
      mock_redis()
      #model = ScopeModel.new(name: "DEFAULT")
      #model.create
      local_s3() if @fsys_s3
      @bucket = Bucket.getClient.create("config")
    end

    after(:each) do
      Bucket.getClient.delete(@bucket) if @bucket
      local_s3_unset()
    end

    after(:all) do
      Bucket.getClient.delete(@bucket) if @bucket
      local_s3_unset()
    end

    describe "self.get" do
      it "returns the specified model" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST2", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        target = TargetModel.get(name: "TEST2", scope: "DEFAULT")
        expect(target["name"]).to eql "TEST2"
        expect(target["folder_name"]).to eql "TEST"
      end
    end

    describe "self.names" do
      it "returns all model names" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "OTHER", name: "OTHER", scope: "OTHER")
        model.create
        names = TargetModel.names(scope: "DEFAULT")
        # contain_exactly doesn't care about ordering and neither do we
        expect(names).to contain_exactly("TEST", "SPEC")
        names = TargetModel.names(scope: "OTHER")
        expect(names).to contain_exactly("OTHER")
      end
    end

    describe "self.all" do
      it "returns all the parsed targets" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        all_targs = TargetModel.all(scope: "DEFAULT")
        expect(all_targs).to_not be_nil
        expect(all_targs.keys).to contain_exactly("TEST", "SPEC")
      end
    end

    describe "render" do
      it "renders" do
        template = '_template.erb'
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        Dir.mktmpdir do |tmpdir|
          tf = File.open(File.join(tmpdir, template), 'w')
          tf.puts "CMD_LOG_CYCLE_TIME 1"
          tf.close
          rendered_result = model.render(File.expand_path(tf.path), {locals: {opt1: '1', opt2: '2', opt3: '3'}})
          expect(rendered_result.encode('ascii-8bit')).to eql("CMD_LOG_CYCLE_TIME 1\n") # because it's not rendering?
        end
      end
    end

    # self.all_modified & self.download aren't unit tested because it's basically just mocking the entire S3 API

    describe "self.all_modified" do
      it "returns all the modified targets" do
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        all_targs = TargetModel.all_modified(scope: "DEFAULT")
        expect(all_targs.keys).to contain_exactly("INST", "SPEC")
      end
    end

    describe "self.modified_files" do
      it "returns all the modified files" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        mods = TargetModel.modified_files('TEST', scope: "DEFAULT")
        expect(mods).to match_array([]) # return empty array when none modified
      end
    end

    describe "self.delete_modified" do
      it "returns all the deleted or modified whatnots" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        dels = TargetModel.delete_modified('TEST', scope: "DEFAULT")
        expect(dels).to match_array([] )# return empty array when none modified
      end
    end

    describe "self.download" do
      it "can download" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = TargetModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        t = TargetModel.download('TEST', scope: "DEFAULT")
        expect(t.filename).to eql('TEST.zip')
      end
    end

    describe "self.packets" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
        model = TargetModel.new(folder_name: "EMPTY", name: "EMPTY", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['EMPTY'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "can set packet" do
        pkts = TargetModel.packets("INST", type: :TLM, scope: "DEFAULT")
        TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        expect { TargetModel.set_packet('INST', 'ADCS', pkts[0], type: :TLM, scope: "DEFAULT") }
        .not_to raise_error
        expect { TargetModel.set_packet('INST', 'ADCS', pkts[0], type: :NILTYPE, scope: "DEFAULT") }
        .to raise_error(RuntimeError, /Unknown type NILTYPE for INST ADCS/)
      end

      it "calls limits_groups" do
         lgs = TargetModel.limits_groups(scope: 'DEFAULT')
         expect(lgs).to be_a(Hash)
      end

      it "gets item-to-packet map from cache" do
        orig_cache = TargetModel.class_variable_get(:@@item_map_cache).dup
        itpm = TargetModel.get_item_to_packet_map("INST", scope: "DEFAULT")
        expect(itpm).to be_a(Hash)
        expect(itpm["CCSDSVER"]).to be_a(Array)
        expect(itpm["CCSDSVER"]).to eql(%w(ADCS HEALTH_STATUS HIDDEN IMAGE MECH PARAMS))
        # Verify cached time was NOT updated
        cache = TargetModel.class_variable_get(:@@item_map_cache)
        expect(cache["INST"][0]).to eq(orig_cache["INST"][0])
      end

      it "gets item-to-packet map on an invalid cache" do
        orig_cache = TargetModel.class_variable_get(:@@item_map_cache).dup
        timeout = TargetModel::ITEM_MAP_CACHE_TIMEOUT
        OpenC3.disable_warnings do
          TargetModel::ITEM_MAP_CACHE_TIMEOUT = 0
        end
        itpm = TargetModel.get_item_to_packet_map("INST", scope: "DEFAULT")
        expect(itpm).to be_a(Hash)
        expect(itpm["CCSDSVER"]).to be_a(Array)
        expect(itpm["CCSDSVER"]).to eql(%w(ADCS HEALTH_STATUS HIDDEN IMAGE MECH PARAMS))
        # Verify cached time was updated
        cache = TargetModel.class_variable_get(:@@item_map_cache)
        expect(cache["INST"][0]).to be > orig_cache["INST"][0]
        OpenC3.disable_warnings do
          TargetModel::ITEM_MAP_CACHE_TIMEOUT = timeout
        end
      end

      it "raises for an unknown type" do
        expect { TargetModel.packets("INST", type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type OTHER/)
      end

      it "raises for a non-existent target" do
        expect { TargetModel.packets("BLAH", scope: "DEFAULT") }.to raise_error("Target 'BLAH' does not exist for scope: DEFAULT")
      end

      it "returns all telemetry packets" do
        pkts = TargetModel.packets("INST", type: :TLM, scope: "DEFAULT")
        # Verify result is Array of packet Hashes
        expect(pkts).to be_a Array
        names = []
        pkts.each do |pkt|
          expect(pkt).to be_a Hash
          expect(pkt['target_name']).to eql "INST"
          names << pkt['packet_name']
        end
        expect(names).to include("ADCS", "HEALTH_STATUS", "PARAMS", "IMAGE", "MECH")
      end

      it "returns empty array for no telemetry packets" do
        pkts = TargetModel.packets("EMPTY", type: :TLM, scope: "DEFAULT")
        # Verify result is Array of packet Hashes
        expect(pkts).to be_a Array
        expect(pkts).to be_empty
      end

      it "returns packet hash if the command exists" do
        pkts = TargetModel.packets("INST", type: :CMD, scope: "DEFAULT")
        expect(pkts).to be_a Array
        names = []
        pkts.each do |pkt|
          expect(pkt).to be_a Hash
          expect(pkt['target_name']).to eql "INST"
          expect(pkt['items']).to be_a Array
          names << pkt['packet_name']
        end
        expect(names).to include("ABORT", "COLLECT", "CLEAR") # Spot check
      end

      it "returns empty array for no command packets" do
        pkts = TargetModel.packets("EMPTY", type: :CMD, scope: "DEFAULT")
        # Verify result is Array of packet Hashes
        expect(pkts).to be_a Array
        expect(pkts).to be_empty
      end
    end

    describe "self.all_packet_name_descriptions" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
        model = TargetModel.new(folder_name: "EMPTY", name: "EMPTY", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['EMPTY'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "returns only the packet_name and description" do
        pkts = TargetModel.all_packet_name_descriptions("INST", type: :TLM, scope: "DEFAULT")
        # Verify result is Array of packet Hashes
        expect(pkts).to be_a Array
        pkts.each do |pkt|
          expect(pkt).to be_a Hash
          expect(pkt.keys).to eql(%w(packet_name description))
        end
      end
    end

    describe "self.packet" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "raises for an unknown type" do
        expect { TargetModel.packet("INST", "HEALTH_STATUS", type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type OTHER/)
      end

      it "raises for a non-existent target" do
        expect { TargetModel.packet("BLAH", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT") }.to raise_error("Packet 'BLAH HEALTH_STATUS' does not exist")
      end

      it "raises for a non-existent packet" do
        expect { TargetModel.packet("INST", "BLAH", type: :TLM, scope: "DEFAULT") }.to raise_error("Packet 'INST BLAH' does not exist")
      end

      it "returns packet hash if the telemetry exists" do
        pkt = TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")
        expect(pkt['target_name']).to eql "INST"
        expect(pkt['packet_name']).to eql "HEALTH_STATUS"
      end

      it "returns packet hash if the command exists" do
        pkt = TargetModel.packet("INST", "ABORT", type: :CMD, scope: "DEFAULT")
        expect(pkt['target_name']).to eql "INST"
        expect(pkt['packet_name']).to eql "ABORT"
      end

      it "caches packet lookups" do
        # Clear cache before test
        TargetModel.clear_packet_cache

        # First call should hit the Store
        expect(Store).to receive(:hget).once.and_call_original
        pkt1 = TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # Second call should hit cache and NOT call Store
        expect(Store).not_to receive(:hget)
        pkt2 = TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # Both packets should be equivalent
        expect(pkt1).to eql pkt2
      end

      it "expires cache after timeout" do
        # Clear cache before test
        TargetModel.clear_packet_cache

        # First call populates cache
        expect(Store).to receive(:hget).once.and_call_original
        TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # Set timeout to 0 to force expiration
        timeout = TargetModel::PACKET_CACHE_TIMEOUT
        OpenC3.disable_warnings do
          TargetModel::PACKET_CACHE_TIMEOUT = 0
        end

        # Next call should miss cache due to expiration and hit Store again
        expect(Store).to receive(:hget).once.and_call_original
        TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # Restore timeout
        OpenC3.disable_warnings do
          TargetModel::PACKET_CACHE_TIMEOUT = timeout
        end
      end

      it "invalidates cache on set_packet" do
        # Clear cache before test
        TargetModel.clear_packet_cache

        # Populate cache
        expect(Store).to receive(:hget).once.and_call_original
        pkt = TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # set_packet should invalidate the cache entry
        TargetModel.set_packet("INST", "HEALTH_STATUS", pkt, type: :TLM, scope: "DEFAULT")

        # Next get should miss cache and hit Store again
        expect(Store).to receive(:hget).once.and_call_original
        TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")
      end

      it "caches different packet types separately" do
        # Clear cache before test
        TargetModel.clear_packet_cache

        # Get telemetry packet - should hit Store
        expect(Store).to receive(:hget).with("DEFAULT__openc3tlm__INST", "HEALTH_STATUS").once.and_call_original
        tlm_pkt = TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")

        # Get command packet - should also hit Store (different cache key)
        expect(Store).to receive(:hget).with("DEFAULT__openc3cmd__INST", "ABORT").once.and_call_original
        cmd_pkt = TargetModel.packet("INST", "ABORT", type: :CMD, scope: "DEFAULT")

        # Verify they are different packets
        expect(tlm_pkt['packet_name']).to eql "HEALTH_STATUS"
        expect(cmd_pkt['packet_name']).to eql "ABORT"

        # Getting them again should NOT hit Store (cache hit)
        expect(Store).not_to receive(:hget)
        TargetModel.packet("INST", "HEALTH_STATUS", type: :TLM, scope: "DEFAULT")
        TargetModel.packet("INST", "ABORT", type: :CMD, scope: "DEFAULT")
      end
    end

    describe "self.packet_item" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "raises for an unknown type" do
        expect { TargetModel.packet_item("INST", "HEALTH_STATUS", "CCSDSVER", type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type OTHER/)
      end

      it "raises for a non-existent target" do
        expect { TargetModel.packet_item("BLAH", "HEALTH_STATUS", "CCSDSVER", scope: "DEFAULT") }.to raise_error("Packet 'BLAH HEALTH_STATUS' does not exist")
      end

      it "raises for a non-existent packet" do
        expect { TargetModel.packet_item("INST", "BLAH", "CCSDSVER", scope: "DEFAULT") }.to raise_error("Packet 'INST BLAH' does not exist")
      end

      it "raises for a non-existent item" do
        expect { TargetModel.packet_item("INST", "HEALTH_STATUS", "BLAH", scope: "DEFAULT") }.to raise_error("Item 'INST HEALTH_STATUS BLAH' does not exist")
      end

      it "returns item hash if the telemetry item exists" do
        item = TargetModel.packet_item("INST", "HEALTH_STATUS", "CCSDSVER", scope: "DEFAULT")
        expect(item['name']).to eql "CCSDSVER"
        expect(item['bit_offset']).to eql 0
      end

      it "returns item hash if the command item exists" do
        item = TargetModel.packet_item("INST", "ABORT", "CCSDSVER", type: :CMD, scope: "DEFAULT")
        expect(item['name']).to eql "CCSDSVER"
        expect(item['bit_offset']).to eql 0
      end
    end

    describe "self.packet_items" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "raises for an unknown type" do
        expect { TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER"], type: :OTHER, scope: "DEFAULT") }.to raise_error(/Unknown type OTHER/)
      end

      it "raises for a non-existent target" do
        expect { TargetModel.packet_items("BLAH", "HEALTH_STATUS", ["CCSDSVER"], scope: "DEFAULT") }.to raise_error("Packet 'BLAH HEALTH_STATUS' does not exist")
      end

      it "raises for a non-existent packet" do
        expect { TargetModel.packet_items("INST", "BLAH", ["CCSDSVER"], scope: "DEFAULT") }.to raise_error("Packet 'INST BLAH' does not exist")
      end

      it "raises for non-existent items" do
        expect { TargetModel.packet_items("INST", "HEALTH_STATUS", ["BLAH"], scope: "DEFAULT") }
          .to raise_error("Item(s) 'INST HEALTH_STATUS BLAH' does not exist")
        expect { TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER", "BLAH"], scope: "DEFAULT") }
          .to raise_error("Item(s) 'INST HEALTH_STATUS BLAH' does not exist")
        expect { TargetModel.packet_items("INST", "HEALTH_STATUS", [:BLAH, :NOPE], scope: "DEFAULT") }
          .to raise_error("Item(s) 'INST HEALTH_STATUS BLAH', 'INST HEALTH_STATUS NOPE' does not exist")
      end

      it "returns item hash array if the telemetry items exists" do
        items = TargetModel.packet_items("INST", "HEALTH_STATUS", ["CCSDSVER", "CCSDSTYPE"], scope: "DEFAULT")
        expect(items.length).to eql 2
        expect(items[0]['name']).to eql "CCSDSVER"
        expect(items[0]['bit_offset']).to eql 0
        expect(items[1]['name']).to eql "CCSDSTYPE"

        # Verify it also works with symbols
        items = TargetModel.packet_items("INST", "HEALTH_STATUS", [:CCSDSVER, :CCSDSTYPE], scope: "DEFAULT")
        expect(items.length).to eql 2
        expect(items[0]['name']).to eql "CCSDSVER"
        expect(items[0]['bit_offset']).to eql 0
        expect(items[1]['name']).to eql "CCSDSTYPE"
      end

      it "returns item hash array if the command items exists" do
        items = TargetModel.packet_items("INST", "ABORT", ["CCSDSVER", "CCSDSTYPE"], type: :CMD, scope: "DEFAULT")
        expect(items.length).to eql 2
        expect(items[0]['name']).to eql "CCSDSVER"
        expect(items[0]['bit_offset']).to eql 0
        expect(items[1]['name']).to eql "CCSDSTYPE"
      end
    end

    describe "self.all_item_names" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      it "returns all item names" do
        items = TargetModel.all_item_names("INST", scope: "DEFAULT")
        expect(items.length).to eql 67
        expect(items.uniq.length).to eql 67
      end

      it "rebuilds the allitems list when missing" do
        Store.del("DEFAULT__openc3tlm__INST__allitems")
        redis_items = Store.zrange("DEFAULT__openc3tlm__INST__allitems", 0, -1)
        expect(redis_items.length).to eql 0
        model_items = TargetModel.all_item_names("INST", scope: "DEFAULT")
        expect(model_items.length).to eql 67
        redis_items = Store.zrange("DEFAULT__openc3tlm__INST__allitems", 0, -1)
        expect(redis_items.length).to eql 67
      end
    end

    describe "self.handle_config" do
      it "only recognizes TARGET" do
        parser = double("ConfigParser").as_null_object
        expect(parser).to receive(:verify_num_parameters)
        TargetModel.handle_config(parser, "TARGET", ["TEST", "TEST"], scope: "DEFAULT")
        expect { TargetModel.handle_config(parser, "TARGETS", ["TEST", "TEST"], scope: "DEFAULT") }.to raise_error(ConfigParser::Error)
      end
    end

    describe "initialize" do
      it "requires name and scope" do
        expect { TargetModel.new(folder_name: "TEST", name: "TEST") }.to raise_error(ArgumentError)
        expect { TargetModel.new(folder_name: "TEST", scope: "DEFAULT") }.to raise_error(ArgumentError)
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        expect(model).to_not be_nil
      end
    end

    describe "create" do
      it "stores model based on scope and class name" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        keys = Store.scan(0)
        # This is an implementation detail but Redis keys are pretty critical so test it
        expect(keys[1]).to include("DEFAULT__openc3_targets").at_most(1).times
        # 21/07/2021 - G this needed to be changed to contain OPENC3__TOKEN
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        json = model.as_json()
        expect(json['name']).to eq "TEST"
        params = model.method(:initialize).parameters
        params.each do |_type, name|
          # Scope isn't included in as_json as it is part of the key used to get the model
          next if name == :scope

          expect(json.key?(name.to_s)).to be true
        end
      end
    end

    describe "handle_config" do
      it "parses tool specific keywords" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "CMD_LOG_CYCLE_TIME 1"
        tf.puts "CMD_LOG_CYCLE_SIZE 2"
        tf.puts "CMD_BUFFER_DEPTH 9"
        tf.puts "CMD_LOG_RETAIN_TIME 10"
        tf.puts "TLM_BUFFER_DEPTH 13"
        tf.puts "TLM_LOG_RETAIN_TIME 14"
        tf.puts "CMD_DECOM_RETAIN_TIME 30d"
        tf.puts "TLM_DECOM_RETAIN_TIME 60d"
        tf.puts "LOG_RETAIN_TIME 19"
        tf.puts "CLEANUP_POLL_TIME 24"
        tf.puts "TARGET_MICROSERVICE DECOM"
        tf.puts "PACKET DECOM"
        tf.puts "DISABLE_ERB"
        tf.puts "SHARD 9"
        tf.puts "TARGET_MICROSERVICE CLEANUP"
        tf.puts "TLM_LOG_CYCLE_TIME 5"
        tf.puts "TLM_LOG_CYCLE_SIZE 6"
        tf.close
        parser.parse_file(tf.path) do |keyword, params|
          model.handle_config(parser, keyword, params)
        end
        json = model.as_json()
        expect(json['cmd_log_cycle_time']).to eql 1
        expect(json['cmd_log_cycle_size']).to eql 2
        expect(json['tlm_log_cycle_time']).to eql 5
        expect(json['tlm_log_cycle_size']).to eql 6
        expect(json['cmd_decom_retain_time']).to eql '30d'
        expect(json['tlm_decom_retain_time']).to eql '60d'
        expect(json['shard']).to eql 9
        tf.unlink
      end

      it "rejects CMD_DECOM_RETAIN_TIME with invalid format" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "CMD_DECOM_RETAIN_TIME 30"
        tf.close
        expect do
          parser.parse_file(tf.path) do |keyword, params|
            model.handle_config(parser, keyword, params)
          end
        end.to raise_error(ConfigParser::Error, /CMD_DECOM_RETAIN_TIME must be a number followed by h, d, w, M, or y/)
        tf.unlink
      end

      it "rejects TLM_DECOM_RETAIN_TIME with invalid format" do
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "TLM_DECOM_RETAIN_TIME abc"
        tf.close
        expect do
          parser.parse_file(tf.path) do |keyword, params|
            model.handle_config(parser, keyword, params)
          end
        end.to raise_error(ConfigParser::Error, /TLM_DECOM_RETAIN_TIME must be a number followed by h, d, w, M, or y/)
        tf.unlink
      end

    end

   describe "deploy" do
      before(:each) do
        @scope = "DEFAULT"
        @target = "INST"
        @target_dir = File.join(SPEC_DIR, "install", "config")
      end

      it "raises if the target can't be found" do
        @target_dir = Dir.pwd
        variables = { "test" => "example" }
        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        expect { model.deploy(@target_dir, variables) }.to raise_error(/No target files found/)
      end

      it "puts the packets in Redis" do
        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        model.deploy(@target_dir, {})
        expect(Store.hkeys("DEFAULT__openc3tlm__INST")).to include("HEALTH_STATUS", "ADCS", "PARAMS", "IMAGE", "MECH")
        expect(Store.hkeys("DEFAULT__openc3cmd__INST")).to include("ABORT", "COLLECT", "CLEAR") # ... etc

        # Spot check a telemetry packet and a command
        telemetry = TargetModel.packet(@target, "HEALTH_STATUS", type: :TLM, scope: @scope)
        expect(telemetry['target_name']).to eql @target
        expect(telemetry['packet_name']).to eql "HEALTH_STATUS"
        expect(telemetry['items'].length).to be > 10
        command = TargetModel.packet(@target, "ABORT", type: :CMD, scope: @scope)
        expect(command['target_name']).to eql @target
        expect(command['packet_name']).to eql "ABORT"
        expect(command['items'].length).to be > 10
      end

      it "creates and deploys Target microservices" do
        variables = { "test" => "example" }
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:create).exactly(5).times
        expect(umodel).to receive(:deploy).with(@target_dir, variables).exactly(5).times
        # Verify the microservices that are started
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{@scope}__COMMANDLOG__#{@target}",
                                                          plugin: 'PLUGIN',
                                                          scope: @scope
                                                        )).and_return(umodel)
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{@scope}__PACKETLOG__#{@target}",
                                                          plugin: 'PLUGIN',
                                                          scope: @scope
                                                        )).and_return(umodel)
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{@scope}__DECOM__#{@target}",
                                                          plugin: 'PLUGIN',
                                                          scope: @scope
                                                        )).and_return(umodel)
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{@scope}__MULTI__#{@target}",
                                                          plugin: 'PLUGIN',
                                                          scope: @scope
                                                        )).and_return(umodel)
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{@scope}__CLEANUP__#{@target}",
                                                          plugin: 'PLUGIN',
                                                          scope: @scope
                                                        )).and_return(umodel)

        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN', tlm_log_retain_time: 60)
        model.create
        capture_io do |stdout|
          model.deploy(@target_dir, variables)
          expect(stdout.string).to include("#{@scope}__COMMANDLOG__#{@target}")
          expect(stdout.string).to include("#{@scope}__PACKETLOG__#{@target}")
          expect(stdout.string).to include("#{@scope}__DECOM__#{@target}")
          expect(stdout.string).to include("#{@scope}__MULTI__#{@target}")
          expect(stdout.string).to include("#{@scope}__CLEANUP__#{@target}")
        end
      end

      it "deploys no microservices if no commands or telemetry" do
        @target = "EMPTY"
        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        capture_io do |stdout|
          model.deploy(@target_dir, {})
          expect(stdout.string).to_not include("#{@scope}__COMMANDLOG__#{@target}")
          expect(stdout.string).to_not include("#{@scope}__PACKETLOG__#{@target}")
          expect(stdout.string).to_not include("#{@scope}__DECOM__#{@target}")
        end
        expect(MicroserviceModel.names()).to be_empty
      end

      it "deploys only command microservices if no telemetry" do
        @target = "EMPTY"
        FileUtils.mkdir_p("#{@target_dir}/targets/#{@target}/cmd_tlm")
        File.open("#{@target_dir}/targets/#{@target}/cmd_tlm/cmd.txt", 'w') do |file|
          file.puts 'COMMAND INST CMD LITTLE_ENDIAN "Command"'
          file.puts '  APPEND_ID_PARAMETER ID 8 UINT 1 1 1 "ID"'
        end
        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        capture_io do |stdout|
          model.deploy(@target_dir, {})
          expect(stdout.string).to include("#{@scope}__COMMANDLOG__#{@target}")
          expect(stdout.string).to_not include("#{@scope}__PACKETLOG__#{@target}")
          expect(stdout.string).to_not include("#{@scope}__DECOM__#{@target}")
        end
        expect(MicroserviceModel.names()).to include("#{@scope}__COMMANDLOG__#{@target}")
        FileUtils.rm_rf("#{@target_dir}/targets/#{@target}/cmd_tlm")
      end

      it "deploys only telemetry microservices if no commands" do
        @target = "EMPTY"
        FileUtils.mkdir_p("#{@target_dir}/targets/#{@target}/cmd_tlm")
        File.open("#{@target_dir}/targets/#{@target}/cmd_tlm/tlm.txt", 'w') do |file|
          file.puts 'TELEMETRY INST TLM LITTLE_ENDIAN "Telemetry"'
          file.puts '  APPEND_ID_ITEM ID 8 UINT 1 "ID"'
        end
        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        capture_io do |stdout|
          model.deploy(@target_dir, {})
          expect(stdout.string).to_not include("#{@scope}__COMMANDLOG__#{@target}")
          expect(stdout.string).to include("#{@scope}__PACKETLOG__#{@target}")
          expect(stdout.string).to include("#{@scope}__DECOM__#{@target}")
        end
        expect(MicroserviceModel.names()).to include(
          "#{@scope}__PACKETLOG__#{@target}",
          "#{@scope}__DECOM__#{@target}")
        FileUtils.rm_rf("#{@target_dir}/targets/#{@target}/cmd_tlm")
      end

      it "deploys TSDB microservice with both telemetry and command topics" do
        # Set TSDB environment variables
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_HOSTNAME').and_return('localhost')
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_QUERY_PORT').and_return('8086')
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_INGEST_PORT').and_return('8087')
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_USERNAME').and_return('admin')
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_PASSWORD').and_return('password')

        model = TargetModel.new(folder_name: @target, name: @target, scope: @scope, plugin: 'PLUGIN')
        model.create
        capture_io do |stdout|
          model.deploy(@target_dir, {})
          expect(stdout.string).to include("#{@scope}__TSDB__#{@target}")
        end

        # Verify TSDB microservice was created with both telemetry and command topics
        tsdb_model = MicroserviceModel.get_model(name: "#{@scope}__TSDB__#{@target}", scope: @scope)
        expect(tsdb_model).to_not be_nil

        # Check that TSDB topics include both DECOM (telemetry) and DECOMCMD (commands)
        decom_topics = tsdb_model.topics.select { |t| t.include?("__DECOM__") }
        decomcmd_topics = tsdb_model.topics.select { |t| t.include?("__DECOMCMD__") }

        expect(decom_topics).to_not be_empty
        expect(decomcmd_topics).to_not be_empty

        # Verify specific topic patterns
        expect(decom_topics.first).to match(/#{@scope}__DECOM__\{#{@target}\}__/)
        expect(decomcmd_topics.first).to match(/#{@scope}__DECOMCMD__\{#{@target}\}__/)
      end
    end

    describe "destroy" do
      before(:each) do
        @target_dir = File.join(SPEC_DIR, "install", "config")
      end

      it "works on created but not deployed instances" do
        model = TargetModel.new(name: "UNKNOWN", scope: "DEFAULT")
        model.create
        tgt = JSON.parse(Store.hget("DEFAULT__openc3_targets", "UNKNOWN"))
        expect(tgt['name']).to eql "UNKNOWN"
        model.destroy
        tgt = Store.hget("DEFAULT__openc3_targets", "UNKNOWN")
        expect(tgt).to be nil
      end

      it "destroys any deployed Target microservices" do
        orig_keys = get_all_redis_keys()
        # Add in the keys that remain when a target is destroyed
        orig_keys << "DEFAULT__CONFIG"
        orig_keys << "DEFAULT__openc3cmd__UNKNOWN"
        orig_keys << "DEFAULT__openc3tlm__UNKNOWN"
        orig_keys << "DEFAULT__openc3tlm__INST__allitems"
        orig_keys << "DEFAULT__openc3tlm__SYSTEM__allitems"
        orig_keys << "DEFAULT__limits_sets"
        orig_keys << "DEFAULT__tlm__UNKNOWN"
        orig_keys << "openc3_microservices"

        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:destroy).exactly(10).times
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).exactly(10).times
        inst_model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT", plugin: "INST_PLUGIN")
        inst_model.create
        inst_model.deploy(@target_dir, {})

        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'created'
        expect(config[0][1]['type']).to eql 'target'
        expect(config[0][1]['name']).to eql 'INST'
        expect(config[0][1]['plugin']).to eql 'INST_PLUGIN'

        sys_model = TargetModel.new(folder_name: "SYSTEM", name: "SYSTEM", scope: "DEFAULT", plugin: "SYSTEM_PLUGIN")
        sys_model.create
        sys_model.deploy(@target_dir, {})

        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'created'
        expect(config[0][1]['type']).to eql 'target'
        expect(config[0][1]['name']).to eql 'SYSTEM'
        expect(config[0][1]['plugin']).to eql 'SYSTEM_PLUGIN'

        keys = get_all_redis_keys()
        # Spot check some keys
        expect(keys).to include("DEFAULT__CONFIG")
        expect(keys).to include("DEFAULT__limits_sets")
        expect(keys).to include("DEFAULT__limits_groups")
        expect(keys).to include("DEFAULT__openc3_targets")
        expect(keys).to include("DEFAULT__openc3cmd__INST")
        expect(keys).to include("DEFAULT__openc3tlm__INST")
        targets = Store.hgetall("DEFAULT__openc3_targets")
        expect(targets.keys).to include("INST")

        inst_model.destroy
        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'deleted'
        expect(config[0][1]['type']).to eql 'target'
        expect(config[0][1]['name']).to eql 'INST'
        expect(config[0][1]['plugin']).to eql 'INST_PLUGIN'

        sys_model.destroy
        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'deleted'
        expect(config[0][1]['type']).to eql 'target'
        expect(config[0][1]['name']).to eql 'SYSTEM'
        expect(config[0][1]['plugin']).to eql 'SYSTEM_PLUGIN'

        targets = Store.hgetall("DEFAULT__openc3_targets")
        expect(targets.keys).to_not include("INST")
        keys = get_all_redis_keys()
        expect(orig_keys.sort).to eql keys.sort
      end
    end

    describe "dynamic_update" do
      before(:each) do
        @scope = "DEFAULT"
        @target = "INST"
        setup_system()
        @model = TargetModel.new(folder_name: @target, name: "INST", scope: @scope)
        @model.create
        @model.update_store(System.new([@target], File.join(SPEC_DIR, 'install', 'config', 'targets')))
        @s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(@s3)
        allow(@s3).to receive(:head_bucket)
        allow(@s3).to receive(:delete_bucket)
      end

      it "adds new commands" do
        packet = Packet.new("INST", "NEW_CMD")
        cmd_log_model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__COMMANDLOG__INST", scope: @scope)
        cmd_log_model.create
        tsdb_model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__TSDB__INST", scope: @scope)
        tsdb_model.create

        pkts = Store.hgetall("#{@scope}__openc3cmd__#{@target}")
        expect(pkts.keys).to_not include("NEW_CMD")
        expect(pkts.keys).to include("ABORT")

        expect(@s3).to receive(:put_object).with(bucket: 'config', key: "#{@scope}/targets_modified/#{@target}/cmd_tlm/dynamic_tlm.txt", body: anything, cache_control: nil, content_type: nil, metadata: nil, checksum_algorithm: anything)

        @model.dynamic_update([packet], :COMMAND)

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall("#{@scope}__openc3cmd__#{@target}")
        expect(pkts.keys).to include("NEW_CMD")
        expect(pkts.keys).to include("ABORT") # Other commands should still be there
        model = MicroserviceModel.get_model(name: "DEFAULT__COMMANDLOG__INST", scope: @scope)
        expect(model.topics).to include("DEFAULT__COMMAND__{INST}__NEW_CMD")
      end

      it "adds new telemetry" do
        packet = Packet.new("INST", "NEW_TLM")
        pkt_log_model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__PACKETLOG__INST", scope: @scope)
        pkt_log_model.create
        decom_model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__DECOM__INST", scope: @scope)
        decom_model.create
        tsdb_model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__TSDB__INST", scope: @scope)
        tsdb_model.create

        pkts = Store.hgetall("#{@scope}__openc3tlm__#{@target}")
        expect(pkts.keys).to_not include("NEW_TLM")
        expect(pkts.keys).to include("HEALTH_STATUS")

        expect(@s3).to receive(:put_object).with(bucket: 'config', key: "#{@scope}/targets_modified/#{@target}/cmd_tlm/dynamic_tlm.txt", body: anything, cache_control: nil, content_type: nil, metadata: nil, checksum_algorithm: anything)

        @model.dynamic_update([packet], :TELEMETRY)

        # Make sure the Store gets updated with the new packet
        pkts = Store.hgetall("#{@scope}__openc3tlm__#{@target}")
        expect(pkts.keys).to include("NEW_TLM")
        expect(pkts.keys).to include("HEALTH_STATUS") # Other telemetry should still be there
        model = MicroserviceModel.get_model(name: "DEFAULT__PACKETLOG__INST", scope: @scope)
        expect(model.topics).to include("DEFAULT__TELEMETRY__{INST}__NEW_TLM")
        model = MicroserviceModel.get_model(name: "DEFAULT__DECOM__INST", scope: @scope)
        expect(model.topics).to include("DEFAULT__TELEMETRY__{INST}__NEW_TLM")
      end
    end

    # Tests for GitHub issue #2855:
    # Stale tlmcnt Redis keys cause interface disconnect loops.
    # When a plugin is upgraded and packets are removed, old Redis TELEMETRYCNTS keys
    # remain. When the interface receives a packet and tries to sync counts, it calls
    # System.telemetry.packet() for every key in Redis — including the stale ones —
    # which raises RuntimeError and causes the interface to disconnect and reconnect.
    describe "stale tlmcnt Redis key handling" do
      before(:each) do
        setup_system()
        model = TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
        # Reset class-level sync state between tests
        TargetModel.class_variable_set(:@@sync_packet_count_data, {})
        TargetModel.class_variable_set(:@@sync_packet_count_time, nil)
        TargetModel.class_variable_set(:@@stale_packet_keys_warned, Set.new)
      end

      describe "self.init_tlm_packet_counts" do
        it "skips stale Redis key and logs a warning" do
          # Simulate a stale Redis key left over from a removed packet definition.
          # INST currently defines HEALTH_STATUS, ADCS, PARAMS, IMAGE, MECH, HIDDEN —
          # OLD_PACKET was removed when the plugin was upgraded but its Redis key remains.
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS", 10)

          # init_tlm_packet_counts must skip the stale key rather than raising RuntimeError.
          expect { TargetModel.init_tlm_packet_counts(["INST"], scope: "DEFAULT") }.not_to raise_error
        end

        it "logs a warning for the stale key" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS", 10)

          expect(Logger).to receive(:warn).with(/Stale tlmcnt Redis key detected for unknown packet INST OLD_PACKET/)
          TargetModel.init_tlm_packet_counts(["INST"], scope: "DEFAULT")
        end

        it "warns only once per stale key per init (epoch reset)" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)

          warn_count = 0
          allow(Logger).to receive(:warn) { |msg| warn_count += 1 if msg.include?("OLD_PACKET") }

          # First init — warns once
          TargetModel.init_tlm_packet_counts(["INST"], scope: "DEFAULT")
          expect(warn_count).to eq(1)

          # Second init resets the epoch and warns again
          TargetModel.init_tlm_packet_counts(["INST"], scope: "DEFAULT")
          expect(warn_count).to eq(2)
        end

        it "still updates counts for known packets" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS", 10)

          allow(Logger).to receive(:warn)
          TargetModel.init_tlm_packet_counts(["INST"], scope: "DEFAULT")

          expect(System.telemetry.packet("INST", "HEALTH_STATUS").received_count).to eq(10)
        end
      end

      describe "self.sync_tlm_packet_counts" do
        it "skips stale Redis key and logs a warning" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)

          packet = System.telemetry.packet("INST", "HEALTH_STATUS")
          # sync_packet_count_time=nil forces the periodic Redis sync to run immediately
          TargetModel.class_variable_set(:@@sync_packet_count_time, nil)

          expect { TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope: "DEFAULT") }.not_to raise_error
        end

        it "logs a warning for the stale key" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)

          packet = System.telemetry.packet("INST", "HEALTH_STATUS")
          TargetModel.class_variable_set(:@@sync_packet_count_time, nil)

          expect(Logger).to receive(:warn).with(/Stale tlmcnt Redis key detected for unknown packet INST OLD_PACKET/)
          TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope: "DEFAULT")
        end

        it "warns only once per stale key within an epoch" do
          Store.hset("DEFAULT__TELEMETRYCNTS__{INST}", "OLD_PACKET", 5)

          packet = System.telemetry.packet("INST", "HEALTH_STATUS")

          warn_count = 0
          allow(Logger).to receive(:warn) { |msg| warn_count += 1 if msg.include?("OLD_PACKET") }

          # First sync — warns once
          TargetModel.class_variable_set(:@@sync_packet_count_time, nil)
          TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope: "DEFAULT")
          expect(warn_count).to eq(1)

          # Second sync (forcing another Redis sync) must NOT repeat the warning
          TargetModel.class_variable_set(:@@sync_packet_count_time, nil)
          TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope: "DEFAULT")
          expect(warn_count).to eq(1)
        end

        it "still updates counts for known packets" do
          packet = System.telemetry.packet("INST", "HEALTH_STATUS")
          TargetModel.class_variable_set(:@@sync_packet_count_time, nil)

          TargetModel.sync_tlm_packet_counts(packet, ["INST"], scope: "DEFAULT")

          expect(packet.received_count).to be > 0
        end
      end
    end
  end
end
