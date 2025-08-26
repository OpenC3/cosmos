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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"
require "openc3/models/queue_model"

RSpec.describe QueuesController, type: :controller do
  before(:each) do
    mock_redis
  end

  def generate_queue_hash
    {
      "name" => "QUEUE1",
      "state" => "RUNNING",
      "type" => "FIFO"
    }
  end

  describe "GET index" do
    it "returns an empty array and status code 200" do
      get :index, params: {scope: "DEFAULT"}
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end

    it "returns an array of queues and status code 200" do
      hash = generate_queue_hash
      allow(OpenC3::QueueModel).to receive(:all).and_return({"QUEUE1" => hash})

      get :index, params: {scope: "DEFAULT"}
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json.length).to eql(1)
      expect(json[0]).to eql(hash)
      expect(response).to have_http_status(:ok)
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::QueueModel).to receive(:all).and_raise(StandardError.new("Unexpected error"))
      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "GET show" do
    it "returns a specific queue and status code 200" do
      hash = generate_queue_hash
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)

      get :show, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("QUEUE1")
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get).and_return(nil)

      get :show, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 400 when a QueueError occurs" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(OpenC3::QueueError.new("Queue processing error"))
      get :show, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Queue processing error")
      expect(json["type"]).to eql("OpenC3::QueueError")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))
      get :show, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST create" do
    it "creates a queue and returns status code 201" do
      hash = generate_queue_hash
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:from_json).and_return(queue_model)
      allow(queue_model).to receive(:create)
      allow(queue_model).to receive(:deploy)
      allow(queue_model).to receive(:as_json).and_return(hash)

      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("QUEUE1")
    end

    it "returns 400 when a queue already exists" do
      hash = generate_queue_hash
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)

      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("QUEUE1 already exists")
      expect(json["type"]).to eql("OpenC3::QueueError")
    end

    it "returns 400 when a QueueError occurs" do
      hash = generate_queue_hash
      allow(OpenC3::QueueModel).to receive(:get).and_raise(OpenC3::QueueError.new("Invalid queue input"))

      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Invalid queue input")
      expect(json["type"]).to eql("OpenC3::QueueError")
    end

    it "returns 500 when an unexpected error occurs" do
      hash = generate_queue_hash
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))

      post :create, params: hash.merge({scope: "DEFAULT"})
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      pp json
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST hold" do
    it "holds a queue and returns status code 200" do
      hash = generate_queue_hash.merge({"state" => "HOLD"})
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)
      allow(OpenC3::QueueModel).to receive(:from_json).and_return(queue_model)
      allow(queue_model).to receive(:state=)
      allow(queue_model).to receive(:update)
      allow(queue_model).to receive(:as_json).and_return(hash)

      post :hold, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("QUEUE1")
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get).and_return(nil)

      post :hold, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))

      post :hold, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST release" do
    it "releases a queue and returns status code 200" do
      hash = generate_queue_hash.merge({"state" => "RELEASE"})
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)
      allow(OpenC3::QueueModel).to receive(:from_json).and_return(queue_model)
      allow(queue_model).to receive(:state=)
      allow(queue_model).to receive(:update)
      allow(queue_model).to receive(:as_json).and_return(hash)

      post :release, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("QUEUE1")
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get).and_return(nil)

      post :release, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))

      post :release, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST disable" do
    it "disables a queue and returns status code 200" do
      hash = generate_queue_hash.merge({"state" => "DISABLE"})
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)
      allow(OpenC3::QueueModel).to receive(:from_json).and_return(queue_model)
      allow(queue_model).to receive(:state=)
      allow(queue_model).to receive(:update)
      allow(queue_model).to receive(:as_json).and_return(hash)

      post :disable, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("QUEUE1")
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get).and_return(nil)

      post :disable, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))

      post :disable, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST insert" do
    it "inserts a command to a queue and returns status code 200" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:insert)

      post :insert, params: {name: "QUEUE1", command: "TEST COMMAND", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("success")
      expect(json["message"]).to eql("Command added to queue")
      expect(queue_model).to have_received(:insert).with(anything, { username: "anonymous", value: "TEST COMMAND", timestamp: anything })
    end

    it "inserts a command at index and returns status code 200" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:insert)
      index = 10

      post :insert, params: {name: "QUEUE1", command: "TEST COMMAND", index: index, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("success")
      expect(json["message"]).to eql("Command added to queue")
      expect(queue_model).to have_received(:insert).with(index.to_f, { username: "anonymous", value: "TEST COMMAND", timestamp: anything })
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(nil)

      post :insert, params: {name: "NONEXISTENT", command: "TEST COMMAND", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 400 when command is missing" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)

      post :insert, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("command is required")
    end

    it "returns 500 when an unexpected error occurs" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:insert).and_raise(StandardError.new("Unexpected error"))

      post :insert, params: {name: "QUEUE1", command: "TEST COMMAND", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "POST remove" do
    it "removes a command from a queue and returns status code 200" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:remove).and_return(true)
      index = 1

      post :remove, params: {name: "QUEUE1", index: index, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("success")
      expect(json["message"]).to eql("Command removed from queue")
      expect(queue_model).to have_received(:remove).with(index)
    end

    it "returns 404 when command not found in queue" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:remove).and_return(false)
      index = 1234567890

      post :remove, params: {name: "QUEUE1", index: index, scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Command not found in queue")
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(nil)
      index = 1

      post :remove, params: {name: "NONEXISTENT", index: index, scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 400 when index is missing" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)

      post :remove, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("index is required")
    end

    it "returns 500 when an unexpected error occurs" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:remove).and_raise(StandardError.new("Unexpected error"))
      index = 1

      post :remove, params: {name: "QUEUE1", index: index, scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "GET list" do
    it "returns the queue list and status code 200" do
      queue_model = double("QueueModel")
      queue_list = [
        { "username" => "user1", "value" =>"COMMAND1" },
        { "username" => "user2", "value" => "COMMAND2" }
      ]
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:list).and_return(queue_list)

      get :list, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql(queue_list)
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(nil)

      get :list, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end

    it "returns 500 when an unexpected error occurs" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:list).and_raise(StandardError.new("Unexpected error"))

      get :list, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(500)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to eql("StandardError")
    end
  end

  describe "DELETE destroy" do
    it "destroys a queue and returns status code 200" do
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(queue_model)
      allow(queue_model).to receive(:destroy)

      delete :destroy, params: {name: "QUEUE1", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(queue_model).to have_received(:destroy)
    end

    it "returns 404 when the queue is not found" do
      allow(OpenC3::QueueModel).to receive(:get_model).and_return(nil)

      delete :destroy, params: {name: "NONEXISTENT", scope: "DEFAULT"}
      expect(response).to have_http_status(404)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("queue not found")
    end
  end

  describe "private method change_state" do
    let(:controller) { QueuesController.new }

    before do
      allow(controller).to receive(:authorization).and_return(true)
      allow(controller).to receive(:params).and_return({ name: "QUEUE1", scope: "DEFAULT" })
      allow(controller).to receive(:render)
    end

    it "changes state successfully" do
      hash = generate_queue_hash
      queue_model = double("QueueModel")
      allow(OpenC3::QueueModel).to receive(:get).and_return(hash)
      allow(OpenC3::QueueModel).to receive(:from_json).and_return(queue_model)
      allow(queue_model).to receive(:state=)
      allow(queue_model).to receive(:update)
      allow(queue_model).to receive(:as_json).and_return(hash)

      controller.send(:change_state, { name: "QUEUE1", scope: "DEFAULT" }, "HOLD")

      expect(queue_model).to have_received(:state=).with("HOLD")
      expect(queue_model).to have_received(:update)
    end

    it "handles queue not found" do
      allow(OpenC3::QueueModel).to receive(:get).and_return(nil)

      controller.send(:change_state, { name: "NONEXISTENT", scope: "DEFAULT" }, "HOLD")

      expect(controller).to have_received(:render).with(json: { status: 'error', message: 'queue not found' }, status: 404)
    end

    it "handles unexpected errors" do
      allow(OpenC3::QueueModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))
      allow(controller).to receive(:log_error)

      controller.send(:change_state, { name: "QUEUE1", scope: "DEFAULT" }, "HOLD")

      expect(controller).to have_received(:render).with(
        json: { status: 'error', message: 'Unexpected error', type: 'StandardError', backtrace: anything },
        status: 500
      )
    end
  end
end