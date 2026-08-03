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
require 'openc3/io/json_drb'

module OpenC3
  describe JsonDRb do
    # Stands in for the object exposed over JSON-RPC. Only #greet is allowed;
    # #secret exists to prove that a real method is still rejected when it is
    # not in the whitelist.
    class JsonDRbSpecTarget
      def greet(name:)
        "hello #{name}"
      end

      def secret
        'unreachable'
      end
    end

    let(:json_drb) do
      drb = JsonDRb.new(method_whitelist: ['greet'])
      drb.object = JsonDRbSpecTarget.new
      drb
    end

    # Builds a JSON-RPC request, processes it, and returns the parsed response
    def process(json_drb, method_name, params: [], keyword_params: {})
      request = { 'jsonrpc' => '2.0', 'method' => method_name, 'id' => 1 }
      request['params'] = params unless params.empty?
      request['keyword_params'] = keyword_params unless keyword_params.empty?
      response_data, error_code = json_drb.process_request(
        request_data: JSON.generate(request), request_headers: {}, start_time: Time.now
      )
      return JSON.parse(response_data), error_code
    end

    describe "method_whitelist" do
      it "is required" do
        expect { JsonDRb.new }.to raise_error(ArgumentError, /missing keyword: :method_whitelist/)
      end

      it "rejects a nil or empty whitelist" do
        [nil, [], Set[]].each do |whitelist|
          expect { JsonDRb.new(method_whitelist: whitelist) }.to raise_error(
            ArgumentError, /method_whitelist is required and must not be empty/
          )
        end
      end

      it "downcases the method names into a Set" do
        drb = JsonDRb.new(method_whitelist: ['Tlm', :CMD])
        expect(drb.method_whitelist).to eql(Set['tlm', 'cmd'])
      end

      it "can be replaced but still cannot be cleared" do
        drb = JsonDRb.new(method_whitelist: ['tlm'])
        drb.method_whitelist = ['cmd']
        expect(drb.method_whitelist).to eql(Set['cmd'])
        expect { drb.method_whitelist = [] }.to raise_error(ArgumentError)
        expect(drb.method_whitelist).to eql(Set['cmd'])
      end
    end

    describe "process_request" do
      it "calls a whitelisted method" do
        response, error_code = process(json_drb, 'greet', keyword_params: { 'name' => 'world' })
        expect(response['result']).to eql('hello world')
        expect(error_code).to be_nil
      end

      it "matches whitelisted methods case insensitively" do
        response, _error_code = process(json_drb, 'GREET', keyword_params: { 'name' => 'world' })
        expect(response['result']).to eql('hello world')
      end

      it "rejects a method that exists on the object but is not whitelisted" do
        response, error_code = process(json_drb, 'secret')
        expect(response['error']['message']).to eql('Cannot call unauthorized methods')
        expect(error_code).to eql(JsonRpcError::ErrorCode::OTHER_ERROR)
      end

      # These are all public methods on Object (several added by ActiveSupport)
      # which allow arbitrary code execution or leak server state. The whitelist
      # is what blocks them; there is no blocklist to keep in sync.
      it "rejects reflection and code evaluation methods" do
        %w[send __send__ public_send try try! instance_eval instance_exec class_eval
           method instance_variable_get instance_variable_set instance_values
           methods public_methods singleton_class extend freeze inspect to_s
           to_yaml to_json as_json].each do |method_name|
          response, _error_code = process(json_drb, method_name, params: ['1+1'])
          expect(response['error']['message']).to eql('Cannot call unauthorized methods'),
                                                  "expected #{method_name} to be rejected"
        end
      end

      it "rejects an unknown method" do
        response, _error_code = process(json_drb, 'does_not_exist')
        expect(response['error']['message']).to eql('Cannot call unauthorized methods')
      end
    end
  end
end
