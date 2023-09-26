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

require 'openc3/processors/processor'

module OpenC3
class StatisticsProcessor(Processor):
    # @return [Array] The set of samples stored by the processor
    attr_accessor :samples

    # @param item_name [String] The name of the item to gather statistics on
    # @param samples_to_average [Integer] The number of samples to store for calculations
    # @param value_type #See Processor::initialize
    def __init__(self, item_name, samples_to_average, value_type = 'CONVERTED'):
      super(value_type)
      self.item_name = str(item_name).upper()
      self.samples_to_average = int(samples_to_average)
      reset()

    # Run statistics on the item
    #
    # See Processor#call
    def call(packet, buffer):
      value = packet.read(self.item_name, self.value_type, buffer)
      # Don't process NaN or Infinite values
      if float(value).nan? or float(value).infinite?:
          return

      self.samples.append(value)
      if len(self.samples) > self.samples_to_average:
          self.samples = self.samples[-self.samples_to_average:]
      mean, stddev = Math.stddev_sample(self.samples)
      self.results['MAX'] = self.samples.max
      self.results['MIN'] = self.samples.min
      self.results['MEAN'] = mean
      self.results['STDDEV'] = stddev

    # Reset any state
    def reset:
      self.samples = []
      self.results['MAX'] = None
      self.results['MIN'] = None
      self.results['MEAN'] = None
      self.results['STDDEV'] = None

    # Make a light weight clone of this processor. This only creates a new hash of results
    #
    # @return [Processor] A copy of the processor with a new hash of results
    def clone:
      processor = super()
      processor.samples = processor.samples.clone
      processor
    alias dup clone

    # Convert to configuration file string
    def to_config:
      "  PROCESSOR {self.name} {self.__class__.__name__. str(name).__class__.__name___name_to_filename} {self.item_name} {self.samples_to_average} {self.value_type}\n"

    def as_json(*a):
      { 'name' : self.name, 'class' : self.__class__.__name__.name, 'params' : [self.item_name, self.samples_to_average, self. str(value_type)] }
  end # class StatisticsProcessor
