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

#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'digest'
require 'spec_helper'
require 'openc3/models/auth_model'

module OpenC3
  PW_HASH_PRIMARY_KEY = 'OPENC3__TOKEN'
  AUTH_INITIAL_PASSWORD = 'password'

  describe AuthModel, type: :model do
    before(:each) do
      @redis = mock_redis()
      wut = @redis.get(PW_HASH_PRIMARY_KEY)
      
      # Disable the auth model mock for this spec
      allow(OpenC3::AuthModel).to receive(:verify).and_call_original
      allow(OpenC3::AuthModel).to receive(:verify_no_service).and_call_original
    end

    describe "authentication" do
      it "creates new" do
        model = AuthModel.new()
        expect(model).to be_a(AuthModel)
      end

      it "self.set" do
        expect{ AuthModel.set('token1token1', nil) }.to \
          raise_error(/old_password must not be nil or empty/)

        expect{ AuthModel.set('token1token1', 'token2token2', PW_HASH_PRIMARY_KEY) }.to \
          raise_error(/old_password incorrect/)

        AuthModel.set('newpassword', AUTH_INITIAL_PASSWORD)
        expect(AuthModel.verify_no_service(AUTH_INITIAL_PASSWORD, no_password: false)).to eq(false)
        expect(AuthModel.verify_no_service('newpassword', no_password: false)).to eq(true)
      end

      it "self.verify" do
        expect(AuthModel.verify('badpassword')).to eq(false)
        expect(AuthModel.verify(AUTH_INITIAL_PASSWORD, no_password: false)).to eq(true)
        expect(AuthModel.verify(AUTH_INITIAL_PASSWORD, no_password: true)).to eq(false)
      end

      it "verifies and terminates a session token" do
        token = AuthModel.generate_session
        expect(AuthModel.verify(token)).to eq(true)

        AuthModel.logout
        expect(AuthModel.verify(token)).to eq(false)
      end

      it "raises when stored password hash is SHA256" do
        @redis.set(PW_HASH_PRIMARY_KEY, Digest::SHA256.hexdigest(AUTH_INITIAL_PASSWORD))
        expect{ AuthModel.verify_no_service(AUTH_INITIAL_PASSWORD, no_password: false) }.to \
          raise_error(/invalid password hash/)
      end
    end
  end
end
