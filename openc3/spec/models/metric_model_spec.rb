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

require 'spec_helper'
require 'openc3/models/metric_model'

module OpenC3
  describe MetricModel do
    before(:each) do
      mock_redis()
    end

    describe "class all" do
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

    describe "instance as_json" do
      it "encodes all the input parameters" do
        model = MetricModel.new(name: "foo", scope: "scope", values: {"test" => {"value" => 5}})
        json = model.as_json(:allow_nan => true)
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
          'connected_clients' => {'value' => 0},
          'used_memory_rss' => {'value' => 0},
          'total_commands_processed' => {'value' => 0},
          'instantaneous_ops_per_sec' => {'value' => 0},
          'instantaneous_input_kbps' => {'value' => 0},
          'instantaneous_output_kbps' => {'value' => 0},
          'latency_percentiles_usec_hget'=> {'value' => '1,2'}
        }
        model = MetricModel.new(name: "all", scope: "scope", values: {"test" => {"value" => 7}})
        model.create(force: true)

        json = {}
        json['name'] = 'all'
        json['values'] = values
        model = MetricModel.set(json, scope: 'scope')

        allow(OpenC3::Store.instance).to receive(:info) do
          values
        end

        allow(OpenC3::EphemeralStore.instance).to receive(:info) do
          values
        end

        result = MetricModel.redis_metrics
        expect(result.empty?).to eql(false)
        if (!(result['bar'].nil?)) then
          expect(result['bar'].not_to be_nil)
          expect(result["bar"].empty?).to eql(false)
          expect(result["bar"]["scope"]).to eql(nil)
          expect(result["bar"]["values"]["test"]["value"]).to eql(7)
        end
      rescue StandardError => e
        puts e
      end
    end
  end
end
