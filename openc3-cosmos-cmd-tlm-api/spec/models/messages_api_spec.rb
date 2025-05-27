# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require "rails_helper"

RSpec.describe MessagesApi, type: :model do
  let(:subscription_key) { "test_subscription_123" }
  let(:scope) { "DEFAULT" }
  let(:start_time) { Time.now.to_nsec_from_epoch }
  let(:end_time) { (Time.now + 3600).to_nsec_from_epoch }
  let(:mock_thread) { double("MessagesThread") }

  before(:each) do
    mock_redis
    setup_system
    allow(MessagesThread).to receive(:new).and_return(mock_thread)
    allow(mock_thread).to receive(:start)
  end

  describe "#initialize" do
    it "creates a MessagesThread and starts it" do
      expect(mock_thread).to receive(:start)

      api = MessagesApi.new(subscription_key, scope: scope)
      expect(api.instance_variable_get(:@thread)).to eq(mock_thread)
    end

    it "initializes with default parameters" do
      api = MessagesApi.new(subscription_key, scope: scope)

      expect(MessagesThread).to have_received(:new).with(
        subscription_key,
        0,
        start_offset: nil,
        start_time: nil,
        end_time: nil,
        types: nil,
        level: nil,
        scope: scope
      )
    end

    it "initializes with custom parameters" do
      types = ["INFO", "ERROR"]
      level = "WARN"
      history_count = 50
      start_offset = "123-0"

      api = MessagesApi.new(
        subscription_key,
        history_count,
        start_offset: start_offset,
        start_time: start_time,
        end_time: end_time,
        types: types,
        level: level,
        scope: scope
      )

      expect(MessagesThread).to have_received(:new).with(
        subscription_key,
        history_count,
        start_offset: start_offset,
        start_time: start_time,
        end_time: end_time,
        types: types,
        level: level,
        scope: scope
      )
    end
  end
end
