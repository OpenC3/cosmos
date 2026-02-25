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
require 'openc3/models/stash_model'

module OpenC3
  describe StashModel, type: :model do
    before(:each) do
      mock_redis()
    end

    describe "process_status" do
      it "creates new" do
        model = StashModel.new(name: 'sm', value: 'stash', scope: 'DEFAULT')
        expect(model).to be_a(StashModel)
      end

      it "self.get" do
        name = StashModel.get(name: 'sm', scope: 'DEFAULT')
        expect(name).to be_nil # eq('sm')
      end

      it "self.all" do
        all = StashModel.all(scope: 'DEFAULT')
        expect(all[0]).to be_nil # eq('sm')
      end

      it "self.names" do
        names = StashModel.names(scope: 'DEFAULT')
        expect(names[0]).to be_nil # eq('sm')
      end

      it "as_json" do
        model = StashModel.new(name: 'sm', value: 'stashef', scope: 'DEFAULT')
        expect(model.as_json()['name']).to eq('sm')
      end
    end
  end
end
