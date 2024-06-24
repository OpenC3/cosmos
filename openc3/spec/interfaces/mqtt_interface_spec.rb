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
require 'openc3/interfaces/mqtt_interface'

module OpenC3
  describe MqttInterface do
    before(:all) do
      setup_system()
    end

    describe "initialize" do
      it "sets all the instance variables" do
        i = MqttInterface.new('localhost', '1883', 'false')
        expect(i.name).to eql "MqttInterface"
        expect(i.instance_variable_get(:@hostname)).to eql 'localhost'
        expect(i.instance_variable_get(:@port)).to eql 1883
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = MqttInterface.new('localhost', '1883', 'false')
        expect(i.connection_string).to eql "localhost:1883 (ssl: false)"

        i = MqttInterface.new('1.2.3.4', '8080', 'true')
        expect(i.connection_string).to eql "1.2.3.4:8080 (ssl: true)"
      end
    end

    # TODO: This needs more testing
  end
end
