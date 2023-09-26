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

require 'spec_helper'
require 'openc3'
require 'openc3/processors/statistics_processor'

class TestStatisticsProcessor(unittest.TestCase):
  describe StatisticsProcessor do
class Initialize(unittest.TestCase):
    def test_takes_an_item_name_samples_to_average_and_value_type(self):
        p = StatisticsProcessor('TEST', '5', 'RAW')
        self.assertEqual(p.value_type,  'RAW')
        self.assertEqual(p.instance_variable_get("self.item_name"),  'TEST')
        self.assertEqual(p.instance_variable_get("self.samples_to_average"),  5)

class Call and reset(unittest.TestCase):
    def test_generates_statistics(self):
        p = StatisticsProcessor('TEST', '5', 'RAW')
        packet = Packet("tgt", "pkt")
        packet.append_item("TEST", 8, 'UINT')
        packet.buffer = "\x01"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  1)
        self.assertEqual(p.results['MIN'],  1)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.0)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.0)
        packet.buffer = "\x02"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  2)
        self.assertEqual(p.results['MIN'],  1)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.5)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.7071)
        packet.buffer = "\x00"
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  2)
        self.assertEqual(p.results['MIN'],  0)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.0)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(1.0)
        p.reset
        self.assertEqual(p.results['MAX'],  None)
        self.assertEqual(p.results['MIN'],  None)
        self.assertEqual(p.results['MEAN'],  None)
        self.assertEqual(p.results['STDDEV'],  None)

    def test_handles_None_and_infinity(self):
        p = StatisticsProcessor('TEST', '5')
        packet = Packet("tgt", "pkt")
        packet.append_item("TEST", 32, 'FLOAT')
        packet.write("TEST", 1)
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  1.0)
        self.assertEqual(p.results['MIN'],  1.0)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.0)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.0)
        packet.write("TEST", Float='NAN')
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  1.0)
        self.assertEqual(p.results['MIN'],  1.0)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.0)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.0)
        packet.write("TEST", 2)
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  2.0)
        self.assertEqual(p.results['MIN'],  1.0)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.5)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.7071)
        packet.write("TEST", Float='INFINITY')
        p.call(packet, packet.buffer)
        self.assertEqual(p.results['MAX'],  2.0)
        self.assertEqual(p.results['MIN'],  1.0)
        self.assertEqual(p.results['MEAN']).to be_within(0.001).of(1.5)
        self.assertEqual(p.results['STDDEV']).to be_within(0.001).of(0.7071)
        p.reset
        self.assertEqual(p.results['MAX'],  None)
        self.assertEqual(p.results['MIN'],  None)
        self.assertEqual(p.results['MEAN'],  None)
        self.assertEqual(p.results['STDDEV'],  None)
