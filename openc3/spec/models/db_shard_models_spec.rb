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

# Verifies models write to and read from the correct db_shard. Each db_shard has
# its own MockRedis (mock_redis_db_shards) so data on the wrong db_shard is missed.

require 'spec_helper'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/interface_status_model'
require 'openc3/models/router_status_model'
require 'openc3/models/microservice_model'
require 'openc3/models/microservice_status_model'
require 'openc3/models/metric_model'
require 'openc3/models/target_model'
require 'openc3/models/cvt_model'

module OpenC3
  describe "db_shard models" do
    before(:each) do
      mock_redis_db_shards()
      [InterfaceStatusModel, RouterStatusModel, MicroserviceStatusModel, MetricModel].each do |model|
        model.instance_variable_set(:@db_shard_cache, nil)
      end
    end

    def store(db_shard)
      Store.instance(db_shard: db_shard)
    end

    def ephemeral(db_shard)
      EphemeralStore.instance(db_shard: db_shard)
    end

    describe InterfaceStatusModel do
      before(:each) do
        InterfaceModel.new(name: 'INT0', scope: 'DEFAULT').create
        InterfaceModel.new(name: 'INT1', scope: 'DEFAULT', db_shard: 1).create
      end

      it "creates, gets and destroys a status on the db_shard of its interface" do
        InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create
        expect(store(1).hget('DEFAULT__openc3_interface_status', 'INT1')).not_to be_nil
        expect(store(0).hget('DEFAULT__openc3_interface_status', 'INT1')).to be_nil
        expect(InterfaceStatusModel.get(name: 'INT1', scope: 'DEFAULT')['state']).to eql 'CONNECTED'

        InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').destroy
        expect(store(1).hget('DEFAULT__openc3_interface_status', 'INT1')).to be_nil
        expect(InterfaceStatusModel.get(name: 'INT1', scope: 'DEFAULT')).to be_nil
      end

      it "checks for an existing status on the db_shard of its interface" do
        # A status on another db_shard doesn't count
        store(0).hset('DEFAULT__openc3_interface_status', 'INT1', JSON.generate({ 'state' => 'OLD' }))
        expect { InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create(update: true) }.to raise_error(/doesn't exist at update/)
        InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create
        expect { InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create }.to raise_error(/already exists at create/)
        InterfaceStatusModel.new(name: 'INT1', state: 'DISCONNECTED', scope: 'DEFAULT').create(update: true)
        expect(InterfaceStatusModel.get(name: 'INT1', scope: 'DEFAULT')['state']).to eql 'DISCONNECTED'
        InterfaceStatusModel.new(name: 'INT1', state: 'ATTEMPTING', scope: 'DEFAULT').create(force: true)
        expect(InterfaceStatusModel.get(name: 'INT1', scope: 'DEFAULT')['state']).to eql 'ATTEMPTING'
      end

      it "writes a queued status to the db_shard of its interface" do
        InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create(queued: true)
        expect(store(1).hget('DEFAULT__openc3_interface_status', 'INT1')).not_to be_nil
        expect(store(0).hget('DEFAULT__openc3_interface_status', 'INT1')).to be_nil
      end

      it "returns names and all from every db_shard" do
        InterfaceModel.new(name: 'INT2', scope: 'DEFAULT', db_shard: 2).create
        %w(INT0 INT1 INT2).each { |name| InterfaceStatusModel.new(name: name, state: 'CONNECTED', scope: 'DEFAULT').create }
        expect(store(2).hkeys('DEFAULT__openc3_interface_status')).to eql ['INT2']
        expect(InterfaceStatusModel.names(scope: 'DEFAULT')).to eql %w(INT0 INT1 INT2)
        expect(InterfaceStatusModel.all(scope: 'DEFAULT').keys.sort).to eql %w(INT0 INT1 INT2)
        expect(InterfaceStatusModel._active_db_shards(scope: 'DEFAULT')).to eql Set[0, 1, 2]
      end

      it "caches the db_shard for create but not for get" do
        InterfaceStatusModel.new(name: 'INT1', state: 'CONNECTED', scope: 'DEFAULT').create
        InterfaceModel.new(name: 'INT1', scope: 'DEFAULT', db_shard: 2).create(update: true)
        # create keeps using the cached db_shard 1
        InterfaceStatusModel.new(name: 'INT1', state: 'DISCONNECTED', scope: 'DEFAULT').create(update: true)
        expect(JSON.parse(store(1).hget('DEFAULT__openc3_interface_status', 'INT1'))['state']).to eql 'DISCONNECTED'
        # get looks up the db_shard every time
        expect(InterfaceStatusModel.get(name: 'INT1', scope: 'DEFAULT')).to be_nil
      end
    end

    describe RouterStatusModel do
      it "uses the db_shard of its router, not an interface of the same name" do
        InterfaceModel.new(name: 'SAME', scope: 'DEFAULT', db_shard: 1).create
        RouterModel.new(name: 'SAME', scope: 'DEFAULT', db_shard: 2).create
        InterfaceStatusModel.new(name: 'SAME', state: 'CONNECTED', scope: 'DEFAULT').create
        RouterStatusModel.new(name: 'SAME', state: 'DISCONNECTED', scope: 'DEFAULT').create
        expect(store(1).hget('DEFAULT__openc3_interface_status', 'SAME')).not_to be_nil
        expect(store(2).hget('DEFAULT__openc3_router_status', 'SAME')).not_to be_nil
        expect(store(1).hget('DEFAULT__openc3_router_status', 'SAME')).to be_nil
        expect(RouterStatusModel.get(name: 'SAME', scope: 'DEFAULT')['state']).to eql 'DISCONNECTED'
        expect(RouterStatusModel.names(scope: 'DEFAULT')).to eql ['SAME']
      end
    end

    describe MicroserviceStatusModel do
      it "uses the db_shard of its microservice and only that scope's db_shards" do
        MicroserviceModel.new(name: 'DEFAULT__TYPE__MS1', scope: 'DEFAULT', db_shard: 1).create
        MicroserviceModel.new(name: 'OTHER__TYPE__MS3', scope: 'OTHER', db_shard: 3).create
        MicroserviceStatusModel.new(name: 'DEFAULT__TYPE__MS1', state: 'RUNNING', scope: 'DEFAULT').create
        expect(store(1).hget('DEFAULT__openc3_microservice_status', 'DEFAULT__TYPE__MS1')).not_to be_nil
        expect(store(0).hget('DEFAULT__openc3_microservice_status', 'DEFAULT__TYPE__MS1')).to be_nil
        expect(MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__MS1', scope: 'DEFAULT')['state']).to eql 'RUNNING'
        expect(MicroserviceStatusModel.names(scope: 'DEFAULT')).to eql ['DEFAULT__TYPE__MS1']
        expect(MicroserviceStatusModel._active_db_shards(scope: 'DEFAULT')).to eql Set[0, 1]

        MicroserviceStatusModel.new(name: 'DEFAULT__TYPE__MS1', scope: 'DEFAULT').destroy
        expect(store(1).hget('DEFAULT__openc3_microservice_status', 'DEFAULT__TYPE__MS1')).to be_nil
      end
    end

    describe MetricModel do
      before(:each) do
        MicroserviceModel.new(name: 'DEFAULT__TYPE__MS1', scope: 'DEFAULT', db_shard: 1).create
      end

      it "sets, gets and destroys metrics on the db_shard of the microservice" do
        MetricModel.set({ 'name' => 'DEFAULT__TYPE__MS1', 'values' => { 'a' => { 'value' => 1 } }, 'db_shard' => 1 }, scope: 'DEFAULT')
        MetricModel.set_process({ 'name' => 'DEFAULT__TYPE__MS1', 'values' => { 'b' => { 'value' => 2 } }, 'db_shard' => 1 }, scope: 'DEFAULT')
        expect(ephemeral(1).hget('DEFAULT__openc3__metric', 'DEFAULT__TYPE__MS1')).not_to be_nil
        expect(ephemeral(1).hget('DEFAULT__openc3__process_metric', 'DEFAULT__TYPE__MS1')).not_to be_nil
        expect(ephemeral(0).hkeys('DEFAULT__openc3__metric')).to be_empty
        # Metrics are ephemeral so nothing goes to the persistent store
        expect(store(1).hkeys('DEFAULT__openc3__metric')).to be_empty

        expect(MetricModel.get(name: 'DEFAULT__TYPE__MS1', scope: 'DEFAULT')['values'].keys.sort).to eql %w(a b)
        expect(MetricModel.names(scope: 'DEFAULT')).to eql ['DEFAULT__TYPE__MS1']
        expect(MetricModel.all(scope: 'DEFAULT').keys).to eql ['DEFAULT__TYPE__MS1']

        MetricModel.destroy(scope: 'DEFAULT', name: 'DEFAULT__TYPE__MS1')
        expect(ephemeral(1).hkeys('DEFAULT__openc3__metric')).to be_empty
        expect(ephemeral(1).hkeys('DEFAULT__openc3__process_metric')).to be_empty
      end

      it "creates and destroys a metric on its own db_shard" do
        metric = MetricModel.new(name: 'DEFAULT__TYPE__MS1', values: {}, db_shard: 1, scope: 'DEFAULT')
        metric.create(expire_seconds: 10)
        expect(ephemeral(1).hkeys('DEFAULT__openc3__metric')).to eql ['DEFAULT__TYPE__MS1']
        metric.destroy
        expect(ephemeral(1).hkeys('DEFAULT__openc3__metric')).to be_empty
      end
    end

    describe "targets" do
      before(:each) do
        setup_system()
        TargetModel.clear_packet_cache
        TargetModel.class_variable_get(:@@item_map_cache).clear
        @model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT', db_shard: 1)
        @model.create
        TargetModel.new(folder_name: 'SYSTEM', name: 'SYSTEM', scope: 'DEFAULT').create
        Store.class_variable_set(:@@db_shard_cache, {})
        @model.update_store_telemetry({ 'INST' => System.telemetry.packets('INST') })
        @model.update_store_commands({ 'INST' => System.commands.packets('INST') })
        @model.update_store_item_map
      end

      it "stores the target definition on db_shard 0 and its packets on its db_shard" do
        expect(store(0).hget('DEFAULT__openc3_targets', 'INST')).not_to be_nil
        expect(store(1).hget('DEFAULT__openc3_targets', 'INST')).to be_nil
        %w(DEFAULT__openc3tlm__INST DEFAULT__openc3cmd__INST DEFAULT__tlm__INST DEFAULT__openc3tlm__INST__allitems DEFAULT__INST__item_to_packet_map).each do |key|
          expect(store(1).exists(key)).to eql(1), "#{key} not on db_shard 1"
          expect(store(0).exists(key)).to eql(0), "#{key} on db_shard 0"
        end
      end

      it "reads packets, items and the item map from the target's db_shard" do
        expect(TargetModel.packet('INST', 'HEALTH_STATUS', scope: 'DEFAULT')['packet_name']).to eql 'HEALTH_STATUS'
        expect(TargetModel.packet('INST', 'ABORT', type: :CMD, scope: 'DEFAULT')['packet_name']).to eql 'ABORT'
        expect(TargetModel.packets('INST', scope: 'DEFAULT').map { |packet| packet['packet_name'] }).to include('HEALTH_STATUS', 'ADCS')
        expect(TargetModel.all_item_names('INST', scope: 'DEFAULT')).to include('TEMP1')
        TargetModel.class_variable_get(:@@item_map_cache).clear
        expect(TargetModel.get_item_to_packet_map('INST', scope: 'DEFAULT')['TEMP1']).to eql ['HEALTH_STATUS']

        packet = TargetModel.packet('INST', 'HEALTH_STATUS', scope: 'DEFAULT')
        packet['description'] = 'Changed'
        TargetModel.set_packet('INST', 'HEALTH_STATUS', packet, scope: 'DEFAULT')
        expect(JSON.parse(store(1).hget('DEFAULT__openc3tlm__INST', 'HEALTH_STATUS'))['description']).to eql 'Changed'
      end

      it "counts packets on each target's db_shard" do
        TargetModel.increment_telemetry_count('INST', 'HEALTH_STATUS', 2, scope: 'DEFAULT')
        TargetModel.increment_telemetry_count('SYSTEM', 'META', 3, scope: 'DEFAULT')
        TargetModel.increment_command_count('INST', 'ABORT', 4, scope: 'DEFAULT')
        expect(store(1).hget('DEFAULT__TELEMETRYCNTS__{INST}', 'HEALTH_STATUS')).to eql '2'
        expect(store(0).hget('DEFAULT__TELEMETRYCNTS__{SYSTEM}', 'META')).to eql '3'
        expect(store(1).hget('DEFAULT__COMMANDCNTS__{INST}', 'ABORT')).to eql '4'
        expect(TargetModel.get_telemetry_count('INST', 'HEALTH_STATUS', scope: 'DEFAULT')).to eql 2
        expect(TargetModel.get_command_count('INST', 'ABORT', scope: 'DEFAULT')).to eql 4
        # Batched lookups across db_shards keep the requested order
        counts = TargetModel.get_telemetry_counts([%w(SYSTEM META), %w(INST HEALTH_STATUS), %w(INST ADCS)], scope: 'DEFAULT')
        expect(counts).to eql [3, 2, 0]
        expect(TargetModel.get_command_counts([%w(INST ABORT), %w(SYSTEM STARTLOGGING)], scope: 'DEFAULT')).to eql [4, 0]
      end

      it "sets, gets and overrides the CVT on the target's db_shard" do
        CvtModel.set({ 'TEMP1' => 1.5 }, target_name: 'INST', packet_name: 'HEALTH_STATUS', scope: 'DEFAULT')
        expect(JSON.parse(store(1).hget('DEFAULT__tlm__INST', 'HEALTH_STATUS'))).to eql({ 'TEMP1' => 1.5 })
        expect(store(0).hget('DEFAULT__tlm__INST', 'HEALTH_STATUS')).to be_nil
        expect(CvtModel.get_item('INST', 'HEALTH_STATUS', 'TEMP1', type: :RAW, scope: 'DEFAULT')).to eql 1.5

        CvtModel.set({ 'TEMP1' => 2.5 }, target_name: 'INST', packet_name: 'HEALTH_STATUS', queued: true, scope: 'DEFAULT')
        expect(JSON.parse(store(1).hget('DEFAULT__tlm__INST', 'HEALTH_STATUS'))).to eql({ 'TEMP1' => 2.5 })

        CvtModel.override('INST', 'HEALTH_STATUS', 'TEMP1', 10, type: :RAW, scope: 'DEFAULT')
        expect(store(1).hget('DEFAULT__override__INST', 'HEALTH_STATUS')).not_to be_nil
        expect(store(0).hget('DEFAULT__override__INST', 'HEALTH_STATUS')).to be_nil
        expect(CvtModel.overrides(scope: 'DEFAULT').map { |item| item['value'] }).to eql [10]
        expect(CvtModel.get_item('INST', 'HEALTH_STATUS', 'TEMP1', type: :RAW, scope: 'DEFAULT')).to eql 10
        CvtModel.normalize('INST', 'HEALTH_STATUS', 'TEMP1', type: :RAW, scope: 'DEFAULT')
        expect(store(1).hget('DEFAULT__override__INST', 'HEALTH_STATUS')).to be_nil

        CvtModel.del(target_name: 'INST', packet_name: 'HEALTH_STATUS', scope: 'DEFAULT')
        expect(store(1).hget('DEFAULT__tlm__INST', 'HEALTH_STATUS')).to be_nil
      end

      it "deletes the target's data from its db_shard on undeploy" do
        TargetModel.increment_telemetry_count('INST', 'HEALTH_STATUS', 1, scope: 'DEFAULT')
        TargetModel.increment_command_count('INST', 'ABORT', 1, scope: 'DEFAULT')
        ephemeral(1).write_topic('DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS', { 'a' => '1' })
        ephemeral(1).write_topic('DEFAULT__COMMAND__{INST}__ABORT', { 'a' => '1' })
        bucket = double('bucket')
        allow(bucket).to receive(:list_objects).and_return([])
        @model.instance_variable_set(:@bucket, bucket)
        expect(Logger).not_to receive(:error)
        @model.undeploy

        %w(DEFAULT__openc3tlm__INST DEFAULT__openc3cmd__INST DEFAULT__TELEMETRYCNTS__{INST} DEFAULT__COMMANDCNTS__{INST} DEFAULT__INST__item_to_packet_map).each do |key|
          expect(store(1).exists(key)).to eql(0), "#{key} still on db_shard 1"
        end
        expect(store(1).hget('DEFAULT__tlm__INST', 'HEALTH_STATUS')).to be_nil
        expect(ephemeral(1).exists('DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS')).to eql 0
        expect(ephemeral(1).exists('DEFAULT__COMMAND__{INST}__ABORT')).to eql 0
      end
    end
  end
end
