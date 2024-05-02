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
require 'openc3/interfaces/http_client_interface'

module OpenC3
  describe HttpClientInterface do
    describe "initialize" do
      it "sets all the instance variables" do
        i = HttpClientInterface.new('localhost', '8080', 'https', '10', '11', '12')
        expect(i.name).to eql "HttpClientInterface"
        expect(i.instance_variable_get(:@hostname)).to eql 'localhost'
        expect(i.instance_variable_get(:@port)).to eql 8080
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = HttpClientInterface.new('localhost', '80', 'http', '10', '11', '12')
        expect(i.connection_string).to eql "http://localhost"

        i = HttpClientInterface.new('machine', '443', 'https', '10', '11', '12')
        expect(i.connection_string).to eql "https://machine"

        i = HttpClientInterface.new('127.0.0.1', '8080', 'http', '10', '11', '12')
        expect(i.connection_string).to eql "http://127.0.0.1:8080"
      end
    end

    # TODO: This needs more testing
  end
end
