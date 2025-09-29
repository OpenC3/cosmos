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

  describe "keywords" do
    it "gets screen keywords" do
      get :keywords, params: { type: 'SCREEN' }
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

  describe "ace_autocomplete_data" do
    it "gets screen autocomplete" do
      get :ace_autocomplete_data, params: { type: 'SCREEN', scope: 'DEFAULT' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Spot check
      expect(ret).to include({"caption"=>"SCREEN",
        "meta"=>"Define a telemetry viewer screen",
        # All parameters required so no <>
        "snippet"=>"SCREEN ${1:Width} ${2:Height} ${3:Polling Period}"})
      expect(ret).to include({"caption"=>"MATRIXBYCOLUMNS",
        "meta"=>"Places the widgets into a table-like matrix",
        # First param is required (no <>), second params optional (<Margin>)
        "snippet"=>"MATRIXBYCOLUMNS ${1:Columns} ${2:<Margin>}"})
      expect(ret).to include({"caption"=>"LABELVALUE",
        "command"=>"startAutocomplete", # params so Autocomplete
        "meta"=>"Displays a LABEL with the item name followed by a VALUE",
        "params"=>
         [{"Target name"=>"The target name"},
          {"Packet name"=>"The packet name"},
          {"Item name"=>"The item name"},
          {"CONVERTED"=>"The type of the value to display. Default is CONVERTED.",
           "FORMATTED"=>"The type of the value to display. Default is CONVERTED.",
           "RAW"=>"The type of the value to display. Default is CONVERTED."},
          # Optional parameter so <>
          {"<Number of characters>"=>
            "The number of characters wide to make the value box (default = 12)"}],
        # Both caption and value when we do Autocomplete
        "value"=>"LABELVALUE "})
     end

    it "gets cmd autocomplete" do
      get :ace_autocomplete_data, params: { type: 'CMD', scope: 'DEFAULT' }
      expect(response).to have_http_status(:success)
      ret = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Sorted so first should be INST ABORT
      expect(ret[0]).to include({"caption" => "INST ABORT"})
      # Spot check
      expect(ret).to include({"caption"=>"INST ASCIICMD",
        "snippet"=>"INST ASCIICMD with STRING ${1:'NOOP'}, BINARY ${2:0xDEADBEEF}, ASCII ${3:'0xDEADBEEF'}",
        "meta"=>"command"})
      expect(ret).to include({"caption"=>"INST COLLECT",
        "snippet"=>"INST COLLECT with TYPE ${1:NORMAL}, DURATION ${2:1.0}, OPCODE ${3:171}, TEMP ${4:0.0}",
        "meta"=>"command"})
    end

    it "gets tlm autocomplete" do
      get :ace_autocomplete_data, params: { type: 'TLM', scope: 'DEFAULT' }
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
