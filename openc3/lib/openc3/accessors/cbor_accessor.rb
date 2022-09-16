# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'cbor'
require 'openc3/accessors/json_accessor'

module OpenC3
  class CborAccessor < JsonAccessor
    def self.read_item(item, buffer)
      return nil if item.data_type == :DERIVED
      if String === buffer
        parsed = CBOR.decode(buffer)
      else
        parsed = buffer
      end
      return super(item, parsed)
    end

    def self.write_item(item, value, buffer)
      return nil if item.data_type == :DERIVED

      # Convert to ruby objects
      if String === buffer
        decoded = CBOR.decode(buffer)
      else
        decoded = buffer
      end

      # Write the value
      write_item_internal(item, value, decoded)

      # Update buffer
      if String === buffer
        buffer.replace(decoded.to_cbor)
      end

      return buffer
    end

    def self.read_items(items, buffer)
      # Prevent JsonPath from decoding every call
      if String === buffer
        decoded = CBOR.decode(buffer)
      else
        decoded = buffer
      end
      super(items, decoded)
    end

    def self.write_items(items, values, buffer)
      # Convert to ruby objects
      if String === buffer
        decoded = CBOR.decode(buffer)
      else
        decoded = buffer
      end

      items.each_with_index do |item, index|
        write_item_internal(item, values[index], decoded)
      end

      # Update buffer
      if String === buffer
        buffer.replace(decoded.to_cbor)
      end

      return buffer
    end

  end
end