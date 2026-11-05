# encoding: ascii-8bit

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
require 'openc3'
require 'openc3/script'

module OpenC3
  describe Script do
    before(:each) do
      @requests = []
      @response = double("response", status: 200, body: '{"filename":"INST/tables/bin/table.csv","contents":"report"}')
      @api_server = double("api_server")
      allow(@api_server).to receive(:request) do |*args, **kwargs|
        @requests << [args, kwargs]
        @response
      end
      $api_server = @api_server
    end

    after(:each) do
      $api_server = nil
    end

    describe "table_create_binary" do
      it "posts the definition to the generate endpoint" do
        table_create_binary("INST/tables/config/table_def.txt")
        args, kwargs = @requests[0]
        expect(args).to eql ['post', '/openc3-api/tables/generate']
        expect(kwargs[:data]).to eql({'definition' => 'INST/tables/config/table_def.txt'})
      end
    end

    describe "table_create_report" do
      it "requests the report be saved by default so get_target_file can read it" do
        result = table_create_report("INST/tables/bin/table.bin", "INST/tables/config/table_def.txt")
        args, kwargs = @requests[0]
        expect(args).to eql ['post', '/openc3-api/tables/report']
        expect(kwargs[:data]).to eql({
          'binary' => 'INST/tables/bin/table.bin',
          'definition' => 'INST/tables/config/table_def.txt',
          'save' => true,
        })
        expect(result['filename']).to eql 'INST/tables/bin/table.csv'
        expect(result['contents']).to eql 'report'
      end

      it "passes the table name and honors save false" do
        table_create_report("INST/tables/bin/table.bin", "INST/tables/config/table_def.txt",
                            table_name: "MY_TABLE", save: false)
        _args, kwargs = @requests[0]
        expect(kwargs[:data]['table_name']).to eql 'MY_TABLE'
        expect(kwargs[:data]['save']).to be false
      end

      it "raises with the report error message on failure" do
        allow(@response).to receive(:status).and_return(500)
        allow(@response).to receive(:body).and_return('{"message":"boom"}')
        expect { table_create_report("INST/tables/bin/table.bin", "INST/tables/config/table_def.txt") }
          .to raise_error(/Failed to create report due to boom/)
      end
    end
  end
end
