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

require 'openc3/top_level'
require 'openc3/ext/config_parser' if RUBY_ENGINE == 'ruby' and !ENV['OPENC3_NO_EXT']
require 'erb'
require 'fileutils'

module OpenC3
  # Reads OpenC3 style configuration data which consists of keywords followed
  # by 0 or more comma delimited parameters. Parameters with spaces must be
  # enclosed in quotes. Quotes should also be used to indicate a parameter is a
  # string. Keywords are case-insensitive and will be returned in uppercase.
  class ConfigParser
    # @return [String] The current keyword being parsed
    attr_accessor :keyword

    # @return [Array<String>] The parameters found after the keyword
    attr_accessor :parameters

    # @return [String] The name of the configuration file being parsed. This
    #   will be an empty string if the parse_string class method is used.
    attr_accessor :filename

    # @return [String] The current line being parsed. This is the raw string
    #   which is useful when printing errors.
    attr_accessor :line

    # @return [Integer] The current line number being parsed.
    #   This will still be populated when using parse_string because lines
    #   still must be delimited by newline characters.
    attr_accessor :line_number

    # @return [String] The default URL to use in errors. The URL can still be
    #   overridden by directly passing it to the error method.
    attr_accessor :url

    # @see message_callback=
    @@message_callback = nil

    # @param message_callback [#call(String)] Callback method called with a
    #   String when various parsing events occur.
    def self.message_callback=(message_callback)
      @@message_callback = message_callback
    end

    # @see progress_callback=
    @@progress_callback = nil

    # @param progress_callback [#call(Float)] Callback method called with a
    #   Float (0.0 to 100.0) based on the amount of the io param that has
    #   currently been processed.
    def self.progress_callback=(progress_callback)
      @@progress_callback = progress_callback
    end

    # Holds the current splash screen
    @@splash = nil

    # @param splash [Splash::SplashDialogBox] Set the splash dialog box which
    #   will be updated with messages and progress.
    def self.splash=(splash)
      if splash
        @@splash = splash
        @@progress_callback = splash.progress_callback
        @@message_callback = splash.message_callback
      else
        @@splash = nil
        @@progress_callback = nil
        @@message_callback = nil
      end
    end

    # Returns the current splash screen if present
    def self.splash
      @@splash
    end

    # Regular expression used to break up an individual line into a keyword and
    # comma delimited parameters. Handles parameters in single or double quotes.
    PARSING_REGEX = %r{ (?:"(?:[^\\"]|\\.)*") | (?:'(?:[^\\']|\\.)*') | \S+ }x # "

    # Error which gets raised by ConfigParser in #verify_num_parameters. This
    # is also the error that classes using ConfigParser should raise when they
    # encounter a configuration error.
    class Error < StandardError
      attr_reader :keyword, :parameters, :filename, :line, :line_number

      # @return [String] The usage string representing how this keyword should
      #   be formatted.
      attr_reader :usage

      # @return [String] URL which points to usage documentation on the OpenC3
      #   Wiki.
      attr_reader :url

      # Create an Error with the specified Config data
      #
      # @param config_parser [ConfigParser] Instance of ConfigParser so Error
      #   has access to the ConfigParser attributes
      # @param message [String] The error message which gets passed to the
      #   StandardError constructor
      # @param usage [String] The usage string representing how this keyword should
      #   be formatted.
      # @param url [String] URL which should point to usage information. By
      #   default this gets constructed to point to the generic configuration
      #   Guide on the OpenC3 Wiki.
      def initialize(config_parser, message = "Configuration Error", usage = "", url = "")
        if Error === message
          super(message.message)
        elsif Exception === message
          super("#{message.class}: #{message.message}")
        else
          super(message)
        end
        @keyword = config_parser.keyword
        @parameters = config_parser.parameters
        @filename = config_parser.filename
        @line = config_parser.line
        @line_number = config_parser.line_number
        @usage = usage
        @url = url
      end
    end

    # @param url [String] The url to link to in error messages
    def initialize(url = "https://docs.openc3.com/docs")
      @url = url
    end

    # Creates an Error
    #
    # @param message [String] The string to set the Exception message to
    # @param usage [String] The usage message
    # @param url [String] Where to get help about this error
    # @return [Error] The constructed error
    def error(message, usage = "", url = @url)
      return Error.new(self, message, usage, url)
    end

    # Called by the ERB template to render a partial
    def render(template_name, options = {})
      raise Error.new(self, "Partial name '#{template_name}' must begin with an underscore.") if File.basename(template_name)[0] != '_'

      b = binding
      if options[:locals]
        options[:locals].each { |key, value| b.local_variable_set(key, value) }
      end

      return ERB.new(read_file(template_name).comment_erb(), trim_mode: "-").result(b)
    end

    # Can be called during parsing to read a referenced file
    def read_file(filename)
      # Assume the file is there. If not we raise a pretty obvious error
      if File.expand_path(filename) == filename # absolute path
        path = filename
      else # relative to the current @filename
        path = File.join(File.dirname(@filename), filename)
      end
      OpenC3.set_working_dir(File.dirname(path)) do
        return File.read(path).force_encoding("UTF-8")
      end
    end

    # Processes a file and yields |config| to the given block
    #
    # @param filename [String] The full name and path of the configuration file
    # @param yield_non_keyword_lines [Boolean] Whether to yield all lines including blank
    #   lines or comment lines.
    # @param remove_quotes [Boolean] Whether to remove beginning and ending single
    #   or double quote characters from parameters.
    # @param run_erb [Boolean] Whether or not to run ERB on the file
    # @param variables [Hash] variables to push to ERB context
    # @param block [Block] The block to yield to
    # @yieldparam keyword [String] The keyword in the current parsed line
    # @yieldparam parameters [Array<String>] The parameters in the current parsed line
    def parse_file(filename,
                   yield_non_keyword_lines = false,
                   remove_quotes = true,
                   run_erb = true,
                   variables = {},
                   &)
      raise Error.new(self, "Configuration file #{filename} does not exist.") unless filename && File.exist?(filename)

      @filename = filename

      # Create a temp file where we write the ERB parsed output
      file = create_parsed_output_file(filename, run_erb, variables)
      size = file.stat.size.to_f

      # Callbacks for beginning of parsing
      @@message_callback.call("Parsing #{size} bytes of #{filename}") if @@message_callback
      @@progress_callback.call(0.0) if @@progress_callback

      begin
        # Loop through each line of the data
        parse_loop(file,
                   yield_non_keyword_lines,
                   remove_quotes,
                   size,
                   PARSING_REGEX,
                   &)
      ensure
        file.close unless file.closed?
      end
    end

    # Verifies the parameters in the config parameter have the specified
    # number of parameter and raises an Error if not.
    #
    # @param [Integer] min_num_params The minimum number of parameters
    # @param [Integer] max_num_params The maximum number of parameters. Pass
    #   nil to indicate there is no maximum number of parameters.
    def verify_num_parameters(min_num_params, max_num_params, usage = "")
      # This syntax works with 0 because each doesn't return any values
      # for a backwards range
      (1..min_num_params).each do |index|
        # If the parameter is nil (0 based) then we have a problem
        if @parameters[index - 1].nil?
          raise Error.new(self, "Not enough parameters for #{@keyword}.", usage, @url)
        end
      end
      # If they pass nil for max_params we don't check for a maximum number
      if max_num_params && !@parameters[max_num_params].nil?
        raise Error.new(self, "Too many parameters for #{@keyword}.", usage, @url)
      end
    end

    # Verifies the indicated parameter in the config doesn't start or end
    # with an underscore, doesn't contain a double underscore or double bracket,
    # doesn't contain spaces and doesn't start with a close bracket.
    #
    # @param [Integer] index The index of the parameter to check
    def verify_parameter_naming(index, usage = "")
      param = @parameters[index - 1]
      if param.end_with? '_'
        raise Error.new(self, "Parameter #{index} (#{param}) for #{@keyword} cannot end with an underscore ('_').", usage, @url)
      end
      if param.include? '__'
        raise Error.new(self, "Parameter #{index} (#{param}) for #{@keyword} cannot contain a double underscore ('__').", usage, @url)
      end
      if param.include? '[[' or param.include? ']]'
        raise Error.new(self, "Parameter #{index} (#{param}) for #{@keyword} cannot contain double brackets ('[[' or ']]').", usage, @url)
      end
      if param.include? ' '
        raise Error.new(self, "Parameter #{index} (#{param}) for #{@keyword} cannot contain a space (' ').", usage, @url)
      end
      if param.start_with?('}')
        raise Error.new(self, "Parameter #{index} (#{param}) for #{@keyword} cannot start with a close bracket ('}').", usage, @url)
      end
    end

    # Converts a String containing '', 'NIL', 'NULL', or 'NONE' to nil Ruby primitive.
    # All other arguments are simply returned.
    #
    # @param value [Object]
    # @return [nil|Object]
    def self.handle_nil(value)
      if String === value
        case value.upcase
        when '', 'NIL', 'NULL', 'NONE'
          return nil
        end
      end
      return value
    end

    # Converts a String containing 'TRUE' or 'FALSE' to true or false Ruby
    # primitive. All other values are simply returned.
    #
    # @param value [Object]
    # @return [true|false|Object]
    def self.handle_true_false(value)
      if String === value
        case value.upcase
        when 'TRUE'
          return true
        when 'FALSE'
          return false
        end
      end
      return value
    end

    # Converts a String containing '', 'NIL', 'NULL', 'TRUE' or 'FALSE' to nil,
    # true or false Ruby primitives. All other values are simply returned.
    #
    # @param value [Object]
    # @return [true|false|nil|Object]
    def self.handle_true_false_nil(value)
      if String === value
        case value.upcase
        when 'TRUE'
          return true
        when 'FALSE'
          return false
        when '', 'NIL', 'NULL'
          return nil
        end
      end
      return value
    end

    # Converts a string representing a defined constant into its value. The
    # defined constants are the minimum and maximum values for all the
    # allowable data types. [MIN/MAX]_[U]INT[8/16/32] and
    # [MIN/MAX]_FLOAT[32/64]. Thus MIN_UINT8, MAX_INT32, and MIN_FLOAT64 are
    # all allowable values. Any other strings raise ArgumentError but all other
    # types are simply returned.
    #
    # @param value [Object] Can be anything
    # @return [Numeric] The converted value. Either a Fixnum or Float.
    def self.handle_defined_constants(value, data_type = nil, bit_size = nil)
      if value.class == String
        case value.upcase
        when 'MIN', 'MAX'
          return self.calculate_range_value(value.upcase, data_type, bit_size)
        when 'MIN_INT8'
          return -128
        when 'MAX_INT8'
          return 127
        when 'MIN_INT16'
          return -32768
        when 'MAX_INT16'
          return 32767
        when 'MIN_INT32'
          return -2147483648
        when 'MAX_INT32'
          return 2147483647
        when 'MIN_INT64'
          return -9223372036854775808
        when 'MAX_INT64'
          return 9223372036854775807
        when 'MIN_UINT8', 'MIN_UINT16', 'MIN_UINT32', 'MIN_UINT64'
          return 0
        when 'MAX_UINT8'
          return 255
        when 'MAX_UINT16'
          return 65535
        when 'MAX_UINT32'
          return 4294967295
        when 'MAX_UINT64'
          return 18446744073709551615
        when 'MIN_FLOAT64'
          return -Float::MAX
        when 'MAX_FLOAT64'
          return Float::MAX
        when 'MIN_FLOAT32'
          return -3.402823e38
        when 'MAX_FLOAT32'
          return 3.402823e38
        when 'POS_INFINITY'
          return Float::INFINITY
        when 'NEG_INFINITY'
          return -Float::INFINITY
        else
          raise ArgumentError, "Could not convert constant: #{value}"
        end
      end
      return value
    end

    protected

    # Writes the ERB parsed results
    def create_parsed_output_file(filename, run_erb, variables)
      begin
        output = nil
        if run_erb
          OpenC3.set_working_dir(File.dirname(filename)) do
            output = ERB.new(File.read(filename).force_encoding("UTF-8").comment_erb(), trim_mode: "-").result(binding.set_variables(variables))
          end
        else
          output = File.read(filename).force_encoding("UTF-8")
        end
      rescue => e
        # The first line of the backtrace indicates the line where the ERB
        # parse failed. Grab the line number for the error message.
        match = /:(.*):/.match(e.backtrace[0])
        line_number = match.captures[0] if match
        raise e, "ERB error at #{filename}:#{line_number}\n#{e}", e.backtrace
      end
      # Make a copy of the filename since we're calling slice! which modifies it directly
      copy = filename.dup
      config_index = copy.index('config')
      if config_index
        copy = copy[config_index..-1]
      elsif copy.include?(':') # Check for Windows drive letter
        copy = copy.split(':')[1]
      end
      parsed_filename = File.join(Dir.tmpdir, 'openc3', 'tmp', copy)
      FileUtils.mkdir_p(File.dirname(parsed_filename)) # Create the path
      file = File.open(parsed_filename, 'w+')
      file.puts output
      file.rewind # Rewind so the file is ready to read
      file
    end

    def self.calculate_range_value(type, data_type, bit_size)
      value = 0 # Default for UINT minimum

      case data_type
      when :INT
        if type == 'MIN'
          value = -2**(bit_size - 1)
        else # 'MAX'
          value = (2**(bit_size - 1)) - 1
        end
      when :UINT
        # Default is 0 for 'MIN'
        if type == 'MAX'
          value = (2**bit_size) - 1
        end
      when :FLOAT
        case bit_size
        when 32
          value = 3.402823e38
          value *= -1 if type == 'MIN'
        when 64
          value = Float::MAX
          value *= -1 if type == 'MIN'
        else
          raise ArgumentError, "Invalid bit size #{bit_size} for FLOAT type."
        end
      else
        raise ArgumentError, "Invalid data type #{data_type} when calculating range."
      end
      value
    end

    def parse_errors(errors)
      return if errors.empty?
      message = ''
      errors.each do |error|
        # Once we have a message we want to ignore errors about bad items, packets, and targets
        # because the real error is probably in a previous definition
        next if message != '' && error.message.include?('No current item')
        next if message != '' && error.message.include?('No current packet')
        next if message != '' && error.message.include?('Unknown keyword and parameters for Target')

        if error.is_a? OpenC3::ConfigParser::Error
          message += "\n#{File.basename(error.filename)}:#{error.line_number}: #{error.line}" if error.filename
          message += "\nError: #{error.message}"
          message += "\nUsage: #{error.usage}" unless error.usage.empty?
          message += "\n"
        # Only capture the first non-ConfigParser::Error which is typically
        # a RuntimeError generated from a raise during parsing
        elsif message == ''
          message += "\n#{error.formatted}\n"
        end
      end
      raise Error.new(self, message)
    end

    if RUBY_ENGINE != 'ruby' or ENV['OPENC3_NO_EXT']
      # Iterates over each line of the io object and yields the keyword and parameters
      def parse_loop(io, yield_non_keyword_lines, remove_quotes, size, rx)
        string_concat = false
        @line_number = 0
        @keyword = nil
        @parameters = []
        @line = ''
        errors = []

        while true
          @line_number += 1

          if @@progress_callback && ((@line_number % 10) == 0)
            @@progress_callback.call(io.pos / size) if size > 0.0
          end

          begin
            line = io.readline
          rescue Exception
            break
          end

          line.strip!
          # Ensure the line length is not 0
          next if line.length == 0

          if string_concat
            # Skip comment lines after a string concatenation
            if (line[0] == '#')
              next
            end
            # Remove the opening quote if we're continuing the line
            line = line[1..-1]
          end

          # Check for string continuation
          case line[-1]
          when '+', '\\' # String concatenation
            newline = line[-1] == '+'
            # Trim off the concat character plus any spaces, e.g. "line" \
            trim = line[0..-2].strip()
            # Now trim off the last quote so it will flow into the next line
            @line += trim[0..-2]
            @line += "\n" if newline
            string_concat = true
            next
          when '&' # Line continuation
            @line += line[0..-2]
            next
          else
            @line += line
          end
          string_concat = false

          data = @line.scan(rx)
          first_item = ''
          if data.length > 0
            first_item += data[0]
          end

          if (first_item.length == 0) || (first_item[0] == '#')
            @keyword = nil
          else
            @keyword = first_item.upcase
          end
          @parameters = []

          # Ignore lines without keywords: comments and blank lines
          if @keyword.nil?
            if yield_non_keyword_lines
              begin
                yield(@keyword, @parameters)
              rescue => e
                errors << e
              end
            end
            @line = ''
            next
          end

          length = data.length
          if length > 1
            (1..(length - 1)).each do |index|
              string = data[index]

              # Don't process trailing comments such as:
              # KEYWORD PARAM #This is a comment
              # But still process Ruby string interpolations such as:
              # KEYWORD PARAM #{var}
              if (string.length > 0) && (string[0] == '#')
                if !((string.length > 1) && (string[1] == '{'))
                  break
                end
              end

              if remove_quotes
                @parameters << string.remove_quotes
              else
                @parameters << string
              end
            end
          end

          begin
            yield(@keyword, @parameters)
          rescue => e
            errors << e
          end
          @line = ''
        end

        parse_errors(errors)

        @@progress_callback.call(1.0) if @@progress_callback

        return nil
      end
    end
  end
end
