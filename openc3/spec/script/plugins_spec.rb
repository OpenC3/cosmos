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
require 'net/http'

module OpenC3
  describe Script do
    describe "plugin_list" do
      let(:plugins) do
        [
          'openc3-cosmos-tool-admin-1.0.0.gem__20260101000000',
          'openc3-tool-base-1.0.0.gem__20260101000000',
          'openc3-cosmos-demo-1.0.0.gem__20260101000000',
          'openc3-cosmos-tool-newtool-1.0.0.gem__20260101000000',
          'my-plugin-1.0.0.gem__20260101000000',
        ]
      end

      before(:each) do
        @orig_scope = $openc3_scope
        @orig_api_server = $api_server
        $openc3_scope = 'DEFAULT'
        $api_server = double("ApiServer")
        allow($api_server).to receive(:generate_url).and_return("http://localhost:2900")
        allow($api_server).to receive(:generate_auth).and_return(double("Auth", token: 'TOKEN'))
      end

      after(:each) do
        $openc3_scope = @orig_scope
        $api_server = @orig_api_server
      end

      def stub_http(body: JSON.generate(plugins), success: true)
        @requested_paths = []
        http = double("Http")
        allow(http).to receive(:request) do |req, &block|
          @requested_paths << req.path
          response = double("Response", body: body)
          if success
            allow(response).to receive(:value)
          else
            allow(response).to receive(:value).and_raise(Net::HTTPServerException.new("500 Server Error", response))
          end
          block.call(response)
        end
        allow(Net::HTTP).to receive(:start) { |_host, _port, **_opts, &block| block.call(http) }
        http
      end

      it "requests the plugins endpoint with the scope and auth" do
        http = stub_http
        expect(http).to receive(:request) do |req, &block|
          expect(req).to be_a(Net::HTTP::Get)
          expect(req.path).to eq("/openc3-api/plugins?scope=OTHER")
          expect(req['Authorization']).to eq('TOKEN')
          block.call(double("Response", body: '[]', value: nil))
        end
        expect(plugin_list(default: true, scope: 'OTHER')).to eq([])
      end

      it "returns all plugins when default is true" do
        stub_http
        expect(plugin_list(default: true)).to eq(plugins)
        expect(@requested_paths).to eq(["/openc3-api/plugins?scope=DEFAULT"])
      end

      it "asks the API to exclude the default plugins when default is false" do
        stub_http(body: JSON.generate(['my-plugin-1.0.0.gem__20260101000000']))
        expect(plugin_list).to eq(['my-plugin-1.0.0.gem__20260101000000'])
        expect(@requested_paths).to eq(["/openc3-api/plugins?scope=DEFAULT&exclude_default=true"])
      end

      it "raises with the uri and response body on an http error" do
        stub_http(body: "boom", success: false)
        expect { plugin_list }.to raise_error(
          RuntimeError, /plugin_list failed.*URI:http:\/\/localhost:2900\/openc3-api\/plugins\?scope=DEFAULT&exclude_default=true.*boom/m
        )
      end

      it "raises when the body is not valid json" do
        stub_http(body: "not json")
        expect { plugin_list }.to raise_error(RuntimeError, /plugin_list failed/)
      end
    end
  end
end
