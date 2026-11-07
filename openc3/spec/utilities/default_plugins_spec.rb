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
require 'openc3/utilities/default_plugins'

module OpenC3
  describe DefaultPlugins do
    describe "NAMES" do
      it "loads the short names from default_plugins.yaml" do
        expect(DefaultPlugins::NAMES).to include('openc3-cosmos-tool-admin', 'openc3-tool-base')
        expect(DefaultPlugins::NAMES).to all(be_a(String))
        expect(DefaultPlugins::NAMES).to be_frozen
      end
    end

    describe "default?" do
      it "is true for default plugins with a version" do
        expect(DefaultPlugins.default?('openc3-cosmos-tool-admin-6.0.0.gem')).to be true
        expect(DefaultPlugins.default?('openc3-tool-base-6.0.0.pre.beta0.gem')).to be true
      end

      it "ignores the __ suffix" do
        expect(DefaultPlugins.default?('openc3-cosmos-tool-admin-6.0.0.gem__20260101000000')).to be true
      end

      it "is false for other plugins" do
        expect(DefaultPlugins.default?('openc3-cosmos-demo-6.0.0.gem__20260101000000')).to be false
        expect(DefaultPlugins.default?('openc3-cosmos-tool-newtool-6.0.0.gem')).to be false
        expect(DefaultPlugins.default?('my-openc3-cosmos-tool-admin-6.0.0.gem')).to be false
      end
    end
  end
end
