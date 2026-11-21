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

# Runs through the full middleware stack (unlike the controller specs) so the
# client address comes from ActionDispatch::RemoteIp as it does in production.
RSpec.describe "Auth client ip", type: :request do
  let(:key_prefix) { 'openc3__auth_bad_attempts__user__' }

  before(:each) do
    mock_redis()
    OpenC3::AuthModel.set('PASSWORD', nil)
  end

  def bad_attempt_keys
    OpenC3::EphemeralStore.scan_each(match: "#{key_prefix}*").to_a
  end

  # The request comes from 172.18.0.1 (a docker bridge gateway, as traefik
  # sees a local browser) and traefik sets X-Forwarded-For to that address
  def proxy_headers(extra = {})
    { 'REMOTE_ADDR' => '172.18.0.1', 'X-Forwarded-For' => '172.18.0.1' }.merge(extra)
  end

  {
    'Client-IP' => ->(i) { "172.18.0.1, 8.8.8.#{i}" },
    'Forwarded' => ->(i) { "for=172.18.0.1, for=8.8.8.#{i}" },
  }.each do |header, value|
    it "ignores the #{header} header when choosing the bad attempt counter" do
      15.times do |i|
        post '/openc3-api/auth/verify', params: { password: 'BAD' }, headers: proxy_headers(header => value.call(i + 1))
        expect(response).to have_http_status(i < 10 ? :unauthorized : :too_many_requests)
      end
      expect(bad_attempt_keys).to eql(["#{key_prefix}172.18.0.1"])
    end
  end

  it "uses the address traefik put in X-Forwarded-For" do
    10.times do
      post '/openc3-api/auth/verify', params: { password: 'BAD' }, headers: proxy_headers('X-Forwarded-For' => '8.8.8.8')
    end
    post '/openc3-api/auth/verify', params: { password: 'PASSWORD' }, headers: proxy_headers('X-Forwarded-For' => '8.8.8.8')
    expect(response).to have_http_status(:too_many_requests)
    expect(bad_attempt_keys).to eql(["#{key_prefix}8.8.8.8"])

    # A different client is not affected
    post '/openc3-api/auth/verify', params: { password: 'PASSWORD' }, headers: proxy_headers('X-Forwarded-For' => '9.9.9.9')
    expect(response).to have_http_status(:ok)
  end
end
