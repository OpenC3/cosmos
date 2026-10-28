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

require 'openc3/processors/processor'

# Processor which sleeps while the decom microservice processes the packet.
# This simulates a decom microservice falling behind so events pile up in the
# streams it reads. Only used on the DECOM_STALL packet, which the target never
# sends, so it only runs when the packet is injected with inject_tlm.
# See procedures/limits_resync.rb
class DecomStallProcessor < OpenC3::Processor
  MAX_SECONDS = 300

  # @param item_name [String] Name of the item holding the seconds to stall
  # @param value_type #See Processor::initialize
  def initialize(item_name, value_type = :CONVERTED)
    super(value_type)
    @item_name = item_name.to_s.upcase
  end

  # See Processor#call
  def call(packet, buffer)
    seconds = packet.read(@item_name, @value_type, buffer).to_f
    sleep([seconds, MAX_SECONDS].min) if seconds > 0
  end

  # Convert to configuration file string
  def to_config
    "  PROCESSOR #{@name} #{self.class.name.to_s.class_name_to_filename} #{@item_name} #{@value_type}\n"
  end

  def as_json(*a)
    { 'name' => @name, 'class' => self.class.name, 'params' => [@item_name, @value_type.to_s] }
  end
end
