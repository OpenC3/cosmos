# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"
require "openc3/models/trigger_group_model"
require "openc3/models/trigger_model"

RSpec.describe TriggerController, type: :controller do
  GROUP = "ALPHA".freeze

  before(:each) do
    mock_redis
    model = OpenC3::TriggerGroupModel.new(name: GROUP, scope: "DEFAULT")
    model.create
  end

  def generate_trigger_hash
    {
      group: GROUP,
      left: {
        type: "item",
        target: "INST",
        packet: "ADCS",
        item: "POSX",
        valueType: "RAW"
      },
      operator: ">",
      right: {
        type: "float",
        float: 10.0
      }
    }
  end

  describe "GET index" do
    it "returns an empty array and status code 200" do
      get :index, params: {group: "TEST", scope: "DEFAULT"}
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::TriggerModel).to receive(:all).and_raise(StandardError.new("Unexpected error"))
      get :index, params: {group: GROUP, scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST then GET index with Triggers" do
    it "returns an array and status code 200" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      trigger = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(trigger["name"]).not_to be_nil
      get :index, params: {group: GROUP, scope: "DEFAULT"}
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]["name"]).to eql(trigger["name"])
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET show" do
    it "returns a specific trigger and status code 200" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      trigger = JSON.parse(response.body, allow_nan: true, create_additions: true)

      get :show, params: {group: GROUP, scope: "DEFAULT", name: trigger["name"]}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql(trigger["name"])
    end

    it "returns 404 when the trigger is not found" do
      get :show, params: {group: GROUP, scope: "DEFAULT", name: "NONEXISTENT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
    end

    it "returns 400 when a TriggerInputError occurs" do
      allow(OpenC3::TriggerModel).to receive(:get).and_raise(OpenC3::TriggerInputError.new("Invalid trigger input"))
      get :show, params: {group: GROUP, scope: "DEFAULT", name: "TRIG1"}
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Invalid trigger input")
      expect(json["type"]).to eql("OpenC3::TriggerInputError")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::TriggerModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))
      get :show, params: {group: GROUP, scope: "DEFAULT", name: "TRIG1"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST create" do
    it "returns a json hash of name and status code 201" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      # Default name is TRIG plus index
      expect(json["name"]).to eql("TRIG1")

      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("TRIG2")
    end

    it "returns 400 with bad operand" do
      hash = generate_trigger_hash
      hash[:left].delete(:target)
      post :create, params: hash.merge({scope: "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to match(/invalid operand, must contain target, packet, item and valueType/)
      expect(response).to have_http_status(400)
    end

    it "returns 418 when a TriggerError occurs" do
      hash = generate_trigger_hash
      allow_any_instance_of(OpenC3::TriggerModel).to receive(:create).and_raise(OpenC3::TriggerError.new("Trigger processing error"))
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(418)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Trigger processing error")
      expect(json["type"]).to eql("OpenC3::TriggerError")
    end

    it "returns 500 when an unexpected error occurs" do
      hash = generate_trigger_hash
      allow_any_instance_of(OpenC3::TriggerModel).to receive(:create).and_raise(StandardError.new("Unexpected error"))
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "PATCH update" do
    before(:each) do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      @trigger_name = JSON.parse(response.body, allow_nan: true, create_additions: true)["name"]
    end

    it "updates a trigger and returns status code 200" do
      update_hash = {
        left: {
          type: "item",
          target: "INST",
          packet: "ADCS",
          item: "POSY",
          valueType: "RAW"
        },
        operator: "<",
        right: {
          type: "float",
          float: 20.0
        }
      }

      patch :update, params: update_hash.merge({scope: "DEFAULT", group: GROUP, name: @trigger_name})
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql(@trigger_name)
      expect(json["left"]["item"]).to eql("POSY")
      expect(json["operator"]).to eql("<")
      expect(json["right"]["float"]).to eql("20.0")
    end

    it "returns 404 when the trigger is not found" do
      update_hash = {
        left: {
          type: "item",
          target: "INST",
          packet: "ADCS",
          item: "POSY",
          valueType: "RAW"
        },
        operator: "<",
        right: {
          type: "float",
          float: 20.0
        }
      }

      patch :update, params: update_hash.merge({scope: "DEFAULT", group: GROUP, name: "NONEXISTENT"})
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
    end

    it "returns 400 when a TriggerInputError occurs" do
      update_hash = {
        left: {
          type: "item",
          target: "INST",
          packet: "ADCS",
          valueType: "RAW" # missing item
        },
        operator: "<",
        right: {
          type: "float",
          float: 20.0
        }
      }

      allow_any_instance_of(OpenC3::TriggerModel).to receive(:left=).and_raise(OpenC3::TriggerInputError.new("Invalid left operand"))
      patch :update, params: update_hash.merge({scope: "DEFAULT", group: GROUP, name: @trigger_name})
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Invalid left operand")
      expect(json["type"]).to eql("OpenC3::TriggerInputError")
    end

    it "returns 418 when a TriggerError occurs" do
      update_hash = {
        left: {
          type: "item",
          target: "INST",
          packet: "ADCS",
          item: "POSY",
          valueType: "RAW"
        },
        operator: "<",
        right: {
          type: "float",
          float: 20.0
        }
      }

      allow_any_instance_of(OpenC3::TriggerModel).to receive(:notify).and_raise(OpenC3::TriggerError.new("Trigger processing error"))
      patch :update, params: update_hash.merge({scope: "DEFAULT", group: GROUP, name: @trigger_name})
      expect(response).to have_http_status(418)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Trigger processing error")
      expect(json["type"]).to eql("OpenC3::TriggerError")
    end

    it "returns 500 when an unexpected error occurs" do
      update_hash = {
        left: {
          type: "item",
          target: "INST",
          packet: "ADCS",
          item: "POSY",
          valueType: "RAW"
        },
        operator: "<",
        right: {
          type: "float",
          float: 20.0
        }
      }

      allow_any_instance_of(OpenC3::TriggerModel).to receive(:notify).and_raise(StandardError.new("Unexpected error"))
      patch :update, params: update_hash.merge({scope: "DEFAULT", group: GROUP, name: @trigger_name})
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST enable" do
    before(:each) do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      @trigger_name = JSON.parse(response.body, allow_nan: true, create_additions: true)["name"]
    end

    it "enables a trigger and returns status code 200" do
      post :enable, params: {scope: "DEFAULT", group: GROUP, name: @trigger_name}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql(@trigger_name)
    end

    it "returns 404 when the trigger is not found" do
      post :enable, params: {scope: "DEFAULT", group: GROUP, name: "NONEXISTENT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
    end

    it "returns 500 when an unexpected error occurs" do
      allow_any_instance_of(OpenC3::TriggerModel).to receive(:notify_enable).and_raise(StandardError.new("Unexpected error"))
      post :enable, params: {scope: "DEFAULT", group: GROUP, name: @trigger_name}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST disable" do
    before(:each) do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      @trigger_name = JSON.parse(response.body, allow_nan: true, create_additions: true)["name"]
    end

    it "disables a trigger and returns status code 200" do
      post :disable, params: {scope: "DEFAULT", group: GROUP, name: @trigger_name}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql(@trigger_name)
    end

    it "returns 404 when the trigger is not found" do
      post :disable, params: {scope: "DEFAULT", group: GROUP, name: "NONEXISTENT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
    end

    it "returns 500 when an unexpected error occurs" do
      allow_any_instance_of(OpenC3::TriggerModel).to receive(:notify_disable).and_raise(StandardError.new("Unexpected error"))
      post :disable, params: {scope: "DEFAULT", group: GROUP, name: @trigger_name}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "DELETE destroy" do
    it "returns a json hash of name and status code 404 if not found" do
      delete :destroy, params: {scope: "DEFAULT", name: "NOPE", group: GROUP}
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).not_to be_nil
    end

    it "returns a json hash of name and status code 200" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      delete :destroy, params: {scope: "DEFAULT", name: "TRIG1", group: GROUP}
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("TRIG1")
    end

    it "returns 404 when the trigger has dependents" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      trigger_name = JSON.parse(response.body, allow_nan: true, create_additions: true)["name"]

      # Mock dependents
      allow_any_instance_of(OpenC3::TriggerModel).to receive(:dependents).and_return(["REACTION1"])

      delete :destroy, params: {scope: "DEFAULT", name: trigger_name, group: GROUP}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to match(/has dependents:/)
      expect(json["type"]).to eql("TriggerError")
    end

    it "returns 500 when an unexpected error occurs" do
      hash = generate_trigger_hash
      post :create, params: hash.merge({scope: "DEFAULT"})
      trigger_name = JSON.parse(response.body, allow_nan: true, create_additions: true)["name"]

      allow_any_instance_of(OpenC3::TriggerModel).to receive(:notify).and_raise(StandardError.new("Unexpected error"))

      delete :destroy, params: {scope: "DEFAULT", name: trigger_name, group: GROUP}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end
end
