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

require "rails_helper"

RSpec.describe StreamingThread, type: :model do
  let(:topic) { "DEFAULT__DECOM__{INST}__HEALTH_STATUS" }
  let(:streaming_api) { double("StreamingApi", transmit_results: nil) }
  let(:object) do
    Struct.new(:offset, :db_shard, :topic).new("0-0", 0, topic)
  end
  let(:collection) do
    double("Collection", objects: [object], topics_offsets_and_objects: [[topic], ["0-0"], { topic => [object] }, {}])
  end

  describe "redis_thread_body" do
    it "reads with a count bounded by the batch size" do
      thread = StreamingThread.new(streaming_api, collection, 25)
      expect(OpenC3::Topic).to receive(:read_topics).with([topic], ["0-0"], anything, 25, db_shard: 0).and_return({ topic => [["1-0", {}]] })
      thread.redis_thread_body
    end

    it "advances offsets past stored packets so a capped read makes progress" do
      thread = StreamingThread.new(streaming_api, collection, 25)
      allow(OpenC3::Topic).to receive(:read_topics) do |*_args, **_kwargs, &block|
        block.call(topic, "5-0", { "stored" => "true" }, nil)
        { topic => [["5-0", {}]] }
      end
      expect(thread).not_to receive(:handle_message)
      thread.redis_thread_body
      expect(object.offset).to eql "5-0"
    end
  end
end
