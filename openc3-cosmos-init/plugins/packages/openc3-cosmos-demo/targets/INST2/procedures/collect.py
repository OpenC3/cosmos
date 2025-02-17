# Instrument code to display line-by-line in Script Runner
load_utility("<%= target_name %>/procedures/utilities/collect.py")
load_utility("<%= target_name %>/procedures/utilities/clear.py")
# Load a target file library (not instrumented)
from INST2.lib.helper import Helper

helper = Helper()
helper.print_help()

number = ask("Enter a number.")
if not isinstance(number, (int, float)):
    raise RuntimeError("Bad return")
number = ask_string("Enter a number.")
if not isinstance(number, str):
    raise RuntimeError("Bad return")

result = message_box("Click something.", "CHOICE1", "CHOICE2")

prompt("Press Ok to start NORMAL Collect")
collect("NORMAL", 1)
prompt("Press Ok to start SPECIAL Collect")
collect("SPECIAL", 2, True)
clear()

wait_check("<%= target_name %> HEALTH_STATUS COLLECTS == 0", 10)
