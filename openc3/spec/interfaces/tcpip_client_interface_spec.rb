# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/tcpip_client_interface'
require 'openc3/interfaces/protocols/burst_protocol'

module OpenC3
  describe TcpipClientInterface do
    describe "initialize" do
      it "is not writeable if no write port given" do
        i = TcpipClientInterface.new('localhost', 'nil', '8889', 'nil', '5', 'burst')
        expect(i.name).to eql "TcpipClientInterface"
        expect(i.write_allowed?).to be false
        expect(i.write_raw_allowed?).to be false
        expect(i.read_allowed?).to be true
      end

      it "is not readable if no read port given" do
        i = TcpipClientInterface.new('localhost', '8888', 'nil', '5', 'nil', 'burst')
        expect(i.name).to eql "TcpipClientInterface"
        expect(i.write_allowed?).to be true
        expect(i.write_raw_allowed?).to be true
        expect(i.read_allowed?).to be false
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = TcpipClientInterface.new('localhost', '8889', '8889', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "localhost:8889 (R/W)"

        i = TcpipClientInterface.new('localhost', '8889', '8890', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "localhost:8889 (write) localhost:8890 (read)"

        i = TcpipClientInterface.new('localhost', '8889', 'nil', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "localhost:8889 (write)"

        i = TcpipClientInterface.new('localhost', 'nil', '8889', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "localhost:8889 (read)"
      end
    end

    # This spec fails when run after all the rest. Is someone opening something
    # that we're connecting to? When run stand alone it works.
    # describe "connect" do
    #  it "raises a timeout when unable to connect" do
    #    i = TcpipClientInterface.new('localhost','8888','8889','5','5','burst')
    #    expect(i.connected?).to be false
    #    i.connect
    #    expect { i.connect }.to raise_error(/Connect timeout/)
    #  end
    # end

    describe "connected?" do
      it "initially returns false" do
        i = TcpipClientInterface.new('localhost', '8888', '8889', '5', '5', 'burst')
        expect(i.connected?).to be false
      end

      it "returns true once connect succeeds" do
        allow_any_instance_of(TcpipClientStream).to receive(:connect_nonblock)
        i = TcpipClientInterface.new('localhost', '8888', '8889', '5', '5', 'burst')
        expect(i.connected?).to be false
        i.connect
        expect(i.connected?).to be true
      end
    end

    describe "details" do
      it "returns detailed interface information" do
        i = TcpipClientInterface.new('localhost', '8888', '8889', '5.0', '10.0', 'burst')

        details = i.details

        expect(details).to be_a(Hash)
        expect(details['hostname']).to eql('localhost')
        expect(details['write_port']).to eql(8888)
        expect(details['read_port']).to eql(8889)
        expect(details['write_timeout']).to eql(5.0)
        expect(details['read_timeout']).to eql(10.0)

        # Check that base interface details are included
        expect(details['name']).to eql('TcpipClientInterface')
        expect(details).to have_key('read_allowed')
        expect(details).to have_key('write_allowed')
        expect(details).to have_key('options')
      end

      it "handles nil values correctly" do
        i = TcpipClientInterface.new('localhost', 'nil', '8889', 'nil', '5.0', 'burst')

        details = i.details

        expect(details['hostname']).to eql('localhost')
        expect(details['write_port']).to be_nil
        expect(details['read_port']).to eql(8889)
        expect(details['write_timeout']).to be_nil
        expect(details['read_timeout']).to eql(5.0)
      end
    end
  end
end
