# encoding: ascii-8bit
require 'openc3/packets/command_validator'

module OpenC3
  # Custom command validator class
  # See https://docs.openc3.com/docs/configuration/command
  class <%= validator_class %> < CommandValidator
    def initialize(*args)
      super()
      @args = args
    end

    # Called before a command is sent
    # @param command [Hash] The command hash containing all the command details
    # @return [Array<Boolean, String>] First element is true/false/nil for success/failure/unknown,
    #   second element is an optional message string
    def pre_check(command)
      # Add your pre-command validation logic here
      # Example:
      # target_name = command['target_name']
      # command_name = command['cmd_name']
      # params = command['cmd_params']
      #
      # if some_condition
      #   return [false, "Command validation failed: reason"]
      # end

      # Return true to indicate Success, false to indicate Failure,
      # and nil to indicate Unknown. The second value is the optional message.
      return [true, nil]
    end

    # Called after a command is sent
    # @param command [Hash] The command hash containing all the command details
    # @return [Array<Boolean, String>] First element is true/false/nil for success/failure/unknown,
    #   second element is an optional message string
    def post_check(command)
      # Add your post-command validation logic here
      # Example:
      # Use the OpenC3 API to check telemetry or wait for responses
      # wait_check("TARGET PACKET ITEM == 'EXPECTED'", 5) # Wait up to 5 seconds
      #
      # if some_condition
      #   return [false, "Post-command validation failed: reason"]
      # end

      # Return true to indicate Success, false to indicate Failure,
      # and nil to indicate Unknown. The second value is the optional message.
      return [true, nil]
    end
  end
end
