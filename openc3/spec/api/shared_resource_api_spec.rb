# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/api/api'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'

module OpenC3
  describe Api do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      mock_redis()
      allow(Logger).to receive(:info)
      allow(Logger).to receive(:warn)
      SharedResourceModel.clear_cache
      @api = ApiTest.new
      %w(DEFAULT OTHER).each do |scope|
        SharedResourceModel.add_member('CHAMBER', scope: scope, type: 'INTERFACE', member_name: "#{scope}__INTERFACE__INT")
        SharedResourceModel.add_member('CHAMBER', scope: scope, type: 'ROUTER', member_name: "#{scope}__ROUTER__ROUTE")
        SharedResourceModel.add_member('CHAMBER', scope: scope, type: 'TARGET', member_name: 'INST')
      end
      SharedResourceModel.add_member('LAB', scope: 'THIRD', type: 'TARGET', member_name: 'INST')
    end

    describe "get_shared_resources" do
      it "returns the shared resources with members in the scope" do
        resources = @api.get_shared_resources(scope: 'DEFAULT')
        expect(resources.map { |resource| resource['name'] }).to eql ['CHAMBER']
        expect(resources[0]['owner']).to eql 'DEFAULT'
        expect(@api.get_shared_resources(scope: 'THIRD').map { |resource| resource['name'] }).to eql ['LAB']
        expect(@api.get_shared_resources(scope: 'NONE')).to eql []
      end
    end

    describe "get_shared_resource" do
      it "returns the shared resource" do
        expect(@api.get_shared_resource('chamber')['members'].keys).to eql %w(DEFAULT OTHER)
        expect(@api.get_shared_resource('NOPE')).to be_nil
      end
    end

    describe "switch_shared_resource" do
      it "defaults to the current scope" do
        record = @api.switch_shared_resource('CHAMBER', scope: 'OTHER')
        expect(record['state']).to eql 'RELEASING'
        expect(record['to']).to eql 'OTHER'
      end

      it "requires admin in both the new and current scopes" do
        expect(@api).to receive(:authorize).with(hash_including(permission: 'admin', scope: 'OTHER')).ordered
        expect(@api).to receive(:authorize).with(hash_including(permission: 'admin', scope: 'DEFAULT')).ordered
        @api.switch_shared_resource('CHAMBER', 'OTHER', scope: 'DEFAULT')
      end

      it "forces the switch" do
        record = @api.switch_shared_resource('CHAMBER', 'OTHER', force: true)
        expect(record['owner']).to eql 'OTHER'
        expect(record['state']).to eql 'ACTIVE'
      end

      it "raises for unknown resources and scopes" do
        expect { @api.switch_shared_resource('NOPE', 'OTHER') }.to raise_error("Shared resource 'NOPE' does not exist")
        expect { @api.switch_shared_resource('CHAMBER', 'THIRD') }.to raise_error(/no members in scope 'THIRD'/)
      end
    end

    describe "release_shared_resource" do
      it "requires admin in the current owner's scope" do
        expect(@api).to receive(:authorize).with(hash_including(permission: 'admin', scope: 'OTHER')).ordered
        expect(@api).to receive(:authorize).with(hash_including(permission: 'admin', scope: 'DEFAULT')).ordered
        record = @api.release_shared_resource('CHAMBER', force: true, scope: 'OTHER')
        expect(record['owner']).to be_nil
      end

      it "raises for unknown resources" do
        expect { @api.release_shared_resource('NOPE') }.to raise_error("Shared resource 'NOPE' does not exist")
      end
    end

    describe "guards" do
      it "rejects commands to a target in an inactive scope" do
        expect(TargetModel).not_to receive(:packet)
        expect { @api.cmd("INST", "ABORT", {}, scope: 'OTHER') }.to raise_error("Target INST is part of shared resource CHAMBER which is active in scope DEFAULT")
      end

      it "allows commands to a target in the active scope" do
        expect(TargetModel).to receive(:packet).and_raise("reached packet")
        expect { @api.cmd("INST", "ABORT", {}, scope: 'DEFAULT') }.to raise_error("reached packet")
      end

      it "rejects interface commands in an inactive scope" do
        expect(InterfaceTopic).not_to receive(:connect_interface)
        expect(InterfaceTopic).not_to receive(:interface_cmd)
        expect(InterfaceTopic).not_to receive(:protocol_cmd)
        expect(InterfaceTopic).not_to receive(:interface_details)
        expect { @api.connect_interface("INT", scope: 'OTHER') }.to raise_error(/Interface INT is part of shared resource CHAMBER/)
        expect { @api.interface_cmd("INT", "CMD", scope: 'OTHER') }.to raise_error(/Interface INT is part of shared resource CHAMBER/)
        expect { @api.interface_protocol_cmd("INT", "CMD", scope: 'OTHER') }.to raise_error(/Interface INT is part of shared resource CHAMBER/)
        expect { @api.interface_details("INT", scope: 'OTHER') }.to raise_error(/Interface INT is part of shared resource CHAMBER/)
      end

      it "allows interface commands in the active scope" do
        expect(InterfaceTopic).to receive(:connect_interface)
        @api.connect_interface("INT", scope: 'DEFAULT')
      end

      it "rejects send_raw in an inactive scope" do
        allow(@api).to receive(:get_interface).and_return({ 'cmd_target_names' => ['INST'] })
        expect(InterfaceTopic).not_to receive(:write_raw)
        expect { @api.send_raw("INT", "\x00", scope: 'OTHER') }.to raise_error(/Interface INT is part of shared resource CHAMBER/)
      end

      it "rejects router commands in an inactive scope" do
        expect(RouterTopic).not_to receive(:connect_router)
        expect(RouterTopic).not_to receive(:router_cmd)
        expect(RouterTopic).not_to receive(:protocol_cmd)
        expect(RouterTopic).not_to receive(:router_details)
        expect { @api.connect_router("ROUTE", scope: 'OTHER') }.to raise_error(/Router ROUTE is part of shared resource CHAMBER/)
        expect { @api.router_cmd("ROUTE", "CMD", scope: 'OTHER') }.to raise_error(/Router ROUTE is part of shared resource CHAMBER/)
        expect { @api.router_protocol_cmd("ROUTE", "CMD", scope: 'OTHER') }.to raise_error(/Router ROUTE is part of shared resource CHAMBER/)
        expect { @api.router_details("ROUTE", scope: 'OTHER') }.to raise_error(/Router ROUTE is part of shared resource CHAMBER/)
      end

      it "allows router commands in the active scope" do
        expect(RouterTopic).to receive(:connect_router)
        @api.connect_router("ROUTE", scope: 'DEFAULT')
      end
    end
  end
end
