# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'spec_helper'
require 'openc3'
require 'openc3/script'
require 'openc3/script/autonomic'
require 'openc3/api/api'

module OpenC3
  describe Script do
    class AutonomicSpecApi
      include Api

      def initialize
        @responses = {}

        # Default successful responses for group methods
        @responses['/openc3-api/autonomic/group'] = {
          'get' => [200, '["DEFAULT","TEST"]'],
          'post' => [201, '{"name":"TEST","scope":"DEFAULT"}']
        }
        @responses['/openc3-api/autonomic/group/TEST'] = {
          'get' => [200, '{"name":"TEST","scope":"DEFAULT"}'],
          'delete' => [200, '{}']
        }

        # Default successful responses for trigger methods
        @responses['/openc3-api/autonomic/DEFAULT/trigger'] = {
          'get' => [200, '[{"name":"TEMP1_HIGH","group":"DEFAULT","left":"INST HEALTH_STATUS TEMP1","operator":">","right":"80","scope":"DEFAULT"}]'],
          'post' => [201, '{"name":"TEMP1_HIGH","group":"DEFAULT","left":"INST HEALTH_STATUS TEMP1","operator":">","right":"80","scope":"DEFAULT"}']
        }
        @responses['/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH'] = {
          'get' => [200, '{"name":"TEMP1_HIGH","group":"DEFAULT","left":"INST HEALTH_STATUS TEMP1","operator":">","right":"80","scope":"DEFAULT"}'],
          'put' => [200, '{"name":"TEMP1_HIGH","group":"DEFAULT","left":"INST HEALTH_STATUS TEMP1","operator":">","right":"90","scope":"DEFAULT"}'],
          'delete' => [200, '{}']
        }
        @responses['/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH/enable'] = {
          'post' => [200, '{}']
        }
        @responses['/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH/disable'] = {
          'post' => [200, '{}']
        }

        # Default successful responses for reaction methods
        @responses['/openc3-api/autonomic/reaction'] = {
          'get' => [200, '[{"name":"TEMP1_REACTION","triggers":["TEMP1_HIGH"],"actions":[{"type":"command","value":"INST CLEAR"}],"trigger_level":"EDGE","snooze":0,"scope":"DEFAULT"}]'],
          'post' => [201, '{"name":"TEMP1_REACTION","triggers":["TEMP1_HIGH"],"actions":[{"type":"command","value":"INST CLEAR"}],"trigger_level":"EDGE","snooze":0,"scope":"DEFAULT"}']
        }
        @responses['/openc3-api/autonomic/reaction/TEMP1_REACTION'] = {
          'get' => [200, '{"name":"TEMP1_REACTION","triggers":["TEMP1_HIGH"],"actions":[{"type":"command","value":"INST CLEAR"}],"trigger_level":"EDGE","snooze":0,"scope":"DEFAULT"}'],
          'put' => [200, '{"name":"TEMP1_REACTION","triggers":["TEMP1_HIGH"],"actions":[{"type":"command","value":"INST CLEAR"}],"trigger_level":"LEVEL","snooze":10,"scope":"DEFAULT"}'],
          'delete' => [200, '{}']
        }
        @responses['/openc3-api/autonomic/reaction/TEMP1_REACTION/enable'] = {
          'post' => [200, '{}']
        }
        @responses['/openc3-api/autonomic/reaction/TEMP1_REACTION/disable'] = {
          'post' => [200, '{}']
        }
        @responses['/openc3-api/autonomic/reaction/TEMP1_REACTION/execute'] = {
          'post' => [200, '{}']
        }
      end

      def shutdown
        # Stubbed method
      end

      def disconnect
        # Stubbed method
      end

      def generate_url
        return "http://localhost:2900"
      end

      def method_missing(name, *params, **kw_params)
        self.send(name, *params, **kw_params)
      end

      def set_response(endpoint, method, status, body)
        @responses[endpoint] ||= {}
        @responses[endpoint][method.to_s.downcase] = [status, body]
      end

      def request(method, endpoint, **options)
        resp = OpenStruct.new
        if @responses[endpoint] && @responses[endpoint][method.to_s.downcase]
          resp.status = @responses[endpoint][method.to_s.downcase][0]
          resp.body = @responses[endpoint][method.to_s.downcase][1]
        else
          # Unknown endpoint or method - return 404
          resp.status = 404
          resp.body = '{"error":"Not found"}'
        end
        resp
      end
    end

    before(:each) do
      mock_redis()
      setup_system()

      @api = AutonomicSpecApi.new
      # Mock the server proxy to directly call the api
      allow(ServerProxy).to receive(:new).and_return(@api)

      initialize_script()
    end

    after(:each) do
      shutdown_script()
    end

    describe "autonomic_group methods" do
      it "lists groups" do
        expect(autonomic_group_list()).to eq(["DEFAULT", "TEST"])
      end

      it "creates a group" do
        result = autonomic_group_create("TEST")
        expect(result).to eq({"name" => "TEST", "scope" => "DEFAULT"})
      end

      it "shows a group" do
        result = autonomic_group_show("TEST")
        expect(result).to eq({"name" => "TEST", "scope" => "DEFAULT"})
      end

      it "destroys a group" do
        expect { autonomic_group_destroy("TEST") }.not_to raise_error
      end

      it "raises error on failed group list" do
        @api.set_response('/openc3-api/autonomic/group', 'get', 500, '{"error":"Internal error"}')
        expect { autonomic_group_list() }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed group create" do
        @api.set_response('/openc3-api/autonomic/group', 'post', 400, '{"message":"Group already exists"}')
        expect { autonomic_group_create("TEST") }.to raise_error(RuntimeError, /autonomic_group_create error: Group already exists/)
      end

      it "raises error on failed group show" do
        @api.set_response('/openc3-api/autonomic/group/TEST', 'get', 404, '{"error":"Group not found"}')
        expect { autonomic_group_show("TEST") }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed group destroy" do
        @api.set_response('/openc3-api/autonomic/group/TEST', 'delete', 404, '{"error":"Group not found"}')
        expect { autonomic_group_destroy("TEST") }.to raise_error(RuntimeError, /autonomic_group_destroy error: Group not found/)
      end
    end

    describe "autonomic_trigger methods" do
      it "lists triggers" do
        result = autonomic_trigger_list()
        expect(result).to be_an(Array)
        expect(result[0]["name"]).to eq("TEMP1_HIGH")
      end

      it "creates a trigger" do
        result = autonomic_trigger_create(left: "INST HEALTH_STATUS TEMP1", operator: ">", right: "80")
        expect(result["name"]).to eq("TEMP1_HIGH")
        expect(result["left"]).to eq("INST HEALTH_STATUS TEMP1")
      end

      it "shows a trigger" do
        result = autonomic_trigger_show("TEMP1_HIGH")
        expect(result["name"]).to eq("TEMP1_HIGH")
        expect(result["left"]).to eq("INST HEALTH_STATUS TEMP1")
      end

      it "enables a trigger" do
        expect { autonomic_trigger_enable("TEMP1_HIGH") }.not_to raise_error
      end

      it "disables a trigger" do
        expect { autonomic_trigger_disable("TEMP1_HIGH") }.not_to raise_error
      end

      it "updates a trigger" do
        result = autonomic_trigger_update("TEMP1_HIGH", right: "90")
        expect(result["right"]).to eq("90")
      end

      it "destroys a trigger" do
        expect { autonomic_trigger_destroy("TEMP1_HIGH") }.not_to raise_error
      end

      it "raises error on failed trigger list" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger', 'get', 500, '{"error":"Internal error"}')
        expect { autonomic_trigger_list() }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed trigger create" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger', 'post', 400, '{"error":"Invalid parameters"}')
        expect { autonomic_trigger_create(left: "INST HEALTH_STATUS TEMP1", operator: ">", right: "80") }.to raise_error(RuntimeError, /autonomic_trigger_create error: Invalid parameters/)
      end

      it "raises error on failed trigger show" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH', 'get', 404, '{"error":"Trigger not found"}')
        expect { autonomic_trigger_show("TEMP1_HIGH") }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed trigger enable" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH/enable', 'post', 404, '{"error":"Trigger not found"}')
        expect { autonomic_trigger_enable("TEMP1_HIGH") }.to raise_error(RuntimeError, /autonomic_trigger_enable error: Trigger not found/)
      end

      it "raises error on failed trigger disable" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH/disable', 'post', 404, '{"error":"Trigger not found"}')
        expect { autonomic_trigger_disable("TEMP1_HIGH") }.to raise_error(RuntimeError, /autonomic_trigger_disable error: Trigger not found/)
      end

      it "raises error on failed trigger update" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH', 'put', 400, '{"error":"Invalid parameters"}')
        expect { autonomic_trigger_update("TEMP1_HIGH", right: "90") }.to raise_error(RuntimeError, /autonomic_trigger_update error: Invalid parameters/)
      end

      it "raises error on failed trigger destroy" do
        @api.set_response('/openc3-api/autonomic/DEFAULT/trigger/TEMP1_HIGH', 'delete', 404, '{"error":"Trigger not found"}')
        expect { autonomic_trigger_destroy("TEMP1_HIGH") }.to raise_error(RuntimeError, /autonomic_trigger_destroy error: Trigger not found/)
      end
    end

    describe "autonomic_reaction methods" do
      it "lists reactions" do
        result = autonomic_reaction_list()
        expect(result).to be_an(Array)
        expect(result[0]["name"]).to eq("TEMP1_REACTION")
      end

      it "creates a reaction" do
        result = autonomic_reaction_create(triggers: ["TEMP1_HIGH"], actions: [{"type" => "command", "value" => "INST CLEAR"}])
        expect(result["name"]).to eq("TEMP1_REACTION")
        expect(result["triggers"]).to eq(["TEMP1_HIGH"])
      end

      it "shows a reaction" do
        result = autonomic_reaction_show("TEMP1_REACTION")
        expect(result["name"]).to eq("TEMP1_REACTION")
        expect(result["triggers"]).to eq(["TEMP1_HIGH"])
      end

      it "enables a reaction" do
        expect { autonomic_reaction_enable("TEMP1_REACTION") }.not_to raise_error
      end

      it "disables a reaction" do
        expect { autonomic_reaction_disable("TEMP1_REACTION") }.not_to raise_error
      end

      it "executes a reaction" do
        expect { autonomic_reaction_execute("TEMP1_REACTION") }.not_to raise_error
      end

      it "updates a reaction" do
        result = autonomic_reaction_update("TEMP1_REACTION", trigger_level: "LEVEL", snooze: 10)
        expect(result["trigger_level"]).to eq("LEVEL")
        expect(result["snooze"]).to eq(10)
      end

      it "destroys a reaction" do
        expect { autonomic_reaction_destroy("TEMP1_REACTION") }.not_to raise_error
      end

      it "raises error on failed reaction list" do
        @api.set_response('/openc3-api/autonomic/reaction', 'get', 500, '{"error":"Internal error"}')
        expect { autonomic_reaction_list() }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed reaction create" do
        @api.set_response('/openc3-api/autonomic/reaction', 'post', 400, '{"error":"Invalid parameters"}')
        expect { autonomic_reaction_create(triggers: ["TEMP1_HIGH"], actions: [{"type" => "command", "value" => "INST CLEAR"}]) }.to raise_error(RuntimeError, /autonomic_reaction_create error: Invalid parameters/)
      end

      it "raises error on failed reaction show" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION', 'get', 404, '{"error":"Reaction not found"}')
        expect { autonomic_reaction_show("TEMP1_REACTION") }.to raise_error(RuntimeError, /Unexpected response/)
      end

      it "raises error on failed reaction enable" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION/enable', 'post', 404, '{"error":"Reaction not found"}')
        expect { autonomic_reaction_enable("TEMP1_REACTION") }.to raise_error(RuntimeError, /autonomic_reaction_enable error: Reaction not found/)
      end

      it "raises error on failed reaction disable" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION/disable', 'post', 404, '{"error":"Reaction not found"}')
        expect { autonomic_reaction_disable("TEMP1_REACTION") }.to raise_error(RuntimeError, /autonomic_reaction_disable error: Reaction not found/)
      end

      it "raises error on failed reaction execute" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION/execute', 'post', 404, '{"error":"Reaction not found"}')
        expect { autonomic_reaction_execute("TEMP1_REACTION") }.to raise_error(RuntimeError, /autonomic_reaction_execute error: Reaction not found/)
      end

      it "raises error on failed reaction update" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION', 'put', 400, '{"error":"Invalid parameters"}')
        expect { autonomic_reaction_update("TEMP1_REACTION", trigger_level: "LEVEL") }.to raise_error(RuntimeError, /autonomic_reaction_update error: Invalid parameters/)
      end

      it "raises error on failed reaction destroy" do
        @api.set_response('/openc3-api/autonomic/reaction/TEMP1_REACTION', 'delete', 404, '{"error":"Reaction not found"}')
        expect { autonomic_reaction_destroy("TEMP1_REACTION") }.to raise_error(RuntimeError, /autonomic_reaction_destroy error: Reaction not found/)
      end
    end
  end
end