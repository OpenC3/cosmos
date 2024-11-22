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

require 'spec_helper'
require 'openc3/models/process_status_model'

module OpenC3
  describe ProcessStatusModel, type: :model do
    before(:each) do
      mock_redis()
    end

    describe "process_status" do
      it "creates new" do
        model = ProcessStatusModel.new(name: 'ps', scope: 'DEFAULT')
        expect(model).to be_a(ProcessStatusModel)
      end

      it "self.get" do
        name = ProcessStatusModel.get(name: 'ps', scope: 'DEFAULT')
        expect(name).to be_nil # eq('ps')
      end

      it "self.all" do
        all = ProcessStatusModel.all(scope: 'DEFAULT')
        expect(all[0]).to be_nil # eq('ps')
      end

      it "self.names" do
        names = ProcessStatusModel.names(scope: 'DEFAULT')
        expect(names[0]).to be_nil # eq('ps')
      end

      it "as_json" do
        model = ProcessStatusModel.new(name: 'ps', scope: 'DEFAULT')
        expect(model.as_json(:allow_nan => true)['name']).to eq('ps')
      end
    end
  end
end
