# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/microservices/multi_microservice'
require 'openc3/models/microservice_model'

module OpenC3
  describe MultiMicroservice do
    let(:name) { 'DEFAULT__MULTIGROUP__HK' }

    before(:each) do
      mock_redis()
      allow(System).to receive(:setup_targets)
      MicroserviceModel.new(name: name, scope: 'DEFAULT').create
      MicroserviceModel.new(name: 'DEFAULT__DECOM__B', parent: name, target_names: ['B'], cmd: ['ruby', 'decom_microservice.rb'], scope: 'DEFAULT').create
      MicroserviceModel.new(name: 'DEFAULT__DECOM__A', parent: name, target_names: ['A'], cmd: ['ruby', 'decom_microservice.rb'], scope: 'DEFAULT').create
      MicroserviceModel.new(name: 'DEFAULT__PACKETLOG__A', parent: name, cmd: ['ruby', 'log_microservice.rb'], scope: 'DEFAULT').create
      MicroserviceModel.new(name: 'DEFAULT__DECOM__C', parent: name, target_names: ['C'], enabled: false, scope: 'DEFAULT').create
      MicroserviceModel.new(name: 'DEFAULT__DECOM__D', parent: 'DEFAULT__MULTI__D', target_names: ['D'], scope: 'DEFAULT').create
      @mm = MultiMicroservice.new(name)
    end

    after(:each) do
      @mm.shutdown
    end

    it "runs the microservices given on the command line" do
      stub_const('ARGV', ['DEFAULT__DECOM__D', 'DEFAULT__PACKETLOG__A'])
      expect(@mm.child_models.map(&:name)).to eql ['DEFAULT__DECOM__D', 'DEFAULT__PACKETLOG__A']
    end

    it "otherwise runs the enabled microservices that name it as their parent" do
      stub_const('ARGV', [])
      expect(@mm.child_models.map(&:name)).to eql ['DEFAULT__DECOM__A', 'DEFAULT__DECOM__B', 'DEFAULT__PACKETLOG__A']
    end

    it "sets up System for every child's targets before starting them" do
      stub_const('ARGV', [])
      threads = []
      allow(Thread).to receive(:new) { |&_block| threads << double('thread'); threads[-1] }
      allow(ThreadManager.instance).to receive(:register)
      allow(ThreadManager.instance).to receive(:monitor)
      allow(ThreadManager.instance).to receive(:shutdown)
      expect(System).to receive(:setup_targets).with(['A', 'B'], anything, scope: 'DEFAULT', descriptions: false).ordered
      expect(Thread).to receive(:new).exactly(3).times.ordered
      @mm.run
      expect(ThreadManager.instance).to have_received(:register).exactly(3).times
    end

    it "sizes the Redis connection pools for its children" do
      models = [MicroserviceModel.new(name: 'DEFAULT__DECOM__X', db_shard: 1, scope: 'DEFAULT')] * 150
      MultiMicroservice.ensure_pool_sizes(models)
      # Two connections per child on top of the default, on shard 0 and every child's shard
      [0, 1].each do |db_shard|
        expect(Store.instance(db_shard: db_shard).pool_size).to eql 400
        expect(EphemeralStore.instance(db_shard: db_shard).pool_size).to eql 400
      end
    end

    it "waits for a shutdown if it has no children" do
      stub_const('ARGV', [])
      empty = MultiMicroservice.new('DEFAULT__MULTIGROUP__EMPTY')
      thread = Thread.new { empty.run }
      sleep 0.1
      expect(thread).to be_alive
      empty.shutdown
      # Shutdown also stops metrics, which can take a moment on a busy machine
      thread.join(10)
      expect(thread).to_not be_alive
    end
  end
end
