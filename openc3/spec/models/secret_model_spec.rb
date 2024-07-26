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
require 'openc3/models/secret_model'

module OpenC3
  describe SecretModel, type: :model do
    before(:each) do
      mock_redis()
    end

    describe "secret" do
      it "creates new" do
        model = SecretModel.new(name: 'secret', value: 'tacit', scope: 'DEFAULT')
        model.create
        expect(model).to be_a(SecretModel)
      end

      it "self.get" do
        name = SecretModel.get(name: 'psecrets', scope: 'DEFAULT')
        expect(name).to be_nil # eq('secret')
      end

      it "self.all" do
        all = SecretModel.all(scope: 'DEFAULT')
        expect(all[0]).to be_nil # eq('secret')
      end

      it "self.names" do
        names = SecretModel.names(scope: 'DEFAULT')
        expect(names[0]).to be_nil # eq('secret')
      end

      it "as_json" do
        model = SecretModel.new(name: 'secreter', value: 'silent', scope: 'DEFAULT')
        expect(model.as_json(:allow_nan => true)['name']).to eq('secreter')
      end
    end
  end
end
