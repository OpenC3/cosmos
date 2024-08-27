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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/script/extract'

module OpenC3
  module ApiShared
    include Extract

    DEFAULT_TLM_POLLING_RATE = 0.25

    private

    # Check the converted value of a telmetry item against a condition.
    # Always print the value of the telemetry item to STDOUT.
    # If the condition check fails, raise an error.
    #
    # Supports two signatures:
    # check(target_name, packet_name, item_name, comparison_to_eval)
    # check('target_name packet_name item_name > 1')
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    def check(*args, type: :CONVERTED, scope: $openc3_scope, token: $openc3_token)
      _check(*args, scope: scope) { |tgt, pkt, item| tlm(tgt, pkt, item, type: type, scope: scope, token: token) }
    end

    def check_raw(*args, scope: $openc3_scope, token: $openc3_token)
      check(*args, type: :RAW, scope: scope, token: token)
    end

    def check_formatted(*args, scope: $openc3_scope, token: $openc3_token)
      check(*args, type: :FORMATTED, scope: scope, token: token)
    end

    def check_with_units(*args, scope: $openc3_scope, token: $openc3_token)
      check(*args, type: :WITH_UNITS, scope: scope, token: token)
    end

    # Executes the passed method and expects an exception to be raised.
    # Raises a CheckError if an Exception is not raised.
    # Usage:
    #   check_exception(method_name, method_params}
    def check_exception(method_name, *args, **kwargs)
      orig_kwargs = kwargs.clone
      kwargs[:scope] = $openc3_scope unless kwargs[:scope]
      kwargs[:token] = $openc3_token unless kwargs[:token]
      send(method_name.intern, *args, **kwargs)
      method = "#{method_name}(#{args.join(", ")}"
      method += ", #{orig_kwargs}" unless orig_kwargs.empty?
      method += ")"
    rescue Exception => e
      puts "CHECK: #{method} raised #{e.class}:#{e.message}"
    else
      raise(CheckError, "#{method} should have raised an exception but did not.")
    end

    # Check the converted value of a telmetry item against an expected value with a tolerance.
    # Always print the value of the telemetry item to STDOUT. If the condition check fails, raise an error.
    #
    # Supports two signatures:
    # check_tolerance(target_name, packet_name, item_name, expected_value, tolerance)
    # check_tolerance('target_name packet_name item_name', expected_value, tolerance)
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW or :CONVERTED (default)
    def check_tolerance(*args, type: :CONVERTED, scope: $openc3_scope, token: $openc3_token)
      raise "Invalid type '#{type}' for check_tolerance" unless %i(RAW CONVERTED).include?(type)

      target_name, packet_name, item_name, expected_value, tolerance =
        _check_tolerance_process_args(args)
      value = tlm(target_name, packet_name, item_name, type: type, scope: scope, token: token)
      if value.is_a?(Array)
        expected_value, tolerance = _array_tolerance_process_args(value.size, expected_value, tolerance, 'check_tolerance')

        message = ""
        all_checks_ok = true
        value.size.times do |i|
          range = (expected_value[i] - tolerance[i]..expected_value[i] + tolerance[i])
          check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)}[#{i}]"
          range_str = "range #{range.first} to #{range.last} with value == #{value[i]}"
          if range.include?(value[i])
            message << "#{check_str} was within #{range_str}\n"
          else
            message << "#{check_str} failed to be within #{range_str}\n"
            all_checks_ok = false
          end
        end

        if all_checks_ok
          puts message
        else
          if $disconnect
            puts "ERROR: #{message}"
          else
            raise CheckError, message
          end
        end
      else
        range = (expected_value - tolerance)..(expected_value + tolerance)
        check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)}"
        range_str = "range #{range.first} to #{range.last} with value == #{value}"
        if range.include?(value)
          puts "#{check_str} was within #{range_str}"
        else
          message = "#{check_str} failed to be within #{range_str}"
          if $disconnect
            puts "ERROR: #{message}"
          else
            raise CheckError, message
          end
        end
      end
    end

    # @deprecated Use check_tolerance with type: :RAW
    def check_tolerance_raw(*args, scope: $openc3_scope, token: $openc3_token)
      check_tolerance(*args, type: :RAW, scope: scope, token: token)
    end

    # Check to see if an expression is true without waiting.  If the expression
    # is not true, the script will pause.
    def check_expression(exp_to_eval, context = nil, scope: $openc3_scope, token: $openc3_token)
      success = _openc3_script_wait_implementation_expression(exp_to_eval, 0, DEFAULT_TLM_POLLING_RATE, context, scope: scope, token: token)
      if success
        puts "CHECK: #{exp_to_eval} is TRUE"
      else
        message = "CHECK: #{exp_to_eval} is FALSE"
        if $disconnect
          puts "ERROR: #{message}"
        else
          raise CheckError, message
        end
      end
    end

    # Wait on an expression to be true. On a timeout, the script will continue.
    #
    # Supports multiple signatures:
    # wait(time)
    # wait('target_name packet_name item_name > 1', timeout, polling_rate)
    # wait('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate)
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    def wait(*args, type: :CONVERTED, quiet: false, scope: $openc3_scope, token: $openc3_token)
      time_diff = nil

      case args.length
      # wait() # indefinitely until they click Go
      when 0
        start_time = Time.now.sys
        openc3_script_sleep()
        time_diff = Time.now.sys - start_time
        puts "WAIT: Indefinite for actual time of #{time_diff} seconds" unless quiet
        return time_diff

      # wait(5) # absolute wait time
      when 1
        if args[0].kind_of? Numeric
          start_time = Time.now.sys
          openc3_script_sleep(args[0])
          time_diff = Time.now.sys - start_time
          puts "WAIT: #{args[0]} seconds with actual time of #{time_diff} seconds" unless quiet
          return time_diff
        else
          raise "Non-numeric wait time specified"
        end

      # wait('target_name packet_name item_name > 1', timeout, polling_rate) # polling_rate is optional
      when 2, 3
        target_name, packet_name, item_name, comparison_to_eval = extract_fields_from_check_text(args[0])
        timeout = args[1]
        if args.length == 3
          polling_rate = args[2]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
        return _execute_wait(target_name, packet_name, item_name, type, comparison_to_eval, timeout, polling_rate, quiet: quiet, scope: scope, token: token)

      # wait('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate) # polling_rate is optional
      when 5, 6
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        comparison_to_eval = args[3]
        timeout = args[4]
        if args.length == 6
          polling_rate = args[5]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
        return _execute_wait(target_name, packet_name, item_name, type, comparison_to_eval, timeout, polling_rate, quiet: quiet, scope: scope, token: token)

      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to wait()"
      end
    end

    # @deprecated Use wait with type: :RAW
    def wait_raw(*args, quiet: false, scope: $openc3_scope, token: $openc3_token)
      wait(*args, type: :RAW, quiet: quiet, scope: scope, token: token)
    end

    # Wait on an expression to be true. On a timeout, the script will continue.
    #
    # Supports two signatures:
    # wait_tolerance('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    # wait_tolerance('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW or :CONVERTED (default)
    def wait_tolerance(*args, type: :CONVERTED, quiet: false, scope: $openc3_scope, token: $openc3_token)
      raise "Invalid type '#{type}' for wait_tolerance" unless %i(RAW CONVERTED).include?(type)

      target_name, packet_name, item_name, expected_value, tolerance, timeout, polling_rate = _wait_tolerance_process_args(args)
      start_time = Time.now.sys
      value = tlm(target_name, packet_name, item_name, type: type, scope: scope, token: token)
      if value.is_a?(Array)
        expected_value, tolerance = _array_tolerance_process_args(value.size, expected_value, tolerance, 'wait_tolerance')

        success, value = _openc3_script_wait_implementation_array_tolerance(value.size, target_name, packet_name, item_name, type, expected_value, tolerance, timeout, polling_rate, scope: scope, token: token)
        time = Time.now.sys - start_time

        message = ""
        value.size.times do |i|
          range = (expected_value[i] - tolerance[i]..expected_value[i] + tolerance[i])
          wait_str = "WAIT: #{_upcase(target_name, packet_name, item_name)}[#{i}]"
          range_str = "range #{range.first} to #{range.last} with value == #{value[i]} after waiting #{time} seconds"
          if range.include?(value[i])
            message << "#{wait_str} was within #{range_str}\n"
          else
            message << "#{wait_str} failed to be within #{range_str}\n"
          end
        end

        if success
          puts message unless quiet
        else
          puts "WARN: #{message}" unless quiet
        end
      else
        success, value = _openc3_script_wait_implementation_tolerance(target_name, packet_name, item_name, type, expected_value, tolerance, timeout, polling_rate, scope: scope, token: token)
        time = Time.now.sys - start_time
        range = (expected_value - tolerance)..(expected_value + tolerance)
        wait_str = "WAIT: #{_upcase(target_name, packet_name, item_name)}"
        range_str = "range #{range.first} to #{range.last} with value == #{value} after waiting #{time} seconds"
        if success
          puts "#{wait_str} was within #{range_str}" unless quiet
        else
          puts "WARN: #{wait_str} failed to be within #{range_str}" unless quiet
        end
      end
      return success
    end

    # @deprecated Use wait_tolerance with type: :RAW
    def wait_tolerance_raw(*args, quiet: false, scope: $openc3_scope, token: $openc3_token)
      wait_tolerance(*args, type: :RAW, quiet: quiet, scope: scope, token: token)
    end

    # Wait on a custom expression to be true
    def wait_expression(exp_to_eval, timeout, polling_rate = DEFAULT_TLM_POLLING_RATE, context = nil, quiet: false, scope: $openc3_scope, token: $openc3_token)
      start_time = Time.now.sys
      success = _openc3_script_wait_implementation_expression(exp_to_eval, timeout, polling_rate, context, scope: scope, token: token)
      time_diff = Time.now.sys - start_time
      if success
        puts "WAIT: #{exp_to_eval} is TRUE after waiting #{time_diff} seconds" unless quiet
      else
        puts "WARN: WAIT: #{exp_to_eval} is FALSE after waiting #{time_diff} seconds" unless quiet
      end
      return success
    end

    # Wait for the converted value of a telmetry item against a condition or for a timeout
    # and then check against the condition.
    #
    # Supports two signatures:
    # wait_check(target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate)
    # wait_check('target_name packet_name item_name > 1', timeout, polling_rate)
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    def wait_check(*args, type: :CONVERTED, scope: $openc3_scope, token: $openc3_token, &block)
      target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate = _wait_check_process_args(args)
      start_time = Time.now.sys
      success, value = _openc3_script_wait_implementation_comparison(target_name, packet_name, item_name, type, comparison_to_eval, timeout, polling_rate, scope: scope, token: token, &block)
      value = "'#{value}'" if value.is_a? String # Show user the check against a quoted string
      time_diff = Time.now.sys - start_time
      check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)}"
      if comparison_to_eval
        check_str += " #{comparison_to_eval}"
      end
      with_value_str = "with value == #{value} after waiting #{time_diff} seconds"
      if success
        puts "#{check_str} success #{with_value_str}"
      else
        message = "#{check_str} failed #{with_value_str}"
        if $disconnect
          puts "ERROR: #{message}"
        else
          raise CheckError, message
        end
      end
      return time_diff
    end

    # @deprecated use wait_check with type: :RAW
    def wait_check_raw(*args, scope: $openc3_scope, token: $openc3_token, &block)
      wait_check(*args, type: :RAW, scope: scope, token: token, &block)
    end

    # Wait for the value of a telmetry item to be within a tolerance of a value
    # and then check against the condition.
    #
    # Supports multiple signatures:
    # wait_tolerance('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    # wait_tolerance('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW or :CONVERTED (default)
    def wait_check_tolerance(*args, type: :CONVERTED, scope: $openc3_scope, token: $openc3_token, &block)
      raise "Invalid type '#{type}' for wait_check_tolerance" unless %i(RAW CONVERTED).include?(type)

      target_name, packet_name, item_name, expected_value, tolerance, timeout, polling_rate = _wait_tolerance_process_args(args)
      start_time = Time.now.sys
      value = tlm(target_name, packet_name, item_name, type: type, scope: scope, token: token)
      if value.is_a?(Array)
        expected_value, tolerance = _array_tolerance_process_args(value.size, expected_value, tolerance, 'wait_check_tolerance')

        success, value = _openc3_script_wait_implementation_array_tolerance(value.size, target_name, packet_name, item_name, type, expected_value, tolerance, timeout, polling_rate, scope: scope, token: token, &block)
        time_diff = Time.now.sys - start_time

        message = ""
        value.size.times do |i|
          range = (expected_value[i] - tolerance[i]..expected_value[i] + tolerance[i])
          check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)}[#{i}]"
          range_str = "range #{range.first} to #{range.last} with value == #{value[i]} after waiting #{time_diff} seconds"
          if range.include?(value[i])
            message << "#{check_str} was within #{range_str}\n"
          else
            message << "#{check_str} failed to be within #{range_str}\n"
          end
        end

        if success
          puts message
        else
          if $disconnect
            puts "ERROR: #{message}"
          else
            raise CheckError, message
          end
        end
      else
        success, value = _openc3_script_wait_implementation_tolerance(target_name, packet_name, item_name, type, expected_value, tolerance, timeout, polling_rate, scope: scope, token: token)
        time_diff = Time.now.sys - start_time
        range = (expected_value - tolerance)..(expected_value + tolerance)
        check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)}"
        range_str = "range #{range.first} to #{range.last} with value == #{value} after waiting #{time_diff} seconds"
        if success
          puts "#{check_str} was within #{range_str}"
        else
          message = "#{check_str} failed to be within #{range_str}"
          if $disconnect
            puts "ERROR: #{message}"
          else
            raise CheckError, message
          end
        end
      end
      return time_diff
    end

    # @deprecated Use wait_check_tolerance with type: :RAW
    def wait_check_tolerance_raw(*args, scope: $openc3_scope, token: $openc3_token, &block)
      wait_check_tolerance(*args, type: :RAW, scope: scope, token: token, &block)
    end

    # Wait on an expression to be true.  On a timeout, the script will pause.
    def wait_check_expression(exp_to_eval,
                              timeout,
                              polling_rate = DEFAULT_TLM_POLLING_RATE,
                              context = nil,
                              scope: $openc3_scope, token: $openc3_token, &block)
      start_time = Time.now.sys
      success = _openc3_script_wait_implementation_expression(exp_to_eval,
                                                             timeout,
                                                             polling_rate,
                                                             context, scope: scope, token: token, &block)
      time_diff = Time.now.sys - start_time
      if success
        puts "CHECK: #{exp_to_eval} is TRUE after waiting #{time_diff} seconds"
      else
        message = "CHECK: #{exp_to_eval} is FALSE after waiting #{time_diff} seconds"
        if $disconnect
          puts "ERROR: #{message}"
        else
          raise CheckError, message
        end
      end
      return time_diff
    end
    alias wait_expression_stop_on_timeout wait_check_expression

    def wait_packet(target_name,
                    packet_name,
                    num_packets,
                    timeout,
                    polling_rate = DEFAULT_TLM_POLLING_RATE,
                    quiet: false,
                    scope: $openc3_scope, token: $openc3_token)
      success, _ = _wait_packet(false, target_name, packet_name, num_packets, timeout, polling_rate, quiet: quiet, scope: scope, token: token)
      return success
    end

    # Wait for a telemetry packet to be received a certain number of times or timeout and raise an error
    def wait_check_packet(target_name,
                          packet_name,
                          num_packets,
                          timeout,
                          polling_rate = DEFAULT_TLM_POLLING_RATE,
                          quiet: false,
                          scope: $openc3_scope, token: $openc3_token)
      _, time_diff = _wait_packet(true, target_name, packet_name, num_packets, timeout, polling_rate, quiet: quiet, scope: scope, token: token)
      return time_diff
    end

    def disable_instrumentation
      if defined? RunningScript and RunningScript.instance
        RunningScript.instance.use_instrumentation = false
        begin
          yield
        ensure
          RunningScript.instance.use_instrumentation = true
        end
      else
        yield
      end
    end

    def set_line_delay(delay)
      if defined? RunningScript
        RunningScript.line_delay = delay if delay >= 0.0
      end
    end

    def get_line_delay
      if defined? RunningScript
        RunningScript.line_delay
      end
    end

    def set_max_output(characters)
      if defined? RunningScript
        RunningScript.max_output_characters = Integer(characters)
      end
    end

    def get_max_output
      if defined? RunningScript
        RunningScript.max_output_characters
      end
    end

    ###########################################################################
    # Scripts Outside of ScriptRunner Support
    # ScriptRunner overrides these methods to work in the OpenC3 cluster
    # They are only here to allow for scripts to have a chance to work
    # unaltered outside of the cluster
    ###########################################################################

    def start(procedure_name)
      cached = false
      begin
        Kernel::load(procedure_name)
      rescue LoadError => e
        raise LoadError, "Error loading -- #{procedure_name}\n#{e.message}"
      end
      # Return whether we had to load and instrument this file, i.e. it was not cached
      !cached
    end

    # Require an additional ruby file
    def load_utility(procedure_name)
      return start(procedure_name)
    end
    def require_utility(procedure_name)
      # Ensure require_utility works like require where you don't need the .rb extension
      if File.extname(procedure_name) != '.rb'
        procedure_name += '.rb'
      end
      @require_utility_cache ||= {}
      if @require_utility_cache[procedure_name]
        return false
      else
        @require_utility_cache[procedure_name] = true
        begin
          return start(procedure_name)
        rescue LoadError
          @require_utility_cache[procedure_name] = false
          raise # reraise the error
        end
      end
    end

    ###########################################################################
    # Private implementation details
    ###########################################################################

    # This must be here for custom microservices that might block.
    # Overridden by running_script.rb for script sleep
    def openc3_script_sleep(sleep_time = nil)
      if sleep_time
        sleep(sleep_time)
      else
        prompt("Press any key to continue...")
      end
      return false
    end

    # Creates a string with the parameters upcased
    def _upcase(target_name, packet_name, item_name)
      "#{target_name.upcase} #{packet_name.upcase} #{item_name.upcase}"
    end

    # Implementation of the various check commands. It yields back to the
    # caller to allow the return of the value through various telemetry calls.
    # This method should not be called directly by application code.
    def _check(*args, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name, comparison_to_eval = _check_process_args(args, 'check')

      value = yield(target_name, packet_name, item_name)
      if comparison_to_eval
        _check_eval(target_name, packet_name, item_name, comparison_to_eval, value)
      else
        puts "CHECK: #{_upcase(target_name, packet_name, item_name)} == #{value}"
      end
    end

    def _check_process_args(args, method_name)
      case args.length
      when 1
        target_name, packet_name, item_name, comparison_to_eval = extract_fields_from_check_text(args[0])
      when 3
        target_name        = args[0]
        packet_name        = args[1]
        item_name          = args[2]
      when 4
        target_name        = args[0]
        packet_name        = args[1]
        item_name          = args[2]
        comparison_to_eval = args[3]
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      if comparison_to_eval and !comparison_to_eval.is_printable?
        raise "ERROR: Invalid comparison to non-ascii value"
      end
      return [target_name, packet_name, item_name, comparison_to_eval]
    end

    def _check_tolerance_process_args(args)
      case args.length
      when 3
        target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        expected_value = args[1]
        if args[2].is_a?(Array)
          tolerance = args[2].map!(&:abs)
        else
          tolerance = args[2].abs
        end
      when 5
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        expected_value = args[3]
        if args[4].is_a?(Array)
          tolerance = args[4].map!(&:abs)
        else
          tolerance = args[4].abs
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to check_tolerance()"
      end
      return [target_name, packet_name, item_name, expected_value, tolerance]
    end

    # Wait for a telemetry packet to be received a certain number of times or timeout
    def _wait_packet(check,
                     target_name,
                     packet_name,
                     num_packets,
                     timeout,
                     polling_rate = DEFAULT_TLM_POLLING_RATE,
                     quiet: false,
                     scope: $openc3_scope, token: $openc3_token)
      type = (check ? 'CHECK' : 'WAIT')
      initial_count = tlm(target_name, packet_name, 'RECEIVED_COUNT', scope: scope, token: token)
      # If the packet has not been received the initial_count could be nil
      initial_count = 0 unless initial_count
      start_time = Time.now.sys
      success, value = _openc3_script_wait_implementation_comparison(target_name,
                                                                     packet_name,
                                                                     'RECEIVED_COUNT',
                                                                     :CONVERTED,
                                                                     ">= #{initial_count + num_packets}",
                                                                     timeout,
                                                                     polling_rate,
                                                                     scope: scope,
                                                                     token: token)
      # If the packet has not been received the value could be nil
      value = 0 unless value
      time_diff = Time.now.sys - start_time
      if success
        puts "#{type}: #{target_name.upcase} #{packet_name.upcase} received #{value - initial_count} times after waiting #{time_diff} seconds" unless quiet
      else
        message = "#{type}: #{target_name.upcase} #{packet_name.upcase} expected to be received #{num_packets} times but only received #{value - initial_count} times after waiting #{time_diff} seconds"
        if check
          if $disconnect
            puts "ERROR: #{message}"
          else
            raise CheckError, message
          end
        else
          puts "WARN: #{message}" unless quiet
        end
      end
      return success, time_diff
    end

    def _execute_wait(target_name, packet_name, item_name, value_type, comparison_to_eval, timeout, polling_rate, quiet: false, scope: $openc3_scope, token: $openc3_token)
      start_time = Time.now.sys
      success, value = _openc3_script_wait_implementation_comparison(target_name, packet_name, item_name, value_type, comparison_to_eval, timeout, polling_rate, scope: scope, token: token)
      value = "'#{value}'" if value.is_a? String # Show user the check against a quoted string
      time_diff = Time.now.sys - start_time
      wait_str = "WAIT: #{_upcase(target_name, packet_name, item_name)} #{comparison_to_eval}"
      value_str = "with value == #{value} after waiting #{time_diff} seconds"
      if success
        puts "#{wait_str} success #{value_str}" unless quiet
      else
        puts "WARN: #{wait_str} failed #{value_str}" unless quiet
      end
      return success
    end

    def _wait_tolerance_process_args(args)
      case args.length
      when 4, 5
        target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        expected_value = args[1]
        if args[2].is_a?(Array)
          tolerance = args[2].map!(&:abs)
        else
          tolerance = args[2].abs
        end
        timeout = args[3]
        if args.length == 5
          polling_rate = args[4]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
      when 6, 7
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        expected_value = args[3]
        if args[4].is_a?(Array)
          tolerance = args[4].map!(&:abs)
        else
          tolerance = args[4].abs
        end
        timeout = args[5]
        if args.length == 7
          polling_rate = args[6]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to wait_tolerance()"
      end
      return [target_name, packet_name, item_name, expected_value, tolerance, timeout, polling_rate]
    end

    # When testing an array with a tolerance, the expected value and tolerance
    # can both be supplied as either an array or a single value.  If a single
    # value is passed in, that value will be used for all array elements.
    def _array_tolerance_process_args(array_size, expected_value, tolerance, method_name)
      if expected_value.is_a?(Array)
        if array_size != expected_value.size
          raise "ERROR: Invalid array size for expected_value passed to #{method_name}()"
        end
      else
        expected_value = Array.new(array_size, expected_value)
      end
      if tolerance.is_a?(Array)
        if array_size != tolerance.size
          raise "ERROR: Invalid array size for tolerance passed to #{method_name}()"
        end
      else
        tolerance = Array.new(array_size, tolerance)
      end
      return [expected_value, tolerance]
    end

    def _wait_check_process_args(args)
      case args.length
      when 2, 3
        target_name, packet_name, item_name, comparison_to_eval = extract_fields_from_check_text(args[0])
        timeout = args[1]
        if args.length == 3
          polling_rate = args[2]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
      when 5, 6
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        comparison_to_eval = args[3]
        timeout = args[4]
        if args.length == 6
          polling_rate = args[5]
        else
          polling_rate = DEFAULT_TLM_POLLING_RATE
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to wait_check()"
      end
      return [target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate]
    end

    def _openc3_script_wait_implementation(target_name, packet_name, item_name, value_type, timeout, polling_rate, exp_to_eval, scope: $openc3_scope, token: $openc3_token, &block)
      end_time = Time.now.sys + timeout
      if exp_to_eval and !exp_to_eval.is_printable?
        raise "ERROR: Invalid comparison to non-ascii value"
      end
      while true
        work_start = Time.now.sys
        value = tlm(target_name, packet_name, item_name, type: value_type, scope: scope, token: token)
        if not block.nil?
          if block.call(value)
            return true, value
          end
        else
          begin
            if eval(exp_to_eval)
              return true, value
            end
          # NoMethodError is raised when the tlm() returns nil and we try to eval the expression
          # In this case we just continue and see if eventually we get a good value from tlm()
          rescue NoMethodError
          end
        end
        break if Time.now.sys >= end_time

        delta = Time.now.sys - work_start
        sleep_time = polling_rate - delta
        end_delta = end_time - Time.now.sys
        sleep_time = end_delta if end_delta < sleep_time
        sleep_time = 0 if sleep_time < 0
        canceled = openc3_script_sleep(sleep_time)

        if canceled
          value = tlm(target_name, packet_name, item_name, type: value_type, scope: scope, token: token)
          if not block.nil?
            if block.call(value)
              return true, value
            else
              return false, value
            end
          else
            begin
              if eval(exp_to_eval)
                return true, value
              else
                return false, value
              end
            # NoMethodError is raised when the tlm() returns nil and we try to eval the expression
            rescue NoMethodError
              return false, value
            end
          end
        end
      end

      return false, value
    rescue NameError => e
      if e.message =~ /uninitialized constant OpenC3::ApiShared::(\w+)/
        new_error = NameError.new("Uninitialized constant #{$1}. Did you mean '#{$1}' as a string?")
        new_error.set_backtrace(e.backtrace)
        raise new_error
      else
        raise e
      end
    end

    # Wait for a converted telemetry item to pass a comparison
    def _openc3_script_wait_implementation_comparison(target_name, packet_name, item_name, value_type, comparison_to_eval, timeout, polling_rate = DEFAULT_TLM_POLLING_RATE, scope: $openc3_scope, token: $openc3_token, &block)
      if comparison_to_eval
        exp_to_eval = "value " + comparison_to_eval
      else
        exp_to_eval = nil
      end
      _openc3_script_wait_implementation(target_name, packet_name, item_name, value_type, timeout, polling_rate, exp_to_eval, scope: scope, token: token, &block)
    end

    def _openc3_script_wait_implementation_tolerance(target_name, packet_name, item_name, value_type, expected_value, tolerance, timeout, polling_rate = DEFAULT_TLM_POLLING_RATE, scope: $openc3_scope, token: $openc3_token, &block)
      exp_to_eval = "((#{expected_value} - #{tolerance})..(#{expected_value} + #{tolerance})).include? value"
      _openc3_script_wait_implementation(target_name, packet_name, item_name, value_type, timeout, polling_rate, exp_to_eval, scope: scope, token: token, &block)
    end

    def _openc3_script_wait_implementation_array_tolerance(array_size, target_name, packet_name, item_name, value_type, expected_value, tolerance, timeout, polling_rate = DEFAULT_TLM_POLLING_RATE, scope: $openc3_scope, token: $openc3_token, &block)
      statements = []
      array_size.times { |i| statements << "(((#{expected_value[i]} - #{tolerance[i]})..(#{expected_value[i]} + #{tolerance[i]})).include? value[#{i}])" }
      exp_to_eval = statements.join(" && ")
      _openc3_script_wait_implementation(target_name, packet_name, item_name, value_type, timeout, polling_rate, exp_to_eval, scope: scope, token: token, &block)
    end

    # Wait on an expression to be true.
    def _openc3_script_wait_implementation_expression(exp_to_eval, timeout, polling_rate, context, scope: $openc3_scope, token: $openc3_token)
      end_time = Time.now.sys + timeout
      raise "Invalid comparison to non-ascii value" unless exp_to_eval.is_printable?

      while true
        work_start = Time.now.sys
        if eval(exp_to_eval, context)
          return true
        end
        break if Time.now.sys >= end_time

        delta = Time.now.sys - work_start
        sleep_time = polling_rate - delta
        end_delta = end_time - Time.now.sys
        sleep_time = end_delta if end_delta < sleep_time
        sleep_time = 0 if sleep_time < 0
        canceled = openc3_script_sleep(sleep_time)

        if canceled
          if eval(exp_to_eval, context)
            return true
          else
            return false
          end
        end
      end

      return false
    rescue NameError => e
      if e.message =~ /uninitialized constant OpenC3::ApiShared::(\w+)/
        new_error = NameError.new("Uninitialized constant #{$1}. Did you mean '#{$1}' as a string?")
        new_error.set_backtrace(e.backtrace)
        raise new_error
      else
        raise e
      end
    end

    def _check_eval(target_name, packet_name, item_name, comparison_to_eval, value)
      string = "value " + comparison_to_eval
      check_str = "CHECK: #{_upcase(target_name, packet_name, item_name)} #{comparison_to_eval}"
      # Show user the check against a quoted string
      # Note: We have to preserve the original 'value' variable because we're going to eval against it
      value_str = value.is_a?(String) ? "'#{value}'" : value
      with_value = "with value == #{value_str}"
      if eval(string)
        puts "#{check_str} success #{with_value}"
      else
        message = "#{check_str} failed #{with_value}"
        if $disconnect
          puts "ERROR: #{message}"
        else
          raise CheckError, message
        end
      end
    rescue NameError => e
      if e.message =~ /uninitialized constant OpenC3::ApiShared::(\w+)/
        new_error = NameError.new("Uninitialized constant #{$1}. Did you mean '#{$1}' as a string?")
        new_error.set_backtrace(e.backtrace)
        raise new_error
      else
        raise e
      end
    end
  end
end
