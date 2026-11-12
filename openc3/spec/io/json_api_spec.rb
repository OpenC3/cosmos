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
require 'openc3/io/json_api'

module OpenC3
  describe JsonApi do
    describe '#_generate_auth' do
      it 'delegates to the shared authentication factory' do
        expect(OpenC3).to receive(:authentication_from_environment).and_return(:auth)
        expect(JsonApi.allocate.send(:_generate_auth)).to eq(:auth)
      end
    end
  end
end
