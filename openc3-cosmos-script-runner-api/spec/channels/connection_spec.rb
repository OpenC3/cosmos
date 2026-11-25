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

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "successfully connects" do
    connect "/cable?scope=DEFAULT"
    expect(connection.uuid).to be_a(String) # Any random string will do
  end

  describe "with a token in the URL (deprecated)" do
    before(:each) do
      mock_redis
      $openc3_authorize = true
      allow(OpenC3::AuthModel).to receive(:verify).and_return(false)
      allow(OpenC3::AuthModel).to receive(:verify).with("good").and_return(true)
    end

    after(:each) do
      $openc3_authorize = false
    end

    it "still authenticates the connection and logs a deprecation warning without the token" do
      expect(OpenC3::Logger).to receive(:warn) do |message, scope:|
        expect(message).to include("deprecated")
        expect(message).not_to include("good")
        expect(scope).to eql("DEFAULT")
      end
      connect "/cable?scope=DEFAULT&authorization=good"
      expect(connection.url_authenticated).to be true
    end

    it "rejects a bad token without logging" do
      expect(OpenC3::Logger).not_to receive(:warn)
      expect { connect "/cable?scope=DEFAULT&authorization=bad" }.to have_rejected_connection
    end
  end

  it "does not log when the token is not in the URL" do
    expect(OpenC3::Logger).not_to receive(:warn)
    connect "/cable?scope=DEFAULT"
    expect(connection.url_authenticated).to be_falsey
  end
end
