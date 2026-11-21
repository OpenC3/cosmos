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
require 'openc3/utilities/client_ip_header_filter'

module OpenC3
  describe ClientIpHeaderFilter do
    it "removes Client-IP and Forwarded and keeps everything else" do
      seen = nil
      app = ->(env) { seen = env.dup; [200, {}, ['OK']] }
      env = {
        'REMOTE_ADDR' => '172.18.0.1',
        'HTTP_X_FORWARDED_FOR' => '172.18.0.1',
        'HTTP_X_REAL_IP' => '172.18.0.1',
        'HTTP_CLIENT_IP' => '172.18.0.1, 8.8.8.5',
        'HTTP_FORWARDED' => 'for=172.18.0.1, for=8.8.8.5',
      }
      result = ClientIpHeaderFilter.new(app).call(env)
      expect(result).to eql([200, {}, ['OK']])
      expected = {
        'REMOTE_ADDR' => '172.18.0.1',
        'HTTP_X_FORWARDED_FOR' => '172.18.0.1',
        'HTTP_X_REAL_IP' => '172.18.0.1',
      }
      expect(seen).to eql(expected)
    end

    it "passes requests without those headers through unchanged" do
      seen = nil
      app = ->(env) { seen = env.dup; [200, {}, ['OK']] }
      env = { 'REMOTE_ADDR' => '127.0.0.1', 'PATH_INFO' => '/' }
      ClientIpHeaderFilter.new(app).call(env)
      expect(seen).to eql({ 'REMOTE_ADDR' => '127.0.0.1', 'PATH_INFO' => '/' })
    end
  end
end
