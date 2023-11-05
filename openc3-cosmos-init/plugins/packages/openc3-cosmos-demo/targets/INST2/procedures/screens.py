all_screens = get_screen_list()
print(all_screens["INST"])
wait(1)
definition = get_screen_definition("INST", "ADCS")
print(definition)
wait(1)
display_screen("INST", "ADCS")
wait(3)
display_screen("INST", "HS", 400, 0)
wait(3)
clear_screen("INST", "ADCS")
wait(3)
display_screen("INST", "IMAGE")
wait(3)
clear_all_screens()
wait(3)
definition = """
SCREEN AUTO AUTO 1.0

VERTICALBOX "Test Screen"
  LABELVALUE INST HEALTH_STATUS TEMP1
  LABELVALUE INST HEALTH_STATUS RECEIVED_TIMEFORMATTED WITH_UNITS 30
END
"""
local_screen("TEST", definition)
wait(3)
clear_all_screens()
create_screen("INST", "TEST", definition)
display_screen("INST", "TEST")
wait(3)
clear_all_screens()
delete_screen("INST", "TEST")
display_screen("INST", "TEST")  # Expected to fail because new screen was deleted
