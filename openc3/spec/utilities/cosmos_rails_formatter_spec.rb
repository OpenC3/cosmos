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
require 'openc3/utilities/cosmos_rails_formatter'

module OpenC3
  describe CosmosRailsFormatter do
    let(:formatter) { CosmosRailsFormatter.new }

    def request(headers: {}, query_parameters: {})
      double('request', headers: headers, query_parameters: query_parameters)
    end

    def log(named_tags: {}, payload: nil, message: 'Completed #index')
      double('log', level: :info, message: message, thread_name: 'puma srv tp 001', duration: 1.5,
                    named_tags: named_tags, payload: payload, exception: nil)
    end

    describe "username" do
      it "resolves the username from the Authorization header" do
        expect(formatter).to receive(:user_info).with('header-token').and_return({ 'username' => 'operator' })
        expect(formatter.username(request(headers: { 'HTTP_AUTHORIZATION' => 'header-token' }))).to eql('operator')
      end

      it "falls back to the authorization query parameter" do
        expect(formatter).to receive(:user_info).with('query-token').and_return({ 'username' => 'operator' })
        expect(formatter.username(request(query_parameters: { authorization: 'query-token' }))).to eql('operator')
      end

      it "returns nil without a token so no tag is added" do
        expect(formatter).not_to receive(:user_info)
        expect(formatter.username(request)).to be_nil
      end

      it "returns anonymous when the token has no username" do
        expect(formatter).to receive(:user_info).and_return({})
        expect(formatter.username(request(headers: { 'HTTP_AUTHORIZATION' => 'token' }))).to eql('anonymous')
      end

      it "returns anonymous when the token is invalid" do
        expect(formatter).to receive(:user_info).and_raise(AuthError.new("Token is invalid"))
        expect(formatter.username(request(headers: { 'HTTP_AUTHORIZATION' => 'bad' }))).to eql('anonymous')
      end
    end

    describe "call" do
      it "logs the username tag without looking up a token" do
        expect(formatter).not_to receive(:user_info)
        json = JSON.parse(formatter.call(log(named_tags: { request_id: 'abc', username: 'operator' },
                                             payload: { path: '/openc3-api/x', status: 200 })))
        expect(json['user']).to eql('operator')
        expect(json['request_id']).to eql('abc')
        expect(json['path']).to eql('/openc3-api/x')
        expect(json['status']).to eql(200)
      end

      it "logs anonymous without a username tag" do
        json = JSON.parse(formatter.call(log(named_tags: { request_id: 'abc' })))
        expect(json['user']).to eql('anonymous')
      end
    end
  end
end
