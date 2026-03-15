from openc3.script import *

INFORMATIVE = "This is informative"
DETAILS = "Additional details"

# This script checks all the interactive APIs
prompt("Would you like to continue?")
answer = combo_box("This is a plain combo box", "one", "two", "three", informative=None)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with info",
    "one",
    "two",
    "three",
    informative=INFORMATIVE,
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with details",
    "one",
    "two",
    "three",
    informative=None,
    details=DETAILS,
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with info & details",
    "one",
    "two",
    "three",
    informative=INFORMATIVE,
    details=DETAILS,
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box",
    "one",
    "two",
    "three",
    details=DETAILS,
)
print(f"answer:{answer}")
answer = combo_box("This is a multi-select combo box", "one", "two", "three", multiple=True)
print(f"answer:{answer} len:{len(answer)}")
answer = check_box("This is a check box", "one", "two", "three")
print(f"answer:{answer} len:{len(answer)}")
answer = check_box(
    "This is a check box with info & details",
    "one",
    "two",
    "three",
    informative=INFORMATIVE,
    details=DETAILS,
)
print(f"answer:{answer} len:{len(answer)}")
answer = prompt(
    "This is a test",
    details=DETAILS,
)
print(f"answer:{answer}")
answer = prompt("This is a test", details=DETAILS)
print(f"answer:{answer}")
answer = message_box(
    "This is a message box",
    "one",
    "two",
    "three",
    informative="Informative stuff",
    details=DETAILS,
)
print(f"answer:{answer}")
answer = vertical_message_box(
    "This is a message box",
    "one",
    "two",
    "three",
    informative="Informative stuff",
    details=DETAILS,
)
print(f"answer:{answer}")
QUESTION = "Let me ask you a question"
answer = ask(QUESTION, "default")
print(f"answer:{answer} type:{type(answer)}")
if not isinstance(answer, str):
    raise RuntimeError("Not a string")
answer = ask(QUESTION, 10)
print(f"answer:{answer} type:{type(answer)}")
if not isinstance(answer, int):
    raise RuntimeError("Not an integer")
answer = ask(QUESTION, 10.5)
print(f"answer:{answer} type:{type(answer)}")
if not isinstance(answer, float):
    raise RuntimeError("Not a float")
answer = ask_string(QUESTION, "default")
print(f"answer:{answer} type:{type(answer)}")
answer = ask_string(QUESTION, 10)
print(f"answer:{answer} type:{type(answer)}")
if not isinstance(answer, str):
    raise RuntimeError("Not a string")
answer = ask("Enter a blank (return)", True)  # allow blank
print(f"answer:{answer}")
answer = ask("Password", False, True)  # password required
print(f"answer:{answer}")
