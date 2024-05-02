# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/http_server_interface'

module OpenC3
  describe HttpServerInterface do
    describe "initialize" do
      it "uses a default port of 80" do
        i = HttpServerInterface.new()
        expect(i.name).to eql "HttpServerInterface"
        expect(i.instance_variable_get(:@port)).to eql 80
      end

      it "sets the listen port" do
        i = HttpServerInterface.new('8080')
        expect(i.name).to eql "HttpServerInterface"
        expect(i.instance_variable_get(:@port)).to eql 8080
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = HttpServerInterface.new()
        expect(i.connection_string).to eql "listening on 0.0.0.0:80"

        i = HttpServerInterface.new('8080')
        expect(i.connection_string).to eql "listening on 0.0.0.0:8080"
      end
    end

    describe "set_option" do
      it "sets the listen address for the tcpip_server" do
        i = HttpServerInterface.new('8888')
        i.set_option('LISTEN_ADDRESS', ['127.0.0.1'])
        expect(i.instance_variable_get(:@listen_address)).to eq '127.0.0.1'
        expect(i.connection_string).to eql "listening on 127.0.0.1:8888"
      end
    end

    # TODO: This needs more testing
  end
end
