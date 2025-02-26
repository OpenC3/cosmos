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

require 'openc3/packets/binary_accessor'
require 'openc3/packets/structure_item'
require 'openc3/ext/packet' if RUBY_ENGINE == 'ruby' and !ENV['OPENC3_NO_EXT']

module OpenC3
  # Maintains knowledge of a raw binary structure. Uses structure_item to
  # create individual structure items which are read and written by
  # binary_accessor.
  class Structure
    # @return [Symbol] Default endianness for items in the structure. One of
    #   {BinaryAccessor::ENDIANNESS}
    attr_reader :default_endianness

    # @return [Hash] Items that make up the structure.
    #   Hash key is the item's name in uppercase
    attr_accessor :items

    # @return [Array] Items sorted by bit_offset.
    attr_accessor :sorted_items

    # @return [Integer] Defined length in bytes (not bits) of the structure
    attr_reader :defined_length

    # @return [Integer] Defined length in bits of the structure
    attr_reader :defined_length_bits

    # @return [Boolean] Flag indicating if the structure contains any variably
    #   sized items or not.
    attr_reader :fixed_size

    # @return [Boolean] Flag indicating if giving a buffer with less than
    #   required data size is allowed.
    attr_accessor :short_buffer_allowed

    # @return [Accessor] Instance of class used to access raw data of structure from buffer
    attr_reader :accessor

    if RUBY_ENGINE != 'ruby' or ENV['OPENC3_NO_EXT']
      # Used to force encoding
      ASCII_8BIT_STRING = "ASCII-8BIT".freeze

      # String providing a single 0 byte
      ZERO_STRING = "\000".freeze

      # Structure constructor
      #
      # @param default_endianness [Symbol] Must be one of
      #   {BinaryAccessor::ENDIANNESS}. By default it uses
      #   BinaryAccessor::HOST_ENDIANNESS to determine the endianness of the host platform.
      # @param buffer [String] Buffer used to store the structure
      # @param item_class [Class] Class used to instantiate new structure items.
      #   Must be StructureItem or one of its subclasses.
      def initialize(default_endianness = BinaryAccessor::HOST_ENDIANNESS, buffer = nil, item_class = StructureItem)
        if (default_endianness == :BIG_ENDIAN) || (default_endianness == :LITTLE_ENDIAN)
          @default_endianness = default_endianness
          if buffer
            raise TypeError, "wrong argument type #{buffer.class} (expected String)" unless String === buffer

            @buffer = buffer.force_encoding(ASCII_8BIT_STRING)
          else
            @buffer = nil
          end
          @item_class = item_class
          @items = {}
          @sorted_items = []
          @defined_length = 0
          @defined_length_bits = 0
          @pos_bit_size = 0
          @neg_bit_size = 0
          @fixed_size = true
          @short_buffer_allowed = false
          @mutex = nil
          @accessor = BinaryAccessor.new(self)
        else
          raise(ArgumentError, "Unknown endianness '#{default_endianness}', must be :BIG_ENDIAN or :LITTLE_ENDIAN")
        end
      end

      # Read an item in the structure
      #
      # @param item [StructureItem] Instance of StructureItem or one of its subclasses
      # @param value_type [Symbol] Not used. Subclasses should overload this
      #   parameter to check whether to perform conversions on the item.
      # @param buffer [String] The binary buffer to read the item from
      # @return Value based on the item definition. This could be a string, integer,
      #   float, or array of values.
      def read_item(item, _value_type = :RAW, buffer = @buffer)
        buffer = allocate_buffer_if_needed() unless buffer
        return @accessor.read_item(item, buffer)
      end

      # Get the length of the buffer used by the structure
      #
      # @return [Integer] Size of the buffer in bytes
      def length
        allocate_buffer_if_needed()
        return @buffer.length
      end

      # Resize the buffer at least the defined length of the structure
      def resize_buffer
        if @buffer
          # Extend data size
          if @buffer.length < @defined_length
            @buffer << (ZERO_STRING * (@defined_length - @buffer.length))
          end
        else
          allocate_buffer_if_needed()
        end

        return self
      end
    end

    # Configure the accessor for this packet
    #
    # @param accessor [Accessor] The class to use as an accessor
    def accessor=(accessor)
      @accessor = accessor
      # Check for Accessor because sometimes we use PythonProxy
      if @accessor.is_a? Accessor and @accessor.enforce_short_buffer_allowed
        @short_buffer_allowed = true
      end
    end

    # Read a list of items in the structure
    #
    # @param items [StructureItem] Array of StructureItem or one of its subclasses
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to read the item from
    # @return Hash of read names and values
    def read_items(items, _value_type = :RAW, buffer = @buffer)
      buffer = allocate_buffer_if_needed() unless buffer
      return @accessor.read_items(items, buffer)
    end

    # Allocate a buffer if not available
    def allocate_buffer_if_needed
      unless @buffer
        @buffer = ZERO_STRING * @defined_length
        @buffer.force_encoding(ASCII_8BIT_STRING)
      end
      return @buffer
    end

    # Indicates if any items have been defined for this structure
    # @return [TrueClass or FalseClass]
    def defined?
      @sorted_items.length > 0
    end

    # Rename an existing item
    #
    # @param item_name [String] Name of the currently defined item
    # @param new_item_name [String] New name for the item
    def rename_item(item_name, new_item_name)
      item = get_item(item_name)
      item.name = new_item_name
      @items.delete(item_name)
      @items[new_item_name] = item
      # Since @sorted_items contains the actual item reference it is
      # updated when we set the item.name
      item
    end

    # Define an item in the structure. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accommodate the new item.
    #
    # @param name [String] Name of the item. Used by the items hash to retrieve
    #   the item.
    # @param bit_offset [Integer] Bit offset of the item in the raw buffer
    # @param bit_size [Integer] Bit size of the item in the raw buffer
    # @param data_type [Symbol] Type of data contained by the item. This is
    #   dependent on the item_class but by default see StructureItem.
    # @param array_size [Integer] Set to a non nil value if the item is to
    #   represented as an array.
    # @param endianness [Symbol] Endianness of this item. By default the
    #   endianness as set in the constructor is used.
    # @param overflow [Symbol] How to handle value overflows. This is
    #   dependent on the item_class but by default see StructureItem.
    # @return [StrutureItem] The structure item defined
    def define_item(name, bit_offset, bit_size, data_type, array_size = nil, endianness = @default_endianness, overflow = :ERROR)
      # Create the item
      item = @item_class.new(name, bit_offset, bit_size, data_type, endianness, array_size, overflow)
      define(item)
    end

    # Adds the given item to the items hash. It also resizes the buffer to
    # accommodate the new item.
    #
    # @param item [StructureItem] The structure item to add
    # @return [StrutureItem] The structure item defined
    def define(item)
      # Handle Overwriting Existing Item
      if @items[item.name]
        item_index = nil
        @sorted_items.each_with_index do |sorted_item, index|
          if sorted_item.name == item.name
            item_index = index
            break
          end
        end
        @sorted_items.delete_at(item_index) if item_index < @sorted_items.length
      end

      # Add to Sorted Items
      unless @sorted_items.empty?
        last_item = @sorted_items[-1]
        @sorted_items << item
        # If the current item or last item have a negative offset then we have
        # to re-sort. We also re-sort if the current item is less than the last
        # item because we are inserting.
        if last_item.bit_offset <= 0 or item.bit_offset <= 0 or item.bit_offset < last_item.bit_offset
          @sorted_items = @sorted_items.sort
        end
      else
        @sorted_items << item
      end

      # Add to the overall hash of defined items
      @items[item.name] = item
      # Update fixed size knowledge
      @fixed_size = false if (item.data_type != :DERIVED and item.bit_size <= 0) or (item.array_size and item.array_size <= 0)

      # Recalculate the overall defined length of the structure
      update_needed = false
      if item.bit_offset >= 0
        if item.bit_size > 0
          if item.array_size
            if item.array_size >= 0
              item_defined_length_bits = item.bit_offset + item.array_size
            else
              item_defined_length_bits = item.bit_offset
            end
          else
            item_defined_length_bits = item.bit_offset + item.bit_size
          end
          if item_defined_length_bits > @pos_bit_size
            @pos_bit_size = item_defined_length_bits
            update_needed = true
          end
        else
          if item.bit_offset > @pos_bit_size
            @pos_bit_size = item.bit_offset
            update_needed = true
          end
        end
      else
        if item.bit_offset.abs > @neg_bit_size
          @neg_bit_size = item.bit_offset.abs
          update_needed = true
        end
      end
      if update_needed
        @defined_length_bits = @pos_bit_size + @neg_bit_size
        @defined_length = @defined_length_bits / 8
        @defined_length += 1 if @defined_length_bits % 8 != 0
      end

      # Resize the buffer if necessary
      resize_buffer() if @buffer

      return item
    end

    # Define an item at the end of the structure. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accommodate the new item.
    #
    # @param name (see #define_item)
    # @param bit_size (see #define_item)
    # @param data_type (see #define_item)
    # @param array_size (see #define_item)
    # @param endianness (see #define_item)
    # @param overflow (see #define_item)
    # @return (see #define_item)
    def append_item(name, bit_size, data_type, array_size = nil, endianness = @default_endianness, overflow = :ERROR)
      if data_type == :DERIVED
        return define_item(name, 0, bit_size, data_type, array_size, endianness, overflow)
      else
        return define_item(name, @defined_length_bits, bit_size, data_type, array_size, endianness, overflow)
      end
    end

    # Adds an item at the end of the structure. It adds the item to the items
    # hash and resizes the buffer to accommodate the new item.
    #
    # @param item (see #define)
    # @return (see #define)
    def append(item)
      if item.data_type == :DERIVED
        item.bit_offset = 0
      else
        # We're appending a new item so set the bit_offset
        item.bit_offset = @defined_length_bits
        # Also set original_bit_offset because it's currently 0
        # due to PacketItemParser::create_packet_item
        # get_bit_offset() returning 0 if append
        item.original_bit_offset = @defined_length_bits
      end
      return define(item)
    end

    # @param name [String] Name of the item to look up in the items Hash
    # @return [StructureItem] StructureItem or one of its subclasses
    def get_item(name)
      item = @items[name.upcase]
      raise ArgumentError, "Unknown item: #{name}" unless item

      return item
    end

    # @param item [#name] Instance of StructureItem or one of its subclasses.
    #   The name method will be used to look up the item and set it to the new instance.
    def set_item(item)
      if @items[item.name]
        @items[item.name] = item
        # Need to allocate space for the variable length item if its minimum size is greater than zero
        if item.variable_bit_size
          minimum_data_bits = 0
          if (item.data_type == :INT or item.data_type == :UINT) and not item.original_array_size
            # Minimum QUIC encoded integer, see https://datatracker.ietf.org/doc/html/rfc9000#name-variable-length-integer-enc
            minimum_data_bits = 6
          # :STRING, :BLOCK, or array item
          elsif item.variable_bit_size['length_value_bit_offset'] > 0
            minimum_data_bits = item.variable_bit_size['length_value_bit_offset'] * item.variable_bit_size['length_bits_per_count']
          end
          if minimum_data_bits > 0 and item.bit_offset >= 0 and @defined_length_bits == item.bit_offset
            @defined_length_bits += minimum_data_bits
          end
        end
      else
        raise ArgumentError, "Unknown item: #{item.name} - Ensure item name is uppercase"
      end
    end

    # @param name [String] Name of the item to delete in the items Hash
    def delete_item(name)
      item = @items[name.upcase]
      raise ArgumentError, "Unknown item: #{name}" unless item

      # Find the item to delete in the sorted_items array
      item_index = nil
      @sorted_items.each_with_index do |sorted_item, index|
        if sorted_item.name == item.name
          item_index = index
          break
        end
      end
      @sorted_items.delete_at(item_index)
      @items.delete(name.upcase)
    end

    # Write a value to the buffer based on the item definition
    #
    # @param item [StructureItem] Instance of StructureItem or one of its subclasses
    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to write the value to
    def write_item(item, value, _value_type = :RAW, buffer = @buffer)
      buffer = allocate_buffer_if_needed() unless buffer
      return @accessor.write_item(item, value, buffer)
    end

    # Write values to the buffer based on the item definitions
    #
    # @param items [StructureItem] Array of StructureItem or one of its subclasses
    # @param value [Object] Array of values based on the item definitions.
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to write the values to
    def write_items(items, values, _value_type = :RAW, buffer = @buffer)
      buffer = allocate_buffer_if_needed() unless buffer
      return @accessor.write_items(items, values, buffer)
    end

    # Read an item in the structure by name
    #
    # @param name [String] Name of an item to read
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to read the item from
    # @return Value based on the item definition. This could be an integer,
    #   float, or array of values.
    def read(name, value_type = :RAW, buffer = @buffer)
      return read_item(get_item(name), value_type, buffer)
    end

    # Write an item in the structure by name
    #
    # @param name [Object] Name of the item to write
    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to write the value to
    def write(name, value, value_type = :RAW, buffer = @buffer)
      write_item(get_item(name), value, value_type, buffer)
    end

    # Read all items in the structure into an array of arrays
    #   [[item name, item value], ...]
    #
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param buffer [String] The binary buffer to write the value to
    # @param top [Boolean] Indicates if this is a top level call for the mutex
    # @return [Array<Array>] Array of two element arrays containing the item
    #   name as element 0 and item value as element 1.
    def read_all(value_type = :RAW, buffer = @buffer, top = true)
      item_array = []
      synchronize_allow_reads(top) do
        @sorted_items.each { |item| item_array << [item.name, read_item(item, value_type, buffer)] }
      end
      return item_array
    end

    # Create a string that shows the name and value of each item in the structure
    #
    # @param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # @param indent [Integer] Amount to indent before printing the item name
    # @param buffer [String] The binary buffer to write the value to
    # @param ignored [Array<String>] List of items to ignore when building the string
    # @return [String] String formatted with all the item names and values
    def formatted(value_type = :RAW, indent = 0, buffer = @buffer, ignored = nil)
      indent_string = ' ' * indent
      string = ''
      synchronize_allow_reads(true) do
        @sorted_items.each do |item|
          next if ignored && ignored.include?(item.name)

          if (item.data_type != :BLOCK) ||
             (item.data_type == :BLOCK and value_type != :RAW and
              item.respond_to? :read_conversion and item.read_conversion)
            string << "#{indent_string}#{item.name}: #{read_item(item, value_type, buffer)}\n"
          else
            value = read_item(item, value_type, buffer)
            if String === value
              string << "#{indent_string}#{item.name}:\n"
              string << value.formatted(1, 16, ' ', indent + 2)
            else
              string << "#{indent_string}#{item.name}: #{value}\n"
            end
          end
        end
      end
      return string
    end

    # Get the buffer used by the structure. The current buffer is copied and
    # thus modifications to the returned buffer will have no effect on the
    # structure items.
    #
    # @param copy [TrueClass/FalseClass] Whether to copy the buffer
    # @return [String] Data buffer backing the structure
    def buffer(copy = true)
      local_buffer = allocate_buffer_if_needed()
      if copy
        return local_buffer.dup
      else
        return local_buffer
      end
    end

    # Set the buffer to be used by the structure. The buffer is copied and thus
    # further modifications to the buffer have no effect on the structure
    # items.
    #
    # @param buffer [String] Buffer of data to back the structure items
    def buffer=(buffer)
      synchronize() do
        internal_buffer_equals(buffer)
      end
    end

    # Make a light weight clone of this structure. This only creates a new buffer
    # of data. The defined structure items are the same.
    #
    # @return [Structure] A copy of the current structure with a new underlying
    #   buffer of data
    def clone
      structure = super()
      # Use instance_variable_set since we have overridden buffer= to do
      # additional work that isn't necessary here
      structure.instance_variable_set("@buffer".freeze, @buffer.clone) if @buffer
      # Need to update reference packet in the Accessor
      structure.accessor = @accessor.clone
      structure.accessor.packet = structure
      return structure
    end
    alias dup clone

    # Clone that also deep copies items
    # @return [Structure] A deep copy of the structure
    def deep_copy
      cloned = clone()
      cloned_items = []
      cloned.sorted_items.each do |item|
        cloned_items << item.clone()
      end
      cloned.sorted_items = cloned_items
      cloned.items = {}
      cloned_items.each do |item|
        cloned.items[item.name] = item
      end
      return cloned
    end

    # Enable the ability to read and write item values as if they were methods
    # to the class
    def enable_method_missing
      extend(MethodMissing)
    end

    protected

    MUTEX = Mutex.new

    def setup_mutex
      return if @mutex

      MUTEX.synchronize do
        @mutex ||= Mutex.new
      end
    end

    # Take the structure mutex to ensure the buffer does not change while you perform activities
    def synchronize
      setup_mutex()
      @mutex.synchronize { || yield } #|
    end

    # Take the structure mutex to ensure the buffer does not change while you perform activities
    # This versions allows reads to happen if a top level function has already taken the mutex
    # @param top [Boolean] If true this will take the mutex and set an allow reads flag to allow
    #      lower level calls to go forward without getting the mutex
    def synchronize_allow_reads(top = false)
      @mutex_allow_reads ||= false
      setup_mutex()
      if top
        @mutex.synchronize do
          @mutex_allow_reads = Thread.current
          begin
            yield
          ensure
            @mutex_allow_reads = false
          end
        end
      else
        got_mutex = @mutex.try_lock
        if got_mutex
          begin
            yield
          ensure
            @mutex.unlock
          end
        elsif @mutex_allow_reads == Thread.current
          yield
        end
      end
    end

    module MethodMissing
      # Method missing provides reading/writing item values as if they were methods to the class
      def method_missing(name, value = nil)
        if value
          # Strip off the equals sign before looking up the item
          return write(name.to_s[0..-2], value)
        else
          return read(name.to_s)
        end
      end
    end

    def calculate_total_bit_size(item)
      if item.variable_bit_size
        # Bit size is determined by length field
        length_value = self.read(item.variable_bit_size['length_item_name'], :CONVERTED)
        if item.data_type == :INT or item.data_type == :UINT and not item.original_array_size
          case length_value
          when 0
            return 6
          when 1
            return 14
          when 2
            return 30
          else
            return 62
          end
        else
          return (length_value * item.variable_bit_size['length_bits_per_count']) + item.variable_bit_size['length_value_bit_offset']
        end
      elsif item.original_bit_size <= 0
        # Bit size is full packet length - bits before item + negative bits saved at end
        return (@buffer.length * 8) - item.bit_offset + item.original_bit_size
      elsif item.original_array_size and item.original_array_size <= 0
        # Bit size is full packet length - bits before item + negative bits saved at end
        return (@buffer.length * 8) - item.bit_offset + item.original_array_size
      else
        raise "Unexpected use of calculate_total_bit_size for non-variable-sized item"
      end
    end

    def recalculate_bit_offsets
      adjustment = 0
      @sorted_items.each do |item|
        # Anything with a negative bit offset should be left alone
        if item.original_bit_offset >= 0
          item.bit_offset = item.original_bit_offset + adjustment

          # May need to update adjustment with variable length items
          # Note legacy variable length does not push anything
          if item.data_type != :DERIVED and item.variable_bit_size # Not DERIVED and New Variable Length
            # Calculate the actual current size of this variable length item
            new_bit_size = calculate_total_bit_size(item)

            if item.original_bit_size != new_bit_size
              # Bit size has changed from original - so we need to adjust everything after this item
              # This includes items that may have the same bit_offset as the variable length item because it
              # started out at zero bit_size
              adjustment += (new_bit_size - item.original_bit_size)
            end
          end
        end
      end
    end

    def internal_buffer_equals(buffer)
      raise ArgumentError, "Buffer class is #{buffer.class} but must be String" unless String === buffer

      @buffer = buffer.dup
      if @accessor.enforce_encoding
        @buffer.force_encoding(@accessor.enforce_encoding)
      end
      if not @fixed_size
        recalculate_bit_offsets()
      end
      if @accessor.enforce_length
        if @buffer.length != @defined_length
          if @buffer.length < @defined_length
            resize_buffer()
            raise "Buffer length less than defined length" unless @short_buffer_allowed
          elsif @fixed_size and @defined_length != 0
            raise "Buffer length greater than defined length"
          end
        end
      end
    end
  end # class Structure
end
