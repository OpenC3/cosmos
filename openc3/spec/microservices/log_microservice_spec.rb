# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/microservices/log_microservice'
require 'openc3/models/microservice_model'

module OpenC3
  describe LogMicroservice do
    before(:each) do
      mock_redis()
      allow(System).to receive(:setup_targets)
      MicroserviceModel.new(name: "DEFAULT__PACKETLOG__INST", options: [["RAW_OR_DECOM", "RAW"], ["CMD_OR_TLM", "TLM"]],
                            topics: [], scope: 'DEFAULT').create
      @lm = LogMicroservice.new("DEFAULT__PACKETLOG__INST")
      allow(@lm.logger).to receive(:error)
    end

    after(:each) do
      @lm.shutdown
    end

    it "keeps reading topics after an error" do
      calls = 0
      allow(Topic).to receive(:read_topics) do
        calls += 1
        raise "Redis unavailable" if calls == 1

        @lm.instance_variable_set(:@cancel_thread, true)
        {}
      end
      allow_any_instance_of(Sleeper).to receive(:sleep).with(1).and_return(false)
      @lm.run
      expect(calls).to eql 2
      expect(@lm.instance_variable_get(:@error_count)).to eql 1
      expect(@lm.error.message).to eql "Redis unavailable"
      expect(@lm.logger).to have_received(:error).with(/error reading topics: .*Redis unavailable/m)
    end

    it "stops retrying when shut down" do
      allow(Topic).to receive(:read_topics).and_raise("Redis unavailable")
      thread = Thread.new { @lm.run }
      sleep 0.1
      expect(thread).to be_alive # Waiting to retry
      @lm.shutdown
      thread.join(10)
      expect(thread).to_not be_alive
    end
  end
end
