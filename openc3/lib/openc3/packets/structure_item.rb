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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/ext/packet' if RUBY_ENGINE == 'ruby' and !ENV['OPENC3_NO_EXT']

module OpenC3
  # Maintains knowledge of an item in a Structure. Multiple StructureItems
  # compose a Structure.
  class StructureItem
    include Comparable

    @@create_index = 0

    # Valid data types adds :DERIVED, :ARRAY, :OBJECT to those defined by BinaryAccessor
    DATA_TYPES = BinaryAccessor::DATA_TYPES << :DERIVED << :ARRAY << :OBJECT

    # Name is used by higher level classes to access the StructureItem.
    # @return [String] Name of the item
    attr_reader :name

    # Key is used to access into nested structures during decom if applicable
    attr_reader :key

    # Indicates where in the binary buffer the StructureItem exists.
    # @return [Integer] 0 based bit offset
    attr_reader :bit_offset

    # Original bit offset when the structure is first defined
    # Will reflect the bit offset with all variable sized items at their
    # minimum size
    # @return [Integer] 0 based bit offset
    attr_accessor :original_bit_offset

    # The number of bits which represent this StructureItem in the binary buffer.
    # @return [Integer] Size in bits
    attr_reader :bit_size

    # Original bit size when the structure is first defined
    # @return [Integer] 0 based bit offset
    attr_reader :original_bit_size

    # The data type is what kind of data this StructureItem
    # represents when extracted from the binary buffer. :INT and :UINT are
    # turned into Integers (Ruby Fixnum). :FLOAT are turned into floating point
    # numbers (Ruby Float). :STRING is turned into an ASCII string (Ruby
    # String). :BLOCK is turned into a binary buffer (Ruby String). :DERIVED is
    # interpreted by the subclass and can result in any type.
    # :ARRAY is an array of unknown types
    # :OBJECT is a Hash type object
    # @return [Symbol] {DATA_TYPES}
    attr_reader :data_type

    # Used to interpret how to read the item from the binary data buffer.
    # @return [Symbol] {BinaryAccessor::ENDIANNESS}
    attr_reader :endianness

    # The total number of bits in the binary buffer that create the array.
    # The array size can be set to nil to indicate the StructureItem is
    # not represented as an array. For example, if the bit_size is 8 bits,
    # an array_size of 16 would result in two 8 bit items.
    # @return [Integer, nil] Array size of the item in bits
    attr_reader :array_size

    # Original array size when the structure is first defined
    # @return [Integer] total array size in bits
    attr_accessor :original_array_size

    # How to handle overflow for :INT, :UINT, :STRING, and :BLOCK data types
    # Note: Has no meaning for :FLOAT data types
    # @return [Symbol] {BinaryAccessor::OVERFLOW_TYPES}
    attr_reader :overflow

    # @return [Boolean] Whether this structure item can overlap another item in the same packet
    attr_accessor :overlap

    # @return [Hash] Variable bit size information
    attr_reader :variable_bit_size

    # @return [Integer] Incrementing value that shows relative order items are created
    attr_reader :create_index

    # Create a StructureItem by setting all the attributes. It
    # calls all the setter routines to do the attribute verification and then
    # verifies the overall integrity.
    #
    # @param name [String] The item name
    # @param bit_offset [Integer] Offset to the item starting at 0
    # @param bit_size [Integer] Size of the items in bits
    # @param data_type [Symbol] {DATA_TYPES}
    # @param endianness [Symbol] {BinaryAccessor::ENDIANNESS}
    # @param array_size [Integer, nil] Size of the array item in bits. For
    #   example, if the bit_size is 8, an array_size of 16 holds two values.
    # @param overflow [Symbol] {BinaryAccessor::OVERFLOW_TYPES}
    def initialize(name, bit_offset, bit_size, data_type, endianness, array_size = nil, overflow = :ERROR)
      @structure_item_constructed = false
      # Assignment order matters due to verifications!
      self.name = name
      self.key = name # Key defaults to name as given (not upcased)
      self.endianness = endianness
      self.data_type = data_type
      self.bit_offset = bit_offset
      @original_bit_offset = self.bit_offset
      self.bit_size = bit_size
      @original_bit_size = self.bit_size
      self.array_size = array_size
      @original_array_size = self.array_size
      self.overflow = overflow
      self.overlap = false
      self.variable_bit_size = nil
      @create_index = @@create_index
      @@create_index += 1
      @structure_item_constructed = true
      verify_overall()
    end

    def name=(name)
      raise ArgumentError, "name must be a String but is a #{name.class}" unless String === name
      raise ArgumentError, "name must contain at least one character" if name.empty?

      @name = name.upcase.clone.freeze
      verify_overall() if @structure_item_constructed
    end

    def key=(key)
      raise ArgumentError, "key must be a String but is a #{key.class}" unless String === key
      raise ArgumentError, "key must contain at least one character" if key.empty?

      @key = key
    end

    def endianness=(endianness)
      raise ArgumentError, "#{@name}: endianness must be a Symbol" unless Symbol === endianness
      unless BinaryAccessor::ENDIANNESS.include? endianness
        raise ArgumentError, "#{@name}: unknown endianness: #{endianness} - Must be :BIG_ENDIAN or :LITTLE_ENDIAN"
      end

      @endianness = endianness
      verify_overall() if @structure_item_constructed
    end

    def bit_offset=(bit_offset)
      raise ArgumentError, "#{@name}: bit_offset must be an Integer" unless Integer === bit_offset
      byte_aligned = ((bit_offset % 8) == 0)
      if (@data_type == :FLOAT or @data_type == :STRING or @data_type == :BLOCK) and !byte_aligned
        raise ArgumentError, "#{@name}: bit_offset for :FLOAT, :STRING, and :BLOCK items must be byte aligned"
      end
      if @data_type == :DERIVED and bit_offset != 0
        raise ArgumentError, "#{@name}: DERIVED items must have bit_offset of zero"
      end

      @bit_offset = bit_offset
      verify_overall() if @structure_item_constructed
    end

    def bit_size=(bit_size)
      raise ArgumentError, "#{@name}: bit_size must be an Integer" unless Integer === bit_size
      byte_multiple = ((bit_size % 8) == 0)
      if bit_size <= 0 and (@data_type == :FLOAT)
        raise ArgumentError, "#{@name}: bit_size cannot be negative or zero for :FLOAT items: #{bit_size}"
      end
      if (@data_type == :STRING or @data_type == :BLOCK) and !byte_multiple
        raise ArgumentError, "#{@name}: bit_size for STRING and BLOCK items must be byte multiples"
      end
      if @data_type == :FLOAT and bit_size != 32 and bit_size != 64
        raise ArgumentError, "#{@name}: bit_size for FLOAT items must be 32 or 64. Given: #{bit_size}"
      end
      if @data_type == :DERIVED and bit_size != 0
        raise ArgumentError, "#{@name}: DERIVED items must have bit_size of zero"
      end

      @bit_size = bit_size
      verify_overall() if @structure_item_constructed
    end

    def data_type=(data_type)
      raise ArgumentError, "#{@name}: data_type must be a Symbol" unless Symbol === data_type

      case data_type
      when *DATA_TYPES
        # Valid data_type
      else
        raise ArgumentError, "#{@name}: unknown data_type: #{data_type} - Must be :INT, :UINT, :FLOAT, :STRING, :BLOCK, or :DERIVED"
      end

      @data_type = data_type
      verify_overall() if @structure_item_constructed
    end

    def array_size=(array_size)
      if array_size
        raise ArgumentError, "#{@name}: array_size must be an Integer" unless Integer === array_size
        raise ArgumentError, "#{@name}: array_size must be a multiple of bit_size" unless @bit_size == 0 or (array_size % @bit_size == 0) or array_size < 0
        raise ArgumentError, "#{@name}: bit_size cannot be negative or zero for array items" if @bit_size <= 0
      end
      @array_size = array_size
      verify_overall() if @structure_item_constructed
    end

    def overflow=(overflow)
      raise ArgumentError, "#{@name}: overflow type must be a Symbol" unless Symbol === overflow

      case overflow
      when *BinaryAccessor::OVERFLOW_TYPES
        # Valid overflow
      else
        raise ArgumentError, "#{@name}: unknown overflow type: #{overflow} - Must be :ERROR, :ERROR_ALLOW_HEX, :TRUNCATE, or :SATURATE"
      end

      @overflow = overflow
      verify_overall() if @structure_item_constructed
    end

    def variable_bit_size=(variable_bit_size)
      if variable_bit_size
        raise ArgumentError, "#{@name}: variable_bit_size must be a Hash" unless Hash === variable_bit_size
        raise ArgumentError, "#{@name}: variable_bit_size['length_item_name'] must be a String" unless String === variable_bit_size['length_item_name']
        raise ArgumentError, "#{@name}: variable_bit_size['length_value_bit_offset'] must be an Integer" unless Integer === variable_bit_size['length_value_bit_offset']
        raise ArgumentError, "#{@name}: variable_bit_size['length_bits_per_count'] must be an Integer" unless Integer === variable_bit_size['length_bits_per_count']
      end
      @variable_bit_size = variable_bit_size

      verify_overall() if @structure_item_constructed
    end

    if RUBY_ENGINE != 'ruby' or ENV['OPENC3_NO_EXT']
      # Comparison Operator primarily based on bit_offset
      def <=>(other)
        return nil unless other.kind_of?(StructureItem)

        other_original_bit_offset = other.original_bit_offset

        # Derived items should be first in the list with multiple derived sorted
        # by create_index
        if @data_type == :DERIVED
          if other.data_type != :DERIVED
            return -1
          else
            if @create_index <= other.create_index
              return -1
            else
              return 1
            end
          end
        elsif other.data_type == :DERIVED
          return 1
        end

        # Handle non-derived items
        if ((@original_bit_offset >= 0) && (other_original_bit_offset >= 0)) || ((@original_bit_offset < 0) && (other_original_bit_offset < 0))
          # Both Have Same Sign
          if @original_bit_offset == other_original_bit_offset
            # New Variable Bit Size items are before regular items
            if @variable_bit_size
              if not other.variable_bit_size
                return -1
              end
              # If both variable_bit_size use create index
            elsif other.variable_bit_size
              return 1
            end

            if @create_index <= other.create_index
              return -1
            else
              return 1
            end
          elsif @original_bit_offset <= other_original_bit_offset
            return -1
          else
            return 1
          end
        else
          # Different Signs
          if @original_bit_offset < other_original_bit_offset
            return 1
          else
            return -1
          end
        end
      end
    end

    # Make a light weight clone of this item
    def clone
      item = super()
      item.name = self.name.clone if self.name
      item.key = self.key.clone if self.key
      item
    end
    alias dup clone

    def self.from_json(hash)
      # Convert strings to symbols
      endianness = hash['endianness'] ? hash['endianness'].intern : nil
      data_type = hash['data_type'] ? hash['data_type'].intern : nil
      overflow = hash['overflow'] ? hash['overflow'].intern : nil
      si = StructureItem.new(hash['name'], hash['bit_offset'], hash['bit_size'], data_type,
        endianness, hash['array_size'], overflow)
      si.key = hash['key'] || hash['name']
      si.variable_bit_size = hash['variable_bit_size']
      si
    end

    def as_json(*a)
      hash = {}
      hash['name'] = self.name
      hash['key'] = self.key
      hash['bit_offset'] = self.original_bit_offset
      hash['bit_size'] = self.original_bit_size
      hash['data_type'] = self.data_type
      hash['endianness'] = self.endianness
      hash['array_size'] = self.original_array_size
      hash['overflow'] = self.overflow
      if @variable_bit_size
        hash['variable_bit_size'] = @variable_bit_size
      end
      hash
    end

    def little_endian_bit_field?
      return false unless @endianness == :LITTLE_ENDIAN
      return false unless @data_type == :INT || @data_type == :UINT
      # If we're not byte aligned we're a bit field
      return true unless (@bit_offset % 8) == 0
      # If we don't have an even number of bytes we're a bit field
      return true unless even_byte_multiple()

      false
    end

    protected

    # Verifies overall integrity of the StructureItem by checking for correct
    # LITTLE_ENDIAN bit fields
    def verify_overall
      # Verify negative bit_offset conditions
      if @bit_offset < 0
        raise ArgumentError, "#{@name}: Can't define an item with negative bit_size #{@bit_size} and negative bit_offset #{@bit_offset}" if @bit_size < 0
        raise ArgumentError, "#{@name}: Can't define an item with negative array_size #{@array_size} and negative bit_offset #{@bit_offset}" if @array_size and @array_size < 0
        if @array_size and @array_size > @bit_offset.abs
          raise ArgumentError, "#{@name}: Can't define an item with array_size #{@array_size} greater than negative bit_offset #{@bit_offset}"
        elsif @bit_size > @bit_offset.abs
          raise ArgumentError, "#{@name}: Can't define an item with bit_size #{@bit_size} greater than negative bit_offset #{@bit_offset}"
        end
      else
        # Verify bounds on little-endian bit fields
        if little_endian_bit_field?()
          # Bitoffset always refers to the most significant bit of a bitfield
          num_bytes = (((@bit_offset % 8) + @bit_size - 1) / 8) + 1
          upper_bound = @bit_offset / 8
          lower_bound = upper_bound - num_bytes + 1

          if lower_bound < 0
            raise ArgumentError, "#{@name}: LITTLE_ENDIAN bitfield with bit_offset #{@bit_offset} and bit_size #{@bit_size} is invalid"
          end
        end
      end
    end

    def even_byte_multiple
      case @bit_size
      when 8, 16, 32, 64
        true
      else
        false
      end
    end
  end
end
