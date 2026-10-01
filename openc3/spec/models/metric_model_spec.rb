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

require 'spec_helper'
require 'openc3/models/metric_model'
require 'openc3/models/scope_model'
module OpenC3
  describe MetricModel do
    before(:each) do
      mock_redis()
      local_s3()
    end

    after(:each) do
      local_s3_unset()
    end

    describe "self.all" do
      it "returns all the metrics" do
        model = MetricModel.new(name: "foo", scope: "scope", values: {"test" => {"value" => 5}})
        model.create(force: true)
        all = MetricModel.all(scope: "scope")
        expect(all.empty?).to eql(false)
        expect(all["foo"].empty?).to eql(false)
        expect(all["foo"]["scope"]).to eql(nil)
        expect(all["foo"]["values"]["test"]["value"]).to eql(5)
      end
    end

    describe "process metrics" do
      # The operator reports cpu/memory on behalf of microservices that exec()
      # into something that never loads the OpenC3 libraries. Those land in a
      # separate redis hash so the two writers never clobber each other, and are
      # merged back together on read.
      it "merges operator reported process metrics into the microservice row" do
        MetricModel.set({ 'name' => 'foo', 'values' => { 'decom_total' => { 'value' => 42 } } },
                        scope: 'scope', queued: false)
        MetricModel.set_process({ 'name' => 'foo', 'values' => { 'average_cpu_utilization' => { 'value' => 0.25 } } },
                                scope: 'scope', queued: false)

        all = MetricModel.all(scope: 'scope')
        expect(all['foo']['values']['decom_total']['value']).to eql(42)
        expect(all['foo']['values']['average_cpu_utilization']['value']).to eql(0.25)
      end

      it "does not let either writer clobber the other" do
        MetricModel.set_process({ 'name' => 'foo', 'values' => { 'average_cpu_utilization' => { 'value' => 0.25 } } },
                                scope: 'scope', queued: false)
        # The microservice publishes again - its own counters must not wipe the
        # process metrics, which is exactly what a shared field would do
        MetricModel.set({ 'name' => 'foo', 'values' => { 'decom_total' => { 'value' => 7 } } },
                        scope: 'scope', queued: false)

        values = MetricModel.all(scope: 'scope')['foo']['values']
        expect(values['decom_total']['value']).to eql(7)
        expect(values['average_cpu_utilization']['value']).to eql(0.25)
      end

      it "surfaces a microservice that only has process metrics" do
        # A plugin running a Rails app or a python script never reports for
        # itself, so the operator's row is all there is
        MetricModel.set_process({ 'name' => 'DEFAULT__USER__CFDP', 'values' => { 'average_cpu_utilization' => { 'value' => 0.1 } } },
                                scope: 'scope', queued: false)

        all = MetricModel.all(scope: 'scope')
        expect(all['DEFAULT__USER__CFDP']['values']['average_cpu_utilization']['value']).to eql(0.1)
        expect(MetricModel.names(scope: 'scope')).to include('DEFAULT__USER__CFDP')
      end

      it "prefers self reported values over operator reported ones" do
        MetricModel.set_process({ 'name' => 'foo', 'values' => { 'num_threads' => { 'value' => 3 } } },
                                scope: 'scope', queued: false)
        MetricModel.set({ 'name' => 'foo', 'values' => { 'num_threads' => { 'value' => 9 } } },
                        scope: 'scope', queued: false)

        expect(MetricModel.get(name: 'foo', scope: 'scope')['values']['num_threads']['value']).to eql(9)
      end

      it "destroys both rows" do
        MetricModel.set({ 'name' => 'foo', 'values' => { 'decom_total' => { 'value' => 42 } } },
                        scope: 'scope', queued: false)
        MetricModel.set_process({ 'name' => 'foo', 'values' => { 'average_cpu_utilization' => { 'value' => 0.25 } } },
                                scope: 'scope', queued: false)

        MetricModel.destroy(scope: 'scope', name: 'foo')
        expect(MetricModel.all(scope: 'scope')['foo']).to be_nil
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = MetricModel.new(name: "foo", scope: "scope", values: {"test" => {"value" => 5}})
        json = model.as_json()
        expect(json["name"]).to eql("foo")
      end
    end

    describe "class get" do
      it "gets by name in scope" do
        model = MetricModel.new(name: "baz", scope: "scope", values: {"test "=> {"value" =>6}})
        model.create
        result = MetricModel.get(name: "baz", scope: "scope")
        expect(result['name']).to eq('baz')
      end
    end

    describe "class destroy" do
      it "destroys by name in scope" do
        model = MetricModel.new(name: "baz", scope: "scope", values: {"test "=> {"value" =>6}})
        model.create
        model = MetricModel.new(name: "bOz", scope: "scope", values: {"test "=> {"value" =>6}})
        model.create
        MetricModel.destroy(scope: 'scope', name: 'baz')
        result = MetricModel.get(name: "baz", scope: "scope")
        expect(result).to be_nil
      end
    end

    describe "names" do
      it "returns all names" do
        model = MetricModel.new(name: 'baz', scope: "scope", values: {"test "=> {"value" =>6}})
        model.create
        result = MetricModel.names(scope: "scope")
        expect(result[0]).to eq('baz')
      end
    end

    describe "redis_metrics" do
      it "returns redis metrics from Store and Ephemeral Store" do
        values = {
          'connected_clients' => 37,
          'used_memory_rss' => 0,
          'total_commands_processed' => 0,
          'instantaneous_ops_per_sec' => 0,
          'instantaneous_input_kbps' => 0,
          'instantaneous_output_kbps' => 0,
          'latency_percentiles_usec_hget' => '1,2'
        }
        model = MetricModel.new(name: "all", scope: "scope", values: {"test" => {"value" => 7}})
        model.create(force: true)

        json = {}
        json['name'] = 'all'
        json['values'] = values
        model = MetricModel.set(json, scope: 'scope')

        # Set up scope and target so redis_metrics can discover db_shards
        scope_model = ScopeModel.new(name: "DEFAULT")
        scope_model.create
        target_model = TargetModel.new(name: "INST", scope: "DEFAULT")
        target_model.create

        allow(OpenC3::Store.instance).to receive(:info) do
          values
        end

        allow(OpenC3::EphemeralStore.instance).to receive(:info) do
          values
        end

        result = MetricModel.redis_metrics
        expect(result.empty?).to eql(false)
        expect(result[0]['redis_connected_clients_total']).to eql(37)
      end
    end
  end
end
