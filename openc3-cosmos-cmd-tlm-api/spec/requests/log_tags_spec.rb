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

require 'rails_helper'

# Runs through the full middleware stack so the log tags are computed by the
# Rack logger, as in production.
RSpec.describe "Request log tags", type: :request do
  before(:each) do
    mock_redis()
    # Write out entries queued by earlier specs so only this request is captured
    SemanticLogger.flush
    @default_level = SemanticLogger.default_level
    SemanticLogger.default_level = :debug
    @logged = []
    allow_any_instance_of(OpenC3::CosmosRailsFormatter).to receive(:call).and_wrap_original do |original, log, appender|
      @logged << log.named_tags.dup
      original.call(log, appender)
    end
  end

  after(:each) do
    SemanticLogger.default_level = @default_level
  end

  def request_tags(headers = {})
    get '/openc3-api/traefik', headers: headers
    SemanticLogger.flush
    expect(@logged).not_to be_empty
    @logged
  end

  it "tags each entry with the request id and the resolved username, not the token" do
    allow_any_instance_of(OpenC3::CosmosRailsFormatter).to receive(:user_info).with('secret-token').and_return({ 'username' => 'operator' })
    request_tags('Authorization' => 'secret-token').each do |tags|
      expect(tags[:request_id]).to match(/\A\h{8}-/)
      expect(tags[:username]).to eql('operator')
      expect(tags).not_to have_key(:token)
      expect(tags.values).not_to include('secret-token')
    end
  end

  it "leaves the username tag off when there is no token" do
    request_tags.each do |tags|
      expect(tags[:request_id]).to match(/\A\h{8}-/)
      expect(tags).not_to have_key(:username)
    end
  end
end
