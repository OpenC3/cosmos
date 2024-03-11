from openc3.script import *

# This script checks all the interactive APIs
prompt("Would you like to continue?")
answer = combo_box("This is a plain combo box", "one", "two", "three", informative=None)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with info",
    "one",
    "two",
    "three",
    informative="This is informative",
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with details",
    "one",
    "two",
    "three",
    informative=None,
    details="This is some details",
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box with info & details",
    "one",
    "two",
    "three",
    informative="This is informative",
    details="Details details details!",
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a combo box",
    "one",
    "two",
    "three",
    text_color="blue",
    background_color="grey",
    font_size=20,
    font_family="courier",
    details="Some more stuff",
)
print(f"answer:{answer}")
answer = combo_box(
    "This is a multi-select combo box", "one", "two", "three", multiple=True
)
print(f"answer:{answer} len:{len(answer)}")
answer = prompt(
    "This is a test",
    text_color="blue",
    background_color="grey",
    font_size=20,
    font_family="courier",
    details="Some more stuff",
)
print(f"answer:{answer}")
answer = prompt("This is a test", font_size=30, details="Some more stuff")
print(f"answer:{answer}")
answer = message_box(
    "This is a message box",
    "one",
    "two",
    "three",
    text_color="blue",
    background_color="grey",
    font_size=20,
    font_family="courier",
    informative="Informative stuff",
    details="Some more stuff",
)
print(f"answer:{answer}")
answer = vertical_message_box(
    "This is a message box",
    "one",
    "two",
    "three",
    text_color="blue",
    background_color="grey",
    font_size=20,
    font_family="courier",
    informative="Informative stuff",
    details="Some more stuff",
)
print(f"answer:{answer}")
answer = ask("Let me ask you a question", "default")
print(f"answer:{answer} type:{type(answer)}")
if type(answer) != str:
    raise RuntimeError("Not a string")
answer = ask("Let me ask you a question", 10)
print(f"answer:{answer} type:{type(answer)}")
if type(answer) != int:
    raise RuntimeError("Not an integer")
answer = ask("Let me ask you a question", 10.5)
print(f"answer:{answer} type:{type(answer)}")
if type(answer) != float:
    raise RuntimeError("Not a float")
answer = ask_string("Let me ask you a question", "default")
print(f"answer:{answer} type:{type(answer)}")
answer = ask_string("Let me ask you a question", 10)
print(f"answer:{answer} type:{type(answer)}")
if type(answer) != str:
    raise RuntimeError("Not a string")
answer = ask("Enter a blank (return)", True)  # allow blank
print(f"answer:{answer}")
answer = ask("Password", False, True)  # password required
print(f"answer:{answer}")
