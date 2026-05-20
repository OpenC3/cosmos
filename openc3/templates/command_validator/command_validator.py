from openc3.packets.command_validator import CommandValidator
# Using the OpenC3 API requires the following imports:
from openc3.api import tlm, wait_check

# Custom command validator class
# See https://docs.openc3.com/docs/configuration/command
class <%= validator_class %>(CommandValidator):
    # Called before a command is sent
    # @param command [Packet] The command object containing all the command details
    # @return [list] First element is True/False/None for success/failure/unknown,
    #   second element is an optional message string
    def pre_check(self, command):
        # Add your pre-command validation logic here
        # Example:
        # target_name = command.target_name
        # command_name = command.packet_name
        # for item_name, item_def in command.items.items():
        #     item_value = command.read(item_name)

        # self.count = tlm("TARGET PACKET COUNT")
        #
        # if some_condition:
        #     return [False, "Command validation failed: reason"]

        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]

    # Called after a command is sent
    # @param command [Packet] The command object containing all the command details
    # @return [list] First element is True/False/None for success/failure/unknown,
    #   second element is an optional message string
    def post_check(self, command):
        # Add your post-command validation logic here
        # Example:
        # Use the OpenC3 API to check telemetry or wait for responses
        # wait_check("TARGET PACKET ITEM == 'EXPECTED'", 5) # Wait up to 5 seconds
        # wait_check(f"TARGET PACKET COUNT > {self.count}", 5) # Wait up to 5 seconds
        #
        # if some_condition:
        #     return [False, "Post-command validation failed: reason"]
        #
        # Wait for telemetry

        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]
