# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.

require 'spec_helper'
require 'openc3/models/bridge_model'

module OpenC3
  describe BridgeModel do
    before(:each) do
      mock_redis()
    end

    describe "generate_enrollment_token" do
      it "timestamps the stored one-time enrollment code" do
        now = Time.at(1_700_000_000).utc
        model = BridgeModel.new(name: "LAB1", scope: "DEFAULT", ticket: "ticket")
        model.create

        allow(Time).to receive(:now).and_return(now)
        token = model.generate_enrollment_token

        stored = BridgeModel.get(name: "LAB1", scope: "DEFAULT")
        payload = JSON.parse(Base64.urlsafe_decode64(token))
        expect(stored["enroll_code_generated_at"]).to eq(now.to_i)
        expect(stored["enroll_code"]).to eq(payload["code"])
      end
    end
  end
end
