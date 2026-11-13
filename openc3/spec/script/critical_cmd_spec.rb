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
require 'openc3/script'

module OpenC3
  describe Script do
    before(:each) do
      @orig_api_server = $api_server
      $api_server = double("ApiServer")
    end

    after(:each) do
      $api_server = @orig_api_server
    end

    def stub_request(method, endpoint, status: 200, body: {})
      response = double("Response", status: status, body: JSON.generate(body))
      expect($api_server).to receive(:request).with(method, endpoint, any_args).and_return(response)
    end

    describe "critical_cmd_status" do
      it "returns the status" do
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', body: { status: 'WAITING', approvers: ['alice'], approvers_required: 2 })
        expect(critical_cmd_status('UUID')).to eql 'WAITING'
      end
    end

    describe "critical_cmd_info" do
      it "returns the status and approvals" do
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', body: { status: 'WAITING', approvers: ['alice'], approvers_required: 2 })
        expect(critical_cmd_info('UUID')).to eql({ 'status' => 'WAITING', 'approvers' => ['alice'], 'approvers_required' => 2 })
      end

      it "defaults approvals for older servers" do
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', body: { status: 'APPROVED' })
        expect(critical_cmd_info('UUID')).to eql({ 'status' => 'APPROVED', 'approvers' => [], 'approvers_required' => 1 })
      end

      it "raises on error" do
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', status: 404, body: { status: 'error', message: 'not found' })
        expect { critical_cmd_info('UUID') }.to raise_error(/critical_cmd_info failed/)
      end
    end

    describe "critical_cmd_status and critical_cmd_info" do
      it "return a nil status if missing" do
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', body: {})
        expect(critical_cmd_status('UUID')).to be_nil
        stub_request('get', '/openc3-api/criticalcmd/status/UUID', body: {})
        expect(critical_cmd_info('UUID')['status']).to be_nil
      end
    end

    describe "critical_cmd_can_approve" do
      it "returns whether the user can approve" do
        stub_request('get', '/openc3-api/criticalcmd/canapprove/UUID', body: { status: 'ok' })
        expect(critical_cmd_can_approve('UUID')).to be true
        stub_request('get', '/openc3-api/criticalcmd/canapprove/UUID', body: { status: 'error', message: 'already approved by alice' })
        expect(critical_cmd_can_approve('UUID')).to be false
      end

      it "raises on error" do
        stub_request('get', '/openc3-api/criticalcmd/canapprove/UUID', status: 404, body: { status: 'error', message: 'not found' })
        expect { critical_cmd_can_approve('UUID') }.to raise_error(/critical_cmd_can_approve failed/)
      end
    end

    describe "critical_cmd_approve" do
      it "raises with the server message" do
        stub_request('post', '/openc3-api/criticalcmd/approve/UUID', status: 500, body: { status: 'error', message: 'already approved by alice' })
        expect { critical_cmd_approve('UUID') }.to raise_error(/already approved by alice/)
      end
    end

    describe "critical_cmd_reject" do
      it "raises with the server message" do
        stub_request('post', '/openc3-api/criticalcmd/reject/UUID', status: 500, body: { status: 'error', message: 'already APPROVED' })
        expect { critical_cmd_reject('UUID') }.to raise_error(/already APPROVED/)
      end
    end
  end
end
