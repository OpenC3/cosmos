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
require 'openc3/models/interface_status_model'

module OpenC3
  describe InterfaceStatusModel, type: :model do
    before(:each) do
      mock_redis()
    end

    describe "process_status" do
      it "creates new" do
        model = InterfaceStatusModel.new(name: 'IS', state: 'up', scope: 'DEFAULT')
        expect(model).to be_a(InterfaceStatusModel)
      end

      it "self.get" do
        name = InterfaceStatusModel.get(name: 'IS', scope: 'DEFAULT')
        expect(name).to be_nil # eq('IS')
      end

      it "self.all" do
        all = InterfaceStatusModel.all(scope: 'DEFAULT')
        expect(all[0]).to be_nil # eq('IS')
      end

      it "self.names" do
        names = InterfaceStatusModel.names(scope: 'DEFAULT')
        expect(names[0]).to be_nil # eq('IS')
      end

      it "as_json" do
        model = InterfaceStatusModel.new(name: 'IS', state: 'up', scope: 'DEFAULT')
        expect(model.as_json()['name']).to eq('IS')
      end
    end
  end
end
