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

require "spec_helper"
require "openc3/utilities/metric"
require "openc3/models/metric_model"

module OpenC3
  describe Metric do
    before(:each) do
      mock_redis_db_shards()
      # Don't start the update thread, tests run a single pass of it
      @update_thread = Metric.class_variable_get(:@@update_thread)
      @instances = Metric.class_variable_get(:@@instances)
      @update_generators = Metric.class_variable_get(:@@update_generators)
      Metric.class_variable_set(:@@update_thread, "Test")
      Metric.class_variable_set(:@@instances, [])
      Metric.class_variable_set(:@@update_generators, [])
    end

    after(:each) do
      Metric.class_variable_set(:@@update_thread, @update_thread)
      Metric.class_variable_set(:@@instances, @instances)
      Metric.class_variable_set(:@@update_generators, @update_generators)
    end

    describe "db_shard" do
      it "uses the given db_shard" do
        expect(Metric.new(microservice: "DEFAULT__DECOM__INST", scope: "DEFAULT", db_shard: 2).db_shard).to eql 2
      end

      it "looks up the db_shard of the microservice on db_shard 0" do
        Store.instance(db_shard: 0).hset('openc3_microservices', 'DEFAULT__DECOM__INST', JSON.generate({ 'name' => 'DEFAULT__DECOM__INST', 'db_shard' => '2' }))
        expect(Metric.new(microservice: "DEFAULT__DECOM__INST", scope: "DEFAULT").db_shard).to eql 2
      end

      it "uses db_shard 0 for a microservice which doesn't exist or can't be looked up" do
        expect(Metric.new(microservice: "DEFAULT__DECOM__MISSING", scope: "DEFAULT").db_shard).to eql 0
        allow(Store).to receive(:hget).and_raise("down")
        expect(Metric.new(microservice: "DEFAULT__DECOM__INST", scope: "DEFAULT").db_shard).to eql 0
      end

      it "sets the metrics with the db_shard of each microservice" do
        metric1 = Metric.new(microservice: "DEFAULT__DECOM__INST", scope: "DEFAULT", db_shard: 1)
        metric1.set(name: 'count', value: 1)
        metric2 = Metric.new(microservice: "OTHER__DECOM__INST2", scope: "OTHER", db_shard: 2)
        metric2.set(name: 'count', value: 2)
        # No values so nothing is set
        Metric.new(microservice: "DEFAULT__DECOM__EMPTY", scope: "DEFAULT", db_shard: 3)
        sets = []
        allow(MetricModel).to receive(:set) { |json, scope:| sets << [json['name'], json['db_shard'], scope] }
        allow_any_instance_of(Sleeper).to receive(:sleep).and_return(true)
        metric1.update_thread_body
        expect(sets).to eql [["DEFAULT__DECOM__INST", 1, "DEFAULT"], ["OTHER__DECOM__INST2", 2, "OTHER"]]
      end
    end
  end
end
