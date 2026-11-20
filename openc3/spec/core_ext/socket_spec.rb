# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/core_ext/socket'

describe Socket do
  describe "get_own_ip_address" do
    it "returns the ip address the machine's hostname resolves to" do
      # Stub the lookup because CI runners don't reliably resolve their own
      # hostname (one returned "" rather than an address or a ResolvError)
      allow(Socket).to receive(:gethostname).and_return("myhost")
      expect(Resolv).to receive(:getaddress).with("myhost").and_return("10.1.2.3")
      expect(Socket.get_own_ip_address).to eql "10.1.2.3"
    end
  end

  describe "lookup_hostname_from_ip" do
    it "returns the hostname for the ip address" do
      ipaddr = Resolv.getaddress "localhost"
      expect(Socket.lookup_hostname_from_ip(ipaddr)).to_not be_nil
    end
  end
end
