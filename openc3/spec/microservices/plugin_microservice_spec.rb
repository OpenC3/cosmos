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
require 'openc3/microservices/plugin_microservice'

# Override at_exit to do nothing for testing
saved_verbose = $VERBOSE; $VERBOSE = nil
def at_exit(*args, &block)
end
$VERBOSE = saved_verbose

module OpenC3
  describe PluginMicroservice do
    before(:each) do
      # Avoid spawning the Metric update thread (would leak past the test)
      allow(Metric).to receive(:new).and_return(double("Metric").as_null_object)
      allow(MetricModel).to receive(:new).and_return(double("MetricModel").as_null_object)
      config = { 'cmd' => ['rails', 's'], 'topics' => [], 'target_names' => [], 'secrets' => nil, 'plugin' => 'PLUGIN', 'work_dir' => '.' }
      allow(MicroserviceModel).to receive(:get).and_return(config)
      client = double("BucketClient")
      allow(client).to receive(:list_objects).and_return([])
      allow(Bucket).to receive(:getClient).and_return(client)
      allow(Dir).to receive(:chdir)
      allow(FileUtils).to receive(:chmod)

      capture_io do
        @microservice = PluginMicroservice.new("DEFAULT__USER__NAME")
      end
      # Microservice.run sets this in memory right before calling run
      @microservice.state = 'RUNNING'
      allow(@microservice).to receive(:exec)
    end

    describe "run" do
      it "publishes RUNNING status before exec replaces the process" do
        expect(MicroserviceStatusModel).to receive(:set).with(hash_including('name' => "DEFAULT__USER__NAME", 'state' => 'RUNNING'), scope: 'DEFAULT').ordered
        expect(@microservice).to receive(:exec).with('rails', 's').ordered
        @microservice.run
      end

      it "still execs the cmd if publishing status fails" do
        allow(MicroserviceStatusModel).to receive(:set).and_raise("redis down")
        expect(@microservice).to receive(:exec).with('rails', 's')
        capture_io do
          @microservice.run
        end
      end
    end
  end
end
