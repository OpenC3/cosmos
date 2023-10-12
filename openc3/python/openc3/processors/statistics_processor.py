# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import math
import statistics
from openc3.processors.processor import Processor


class StatisticsProcessor(Processor):
    # @param item_name [String] The name of the item to gather statistics on
    # @param samples_to_average [Integer] The number of samples to store for calculations
    # @param value_type #See Processor::initialize
    def __init__(self, item_name, samples_to_average, value_type="CONVERTED"):
        super().__init__(value_type)
        self.item_name = str(item_name).upper()
        self.samples_to_average = int(samples_to_average)
        self.reset()

    # Run statistics on the item
    #
    # See Processor#call
    def call(self, packet, buffer):
        value = packet.read(self.item_name, self.value_type, buffer)
        # Don't process NaN or Infinite values
        if math.isnan(value) or math.isinf(value):
            return

        self.samples.append(value)
        if len(self.samples) > self.samples_to_average:
            self.samples = self.samples[-self.samples_to_average :]
        self.results["MAX"] = max(self.samples)
        self.results["MIN"] = min(self.samples)
        self.results["MEAN"] = statistics.fmean(self.samples)
        if len(self.samples) > 1:
            self.results["STDDEV"] = statistics.stdev(self.samples)
        else:
            self.results["STDDEV"] = 0

    # Reset any state
    def reset(self):
        self.samples = []
        self.results["MAX"] = None
        self.results["MIN"] = None
        self.results["MEAN"] = None
        self.results["STDDEV"] = None

    # Make a light weight clone of this processor. This only creates a new hash of results
    #
    # @return [Processor] A copy of the processor with a new hash of results
    def clone(self):
        processor = super().clone()
        processor.samples = processor.samples[:]
        return processor

    # Convert to configuration file string
    def to_config(self):
        return f"  PROCESSOR {self.name} {self.__class__.__name__} {self.item_name} {self.samples_to_average} {self.value_type}\n"

    def as_json(self):
        return {
            "name": self.name,
            "class": self.__class__.__name__,
            "params": [self.item_name, self.samples_to_average, self.value_type],
        }
