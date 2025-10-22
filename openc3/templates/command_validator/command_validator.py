from openc3.packets.command_validator import CommandValidator
# Using the OpenC3 API requires the following imports:
# from openc3.api import wait_check

# Custom command validator class
# See https://docs.openc3.com/docs/configuration/command
class <%= validator_class %>(CommandValidator):
    def __init__(self, *args):
        super().__init__()
        self.args = args

    # Called before a command is sent
    # @param command [dict] The command dictionary containing all the command details
    # @return [list] First element is True/False/None for success/failure/unknown,
    #   second element is an optional message string
    def pre_check(self, command):
        # Add your pre-command validation logic here
        # Example:
        # target_name = command['target_name']
        # command_name = command['cmd_name']
        # params = command['cmd_params']
        # self.count = tlm("TARGET PACKET COUNT")
        #
        # if some_condition:
        #     return [False, "Command validation failed: reason"]

        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]

    # Called after a command is sent
    # @param command [dict] The command dictionary containing all the command details
    # @return [list] First element is True/False/None for success/failure/unknown,
    #   second element is an optional message string
    def post_check(self, command):
        # Add your post-command validation logic here
        # Example:
        # Use the OpenC3 API to check telemetry or wait for responses
        # wait_check(f"TARGET PACKET COUNT > {self.count}", 5) # Wait up to 5 seconds
        #
        # if some_condition:
        #     return [False, "Post-command validation failed: reason"]
        #
        # Wait for telemetry

        # Return True to indicate Success, False to indicate Failure,
        # and None to indicate Unknown. The second value is the optional message.
        return [True, None]
