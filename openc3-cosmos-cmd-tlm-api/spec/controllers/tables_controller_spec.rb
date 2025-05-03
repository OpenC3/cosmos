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

require "rails_helper"

RSpec.describe TablesController, type: :controller do
  before(:each) do
    mock_redis
    ENV.delete("OPENC3_LOCAL_MODE")
    allow(controller).to receive(:username).and_return("testuser")
    allow(OpenC3::Logger).to receive(:info)
  end

  describe "index" do
    it "lists all tables for a scope" do
      allow(Table).to receive(:all).and_return(["table1.bin", "table2.bin"])
      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret).to eql(["table1.bin", "table2.bin"])
    end

    it "rejects a bad scope param" do
      get :index, params: {scope: "../DEFAULT"}
      expect(response).to have_http_status(:bad_request)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret["message"]).to eql("Invalid scope: ../DEFAULT")
    end

    it "rejects unauthorized requests" do
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "binary" do
    it "returns a binary file" do
      binary_file = OpenStruct.new(filename: "table.bin", contents: "binary content")
      allow(Table).to receive(:binary).and_return(binary_file)

      get :binary, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("table.bin")
      expect(json["contents"]).to eq(Base64.encode64("binary content"))
    end

    it "returns a specific table from the binary" do
      binary_file = OpenStruct.new(filename: "MyTable.bin", contents: "table binary content")
      allow(Table).to receive(:binary).and_return(binary_file)

      get :binary, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt",
        table_name: "MY_TABLE"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("MyTable.bin")
      expect(json["contents"]).to eq(Base64.encode64("table binary content"))
    end

    it "handles not found errors" do
      allow(Table).to receive(:binary).and_raise(Table::NotFound.new("Binary file not found"))
      allow(controller).to receive(:log_error)

      get :binary, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/nonexistent.bin",
        definition: "INST/tables/config/nonexistent_def.txt"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Binary file not found")
    end

    it "rejects invalid parameters" do
      get :binary, params: {scope: "../DEFAULT", binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      get :binary, params: {binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "definition" do
    it "returns a definition file" do
      definition_file = OpenStruct.new(filename: "table_def.txt", contents: "definition content")
      allow(Table).to receive(:definition).and_return(definition_file)

      get :definition, params: {
        scope: "DEFAULT",
        definition: "INST/tables/config/table_def.txt"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("table_def.txt")
      expect(json["contents"]).to eq("definition content")
    end

    it "returns a specific table definition" do
      definition_file = OpenStruct.new(filename: "my_table_def.txt", contents: "table definition content")
      allow(Table).to receive(:definition).and_return(definition_file)

      get :definition, params: {
        scope: "DEFAULT",
        definition: "INST/tables/config/table_def.txt",
        table_name: "MY_TABLE"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("my_table_def.txt")
      expect(json["contents"]).to eq("table definition content")
    end

    it "handles not found errors" do
      allow(Table).to receive(:definition).and_raise(Table::NotFound.new("Definition file not found"))
      allow(controller).to receive(:log_error)

      get :definition, params: {
        scope: "DEFAULT",
        definition: "INST/tables/config/nonexistent_def.txt"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Definition file not found")
    end

    it "rejects invalid parameters" do
      get :definition, params: {scope: "../DEFAULT", definition: "INST/tables/config/table_def.txt"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      get :definition, params: {definition: "INST/tables/config/table_def.txt"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "report" do
    it "returns a report file" do
      report_file = OpenStruct.new(filename: "table.csv", contents: "report content")
      allow(Table).to receive(:report).and_return(report_file)

      get :report, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("table.csv")
      expect(json["contents"]).to eq("report content")
    end

    it "returns a report for a specific table" do
      report_file = OpenStruct.new(filename: "MyTable.csv", contents: "table report content")
      allow(Table).to receive(:report).and_return(report_file)

      get :report, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt",
        table_name: "MY_TABLE"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("MyTable.csv")
      expect(json["contents"]).to eq("table report content")
    end

    it "handles not found errors" do
      allow(Table).to receive(:report).and_raise(Table::NotFound.new("Report file not found"))
      allow(controller).to receive(:log_error)

      get :report, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/nonexistent.bin",
        definition: "INST/tables/config/nonexistent_def.txt"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Report file not found")
    end

    it "rejects invalid parameters" do
      get :report, params: {scope: "../DEFAULT", binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      get :report, params: {binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "body" do
    it "returns a text file content" do
      allow(Table).to receive(:body).and_return("text file content")

      get :body, params: {
        scope: "DEFAULT",
        name: "INST/tables/config/table.txt"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq("text file content")
    end

    it "returns base64 encoded binary content" do
      binary_content = "\x01\x02\x03\x04"
      allow(Table).to receive(:body).and_return(binary_content)
      allow(Table).to receive(:locked?).and_return(false)
      allow(Table).to receive(:lock)

      get :body, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(Base64.encode64(binary_content))
      expect(json["locked"]).to eq(false)
    end

    it "indicates if the file is locked" do
      binary_content = "\x01\x02\x03\x04"
      allow(Table).to receive(:body).and_return(binary_content)
      allow(Table).to receive(:locked?).and_return("otheruser")

      get :body, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(Base64.encode64(binary_content))
      expect(json["locked"]).to eq("otheruser")
    end

    it "returns 404 if file not found" do
      allow(Table).to receive(:body).and_return(nil)

      get :body, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/nonexistent.bin"
      }

      expect(response).to have_http_status(:not_found)
    end

    it "passes along ignore errors header" do
      allow(Table).to receive(:body).and_return(nil)
      request.headers["HTTP_IGNORE_ERRORS"] = "404"

      get :body, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/nonexistent.bin"
      }

      expect(response).to have_http_status(:not_found)
      expect(response.headers["Ignore-Errors"]).to eq("404")
    end

    it "rejects invalid parameters" do
      get :body, params: {scope: "../DEFAULT", name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      get :body, params: {name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "load" do
    it "loads a binary file" do
      json_response = '{"tables": [], "definition": "INST/tables/config/table_def.txt"}'
      allow(Table).to receive(:load).and_return(json_response)

      get :load, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(json_response)
    end

    it "handles not found errors" do
      allow(Table).to receive(:load).and_raise(Table::NotFound.new("Binary file not found"))
      allow(controller).to receive(:log_error)

      get :load, params: {
        scope: "DEFAULT",
        binary: "INST/tables/bin/nonexistent.bin",
        definition: "INST/tables/config/nonexistent_def.txt"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Binary file not found")
    end

    it "rejects invalid parameters" do
      get :load, params: {scope: "../DEFAULT", binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      get :load, params: {binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "save" do
    it "saves table data" do
      allow(Table).to receive(:save)

      post :save, params: {
        name: "INST/tables/bin/table.bin",
        scope: "DEFAULT",
        binary: "INST/tables/bin/table.bin",
        definition: "INST/tables/config/table_def.txt",
        tables: '{"tables": []}'
      }

      expect(response).to have_http_status(:ok)
      expect(Table).to have_received(:save).with(
        "DEFAULT",
        "INST/tables/bin/table.bin",
        "INST/tables/config/table_def.txt",
        '{"tables": []}'
      )
    end

    it "handles not found errors" do
      allow(Table).to receive(:save).and_raise(Table::NotFound.new("Binary file not found"))
      allow(controller).to receive(:log_error)

      post :save, params: {
        name: "INST/tables/bin/table.bin",
        scope: "DEFAULT",
        binary: "INST/tables/bin/nonexistent.bin",
        definition: "INST/tables/config/nonexistent_def.txt",
        tables: '{"tables": []}'
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Binary file not found")
    end

    it "rejects unauthorized requests" do
      post :save, params: {name: "INST/tables/bin/table.bin", binary: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "save_as" do
    it "saves a file with a new name" do
      allow(Table).to receive(:save_as)

      post :save_as, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin",
        new_name: "INST/tables/bin/table_copy.bin"
      }

      expect(response).to have_http_status(:ok)
      expect(Table).to have_received(:save_as).with(
        "DEFAULT",
        "INST/tables/bin/table.bin",
        "INST/tables/bin/table_copy.bin"
      )
    end

    it "handles not found errors" do
      allow(Table).to receive(:save_as).and_raise(Table::NotFound.new("File not found"))
      allow(controller).to receive(:log_error)

      post :save_as, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/nonexistent.bin",
        new_name: "INST/tables/bin/copy.bin"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("File not found")
    end

    it "rejects unauthorized requests" do
      post :save_as, params: {name: "INST/tables/bin/table.bin", new_name: "INST/tables/bin/table_copy.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "generate" do
    it "generates a new binary file" do
      allow(Table).to receive(:generate).and_return("INST/tables/bin/table.bin")

      post :generate, params: {
        scope: "DEFAULT",
        definition: "INST/tables/config/table_def.txt"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["filename"]).to eq("INST/tables/bin/table.bin")
    end

    it "handles not found errors" do
      allow(Table).to receive(:generate).and_raise(Table::NotFound.new("Definition file not found"))
      allow(controller).to receive(:log_error)

      post :generate, params: {
        scope: "DEFAULT",
        definition: "INST/tables/config/nonexistent_def.txt"
      }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Definition file not found")
    end

    it "rejects invalid parameters" do
      post :generate, params: {scope: "../DEFAULT", definition: "INST/tables/config/table_def.txt"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      post :generate, params: {definition: "INST/tables/config/table_def.txt"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "lock" do
    it "locks a table for a user" do
      allow(Table).to receive(:lock)

      post :lock, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      expect(Table).to have_received(:lock).with("DEFAULT", "INST/tables/bin/table.bin", "testuser")
    end

    it "rejects invalid parameters" do
      post :lock, params: {scope: "../DEFAULT", name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      post :lock, params: {name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "unlock" do
    it "unlocks a table if locked by the same user" do
      allow(Table).to receive(:locked?).and_return("testuser")
      allow(Table).to receive(:unlock)

      post :unlock, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      expect(Table).to have_received(:unlock).with("DEFAULT", "INST/tables/bin/table.bin")
    end

    it "does not unlock if locked by a different user" do
      allow(Table).to receive(:locked?).and_return("otheruser")
      allow(Table).to receive(:unlock)

      post :unlock, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      expect(Table).not_to have_received(:unlock)
    end

    it "rejects invalid parameters" do
      post :unlock, params: {scope: "../DEFAULT", name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      post :unlock, params: {name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "destroy" do
    it "destroys a table file" do
      allow(Table).to receive(:destroy)

      delete :destroy, params: {
        scope: "DEFAULT",
        name: "INST/tables/bin/table.bin"
      }

      expect(response).to have_http_status(:ok)
      expect(Table).to have_received(:destroy).with("DEFAULT", "INST/tables/bin/table.bin")
      expect(OpenC3::Logger).to have_received(:info).with(
        "Table destroyed: INST/tables/bin/table.bin",
        {scope: "DEFAULT", user: "testuser"}
      )
    end

    it "rejects invalid parameters" do
      delete :destroy, params: {scope: "../DEFAULT", name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unauthorized requests" do
      delete :destroy, params: {name: "INST/tables/bin/table.bin"}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
