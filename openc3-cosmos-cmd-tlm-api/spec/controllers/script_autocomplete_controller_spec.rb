# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

require 'rails_helper'
require 'openc3/models/target_model'

RSpec.describe ScriptAutocompleteController, :type => :controller do
  before(:each) do
    mock_redis()
    setup_system()
    model = OpenC3::TargetModel.new(folder_name: "INST", name: "INST", scope: "DEFAULT")
    model.create
    dir = File.join(__dir__, '..', '..', '..', 'openc3', 'spec', 'install', 'config', 'targets')
    model.update_store(OpenC3::System.new(['INST'], dir))
  end

  describe "get_keywords" do
    it "gets screen keywords" do
      get :get_keywords, params: { type: 'SCREEN' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Spot check
      expect(ret).to include("SCREEN")
      expect(ret).to include("END")
      expect(ret).to include("END")
      expect(ret).to include("LABEL")
      expect(ret).to include("VALUE")
      expect(ret).to include("VERTICAL")
    end
  end

  describe "get_ace_autocomplete_data" do
    it "gets screen autocomplete" do
      get :get_ace_autocomplete_data, params: { type: 'SCREEN', scope: 'DEFAULT' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      pp ret
      # Spot check
      expect(ret).to include({"caption"=>"SCREEN",
        "snippet"=>"SCREEN ${1:<Width>} ${2:<Height>} ${3:<Polling Period>}",
        "meta"=>"Define a telemetry viewer screen"})
      expect(ret).to include({"caption"=>"CANVAS",
        "snippet"=>"CANVAS ${1:<Width>} ${2:<Height>}",
        "meta"=>"Layout widget for the other canvas widgets"})
      expect(ret).to include({"caption"=>"VALUE",
        # Packet names as options ${1|INST|} and type as options ${4|RAW,CONVERTED,FORMATTED,WITH_UNITS|}
        "snippet"=>"VALUE ${1|INST|} ${2:<Packet name>} ${3:<Item name>} ${4|RAW,CONVERTED,FORMATTED,WITH_UNITS|} ${5:<Number of characters>}",
        "meta"=>"Displays a box with a telemetry item value"})
    end

    it "gets cmd autocomplete" do
      get :get_ace_autocomplete_data, params: { type: 'CMD', scope: 'DEFAULT' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Sorted so first should be INST ABORT
      expect(ret[0]).to include({"caption" => "INST ABORT"})
      # Spot check
      expect(ret).to include({"caption"=>"INST COLLECT",
        "snippet"=>"INST COLLECT with TYPE ${1:NORMAL}, DURATION ${2:1.0}, OPCODE ${3:171}, TEMP ${4:0.0}",
        "meta"=>"command"})
    end

    it "gets tlm autocomplete" do
      get :get_ace_autocomplete_data, params: { type: 'TLM', scope: 'DEFAULT' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Sorted so first should be INST ADCS CCSDSVER
      expect(ret[0]).to include({"caption" => "INST ADCS CCSDSVER"})
      # Spot check
      expect(ret).to include({"caption"=>"INST HEALTH_STATUS DURATION",
        "snippet"=>"INST HEALTH_STATUS DURATION",
        "meta"=>"telemetry"})
    end
  end
end
