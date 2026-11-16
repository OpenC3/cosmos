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
require 'base64'
require 'json'
require 'openc3/utilities/service_account_script_auth'

module OpenC3
  describe ServiceAccountScriptAuth do
    describe '.persist_service_account_script_auth_context' do
      let(:payload) { Base64.urlsafe_encode64({ 'azp' => 'cosmos-m2m' }.to_json).delete('=') }
      let(:token) { "header.#{payload}.signature" }
      let(:secret_client) { double('secrets_client') }

      it 'upserts the durable service-account auth context' do
        allow(OpenC3::Secrets).to receive(:getClient).and_return(secret_client)
        expect(secret_client).to receive(:get).with('cosmos-m2m', scope: 'DEFAULT').and_return('stored-m2m-secret')
        expect(OpenC3::ServiceAccountScriptAuthModel).to receive(:set).with(
          {
            name: 'service-account-cosmos-m2m',
            auth_kind: 'client_credentials',
            client_id: 'cosmos-m2m',
            client_secret_name: 'cosmos-m2m',
            secret_store: nil,
          },
          scope: 'DEFAULT',
        )

        ServiceAccountScriptAuth.persist_service_account_script_auth_context(
          scope: 'DEFAULT',
          username: 'service-account-cosmos-m2m',
          token: token,
        )
      end
    end
  end
end
