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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "spec_helper"
require "openc3/utilities/metric"

module OpenC3
  describe Metric do
    it "sets a metric" do
      Metric.class_variable_set(:@@update_thread, "Test")
      metric = Metric.new(microservice: "foo", scope: "DEFAULT")
      metric.set(name: 'test', value: 4, type: 'counter', unit: 'seconds', help: 'Test Metric', labels: {'label' => 'alabel'}, time_ms: 12345.6)
      expect(metric.data['test']['value']).to eq(4)
      expect(metric.data['test']['type']).to eq('counter')
      expect(metric.data['test']['unit']).to eq('seconds')
      expect(metric.data['test']['help']).to eq('Test Metric')
      expect(metric.data['test']['labels']).to eq({'label' => 'alabel'})
      expect(metric.data['test']['time_ms']).to eq(12345.6)
      Metric.class_variable_set(:@@update_thread, nil)
    end
  end
end
